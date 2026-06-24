-- RR Dupe Finder — entry point (scan-dump diagnostic; report wired in Session 3)
local Config = require("config")
local scan   = require("scan")

local P = "[RR-Dupe] "
local function log(m) print(P .. m .. "\n") end

local function dumpScan()
    local records = scan.run()
    log(string.format("Scan found %d readable cassettes.", #records))
    for i, r in ipairs(records) do
        if i > 10 then log("  ... (first 10 shown)"); break end
        log(string.format("  SKU %s  (%.1f, %.1f, %.1f)", tostring(r.sku), r.x, r.y, r.z))
    end
end

local function onScanKey()
    ExecuteInGameThread(function()
        local ok, err = pcall(dumpScan)
        if not ok then log("Scan error: " .. tostring(err)) end
    end)
end

RegisterKeyBind(Key[Config.ScanKey], onScanKey)
log("RR Dupe Finder loaded (scan-dump). Press " .. Config.ScanKey .. " to dump cassettes.")
