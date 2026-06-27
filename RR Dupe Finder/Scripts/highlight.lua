-- RR Dupe Finder — in-world markers for sellable duplicate cassettes (UE-bound).
--
-- v4 (static, one-pointer-per-movie). Two marker types, chosen by Config.MarkerStyle:
--   * outline — the v3 amber VHS outline shell ON each duplicate box (good up close).
--   * beacon  — ONE high-contrast pointer floated ABOVE each duplicated movie's cluster of
--               sellable copies, pointing DOWN at it, so it reads from across the store and
--               doesn't clash with the cassette colour. One per movie, NOT one per cassette.
-- Everything is STATIC: a continuous LoopAsync animation hard-crashed the game (async-thread Lua
-- corrupts the VM; see CLAUDE.md + config.lua). Do NOT reintroduce an async animation loop.
-- Colour is fixed by the material asset (DMIs crash — gotcha 10). All mesh/material paths are
-- base-pak (cooked) assets, resolved via StaticFindObject and LoadAsset-on-demand (cooked assets
-- load fine — gotcha 16 only blocked our *additive* custom paks). The beacon mesh/material are
-- chosen from a priority list at scan time and the resolved choice is logged.
local UEHelpers  = require("UEHelpers")
local Config     = require("config")
local markerMath = require("marker_math")

local M = {}
local function log(m) print("[RR-Dupe] " .. m .. "\n") end

-- Outline shell (v3, unchanged) — spawned per duplicate box.
local SHELL_MESH    = "/Game/VideoStore/asset/prop/vhs/LA_VHS_Box_Outline_01.LA_VHS_Box_Outline_01"
local OUTLINE_MAT   = "/Game/VideoStore/core/shader/environment/Neon/M_Opaque_Neon_Tintable.M_Opaque_Neon_Tintable"
local OUTLINE_SCALE = 1.1

-- Beacon pointer candidates (priority order). { pkg = package path for LoadAsset, obj = full
-- Package.Object for StaticFindObject }. First that resolves wins; the choice is logged.
local BEACON_MESHES = {
    { pkg = "/Game/VideoStore/asset/global/Widget3D/SM_3DWidget_Arrow",      obj = "/Game/VideoStore/asset/global/Widget3D/SM_3DWidget_Arrow.SM_3DWidget_Arrow" },
    { pkg = "/Engine/BasicShapes/Cone",                                      obj = "/Engine/BasicShapes/Cone.Cone" },
    { pkg = "/Game/VideoStore/asset/prop/vhs/LA_VHS_Box_Outline_01",         obj = "/Game/VideoStore/asset/prop/vhs/LA_VHS_Box_Outline_01.LA_VHS_Box_Outline_01" },
}
local BEACON_MATS = {
    { pkg = "/Game/VideoStore/core/shader/environment/Neon/M_Opaque_Neon_WhiteCold_01", obj = "/Game/VideoStore/core/shader/environment/Neon/M_Opaque_Neon_WhiteCold_01.M_Opaque_Neon_WhiteCold_01" },
    { pkg = "/Game/VideoStore/core/shader/environment/Neon/M_Opaque_Neon_Tintable",     obj = "/Game/VideoStore/core/shader/environment/Neon/M_Opaque_Neon_Tintable.M_Opaque_Neon_Tintable" },
}

local SMA_CLASS = "/Script/Engine.StaticMeshActor"

local spawned = {}   -- every tracked spawned StaticMeshActor, for clear()

local function valid(o) return o ~= nil and o:IsValid() end
local function isOrigin(loc)
    return math.abs(loc.X) < 0.5 and math.abs(loc.Y) < 0.5 and math.abs(loc.Z) < 0.5
end

-- resolveAsset(candidates, label): return the first candidate that resolves (already loaded, or
-- loadable on demand) and its object path, else nil. Logs the choice. LoadAsset handles cooked
-- assets that aren't resident yet (e.g. the arrow/cone, which nothing references until we ask).
local function resolveAsset(candidates, label)
    for _, c in ipairs(candidates) do
        local o = StaticFindObject(c.obj)
        if not valid(o) then
            pcall(function() LoadAsset(c.pkg) end)
            o = StaticFindObject(c.obj)
        end
        if valid(o) then
            log(("beacon %s = %s"):format(label, c.obj))
            return o, c.obj
        end
    end
    log(("beacon %s = NONE resolved"):format(label))
    return nil
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
--   beaconPoints  — { {x,y,z}, ... } one hover point per duplicated movie (marker_math.groupPoints).
-- Returns (outlineCount, beaconCount). Caller (main) must be on the game thread.
function M.apply(outlineActors, beaconPoints)
    local world = UEHelpers.GetWorld()
    local gs    = UEHelpers.GetGameplayStatics()
    local kml   = UEHelpers.GetKismetMathLibrary()
    if not (world and gs and kml) then return 0, 0 end
    local smaClass = StaticFindObject(SMA_CLASS)
    if not valid(smaClass) then return 0, 0 end
    local which = markerMath.markersFor(Config.MarkerStyle)
    local outlines, beacons = 0, 0

    -- per-box outlines (v3 behaviour)
    if which.outline then
        local shellMesh = StaticFindObject(SHELL_MESH)
        local outMat    = StaticFindObject(OUTLINE_MAT)
        if valid(shellMesh) then
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
    end

    -- ONE pointer per movie, floated above the cluster, pointing down (rotation/scale/offset from config)
    if which.beacon then
        local beaconMesh = resolveAsset(BEACON_MESHES, "mesh")
        local beaconMat  = resolveAsset(BEACON_MATS, "material")
        if valid(beaconMesh) then
            local zoff   = Config.BeaconZOffset or 15
            local bscale = Config.BeaconScale or 0.08
            -- Build a REAL FRotator: MakeTransform ignores a plain {Pitch,Yaw,Roll} Lua table (the
            -- arrow kept rendering at its native/up orientation regardless of BeaconPitch). MakeRotator
            -- takes (Roll, Pitch, Yaw). Fall back to a table if MakeRotator isn't available.
            local rot
            local okR = pcall(function()
                rot = kml:MakeRotator(Config.BeaconRoll or 0, Config.BeaconPitch or 0, Config.BeaconYaw or 0)
            end)
            if not okR or not rot then
                rot = { Pitch = Config.BeaconPitch or 0, Yaw = Config.BeaconYaw or 0, Roll = Config.BeaconRoll or 0 }
            end
            log(("beacon rot via %s (pitch=%s yaw=%s roll=%s)"):format(
                (okR and rot) and "MakeRotator" or "table-fallback",
                tostring(Config.BeaconPitch or 0), tostring(Config.BeaconYaw or 0), tostring(Config.BeaconRoll or 0)))
            for _, pt in pairs(beaconPoints or {}) do
                pcall(function()
                    if not (pt and pt.x) then return end
                    local bloc = { X = pt.x, Y = pt.y, Z = pt.z + zoff }
                    local a = spawnShell(world, gs, kml, smaClass, beaconMesh, beaconMat, bloc, rot, bscale)
                    if a then spawned[#spawned + 1] = a; beacons = beacons + 1 end
                end)
            end
        end
    end

    return outlines, beacons
end

-- clear(): destroy ONLY the markers we spawned (tracked in `spawned`).
--
-- DO NOT sweep FindAllOf("StaticMeshActor") and match by mesh name. LA_VHS_Box_Outline_01 is the
-- game's OWN per-cassette box mesh: a v4 diagnostic (rrdiag) found 544 game StaticMeshActors using
-- it, exactly one per the 544 Cartridge_Base_C/videotape_C in the store, all pre-existing level
-- actors. The old mesh-name sweep K2_DestroyActor'd all of them on F7 (and on the clear at the start
-- of every F6) — that is the "I place duplicates, hit F7, and they vanish until I pick them back up
-- and replace them" bug, and almost certainly the stuck-info-box bug too (destroying a box orphans
-- its Widget3D_PickUp). `spawned` is reliable for the player flow (apply appends; clear resets; a
-- shipped game never hot reloads), so tracking alone is sufficient AND can never touch a game actor.
--
-- Trade-off: a DEV hot reload (Ctrl+R) wipes `spawned`, stranding any live markers until a game
-- restart. That is acceptable (players don't hot reload). If orphan recovery is ever wanted back, do
-- it via a per-actor tag WE set on spawn — never by a mesh name the game itself uses.
function M.clear()
    for _, a in pairs(spawned) do
        pcall(function() if valid(a) then a:K2_DestroyActor() end end)
    end
    spawned = {}
end

return M
