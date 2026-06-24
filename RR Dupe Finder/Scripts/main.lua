-- RR Dupe Finder — entry point
local Config = require("config")
local scan   = require("scan")
local report = require("report")

local P = "[RR-Dupe] "
local function log(m) print(P .. m .. "\n") end

local function runScan()
    local records  = scan.run()
    local analysis = report.analyze(records, Config.MinCopies)
    for _, line in ipairs(report.format(analysis)) do log(line) end
end

local function onScanKey()
    ExecuteInGameThread(function()                 -- UObject reads must be on the game thread
        local ok, err = pcall(runScan)
        if not ok then log("Scan error: " .. tostring(err)) end
    end)
end

local key = Key[Config.ScanKey]
if Config.Modifiers and #Config.Modifiers > 0 then
    local mods = {}
    for _, name in ipairs(Config.Modifiers) do mods[#mods + 1] = ModifierKey[name] end
    RegisterKeyBind(key, mods, onScanKey)
else
    RegisterKeyBind(key, onScanKey)
end

log("RR Dupe Finder loaded. Press " .. Config.ScanKey .. " to scan.")
