-- RR Dupe Finder — cassette enumeration
local sku = require("sku")
local M = {}

-- Returns: records (array), skipped (int count of cassettes with unreadable SKU)
-- Each cassette read is wrapped in pcall so one bad actor never aborts the scan.
function M.run()
    local out, skipped = {}, 0
    local carts = FindAllOf("Cartridge_Base_C") or {}
    for _, cart in pairs(carts) do
        pcall(function()
            if not sku.isCartridge(cart) then return end
            local s = sku.read(cart)
            if not s then skipped = skipped + 1; return end
            local loc = cart:K2_GetActorLocation()
            out[#out + 1] = {
                sku = s, title = sku.readTitle(cart),
                x = loc.X, y = loc.Y, z = loc.Z, name = cart:GetFullName(),
                actor = cart,   -- live actor, so highlight can tint placed dupes from this scan
            }
        end)
    end
    return out, skipped
end

return M
