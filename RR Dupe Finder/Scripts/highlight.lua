-- RR Dupe Finder — in-world markers for sellable duplicate cassettes (UE-bound).
--
-- v4: two marker types, chosen by Config.MarkerStyle ("outline" | "beacon" | "both"):
--   * outline — the v3 amber VHS outline shell ON the box (good up close on non-amber boxes).
--   * beacon  — a high-contrast marker floated ABOVE the box (Task 4 adds bob + spin), so it
--               stays visible when the cassette's own colour matches the outline and reads from
--               across the store.
-- Colour is fixed by the material asset (DMIs hard-crash — gotcha 10); additive mod-pak assets
-- won't load (gotcha 16), so every mesh/material here is a base-pak path. The beacon mesh/material
-- ship as known-loadable FALLBACK values (= the outline mesh + its neon material, floated above);
-- recon (plan Task 6) upgrades BEACON_MAT (and maybe BEACON_MESH) to a higher-contrast colour.
local UEHelpers  = require("UEHelpers")
local Config     = require("config")
local markerMath = require("marker_math")

local M = {}

-- Outline shell (v3, unchanged).
local SHELL_MESH    = "/Game/VideoStore/asset/prop/vhs/LA_VHS_Box_Outline_01.LA_VHS_Box_Outline_01"
local OUTLINE_MAT   = "/Game/VideoStore/core/shader/environment/Neon/M_Opaque_Neon_Tintable.M_Opaque_Neon_Tintable"
local OUTLINE_SCALE = 1.1

-- Beacon (floated above). FALLBACK values below; recon replaces them (and appends the beacon
-- mesh name to MESH_TAGS if BEACON_MESH changes). See the spec Appendix for the chosen values.
local BEACON_MESH = "/Game/VideoStore/asset/prop/vhs/LA_VHS_Box_Outline_01.LA_VHS_Box_Outline_01"
local BEACON_MAT  = "/Game/VideoStore/core/shader/environment/Neon/M_Opaque_Neon_Tintable.M_Opaque_Neon_Tintable"

local SMA_CLASS = "/Script/Engine.StaticMeshActor"

-- Mesh-name substrings the orphan sweep matches in clear() (plain-text find — gotcha 13). Both
-- markers reuse the outline mesh in the fallback; recon appends the beacon mesh name if it differs.
local MESH_TAGS = { "LA_VHS_Box_Outline_01" }

local spawned = {}   -- every tracked spawned StaticMeshActor, for clear()
local beacons = {}   -- animated beacons: { actor, baseX, baseY, baseZ, baseYaw, phaseOffset }

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
    smc:SetMobility(2)                                  -- Movable (required for runtime spawn + animation)
    smc:SetStaticMesh(meshObj)
    gs:FinishSpawningActor(a, xform, 1)
    if valid(matObj) then smc:SetMaterial(0, matObj) end   -- AFTER finish (pre-finish set is reset)
    pcall(function() smc:SetCollisionEnabled(0) end)       -- NoCollision (don't block the player)
    return a
end

-- apply(actors, _colour): spawn the configured marker(s) over each placed cassette actor. `_colour`
-- is informational only (recon R3; colour is fixed by the material). Returns the number of cassettes
-- marked. Caller (main) must be on the game thread. (Task 4 starts the animation driver here.)
function M.apply(actors, _colour)
    local world = UEHelpers.GetWorld()
    local gs    = UEHelpers.GetGameplayStatics()
    local kml   = UEHelpers.GetKismetMathLibrary()
    if not (world and gs and kml) then return 0 end
    local smaClass   = StaticFindObject(SMA_CLASS)
    if not valid(smaClass) then return 0 end
    local which      = markerMath.markersFor(Config.MarkerStyle)
    local shellMesh  = StaticFindObject(SHELL_MESH)
    local outMat     = StaticFindObject(OUTLINE_MAT)
    local beaconMesh = StaticFindObject(BEACON_MESH)
    local beaconMat  = StaticFindObject(BEACON_MAT)
    local zoff       = Config.BeaconZOffset or 40
    local bscale     = Config.BeaconScale or 1.3
    local n = 0
    for _, cart in pairs(actors or {}) do
        pcall(function()
            if not valid(cart) then return end
            local loc = cart:K2_GetActorLocation()
            if isOrigin(loc) then return end                 -- never mark backstock (defensive)
            local rot = cart:K2_GetActorRotation()
            local marked = false
            if which.outline and valid(shellMesh) then
                local a = spawnShell(world, gs, kml, smaClass, shellMesh, outMat, loc, rot, OUTLINE_SCALE)
                if a then spawned[#spawned + 1] = a; marked = true end
            end
            if which.beacon and valid(beaconMesh) then
                local bloc = { X = loc.X, Y = loc.Y, Z = loc.Z + zoff }
                local a = spawnShell(world, gs, kml, smaClass, beaconMesh, beaconMat, bloc, rot, bscale)
                if a then
                    spawned[#spawned + 1] = a
                    beacons[#beacons + 1] = {
                        actor = a, baseX = bloc.X, baseY = bloc.Y, baseZ = bloc.Z,
                        baseYaw = (rot and rot.Yaw) or 0, phaseOffset = #beacons * 0.7,
                    }
                    marked = true
                end
            end
            if marked then n = n + 1 end
        end)
    end
    return n
end

-- clear(): destroy every shell we spawned, then sweep for orphans. A hot reload (or a prior run)
-- loses the Lua refs in `spawned`/`beacons`, so the mesh-match sweep recovers shells we can no
-- longer track (read mesh via the .StaticMesh property — GetStaticMesh() is not exposed, gotcha 12;
-- plain-text find for hyphen-safety — gotcha 13). (Task 4 also bumps the animation epoch here.)
function M.clear()
    for _, a in pairs(spawned) do
        pcall(function() if valid(a) then a:K2_DestroyActor() end end)
    end
    spawned = {}
    beacons = {}
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
