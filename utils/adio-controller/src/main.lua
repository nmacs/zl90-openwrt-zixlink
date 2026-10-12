#!/usr/bin/luajit

local copas    = require("copas")
local posix    = require("posix")
local signal   = require("posix.signal")
local json     = require("cjson")
local settings = require("settings")

local api        = require("api")
local log        = require("log")
local adio       = require("adio")
local datetime   = require("datetime")

local dbg = true



local function shutdown(signo)
  print("Shutting down...")
  os.exit()
end


signal.signal(signal.SIGINT,  shutdown)
signal.signal(signal.SIGTERM, shutdown)

adio.init()

print("Loop...")
copas.loop()
