local sched = require 'sched'
local socket = require 'socket'
local log = require('log')
local JSON = assert(loadfile "json.lua")()
local config = require 'config'
local modbus_lib = require 'modbus_lib'

modbus_lib.init(10,2, config.LOG_NAME)
log.setlevel(config.LOG_LEVEL, config.LOG_NAME)

local function transferOnRequest(contract)
	local modbus = {}
	local err
	if contract.transfers then
		for devKey, devVal in pairs(contract.transfers) do
			if devVal.data then
				local read = {}
				local write = {}
				for tKey, transfer in pairs(devVal.data) do
					if transfer._direction == "IN" then 
						table.insert(read, {type = transfer._type, address = transfer._remote, length = transfer._length})
					else
						local modbusRes, modbusErr
						if transfer._type == "holdingregister" then
							modbusRes, modbusErr = modbus_lib.readHoldingRegister(devVal.localDevice, 502, transfer._local, 1)
						elseif transfer._type == "inputregister" then
							modbusRes, modbusErr = modbus_lib.readInputRegisters(devVal.localDevice, 502, transfer._local, 1)
						elseif transfer._type == "digitaloutput" then
							modbusRes, modbusErr = modbus_lib.readCoils(devVal.localDevice, 502, transfer._local)
						elseif transfer._type == "digitalinput" then
							modbusRes, modbusErr = modbus_lib.readDiscreteInputs(devVal.localDevice, 502, transfer._local)
						end
						if not modbusErr then
							if modbusRes then
								log(config.LOG_NAME, "DEBUG", "(%s)(REQUEST_TRANSFER) %s ==> %s = %s (%s)", contract.name, transfer._local, transfer._remote, modbusRes[1], transfer._type)
								table.insert(write, {type = transfer._type, address = transfer._remote, value = modbusRes[1]})
							end
						else
							err = modbusErr		
						end
					end
				end
				table.insert(modbus, {address = devVal.remoteDevice, port = 502, read = read, write = write})
			end
		end
	end
	return modbus, err
end

local function transferOnResponse(contract, response)
	if contract.transfers and response then -- Only if transfer are defined and response is available
		for devKey, devVal in pairs(contract.transfers) do -- Try to process each transfer definition 
			for rKey, rVal in pairs(response.modbus) do -- Check each modbus device response for each transfer
				if rKey == devVal.remoteDevice then 
					for tKey, tVal in pairs(rVal) do -- Read through the actual values returned from IOCONTROL
						for dataKey, dataVal in pairs(devVal.data) do -- Match with the transfer definition
							if dataVal._direction == "IN" and dataVal._remote == tVal.address and dataVal._type == tVal.type then
								if dataVal._type == "digitaloutput" then
									modbus_lib.writeCoil(devVal.localDevice, 502, dataVal._local, tVal.value)
								elseif dataVal._type == "float" then
									modbus_lib.writeFloat(devVal.localDevice, 502, dataVal._local, tVal.value)
								elseif dataVal._type == "long" then
									modbus_lib.writeLong(devVal.localDevice, 502, dataVal._local, tVal.value)
								elseif dataVal._type == "holdingregister" then
									modbus_lib.writeRegister(devVal.localDevice, 502, dataVal._local, tVal.value)
								end
								log(config.LOG_NAME, "DEBUG", "(%s)(RESPONSE_TRANSFER) %s ==> %s = %s (%s)", contract.name, tVal.address, dataVal._local, tVal.value, dataVal._type)
							end
						end
					end
				end
			end
		end
	end
end

local function run(contract)
	while true do
		local ip, err = socket.dns.toip(contract.name)
		if ip then
			log(config.LOG_NAME, "DEBUG", "(%s) Dnsname resolved : %s", contract.name, ip)	
			local client = socket.tcp()
			client:settimeout(config.TIMEOUT)
			client:connect(ip, contract.port)
			local recv,sent,age = client:getstats()
			if age <= config.TIMEOUT then
				local reqModbus, reqModbusErr = transferOnRequest(contract)
				if reqModbusErr then
					log(config.LOG_NAME, "WARNING", "(%s)(REQUEST_MODBUS) An error occurent when preparing modbus request", contract.name)
				end
				local request = {
					authKey = contract.authKey,
					modbus = reqModbus
				}
				local jsonRequest = JSON:encode(request)
				log(config.LOG_NAME, "DEBUG", "(%s)(REQUEST) %s", contract.name, jsonRequest)
				client:send(string.format("%s\r\n", jsonRequest))
				local res, err = client:receive()
				if not err then
					log(config.LOG_NAME, "DEBUG", "(%s)(RESPONSE) %s", contract.name, res)
					local response = JSON:decode(res);
					transferOnResponse(contract, response)
					contract.responseHandler(response)
				else
					log(config.LOG_NAME, "ERROR", "(%s)(RESPONSE) %s", contract.name, err)
					contract.connectionErrorHandler(err)
					contract.responseHandler(nil)
				end
			else
				log(config.LOG_NAME, "ERROR", "(%s) Unable to connect to %s:%d, %fs", contract.name, ip, contract.port, age)	
				contract.connectionErrorHandler(err)
			end
			client:close()
		else
			log(config.LOG_NAME, "ERROR", "(%s) Dnsname resolving error : %s", contract.name, err)
			contract.connectionErrorHandler(err)
		end
		sched.wait(config.INTERVAL)
	end
end

local function main()
	for i=1,table.getn(config.IOCONTROLS) do
  		sched.run(run, config.IOCONTROLS[i])
  	end
  	sched.loop()
end

main()

