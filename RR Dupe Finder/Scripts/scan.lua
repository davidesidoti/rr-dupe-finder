-- RR Dupe Finder — cassette enumeration
local sku = require("sku")
local M = {}

-- Returns: array of { sku=<int>, x=, y=, z=, name=<fullname> }
-- Each cassette read is wrapped in pcall so one bad actor never aborts the scan.
function M.run()
    local out = {}
    local carts = FindAllOf("Cartridge_Base_C") or {}
    for _, cart in pairs(carts) do
        pcall(function()
            if not sku.isCartridge(cart) then return end
            local s = sku.read(cart); if not s then return end
            local loc = cart:K2_GetActorLocation()
            out[#out + 1] = { sku = s, x = loc.X, y = loc.Y, z = loc.Z, name = cart:GetFullName() }
        end)
    end
    return out
end

return M
