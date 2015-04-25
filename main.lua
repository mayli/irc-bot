#!/usr/bin/env lua5.2

local lfs = require "lfs"
local irce = require "irce"
local cqueues = require "cqueues"
local cs = require "cqueues.socket"

local function log(...)
	io.stderr:write(string.format(...), "\n")
end

local plugins = {}
local function clear_plugins()
	for k,v in pairs(plugins) do
		plugins[k] = nil
	end
end
local function load_plugins()
	for file in lfs.dir("./plugins") do
		if file:sub(1,1) ~= "." and file:match(".lua$") then
			local func, err = loadfile("./plugins/"..file)
			if func == nil then
				log("Failed to load plugin %s: %s", file, err)
			else
				local ok, plugin = pcall(func)
				if not ok then
					log("Failed to run plugin %s: %s", file, plugin)
				else
					log("Successfully loaded plugin %s", file)
					plugins[file] = plugin
				end
			end
		end
	end
end

local cq = cqueues.new()
local function start(cd, channels, nick)
	local irc = irce.new()
	irc:load_module(require "irce.modules.base")
	irc:load_module(require "irce.modules.message")
	irc:load_module(require "irce.modules.channel")

	local sock = assert(cs.connect {
		host = cd.host;
		port = cd.port or 6667;
	})
	sock:setmode("t", "bn") -- Binary mode, no output buffering
	if cd.tls then assert(sock:starttls(cd.tls)) end
	irc:set_send_func(function(message)
		return sock:write(message)
	end)
	cqueues.running():wrap(function()
		for line in sock:lines() do
			irc:process(line)
		end
		log("Disconnected.")
	end)

	-- Print to local console
	irc:set_callback("RAW", function(send, message)
		print(("%s %s"):format(send and ">>>" or "<<<", message))
	end)

	-- Do connecting
	irc:NICK(nick or "[]")
	irc:USER(os.getenv"USER", "hashbang-bot")

	-- Once server has sent "welcome" line, join channels
	irc:set_callback("001", function(...)
		for i, v in ipairs(channels) do
			irc:JOIN(v)
		end
	end)

	-- Quick hack to get plugin reloading
	load_plugins()
	function irc:reload_plugins()
		clear_plugins()
		load_plugins()
	end

	irc:set_callback("PRIVMSG", function(sender, origin, message, pm)
		for name, plugin in pairs(plugins) do
			if plugin.PRIVMSG then
				local ok, err = pcall(plugin.PRIVMSG, irc, sender, origin, message, pm)
				if not ok then
					log("Plugin %s failed: %s", name, tostring(err))
				end
			end
		end
	end)
end
cq:wrap(start, {host="irc.hashbang.sh", port=6697, tls=true}, {
	"#!"; -- We should join automatically; but just in case.
	"#!social";
	"#!plan";
})
assert(cq:loop())
