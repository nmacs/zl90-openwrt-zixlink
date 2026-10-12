local xavante = require("xavante.xavante")
local httpd   = require("xavante.httpd")
local http    = require("copas.http")
local hurl    = require("xavante.urlhandler")
local json    = require("cjson")
local zlib    = require("zlib")
local ltn12   = require("ltn12")
local log     = require("log")

local settings   = require("settings")
local adio       = require("adio")

local M = {}
M.__index = M
M.DEFLATE_LEVEL = 6

local dbg = true

-------------------------------------------------------------------------------
-- Module data
-------------------------------------------------------------------------------

local function zstream(res, deflate, level)
	local item = 0
	local stream
	if deflate then
		stream = zlib.deflate(level)
	end
	return function(data)
		if deflate then 
			local out = stream(data)
			if string.len(out) > 0 then
				res:send_data(out)
			end
		else
			res:send_data(data)
		end
	end
end

local function deflate_res(req, res, data)
 	local deflate = false
	local accept_encoding = req.headers["accept-encoding"]
	if accept_encoding and string.find(accept_encoding, "deflate") then
		deflate = true
		res.headers["Content-Encoding"]  = "deflate"
	end
  
	if (deflate) then
		local stream = zlib.deflate(M.DEFLATE_LEVEL)
		data = stream(data, "finish")
	end
  
	return data
end

-------------------------------------------------------------------------------
-- Module data
-------------------------------------------------------------------------------

local function req_data(req)
	local data = ""
	local chunked = (req.headers["Transfer-Encoding"] and (req.headers["Transfer-Encoding"]).find("chunked")) or (false)
	local content_len = tonumber(req.headers["content-length"])
	
	--log.trace(dbg, "API: request, chunked: %s, len: %s", tostring(chunked), tostring(content_len))
	
	if (chunked) then
		log.trace(dbg, "API: request, chunked request is not supported")
		return nil
	elseif (content_len and content_len > 0) then
		data = req.socket:receive(content_len)
		log.trace(dbg, "API: request, content length: %d", content_len)
	else
		log.trace(dbg, "API: request, unknown content")
		return nil
	end
	
	return data
end

local function adio_set_handler(req, res)
	local data = req_data(req)
	if (not data) then
		log.trace(dbg, "API: ADIO-SET request, null data")
		return httpd.err_json(req, res, 400, "null_data")
	end
	
	local ok, jsondata = pcall(json.decode, data)
	if (not ok) then
		log.trace(dbg, "API: ADIO-SET request, json decoding error")
		return httpd.err_json(req, res, 400, "json_decoding_error")
	end
	
	ok = adio.set_values(jsondata)
	if (not ok) then
		log.trace(dbg, "API: ADIO-SET request - failed")
	end
	
	res.headers["Content-Length"]		= 0
	res.headers["Connection"]				= "close"
	
	res:send_headers()
	return res
end

local function adio_get_handler(req, res)
	local params = httpd.getparams(req)
	local data = {}
	
	data = adio.get_values()
	
	data = json.encode(data)
	data = deflate_res(req, res, data)

	res.headers["Content-Length"]		= #data
	res.headers["Content-Type"]			= "application/json"
	res.headers["Connection"]				= "close"

	res:send_headers()
	res:send_data(data)

	return res
end

local function adio_configuration_get_handler(req, res)
	local params = httpd.getparams(req)
	local data = {}
	
	data = adio.get_configuration()
	
	data = json.encode(data)
	data = deflate_res(req, res, data)

	res.headers["Content-Length"]		= #data
	res.headers["Content-Type"]			= "application/json"
	res.headers["Connection"]				= "close"

	res:send_headers()
	res:send_data(data)

	return res
end

local function adio_configuration_set_handler(req, res)
	local data = req_data(req)
	if (not data) then
		log.trace(dbg, "API: ADIO-SET request, null data")
		return httpd.err_json(req, res, 400, "null_data")
	end
	
	local ok, jsondata = pcall(json.decode, data)
	if (not ok) then
		log.trace(dbg, "API: ADIO-SET request, json decoding error")
		return httpd.err_json(req, res, 400, "json_decoding_error")
	end
	
	ok = adio.set_configuration(jsondata)
	if (not ok) then
		log.trace(dbg, "API: ADIO-SET request - failed")
	end
	
	res.headers["Content-Length"]		= 0
	res.headers["Connection"]				= "close"
	
	res:send_headers()
	return res
end

-------------------------------------------------------------------------------
-- Module common functions
-------------------------------------------------------------------------------
		
local function _adio_get_handler(req, res)
	local method = req.cmd_mth
	if (method == "GET") then
		return adio_get_handler(req, res)
	else
		return httpd.err_json(req, res, 405, "method_is_not_support")
	end
end

local function _adio_configuration_handler(req, res)
	local method = req.cmd_mth
	if (method == "GET") then
		return adio_configuration_get_handler(req, res)
	elseif (method == "PUT" or method == "POST") then
		return adio_configuration_set_handler(req, res)
	else
		return httpd.err_json(req, res, 405, "method_is_not_support")
	end
end

local function _adio_set_handler(req, res)
	local method = req.cmd_mth
	if (method == "PUT" or method == "POST") then
		return adio_set_handler(req, res)
	else
		return httpd.err_json(req, res, 405, "method_is_not_support")
	end
end

-------------------------------------------------------------------------------
-- API handlers description
-------------------------------------------------------------------------------
		
local handlers = {}

handlers["/api/adio/configuration"]							= _adio_configuration_handler
handlers["/api/adio/get"]												= _adio_get_handler
handlers["/api/adio/set"]												= _adio_set_handler


local rules = {
	{
		match = ".",
		with = hurl,
		params = handlers
	},
}

xavante.HTTP {
	server = {host = settings.api.host, port = settings.api.port},
	defaultHost = {
		rules = rules
	},
}

return M
