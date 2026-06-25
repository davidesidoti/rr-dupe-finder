-- tests/marker_math_test.lua — run from repo root: lua tests/marker_math_test.lua
local mm = dofile("RR Dupe Finder/Scripts/marker_math.lua")

local failures = 0
local function check(name, cond)
    if cond then print("PASS: " .. name)
    else print("FAIL: " .. name); failures = failures + 1 end
end
local function approx(a, b) return math.abs(a - b) < 1e-9 end

-- markersFor: each style selects the right marker set
do
    local o = mm.markersFor("outline")
    check("outline → outline only", o.outline == true and o.beacon == false)
    local b = mm.markersFor("beacon")
    check("beacon → beacon only",   b.outline == false and b.beacon == true)
    local t = mm.markersFor("both")
    check("both → both",            t.outline == true and t.beacon == true)
    -- fail-safe: unknown/nil style still shows markers (treated as "both")
    local u = mm.markersFor("nonsense")
    check("unknown → both",         u.outline == true and u.beacon == true)
    local n = mm.markersFor(nil)
    check("nil → both",             n.outline == true and n.beacon == true)
end

-- groupPoints: ONE point per duplicated movie that has >=1 markable copy.
-- markable = placed AND not keeper AND not (rented and excludeRented). Point = centroid of
-- markable copies in X/Y, and the MAX Z among them (so the pointer floats above the tallest copy).

-- empty input → no points
do
    check("groupPoints empty", #mm.groupPoints({}, true) == 0)
    check("groupPoints nil",   #mm.groupPoints(nil, true) == 0)
end

-- single markable copy → its own coordinates
do
    local dupes = { { locs = { { x = 10, y = 20, z = 30, placed = true } } } }
    local p = mm.groupPoints(dupes, true)
    check("single one point", #p == 1)
    check("single x", approx(p[1].x, 10))
    check("single y", approx(p[1].y, 20))
    check("single z", approx(p[1].z, 30))
end

-- centroid of markable copies in X/Y, max Z; keeper excluded
do
    local dupes = { { locs = {
        { x = 0,  y = 0, z = 5,  placed = true, keep = true },  -- keeper → excluded
        { x = 10, y = 0, z = 40, placed = true },               -- markable
        { x = 20, y = 0, z = 60, placed = true },               -- markable
    } } }
    local p = mm.groupPoints(dupes, true)
    check("centroid count", #p == 1)
    check("centroid x avg", approx(p[1].x, 15))   -- (10+20)/2
    check("centroid y avg", approx(p[1].y, 0))
    check("centroid max z", approx(p[1].z, 60))    -- max(40,60)
end

-- rented excluded when excludeRented true
do
    local dupes = { { locs = {
        { x = 10, y = 0, z = 40, placed = true },
        { x = 30, y = 0, z = 40, placed = true, rented = true },
    } } }
    local p = mm.groupPoints(dupes, true)
    check("rented excluded count", #p == 1)
    check("rented excluded x", approx(p[1].x, 10))   -- only the non-rented copy
end

-- rented included when excludeRented false
do
    local dupes = { { locs = {
        { x = 10, y = 0, z = 40, placed = true },
        { x = 30, y = 0, z = 40, placed = true, rented = true },
    } } }
    local p = mm.groupPoints(dupes, false)
    check("rented included x", approx(p[1].x, 20))   -- (10+30)/2
end

-- group with no markable copy (all backstock / keeper) → no point
do
    local dupes = { { locs = {
        { x = 0, y = 0, z = 0, placed = false },             -- backstock
        { x = 5, y = 5, z = 5, placed = true, keep = true }, -- keeper
    } } }
    check("no markable → no point", #mm.groupPoints(dupes, true) == 0)
end

-- multiple groups → one point each, order preserved; groups with no markable are skipped
do
    local dupes = {
        { locs = { { x = 1, y = 1, z = 1, placed = true } } },            -- markable → point
        { locs = { { x = 9, y = 9, z = 9, placed = false } } },           -- backstock only → skip
        { locs = { { x = 2, y = 2, z = 2, placed = true } } },            -- markable → point
    }
    local p = mm.groupPoints(dupes, true)
    check("multi count", #p == 2)
    check("multi order 1", approx(p[1].x, 1))
    check("multi order 2", approx(p[2].x, 2))
end

-- copyPoints: flat list of EVERY markable copy position (placed, not keeper, not rented-if-excluded).
-- Unlike groupPoints it does NOT average per movie — so a stray copy far from the cluster stays its
-- own point (and later clusters separately) instead of dragging the movie's arrow off the shelf.
do
    local dupes = { { locs = {
        { x = 0,  y = 0, z = 5,  placed = true, keep = true },   -- keeper → excluded
        { x = 10, y = 1, z = 40, placed = true },                -- markable
        { x = 20, y = 2, z = 60, placed = true },                -- markable
        { x = 0,  y = 0, z = 0,  placed = false },               -- backstock → excluded
        { x = 30, y = 3, z = 50, placed = true, rented = true }, -- rented
    } } }
    local p = mm.copyPoints(dupes, true)   -- excludeRented
    check("copyPoints count", #p == 2)
    check("copyPoints keeps each (not centroid)", approx(p[1].x, 10) and approx(p[2].x, 20))
    check("copyPoints z each", approx(p[1].z, 40) and approx(p[2].z, 60))
    check("copyPoints rented included when not excluded", #mm.copyPoints(dupes, false) == 3)
    check("copyPoints empty", #mm.copyPoints({}, true) == 0)
end

-- clusterPoints: merge points within `radius` (2D XY distance) into one, at the XY centroid and
-- the MAX Z of the cluster. Declutters co-located arrows (e.g. many movies' copies in one sell bin).
do
    check("cluster empty", #mm.clusterPoints({}, 100) == 0)
    check("cluster nil",   #mm.clusterPoints(nil, 100) == 0)
end
do  -- single point unchanged
    local c = mm.clusterPoints({ { x = 0, y = 0, z = 10 } }, 100)
    check("cluster single count", #c == 1)
    check("cluster single xyz", approx(c[1].x, 0) and approx(c[1].y, 0) and approx(c[1].z, 10))
end
do  -- two close points (dist 50 < 100) → one cluster at XY centroid, max Z
    local c = mm.clusterPoints({ { x = 0, y = 0, z = 10 }, { x = 50, y = 0, z = 30 } }, 100)
    check("cluster merge count", #c == 1)
    check("cluster merge x avg", approx(c[1].x, 25))
    check("cluster merge max z", approx(c[1].z, 30))
end
do  -- two far points (dist 200 > 100) → two clusters, unchanged
    local c = mm.clusterPoints({ { x = 0, y = 0, z = 10 }, { x = 200, y = 0, z = 10 } }, 100)
    check("cluster split count", #c == 2)
end
do  -- greedy: 1&2 merge, 3 far → 2 clusters
    local c = mm.clusterPoints({ { x = 0, y = 0, z = 5 }, { x = 40, y = 0, z = 5 }, { x = 300, y = 0, z = 5 } }, 100)
    check("cluster greedy count", #c == 2)
    check("cluster greedy first xy", approx(c[1].x, 20) and approx(c[1].y, 0))
    check("cluster greedy second xy", approx(c[2].x, 300))
end

print(string.format("\n%s", failures == 0 and "ALL PASS" or (failures .. " FAILURE(S)")))
os.exit(failures == 0 and 0 or 1)
