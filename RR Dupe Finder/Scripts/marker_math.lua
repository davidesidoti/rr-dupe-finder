-- RR Dupe Finder — pure marker math (NO UE deps; unit-tested in tests/marker_math_test.lua).
-- The small bits of v4 logic worth testing in isolation: which markers a style selects, and the
-- per-tick bob/spin offsets for the animated beacon. Everything UE-bound stays in highlight.lua.
local M = {}

-- markersFor(style): which marker types to spawn for a MarkerStyle string. Unknown/nil → both
-- (fail-safe: a typo'd style still shows markers rather than silently hiding duplicates).
function M.markersFor(style)
    if style == "outline" then return { outline = true,  beacon = false } end
    if style == "beacon"  then return { outline = false, beacon = true  } end
    return { outline = true, beacon = true }   -- "both" and any unrecognised value
end

-- bobZ(baseZ, phase, amplitude, speed, offset): vertical position of a bobbing beacon. phase is
-- elapsed seconds; speed is radians/sec; offset (radians) desynchronises beacons. Oscillates
-- around baseZ — never drifts.
function M.bobZ(baseZ, phase, amplitude, speed, offset)
    return baseZ + amplitude * math.sin(phase * speed + (offset or 0))
end

-- spinYaw(baseYaw, phase, speed): yaw of a spinning beacon. phase seconds, speed deg/sec. The
-- spin term is wrapped to [0,360) so it never grows unbounded across a long session.
function M.spinYaw(baseYaw, phase, speed)
    return baseYaw + (phase * speed) % 360
end

return M
