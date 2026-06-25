-- RR Dupe Finder — duplicate grouping + report formatting (pure; no UE calls)
local M = {}

local function isOrigin(x, y, z)
    return math.abs(x) < 0.5 and math.abs(y) < 0.5 and math.abs(z) < 0.5
end

-- records: array of { sku, title?, x, y, z, actor?, rented? }
-- keepOne (default true): mark one copy of each duplicated SKU as the "keeper" (the first placed,
--   non-rented copy — a displayed copy) via loc.keep = true, so the caller can leave exactly one
--   copy of each movie unmarked/unsold and only flag the extras.
-- Each copy buckets by precedence: rented → backstock(origin) → sellable.
-- Returns: { totalCarts, uniqueSkus, sellableExtras,
--            dupes = { { sku, title, copies, placedCopies,
--                        sellableCopies, backstockCopies, rentedCopies,
--                        locs = { { x, y, z, actor, placed, rented, keep? }, ... } } } }
function M.analyze(records, minCopies, keepOne)
    minCopies = minCopies or 2
    if keepOne == nil then keepOne = true end
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
            x = r.x, y = r.y, z = r.z, actor = r.actor,
            placed = not isOrigin(r.x, r.y, r.z),
            rented = r.rented == true,
        }
    end
    local dupes, sellableExtras = {}, 0
    for _, s in ipairs(order) do
        local g = bySku[s]
        g.copies, g.placedCopies = #g.locs, 0
        g.sellableCopies, g.backstockCopies, g.rentedCopies = 0, 0, 0
        for _, p in ipairs(g.locs) do
            if p.placed then g.placedCopies = g.placedCopies + 1 end
            if p.rented then
                g.rentedCopies = g.rentedCopies + 1
            elseif not p.placed then
                g.backstockCopies = g.backstockCopies + 1
            else
                g.sellableCopies = g.sellableCopies + 1
            end
        end
        if g.copies >= minCopies then
            dupes[#dupes + 1] = g
            sellableExtras = sellableExtras + math.max(0, (g.copies - g.rentedCopies) - 1)
            if keepOne then                          -- leave one copy of each dupe unmarked: the keeper
                for _, p in ipairs(g.locs) do        -- first placed, non-rented copy (a displayed copy)
                    if p.placed and not p.rented then p.keep = true; break end
                end
            end
        end
    end
    table.sort(dupes, function(a, b)
        if a.copies ~= b.copies then return a.copies > b.copies end   -- most-duplicated first
        return a.sku < b.sku                                          -- tie-break by SKU asc
    end)
    return { totalCarts = #records, uniqueSkus = #order, dupes = dupes, sellableExtras = sellableExtras }
end

-- Returns: array of strings (no prefix; main adds the "[RR-Dupe] " tag)
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
        -- suffix = non-zero buckets, omitted entirely when everything is sellable
        if g.backstockCopies > 0 or g.rentedCopies > 0 then
            local parts = {}
            if g.sellableCopies  > 0 then parts[#parts + 1] = g.sellableCopies  .. " sellable"  end
            if g.backstockCopies > 0 then parts[#parts + 1] = g.backstockCopies .. " backstock" end
            if g.rentedCopies    > 0 then parts[#parts + 1] = g.rentedCopies    .. " rented"     end
            head = head .. " (" .. table.concat(parts, ", ") .. ")"
        end
        lines[#lines + 1] = head .. ":"
        for i, p in ipairs(g.locs) do
            if p.rented then
                lines[#lines + 1] = string.format("    #%d  rented (can't sell)", i)
            elseif p.placed and p.keep then
                lines[#lines + 1] = string.format("    #%d  (%.1f, %.1f, %.1f)  <- KEEP this one", i, p.x, p.y, p.z)
            elseif p.placed then
                lines[#lines + 1] = string.format("    #%d  (%.1f, %.1f, %.1f)", i, p.x, p.y, p.z)
            else
                lines[#lines + 1] = string.format("    #%d  backstock (unplaced)", i)
            end
        end
    end
    lines[#lines + 1] = string.format(
        "Total sellable extras: %d   (copies minus rented, minus one to keep, per duplicated SKU)",
        a.sellableExtras)
    return lines
end

return M
