-- RR Dupe Finder — in-world highlight of placed duplicate cassettes (UE-bound)
--
-- R3 verdict (v2 recon) = `marker`: spawn the game's VHS outline shell over each PLACED
-- duplicate, materialled with a static amber/gold neon. The other mechanisms were rejected in
-- recon: `SetOverlayMaterial` only whole-mesh-fills (no border), `SetRenderCustomDepth` draws
-- nothing in this Shipping build (gotcha 1), the cassette has no hidden outline component, and
-- `CreateDynamicMaterialInstance` HARD-CRASHES the process (gotcha 10) — so the colour is fixed
-- by the material asset, not Config.TintColor. Spawn recipe + asset paths are from the recon doc
-- (docs/superpowers/specs/2026-06-24-rr-dupe-finder-v2-recon.md, R3) — do NOT guess these.
local UEHelpers = require("UEHelpers")

local M = {}

local SHELL_MESH = "/Game/VideoStore/asset/prop/vhs/LA_VHS_Box_Outline_01.LA_VHS_Box_Outline_01"
local MAT_PATH   = "/Game/VideoStore/core/shader/environment/Neon/M_Opaque_Neon_Tintable.M_Opaque_Neon_Tintable"
local SMA_CLASS  = "/Script/Engine.StaticMeshActor"
local SCALE      = 1.1                       -- slightly larger than the cassette (user preference)
local MESH_TAG   = "LA_VHS_Box_Outline_01"   -- substring the orphan sweep matches in clear()

local spawned = {}   -- tracked spawned StaticMeshActors, for clear()

local function isOrigin(loc)
    return math.abs(loc.X) < 0.5 and math.abs(loc.Y) < 0.5 and math.abs(loc.Z) < 0.5
end

-- apply(actors, colour): spawn an outline shell over each placed cassette actor.
-- `colour` is informational only — the shell colour is fixed by MAT_PATH (recon R3).
-- Returns the number of shells spawned. Caller (main) must be on the game thread.
function M.apply(actors, colour)
    local world = UEHelpers.GetWorld()
    local gs    = UEHelpers.GetGameplayStatics()
    local kml   = UEHelpers.GetKismetMathLibrary()
    if not (world and gs and kml) then return 0 end
    local shellMesh = StaticFindObject(SHELL_MESH)
    local mat       = StaticFindObject(MAT_PATH)
    local smaClass  = StaticFindObject(SMA_CLASS)
    if not (shellMesh and shellMesh:IsValid()) then return 0 end
    if not (smaClass and smaClass:IsValid()) then return 0 end
    local n = 0
    for _, cart in pairs(actors or {}) do
        pcall(function()
            if not cart or not cart:IsValid() then return end
            local loc = cart:K2_GetActorLocation()
            if isOrigin(loc) then return end                 -- never mark backstock (defensive)
            local rot   = cart:K2_GetActorRotation()
            local xform = kml:MakeTransform(loc, rot, { X = SCALE, Y = SCALE, Z = SCALE })
            -- UE5.4 arg counts: BeginDeferredActorSpawnFromClass = 6 in-args, FinishSpawningActor = 3.
            local a = gs:BeginDeferredActorSpawnFromClass(world, smaClass, xform, 1, nil, 1)
            if not a or not a:IsValid() then return end
            local smc = a.StaticMeshComponent
            if not smc or not smc:IsValid() then return end
            smc:SetMobility(2)                               -- Movable (required for runtime spawn)
            smc:SetStaticMesh(shellMesh)
            gs:FinishSpawningActor(a, xform, 1)
            if mat and mat:IsValid() then smc:SetMaterial(0, mat) end   -- AFTER finish (pre-finish set is reset)
            pcall(function() smc:SetCollisionEnabled(0) end)            -- NoCollision (don't block the player)
            spawned[#spawned + 1] = a
            n = n + 1
        end)
    end
    return n
end

-- clear(): destroy every shell we spawned, then sweep for orphans. A hot-reload or a prior run
-- loses the Lua refs in `spawned`, so the mesh-match sweep recovers tints we can no longer track.
-- Ownership caveat (recon R3): the sweep assumes the game never places its own
-- LA_VHS_Box_Outline_01 StaticMeshActors (held true during recon). The tracked set is primary.
function M.clear()
    for _, a in pairs(spawned) do
        pcall(function() if a and a:IsValid() then a:K2_DestroyActor() end end)
    end
    spawned = {}
    local actors = FindAllOf("StaticMeshActor") or {}
    for _, a in pairs(actors) do
        pcall(function()
            if not a or not a:IsValid() then return end
            if a:GetFullName():find("Default__") then return end
            local smc = a.StaticMeshComponent
            if not smc or not smc:IsValid() then return end
            -- NB: smc:GetStaticMesh() is NOT exposed in this UE4SS build (returns nil / throws,
            -- proven via the rrsweepdbg probe); the StaticMesh *property* is the read accessor
            -- that works. The Set* methods (apply) work fine — it's only the Get method missing.
            local m  = smc.StaticMesh
            local nm = m and m:GetFullName()
            if nm and nm:find(MESH_TAG) then
                a:K2_DestroyActor()
            end
        end)
    end
end

return M
