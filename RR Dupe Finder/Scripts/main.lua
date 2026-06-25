-- RR Dupe Finder — entry point (v2: report + in-world tint)
local Config    = require("config")
local scan      = require("scan")
local report    = require("report")
local highlight = require("highlight")

local P = "[RR-Dupe] "
local function log(m) print(P .. m .. "\n") end

-- Live actors of every EXTRA copy to mark for selling: placed, not rented (unless the player opts
-- in), and not the keeper. `keep` is set by report.analyze when Config.KeepOneCopy — it leaves one
-- copy of each duplicated movie unmarked so you always retain one for your collection.
local function sellableDupeActors(analysis)
    local actors = {}
    for _, g in ipairs(analysis.dupes) do
        for _, p in ipairs(g.locs) do
            local skip = (p.rented and Config.ExcludeRented) or p.keep
            if p.placed and not skip and p.actor then actors[#actors + 1] = p.actor end
        end
    end
    return actors
end

local function runScan()
    highlight.clear()                                   -- drop any prior tint (refresh)
    local records, skipped = scan.run()
    local analysis = report.analyze(records, Config.MinCopies, Config.KeepOneCopy)
    for _, line in ipairs(report.format(analysis)) do log(line) end
    if Config.Debug and skipped > 0 then
        log(string.format("(debug) skipped %d cassette(s) with unreadable SKU", skipped))
    end
    if Config.HighlightEnabled then
        local actors = sellableDupeActors(analysis)
        local n = highlight.apply(actors, Config.TintColor) or #actors
        local kept = Config.KeepOneCopy ~= false and " (one copy of each is left unmarked to keep)" or ""
        log(string.format("Outlined %d extra duplicate copy(ies) to sell%s. Press %s to refresh or 'rrdupe clear' to clear.",
            n, kept, Config.ScanKey))
    end
end

local function onScanKey()
    ExecuteInGameThread(function()                      -- UObject reads + material writes on the game thread
        local ok, err = pcall(runScan)
        if not ok then log("Scan error: " .. tostring(err)) end
    end)
end

local function onClear()
    ExecuteInGameThread(function()
        local ok, err = pcall(function() highlight.clear() end)
        if ok then log("Cleared duplicate markers.") else log("Clear error: " .. tostring(err)) end
    end)
end

-- scan keybind (+ optional modifiers)
local key = Key[Config.ScanKey]
if Config.Modifiers and #Config.Modifiers > 0 then
    local mods = {}
    for _, name in ipairs(Config.Modifiers) do mods[#mods + 1] = ModifierKey[name] end
    RegisterKeyBind(key, mods, onScanKey)
else
    RegisterKeyBind(key, onScanKey)
end

-- optional dedicated clear key
if Config.ClearKey then RegisterKeyBind(Key[Config.ClearKey], onClear) end

-- console: "rrdupe" = scan/refresh, "rrdupe clear" = clear only
RegisterConsoleCommandHandler("rrdupe", function(fullCommand, parameters, outputDevice)
    if parameters and parameters[1] and tostring(parameters[1]):lower() == "clear" then
        onClear()
    else
        onScanKey()
    end
    return true
end)

log("RR Dupe Finder loaded. Press " .. Config.ScanKey .. " to scan.")
