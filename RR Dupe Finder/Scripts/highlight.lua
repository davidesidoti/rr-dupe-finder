-- RR Dupe Finder — in-world markers for sellable duplicate cassettes (UE-bound).
--
-- v3 note: the original v3 goal was a custom-pak "DUPLICATE" *texture* sticker, but the S3 load
-- gate proved this title cannot load additive (brand-new) asset paths from a mod pak (UE4SS #1101 —
-- see docs/superpowers/specs/2026-06-25-rr-dupe-finder-v3-tooling.md). So the marker is the union of
-- two pak-free pieces, each Config-gated:
--   * OUTLINE  — the v2 amber/gold VHS outline shell over the cassette (spot it from across the room).
--                Mechanism unchanged from v2 (recon R3 `marker`; DMIs crash gotcha 10, so the colour is
--                fixed by the material asset). This path is proven.
--   * TEXT     — a floating red "DUPLICATE" 3D label via a spawned TextRenderActor (the literal word
--                the texture sticker would have carried). New in v3; fully pcall-guarded so a misbehaving
--                text primitive never breaks the outline.
local UEHelpers = require("UEHelpers")

local M = {}

local SHELL_MESH   = "/Game/VideoStore/asset/prop/vhs/LA_VHS_Box_Outline_01.LA_VHS_Box_Outline_01"
local SHELL_MAT    = "/Game/VideoStore/core/shader/environment/Neon/M_Opaque_Neon_Tintable.M_Opaque_Neon_Tintable"
local SMA_CLASS    = "/Script/Engine.StaticMeshActor"
local TRA_CLASS    = "/Script/Engine.TextRenderActor"
local SHELL_SCALE  = 1.1                       -- slightly larger than the cassette (user preference)
local MESH_TAG     = "LA_VHS_Box_Outline_01"   -- substring the outline orphan-sweep matches in clear()
local LABEL_TEXT   = "DUPLICATE"               -- also the unique key the text orphan-sweep matches
local TEXT_Z       = 20.0                      -- lift the label above the box so it reads

local spawned = {}   -- tracked spawned actors (outline shells AND text actors), for clear()

local function valid(o) return o ~= nil and o:IsValid() end

local function isOrigin(loc)
    return math.abs(loc.X) < 0.5 and math.abs(loc.Y) < 0.5 and math.abs(loc.Z) < 0.5
end

-- Spawn the amber outline shell over a cassette (v2, proven). Tracks the actor.
local function spawnOutline(cart, world, gs, kml, shellMesh, shellMat, smaClass)
    local loc   = cart:K2_GetActorLocation()
    local rot   = cart:K2_GetActorRotation()
    local xform = kml:MakeTransform(loc, rot, { X = SHELL_SCALE, Y = SHELL_SCALE, Z = SHELL_SCALE })
    -- UE5.4 arg counts: BeginDeferredActorSpawnFromClass = 6 in-args, FinishSpawningActor = 3.
    local a = gs:BeginDeferredActorSpawnFromClass(world, smaClass, xform, 1, nil, 1)
    if not valid(a) then return end
    local smc = a.StaticMeshComponent
    if not valid(smc) then return end
    smc:SetMobility(2)                                 -- Movable (required for runtime spawn)
    smc:SetStaticMesh(shellMesh)
    gs:FinishSpawningActor(a, xform, 1)
    if valid(shellMat) then smc:SetMaterial(0, shellMat) end   -- AFTER finish (pre-finish set is reset)
    pcall(function() smc:SetCollisionEnabled(0) end)           -- NoCollision (don't block the player)
    spawned[#spawned + 1] = a
end

-- Spawn a floating red "DUPLICATE" 3D label above a cassette (v3). Tracks the actor.
-- Returns true if the text component was reached + set (so apply() can log whether text worked).
local function spawnText(cart, world, gs, kml, traClass, color, size)
    local loc   = cart:K2_GetActorLocation()
    local pos   = { X = loc.X, Y = loc.Y, Z = loc.Z + TEXT_Z }
    local rot   = { Pitch = 0.0, Yaw = 0.0, Roll = 0.0 }   -- upright, world-aligned (orientation tunable)
    local xform = kml:MakeTransform(pos, rot, { X = 1.0, Y = 1.0, Z = 1.0 })
    local a = gs:BeginDeferredActorSpawnFromClass(world, traClass, xform, 1, nil, 1)
    if not valid(a) then return false end
    gs:FinishSpawningActor(a, xform, 1)
    spawned[#spawned + 1] = a
    -- TextRenderActor exposes its component as the .TextRender property (Get* can be missing — gotcha 12).
    local trc = a.TextRender
    if not valid(trc) then pcall(function() trc = a:GetTextRender() end) end
    if not valid(trc) then return false end
    -- SetText takes an FText; UE4SS marshals a { SourceString = "..." } table, else try a plain string.
    local setOk = pcall(function() trc:SetText({ SourceString = LABEL_TEXT }) end)
    if not setOk then setOk = pcall(function() trc:SetText(LABEL_TEXT) end) end
    pcall(function() trc:SetTextRenderColor(color) end)
    pcall(function() trc:SetWorldSize(size) end)
    pcall(function() trc:SetHorizontalAlignment(1) end)   -- EHTA_Center
    return setOk
end

-- apply(actors, _colour): mark each sellable duplicate with the outline and/or the DUPLICATE text,
-- per Config. `_colour` is informational only (kept for the v2 call signature). Returns the number
-- of cassettes marked. Caller (main) must be on the game thread.
function M.apply(actors, _colour)
    local Config = require("config")
    local world  = UEHelpers.GetWorld()
    local gs     = UEHelpers.GetGameplayStatics()
    local kml    = UEHelpers.GetKismetMathLibrary()
    if not (world and gs and kml) then return 0 end

    local doOutline = Config.OutlineEnabled ~= false
    local doText    = Config.TextLabelEnabled ~= false
    local smaClass  = StaticFindObject(SMA_CLASS)
    local shellMesh = doOutline and StaticFindObject(SHELL_MESH) or nil
    local shellMat  = doOutline and StaticFindObject(SHELL_MAT) or nil
    local traClass  = doText and StaticFindObject(TRA_CLASS) or nil
    local color     = Config.TextColor or { R = 255, G = 0, B = 0, A = 255 }
    local size      = Config.TextWorldSize or 18

    if doOutline and not (valid(shellMesh) and valid(smaClass)) then doOutline = false end
    if doText and not valid(traClass) then doText = false end

    local n, textOk = 0, 0
    for _, cart in pairs(actors or {}) do
        pcall(function()
            if not valid(cart) then return end
            if isOrigin(cart:K2_GetActorLocation()) then return end   -- never mark backstock (defensive)
            if doOutline then spawnOutline(cart, world, gs, kml, shellMesh, shellMat, smaClass) end
            if doText and spawnText(cart, world, gs, kml, traClass, color, size) then textOk = textOk + 1 end
            n = n + 1
        end)
    end
    if Config.Debug then   -- log whether each marker path ran (textSet>0 ⇒ the text primitive worked)
        print(string.format("[RR-Dupe] (debug) markers: %d cassette(s); outline=%s text=%s textSet=%d\n",
            n, tostring(doOutline), tostring(doText), textOk))
    end
    return n
end

-- clear(): destroy every actor we spawned, then orphan-sweep (a hot-reload loses the tracked refs):
--   * outline shells — matched by their mesh tag (LA_VHS_Box_Outline_01);
--   * DUPLICATE text — matched by their (unique) text content "DUPLICATE" (the game uses no such actor).
-- The tracked set is primary; the sweeps recover marks left after a Ctrl+R.
function M.clear()
    for _, a in pairs(spawned) do
        pcall(function() if valid(a) then a:K2_DestroyActor() end end)
    end
    spawned = {}
    -- 1) outline shells by mesh (read .StaticMesh property; GetStaticMesh() not exposed — gotcha 12)
    pcall(function()
        for _, a in pairs(FindAllOf("StaticMeshActor") or {}) do
            pcall(function()
                if not valid(a) or a:GetFullName():find("Default__") then return end
                local smc = a.StaticMeshComponent
                if not valid(smc) then return end
                local m  = smc.StaticMesh
                local nm = m and m:GetFullName()
                if nm and nm:find(MESH_TAG) then a:K2_DestroyActor() end
            end)
        end
    end)
    -- 2) our DUPLICATE text actors by their text content
    pcall(function()
        for _, a in pairs(FindAllOf("TextRenderActor") or {}) do
            pcall(function()
                if not valid(a) or a:GetFullName():find("Default__") then return end
                local trc = a.TextRender
                if not valid(trc) then return end
                local ok2, s = pcall(function() return trc.Text:ToString() end)
                if ok2 and s == LABEL_TEXT then a:K2_DestroyActor() end
            end)
        end
    end)
end

return M
