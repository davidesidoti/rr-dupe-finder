-- RR Dupe Finder — SKU read path (isolated; the most build-fragile module)
local M = {}

-- GUID-mangled Blueprint struct property names. Verbatim from SKU QoL. Do NOT guess.
local PRODUCT_STRUCTURE_KEY = "Product Structure"
local BASE_STRUCTURE_KEY    = "BaseStructure_2_FBB12C464AE570CAFD12ED8506160683"
local BOX_DATA_KEY          = "BoxData_25_B5A798DA4F509BDCCF4B189171C1DA10"
local SKU_KEY               = "SKU_26_C5F25F4E49D05A4DEC2DEEAE5AEE5876"

-- True only for a real, usable cassette actor (valid + not the class default object).
function M.isCartridge(obj)
    if not obj or not obj:IsValid() then return false end
    if obj:GetFullName():find("Default__") then return false end
    return true
end

-- Returns the integer SKU, or nil if any struct level is missing.
function M.read(cart)
    local ps   = cart[PRODUCT_STRUCTURE_KEY]; if not ps   then return nil end
    local base = ps[BASE_STRUCTURE_KEY];      if not base then return nil end
    local box  = base[BOX_DATA_KEY];          if not box  then return nil end
    return box[SKU_KEY]
end

return M
