-- RR Dupe Finder — entry point (scaffold)
local Config = require("config")

local P = "[RR-Dupe] "
local function log(m) print(P .. m .. "\n") end

local key = Key[Config.ScanKey]
RegisterKeyBind(key, function()
    log("Scan key pressed (stub — scan not implemented yet).")
end)

log("RR Dupe Finder loaded (scaffold). Press " .. Config.ScanKey .. " to test the keybind.")
