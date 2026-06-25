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

-- bobZ: oscillates around baseZ; sin(0)=0, sin(pi/2)=1; offset shifts the phase
do
    check("bob phase0 == base",   approx(mm.bobZ(100, 0,        6, 3.0, 0), 100))
    check("bob peak == base+amp", approx(mm.bobZ(100, math.pi/2, 6, 1.0, 0), 106))
    check("bob offset shifts",    approx(mm.bobZ(100, math.pi/2, 6, 1.0, math.pi/2), 100)) -- sin(pi)=0
end

-- spinYaw: base + (phase*speed) wrapped to [0,360)
do
    check("spin 180",         approx(mm.spinYaw(10, 2.0, 90), 190))   -- (180)%360 = 180
    check("spin wrap 90",     approx(mm.spinYaw(10, 5.0, 90), 100))   -- (450)%360 = 90
    check("spin full wrap 0", approx(mm.spinYaw(0, 4.0, 90), 0))      -- (360)%360 = 0
end

print(string.format("\n%s", failures == 0 and "ALL PASS" or (failures .. " FAILURE(S)")))
os.exit(failures == 0 and 0 or 1)
