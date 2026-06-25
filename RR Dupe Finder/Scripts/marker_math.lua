-- RR Dupe Finder — pure marker math (NO UE deps; unit-tested in tests/marker_math_test.lua).
-- The bits of v4 marker logic worth testing in isolation: which markers a style selects, and
-- where the one-per-movie beacon should hover. Everything UE-bound stays in highlight.lua.
local M = {}

-- markersFor(style): which marker types to spawn for a MarkerStyle string. Unknown/nil → both
-- (fail-safe: a typo'd style still shows markers rather than silently hiding duplicates).
function M.markersFor(style)
    if style == "outline" then return { outline = true,  beacon = false } end
    if style == "beacon"  then return { outline = false, beacon = true  } end
    return { outline = true, beacon = true }   -- "both" and any unrecognised value
end

-- groupPoints(dupes, excludeRented): ONE hover point per duplicated movie that has at least one
-- markable copy, so the in-world beacon is a single pointer per movie (not one per cassette).
--   dupes         — report.analyze(...).dupes: array of groups, each with a `locs` array whose
--                   entries carry x/y/z and the placed / rented / keep flags.
--   excludeRented — when true, rented copies don't count (you can't sell them).
-- A copy is "markable" iff placed AND not the keeper AND not (rented and excludeRented). The point
-- is the centroid of the markable copies in X/Y and the MAX Z among them (so the pointer floats
-- above the tallest copy of the cluster). Groups with no markable copy are skipped.
function M.groupPoints(dupes, excludeRented)
    local points = {}
    for _, g in ipairs(dupes or {}) do
        local sx, sy, maxz, cnt = 0, 0, nil, 0
        for _, p in ipairs(g.locs or {}) do
            local skip = (p.rented and excludeRented) or p.keep
            if p.placed and not skip then
                sx = sx + p.x
                sy = sy + p.y
                maxz = (maxz == nil or p.z > maxz) and p.z or maxz
                cnt = cnt + 1
            end
        end
        if cnt > 0 then
            points[#points + 1] = { x = sx / cnt, y = sy / cnt, z = maxz }
        end
    end
    return points
end

-- copyPoints(dupes, excludeRented): a FLAT list of every markable copy's {x,y,z} (markable = placed
-- AND not keeper AND not (rented and excludeRented)). Unlike groupPoints it does not average per
-- movie, so feeding this to clusterPoints groups markers by physical pile — a movie split across two
-- shelves yields a marker on each, and a stray copy never drags its movie's marker off the shelf.
function M.copyPoints(dupes, excludeRented)
    local pts = {}
    for _, g in ipairs(dupes or {}) do
        for _, p in ipairs(g.locs or {}) do
            local skip = (p.rented and excludeRented) or p.keep
            if p.placed and not skip then
                pts[#pts + 1] = { x = p.x, y = p.y, z = p.z }
            end
        end
    end
    return pts
end

-- clusterPoints(points, radius): merge points whose XY distance is within `radius` into a single
-- point (greedy, single pass), at the running XY centroid and the MAX Z of the cluster. Declutters
-- co-located markers — e.g. many different movies whose sellable copy sits in the same sell bin or
-- display cabinet collapse to one arrow instead of a pile. 2D (XY) so a tall shelf face merges too.
function M.clusterPoints(points, radius)
    local r2 = (radius or 100) * (radius or 100)
    local clusters = {}
    for _, p in ipairs(points or {}) do
        local placed = false
        for _, c in ipairs(clusters) do
            local dx, dy = p.x - c.cx, p.y - c.cy
            if dx * dx + dy * dy <= r2 then
                c.sx = c.sx + p.x; c.sy = c.sy + p.y; c.n = c.n + 1
                c.cx = c.sx / c.n; c.cy = c.sy / c.n
                if p.z > c.z then c.z = p.z end
                placed = true
                break
            end
        end
        if not placed then
            clusters[#clusters + 1] = { sx = p.x, sy = p.y, n = 1, cx = p.x, cy = p.y, z = p.z }
        end
    end
    local out = {}
    for _, c in ipairs(clusters) do out[#out + 1] = { x = c.cx, y = c.cy, z = c.z } end
    return out
end

return M
