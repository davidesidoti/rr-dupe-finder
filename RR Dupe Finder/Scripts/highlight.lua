-- RR Dupe Finder — in-world markers for sellable duplicate cassettes (UE-bound).
--
-- v4 (static, one-pointer-per-movie). Two marker types, chosen by Config.MarkerStyle:
--   * outline — the v3 amber VHS outline shell ON each duplicate box (good up close).
--   * beacon  — ONE high-contrast pointer floated ABOVE each duplicated movie's cluster of
--               sellable copies (centroid + height), so it reads from across the store and
--               doesn't clash with the cassette colour. One per movie, NOT one per cassette.
-- Everything is STATIC: a continuous LoopAsync animation was tried and hard-crashed the game
-- (EXCEPTION_ACCESS_VIOLATION — LoopAsync runs Lua on a worker thread, which corrupts the VM
-- when the game thread is also in Lua; see CLAUDE.md + config.lua). Do NOT reintroduce an
-- async animation loop. Colour is fixed by the material asset (DMIs crash —
-- gotcha 10); additive mod-pak assets won't load (gotcha 16), so every path is a base-pak path.
-- BEACON_MESH/BEACON_MAT ship as known-loadable FALLBACKs; recon upgrades them to a downward
-- pointer mesh + a high-contrast colour (see the spec Appendix).
local UEHelpers  = require("UEHelpers")
local Config     = require("config")
local markerMath = require("marker_math")

local M = {}

-- Outline shell (v3, unchanged) — spawned per duplicate box.
local SHELL_MESH    = "/Game/VideoStore/asset/prop/vhs/LA_VHS_Box_Outline_01.LA_VHS_Box_Outline_01"
local OUTLINE_MAT   = "/Game/VideoStore/core/shader/environment/Neon/M_Opaque_Neon_Tintable.M_Opaque_Neon_Tintable"
local OUTLINE_SCALE = 1.1

-- Beacon pointer (one per movie, floated above). FALLBACK = the known-loadable outline mesh +
-- its neon material; recon replaces BEACON_MESH with a downward pointer (cone/pin) and BEACON_MAT
-- with a high-contrast colour, appending the new mesh name to MESH_TAGS if it changes.
local BEACON_MESH = "/Game/VideoStore/asset/prop/vhs/LA_VHS_Box_Outline_01.LA_VHS_Box_Outline_01"
local BEACON_MAT  = "/Game/VideoStore/core/shader/environment/Neon/M_Opaque_Neon_Tintable.M_Opaque_Neon_Tintable"

local SMA_CLASS = "/Script/Engine.StaticMeshActor"

-- Mesh-name substrings the orphan sweep matches in clear() (plain-text find — gotcha 13). Both
-- markers reuse the outline mesh in the fallback; recon appends the beacon mesh name if it differs.
local MESH_TAGS = { "LA_VHS_Box_Outline_01" }

local spawned = {}   -- every tracked spawned StaticMeshActor, for clear()

local function valid(o) return o ~= nil and o:IsValid() end
local function isOrigin(loc)
    return math.abs(loc.X) < 0.5 and math.abs(loc.Y) < 0.5 and math.abs(loc.Z) < 0.5
end

-- spawnShell: the proven v3 spawn path, parameterised by mesh/material/transform. Returns the
-- spawned StaticMeshActor (Movable, no-collision, material applied) or nil. Game thread only.
-- UE5.4 arg counts: BeginDeferredActorSpawnFromClass = 6 in-args, FinishSpawningActor = 3.
local function spawnShell(world, gs, kml, smaClass, meshObj, matObj, loc, rot, scale)
    local xform = kml:MakeTransform(loc, rot, { X = scale, Y = scale, Z = scale })
    local a = gs:BeginDeferredActorSpawnFromClass(world, smaClass, xform, 1, nil, 1)
    if not valid(a) then return nil end
    local smc = a.StaticMeshComponent
    if not valid(smc) then return nil end
    smc:SetMobility(2)                                  -- Movable (required for runtime spawn)
    smc:SetStaticMesh(meshObj)
    gs:FinishSpawningActor(a, xform, 1)
    if valid(matObj) then smc:SetMaterial(0, matObj) end   -- AFTER finish (pre-finish set is reset)
    pcall(function() smc:SetCollisionEnabled(0) end)       -- NoCollision (don't block the player)
    return a
end

-- apply(outlineActors, beaconPoints): spawn the configured marker(s).
--   outlineActors — live cassette actors to outline per-box (placed sellable extras).
--   beaconPoints  — { {x,y,z}, ... } one hover point per duplicated movie (from marker_math.groupPoints).
-- Returns (outlineCount, beaconCount). Caller (main) must be on the game thread.
function M.apply(outlineActors, beaconPoints)
    local world = UEHelpers.GetWorld()
    local gs    = UEHelpers.GetGameplayStatics()
    local kml   = UEHelpers.GetKismetMathLibrary()
    if not (world and gs and kml) then return 0, 0 end
    local smaClass = StaticFindObject(SMA_CLASS)
    if not valid(smaClass) then return 0, 0 end
    local which      = markerMath.markersFor(Config.MarkerStyle)
    local shellMesh  = StaticFindObject(SHELL_MESH)
    local outMat     = StaticFindObject(OUTLINE_MAT)
    local beaconMesh = StaticFindObject(BEACON_MESH)
    local beaconMat  = StaticFindObject(BEACON_MAT)
    local zoff       = Config.BeaconZOffset or 40
    local bscale     = Config.BeaconScale or 1.3
    local outlines, beacons = 0, 0

    -- per-box outlines (v3 behaviour)
    if which.outline and valid(shellMesh) then
        for _, cart in pairs(outlineActors or {}) do
            pcall(function()
                if not valid(cart) then return end
                local loc = cart:K2_GetActorLocation()
                if isOrigin(loc) then return end             -- never mark backstock (defensive)
                local rot = cart:K2_GetActorRotation()
                local a = spawnShell(world, gs, kml, smaClass, shellMesh, outMat, loc, rot, OUTLINE_SCALE)
                if a then spawned[#spawned + 1] = a; outlines = outlines + 1 end
            end)
        end
    end

    -- ONE pointer per movie, floated above the cluster
    if which.beacon and valid(beaconMesh) then
        local rot0 = { Pitch = 0, Yaw = 0, Roll = 0 }
        for _, pt in pairs(beaconPoints or {}) do
            pcall(function()
                if not (pt and pt.x) then return end
                local bloc = { X = pt.x, Y = pt.y, Z = pt.z + zoff }
                local a = spawnShell(world, gs, kml, smaClass, beaconMesh, beaconMat, bloc, rot0, bscale)
                if a then spawned[#spawned + 1] = a; beacons = beacons + 1 end
            end)
        end
    end

    return outlines, beacons
end

-- clear(): destroy every shell we spawned, then sweep for orphans. A hot reload (or a prior run)
-- loses the Lua refs in `spawned`, so the mesh-match sweep recovers shells we can no longer track
-- (read mesh via the .StaticMesh property — GetStaticMesh() is not exposed, gotcha 12; plain-text
-- find for hyphen-safety — gotcha 13).
function M.clear()
    for _, a in pairs(spawned) do
        pcall(function() if valid(a) then a:K2_DestroyActor() end end)
    end
    spawned = {}
    local actors = FindAllOf("StaticMeshActor") or {}
    for _, a in pairs(actors) do
        pcall(function()
            if not valid(a) or a:GetFullName():find("Default__") then return end
            local smc = a.StaticMeshComponent
            if not valid(smc) then return end
            local m  = smc.StaticMesh
            local nm = m and m:GetFullName()
            if not nm then return end
            for _, tag in ipairs(MESH_TAGS) do
                if nm:find(tag, 1, true) then a:K2_DestroyActor(); return end
            end
        end)
    end
end

return M
