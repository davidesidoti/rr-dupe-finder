-- RR Dupe Finder — cassette enumeration
local sku = require("sku")
local M = {}

-- A cassette is rented iff it carries a VISIBLE Reserved-sticker mesh among its
-- construction-script components. The sticker (SM_VHS_Reserved-Sticker_01) lives in
-- AActor.BlueprintCreatedComponents, NOT in K2_GetComponentsByClass (probe-confirmed:
-- the latter returned 0 stickers; BCC returned all 7 reserved). Per component, read
-- .StaticMesh (GetStaticMesh() not exposed -- gotcha 12) THEN GetFullName, BOTH guarded:
-- some components yield a non-nil .StaticMesh whose GetFullName() returns nil, and an
-- unguarded nm:find on that nil aborts the whole sweep (that was the real bug). Plain-text
-- find (4th arg true) -- the mesh name's hyphen is a Lua pattern metachar. Defaults false.
local RESERVED_MESH = "SM_VHS_Reserved-Sticker_01"
local function isRented(cart)
    local rented = false
    pcall(function()
        local comps = cart.BlueprintCreatedComponents
        if not comps then return end
        comps:ForEach(function(_, e)
            if rented then return end
            local c = e:get(); if not c then return end
            local sm; pcall(function() sm = c.StaticMesh end)
            if not sm then return end
            local nm; pcall(function() nm = sm:GetFullName() end)
            if nm and nm:find(RESERVED_MESH, 1, true) then
                local vis = false; pcall(function() vis = c:IsVisible() end)
                if vis then rented = true end
            end
        end)
    end)
    return rented
end

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
                actor = cart, rented = isRented(cart),   -- live actor + rented flag for highlight/report
            }
        end)
    end
    return out, skipped
end

return M
