-- RR Dupe Finder — in-world highlight of sellable duplicate cassettes (UE-bound).
--
-- The marker is the amber/gold VHS outline shell spawned over each sellable, placed duplicate
-- (recon R3 verdict `marker`; the colour is fixed by the material asset because DMIs hard-crash —
-- gotcha 10). v3 tried to add a literal "DUPLICATE" label and hit two hard walls, so the outline
-- stands as the v3 marker:
--   * custom-pak texture sticker — won't load: this title can't resolve additive (brand-new) asset
--     paths from a mod pak (UE4SS #1101; see docs/.../2026-06-25-rr-dupe-finder-v3-tooling.md);
--   * 3D TextRenderActor label — native-crashes at SetText() (FText marshal; pcall can't catch it).
--     The spawn + component access work; only SetText is hostile. Don't retry without a proven FText
--     idiom (see CLAUDE.md gotcha). Rented copies are excluded upstream (main.sellableDupeActors).
local UEHelpers = require("UEHelpers")

local M = {}

local SHELL_MESH = "/Game/VideoStore/asset/prop/vhs/LA_VHS_Box_Outline_01.LA_VHS_Box_Outline_01"
local MAT_PATH   = "/Game/VideoStore/core/shader/environment/Neon/M_Opaque_Neon_Tintable.M_Opaque_Neon_Tintable"
local SMA_CLASS  = "/Script/Engine.StaticMeshActor"
local SCALE      = 1.1                       -- slightly larger than the cassette (user preference)
local MESH_TAG   = "LA_VHS_Box_Outline_01"   -- substring the orphan sweep matches in clear()

local spawned = {}   -- tracked spawned StaticMeshActors, for clear()

local function valid(o) return o ~= nil and o:IsValid() end
local function isOrigin(loc)
    return math.abs(loc.X) < 0.5 and math.abs(loc.Y) < 0.5 and math.abs(loc.Z) < 0.5
end

-- apply(actors, _colour): spawn an outline shell over each placed cassette actor. `_colour` is
-- informational only — the shell colour is fixed by MAT_PATH (recon R3). Returns the number of
-- shells spawned. Caller (main) must be on the game thread.
function M.apply(actors, _colour)
    local world = UEHelpers.GetWorld()
    local gs    = UEHelpers.GetGameplayStatics()
    local kml   = UEHelpers.GetKismetMathLibrary()
    if not (world and gs and kml) then return 0 end
    local shellMesh = StaticFindObject(SHELL_MESH)
    local mat       = StaticFindObject(MAT_PATH)
    local smaClass  = StaticFindObject(SMA_CLASS)
    if not (valid(shellMesh) and valid(smaClass)) then return 0 end
    local n = 0
    for _, cart in pairs(actors or {}) do
        pcall(function()
            if not valid(cart) then return end
            local loc = cart:K2_GetActorLocation()
            if isOrigin(loc) then return end                 -- never mark backstock (defensive)
            local xform = kml:MakeTransform(loc, cart:K2_GetActorRotation(), { X = SCALE, Y = SCALE, Z = SCALE })
            -- UE5.4 arg counts: BeginDeferredActorSpawnFromClass = 6 in-args, FinishSpawningActor = 3.
            local a = gs:BeginDeferredActorSpawnFromClass(world, smaClass, xform, 1, nil, 1)
            if not valid(a) then return end
            local smc = a.StaticMeshComponent
            if not valid(smc) then return end
            smc:SetMobility(2)                               -- Movable (required for runtime spawn)
            smc:SetStaticMesh(shellMesh)
            gs:FinishSpawningActor(a, xform, 1)
            if valid(mat) then smc:SetMaterial(0, mat) end   -- AFTER finish (pre-finish set is reset)
            pcall(function() smc:SetCollisionEnabled(0) end)            -- NoCollision (don't block the player)
            spawned[#spawned + 1] = a
            n = n + 1
        end)
    end
    return n
end

-- clear(): destroy every shell we spawned, then sweep for orphans. A hot-reload or a prior run loses
-- the Lua refs in `spawned`, so the mesh-match sweep recovers shells we can no longer track. Read the
-- mesh via the .StaticMesh property — GetStaticMesh() is not exposed in this build (gotcha 12).
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
            if nm and nm:find(MESH_TAG) then a:K2_DestroyActor() end
        end)
    end
end

return M
