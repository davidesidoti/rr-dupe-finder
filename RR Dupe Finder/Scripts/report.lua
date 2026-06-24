-- RR Dupe Finder — duplicate grouping + report formatting (pure; no UE calls)
local M = {}

-- records: array of { sku, x, y, z }
-- Returns: { totalCarts, uniqueSkus, dupes = { {sku, copies, locs={{x,y,z},...}} }, sellableExtras }
function M.analyze(records, minCopies)
    minCopies = minCopies or 2
    local bySku, order = {}, {}
    for _, r in ipairs(records) do
        local g = bySku[r.sku]
        if not g then
            g = { sku = r.sku, locs = {} }
            bySku[r.sku] = g
            order[#order + 1] = r.sku
        end
        g.locs[#g.locs + 1] = { x = r.x, y = r.y, z = r.z }
    end
    local dupes, sellable = {}, 0
    for _, s in ipairs(order) do
        local g = bySku[s]
        g.copies = #g.locs
        if g.copies >= minCopies then
            dupes[#dupes + 1] = g
            sellable = sellable + (g.copies - 1)
        end
    end
    table.sort(dupes, function(a, b)
        if a.copies ~= b.copies then return a.copies > b.copies end
        return a.sku < b.sku
    end)
    return { totalCarts = #records, uniqueSkus = #order, dupes = dupes, sellableExtras = sellable }
end

-- Returns: array of strings (no prefix; main.lua adds the "[RR-Dupe] " tag)
function M.format(a)
    local lines = {}
    if a.totalCarts == 0 then
        lines[1] = "No cassettes found."
        return lines
    end
    lines[#lines + 1] = string.format(
        "Scan complete: %d cassettes, %d unique SKUs, %d duplicated.",
        a.totalCarts, a.uniqueSkus, #a.dupes)
    if #a.dupes == 0 then
        lines[#lines + 1] = "No duplicates — collection is clean."
        return lines
    end
    for _, g in ipairs(a.dupes) do
        lines[#lines + 1] = string.format("SKU %s — %d copies:", tostring(g.sku), g.copies)
        for i, p in ipairs(g.locs) do
            lines[#lines + 1] = string.format("    #%d  (%.1f, %.1f, %.1f)", i, p.x, p.y, p.z)
        end
    end
    lines[#lines + 1] = string.format(
        "Total sellable extras: %d   (sum of copies-1 across duplicated SKUs)", a.sellableExtras)
    return lines
end

return M
