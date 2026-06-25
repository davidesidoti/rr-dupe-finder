-- RR Dupe Finder — product-struct read path (isolated; the most build-fragile module)
local M = {}

-- GUID-mangled Blueprint struct property names. SKU verbatim from SKU QoL.
-- TITLE_KEY from v2 recon R1 (docs/superpowers/specs/…-v2-recon.md). Do NOT guess.
local PRODUCT_STRUCTURE_KEY = "Product Structure"
local BASE_STRUCTURE_KEY    = "BaseStructure_2_FBB12C464AE570CAFD12ED8506160683"
local BOX_DATA_KEY          = "BoxData_25_B5A798DA4F509BDCCF4B189171C1DA10"
local SKU_KEY               = "SKU_26_C5F25F4E49D05A4DEC2DEEAE5AEE5876"
local TITLE_KEY             = "ProductName_14_055828B1436E5AD27BFA95AF181099DE"

-- True only for a real, usable cassette actor (valid + not the class default object).
function M.isCartridge(obj)
    if not obj or not obj:IsValid() then return false end
    if obj:GetFullName():find("Default__") then return false end   -- skip CDO
    return true
end

-- Navigate to the BoxData struct that holds SKU + title. Returns the struct or nil.
local function box(cart)
    local ps   = cart[PRODUCT_STRUCTURE_KEY]; if not ps   then return nil end
    local base = ps[BASE_STRUCTURE_KEY];      if not base then return nil end
    return base[BOX_DATA_KEY]
end

-- Returns the integer SKU, or nil if any struct level is missing.
function M.read(cart)
    local b = box(cart); if not b then return nil end
    return b[SKU_KEY]
end

-- Returns the movie title as a Lua string, or nil.
-- R1: the field is an FText (userdata) → stringify with value:ToString() (NOT tostring,
-- which yields a userdata address). pcall-wrapped; an empty string is treated as nil.
function M.readTitle(cart)
    local b = box(cart); if not b then return nil end
    local t = b[TITLE_KEY]; if t == nil then return nil end
    local ok, s = pcall(function() return t:ToString() end)
    if not ok or s == nil or s == "" then return nil end
    return s
end

return M
