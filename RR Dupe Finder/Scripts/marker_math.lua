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

return M
