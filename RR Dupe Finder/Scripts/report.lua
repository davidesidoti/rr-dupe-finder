-- RR Dupe Finder — duplicate grouping + report formatting (pure; no UE calls)
local M = {}

local function isOrigin(x, y, z)
    return math.abs(x) < 0.5 and math.abs(y) < 0.5 and math.abs(z) < 0.5
end

-- records: array of { sku, title?, x, y, z, actor? }
-- Returns: { totalCarts, uniqueSkus, sellableExtras,
--            dupes = { { sku, title, copies, placedCopies,
--                        locs = { { x, y, z, actor, placed }, ... } } } }
function M.analyze(records, minCopies)
    minCopies = minCopies or 2
    local bySku, order = {}, {}
    for _, r in ipairs(records) do
        local g = bySku[r.sku]
        if not g then
            g = { sku = r.sku, title = nil, locs = {} }
            bySku[r.sku] = g
            order[#order + 1] = r.sku
        end
        if g.title == nil and r.title ~= nil and r.title ~= "" then g.title = r.title end
        g.locs[#g.locs + 1] = {
            x = r.x, y = r.y, z = r.z, actor = r.actor, placed = not isOrigin(r.x, r.y, r.z),
        }
    end
    local dupes, sellable = {}, 0
    for _, s in ipairs(order) do
        local g = bySku[s]
        g.copies, g.placedCopies = #g.locs, 0
        for _, p in ipairs(g.locs) do if p.placed then g.placedCopies = g.placedCopies + 1 end end
        if g.copies >= minCopies then
            dupes[#dupes + 1] = g
            sellable = sellable + (g.copies - 1)
        end
    end
    table.sort(dupes, function(a, b)
        if a.copies ~= b.copies then return a.copies > b.copies end   -- most-duplicated first
        return a.sku < b.sku                                          -- tie-break by SKU asc
    end)
    return { totalCarts = #records, uniqueSkus = #order, dupes = dupes, sellableExtras = sellable }
end

-- Returns: array of strings (no prefix; main.lua adds the "[RR-Dupe] " tag)
function M.format(a)
    local lines = {}
    if a.totalCarts == 0 then lines[1] = "No cassettes found."; return lines end
    lines[#lines + 1] = string.format("Scan complete: %d cassettes, %d unique SKUs, %d duplicated.",
        a.totalCarts, a.uniqueSkus, #a.dupes)
    if #a.dupes == 0 then lines[#lines + 1] = "No duplicates — collection is clean."; return lines end
    for _, g in ipairs(a.dupes) do
        local head
        if g.title and g.title ~= "" then
            head = string.format('"%s" (SKU %s) — %d copies', g.title, tostring(g.sku), g.copies)
        else
            head = string.format("SKU %s — %d copies", tostring(g.sku), g.copies)
        end
        local backstock = g.copies - g.placedCopies
        if backstock > 0 then
            head = head .. string.format(" (%d placed, %d backstock)", g.placedCopies, backstock)
        end
        lines[#lines + 1] = head .. ":"
        for i, p in ipairs(g.locs) do
            if p.placed then
                lines[#lines + 1] = string.format("    #%d  (%.1f, %.1f, %.1f)", i, p.x, p.y, p.z)
            else
                lines[#lines + 1] = string.format("    #%d  backstock (unplaced)", i)
            end
        end
    end
    lines[#lines + 1] = string.format(
        "Total sellable extras: %d   (sum of copies-1 across duplicated SKUs)", a.sellableExtras)
    return lines
end

return M
