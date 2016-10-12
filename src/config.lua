local modbus_lib = require 'modbus_lib'
local log = require 'log'

local LOGNAME = "IOCLIENT"

local config = {
	TIMEOUT = 10,
	INTERVAL = 4,
	LOG_NAME = LOGNAME,
	LOG_LEVEL = "INFO",
}

local connectionErrorCounter = 0
config.IOCONTROLS = {
	{
		name = "dnsname.target.com", -- DNS name
		port = 9000, -- IOCONTROL server port
		authKey = "123",
		transfers = {
			{
				localDevice = "192.168.8.2", -- Local PLC IP
				remoteDevice = "192.168.7.2", -- Remote PLC IP
				data = {
					{_remote = 0, _local = 1970, _type = "holdingregister", _length = 1, _direction = "IN"},
					{_remote = 105, _local = 9, _type = "digitaloutput", _direction = "OUT"}
				}
			}
		},
		responseHandler = function(res)
			connectionErrorCounter = 0
			modbus_lib.writeCoil("192.168.8.2", 502, 921, 1)
		end,
		connectionErrorHandler = function(err)
			connectionErrorCounter = connectionErrorCounter + 1
			if connectionErrorCounter >= 6 then
				modbus_lib.writeCoil("192.168.8.2", 502, 921, 0)
			end
		end
	}
}

return config