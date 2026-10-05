-- Signal Smoke : partie client (et solo). Fabrique et entretient localement ce que décrit le registre
-- du serveur (SignalSmoke.lua) : en multijoueur, la fumée vanilla n'existe que chez les clients
-- (docs/recherche-v1.md, .claude/pz-knowledge/staging-effects.md).
-- Une fois par seconde réelle, pour chaque entrée dont la case est chargée :
-- - fumée : un IsoFire de fumée par case du disque (rayon 0 à 2), marqué de l'identifiant (ModData),
--   teint à chaque passage (la teinte se perd à chaque changement de stade) ; recréé avant qu'il ne
--   s'efface (stade 5) et après un chargement (son minuteur de stade est alors ramené à un tiers).
--   Un feu disparu sans que nous l'ayons éteint (éviction au-delà de 75 feux, IsoFireManager) n'est
--   recréé qu'après un délai, et le mod ne garde pas plus de MAX_OWN_FIRES feux : sinon il évincerait
--   chaque seconde le feu suivant le plus ancien, réels compris ;
-- - lampe de la même couleur : la nuit pour une fumée, toujours pour une fusée ou un bâton lumineux
--   (petit rayon, sans fumée : SignalSmoke.hasSmoke). Couleur divisée par
--   deux (le moteur envoie min(couleur × 2, 1)). Recréée si le moteur l'a retirée (case sortie de la
--   zone chargée) : on teste sa présence dans getLamppostPositions, car getLightSourceAt ne renvoie que
--   la première lampe de la case (une autre lumière au même endroit ferait croire à une perte) ;
-- - son en boucle (fusée, grenade) près d'un joueur local ; un émetteur libre est rendu à la réserve
--   dès qu'il ne joue plus : on en reprend un neuf au lieu de réutiliser l'ancien.
-- Une entrée dont la position, le rayon, le type ou la couleur change (même identifiant) est d'abord
-- nettoyée. Les fusées scintillent (lampe modulée quelques fois par seconde ; l'éclairage est recalculé
-- avec un fondu, un scintillement rapide serait lissé) : OnTick seulement tant qu'une fusée brûle.

local SignalSmoke = require "SignalSmoke/SignalSmoke"

local CHECK_INTERVAL_MS = 1000
-- Vie d'une fumée (unités ≈ 30 par seconde réelle) : stade 4 long, recréée sous RENEW_FRACTION.
local SMOKE_LIFE = 144000
local RENEW_FRACTION = 0.78
local SMOKE_ENERGY = 100
local MAX_OWN_FIRES = 40
local EVICTED_RETRY_MS = 5000
-- En dessous de cette lumière du jour, la fumée a une lampe (sinon elle est assombrie par la nuit).
local NIGHT_DAYLIGHT = 0.45
local SMOKE_LIGHT_RADIUS = 5
local FLARE_LIGHT_RADIUS = 8
local LIGHT_COLOR_FACTOR = 0.5
-- Bâton lumineux : lueur plus douce qu'une fusée.
local CHEMLIGHT_COLOR_FACTOR = 0.35
local FLICKER_INTERVAL_MS = 220
local FLICKER_MIN = 0.45
local SOUND_RANGE = 40
local MARK_KEY = "batmanSS"

-- État local par entrée : { signature, fires = { [clé] = IsoFire }, retryAt = { [clé] = ms }, light,
-- emitter, soundId }.
local live = {}
local lastCheckMs = 0
local lastFlickerMs = 0
local isFlickering = false

local function registryEntries()
    local data = SignalSmoke.registryData()
    return type(data) == "table" and type(data.entries) == "table" and data.entries or {}
end

local function squareKey(x, y, z)
    return x .. "," .. y .. "," .. z
end

-- Cases d'un disque de rayon r autour du centre (r = 1 : une croix de cinq cases).
local function diskOffsets(radius)
    local offsets = {}
    for dx = -radius, radius do
        for dy = -radius, radius do
            if dx * dx + dy * dy <= radius * radius then
                offsets[#offsets + 1] = { dx = dx, dy = dy }
            end
        end
    end
    return offsets
end

local function signature(entry)
    local c = entry.color
    return table.concat({ entry.kind, entry.x, entry.y, entry.z, entry.radius or 0,
        c.r, c.g, c.b, tostring(entry.light), tostring(entry.sound), tostring(SignalSmoke.hasSmoke(entry)),
        tostring(entry.lightRadius) }, "|")
end

local function tint(fire, color)
    local sprites = fire:getAttachedAnimSprite()
    if not sprites then return end
    local tintColor = ColorInfo.new(color.r, color.g, color.b, 1)
    for index = 0, sprites:size() - 1 do
        local parent = sprites:get(index):getParentSprite()
        if parent then
            parent:ChangeTintMod(tintColor)
        end
    end
end

-- A fire whose square lost its chunk (player teleported away) still has an index, but
-- extinctFire then throws in IsoGridSquare.RemoveTileObject (getChunk() null): treat it as gone,
-- the unloaded client-only fire is not saved.
local function isGone(fire)
    if fire == nil or fire:getObjectIndex() == -1 then
        return true
    end
    local square = fire:getSquare()
    return square == nil or square:getChunk() == nil
end

local function countOwnFires()
    local count = 0
    for _, state in pairs(live) do
        for _, fire in pairs(state.fires) do
            if not isGone(fire) then
                count = count + 1
            end
        end
    end
    return count
end

local function createFire(state, entry, square, key, nowMs)
    if countOwnFires() >= MAX_OWN_FIRES or not IsoFire.CanAddSmoke(square, true) then
        state.fires[key] = nil
        return
    end
    local fire = IsoFire.new(getCell(), square, true, SMOKE_ENERGY, SMOKE_LIFE, true)
    square:AddTileObject(fire)
    fire:getModData()[MARK_KEY] = entry.id
    tint(fire, entry.color)
    state.fires[key] = fire
    state.retryAt[key] = nil
end

-- Fumée à cette case : teinte appliquée ; recréée si ancienne (chargement) ou bientôt effacée ; si
-- elle a disparu sans nous (éviction), recréée seulement après un délai.
local function ensureFire(state, entry, square, nowMs)
    local key = squareKey(square:getX(), square:getY(), square:getZ())
    local fire = state.fires[key]
    if fire and not isGone(fire) then
        if fire:getLife() >= SMOKE_LIFE * RENEW_FRACTION then
            tint(fire, entry.color)
            return
        end
        fire:extinctFire()
        createFire(state, entry, square, key, nowMs)
        return
    end
    if fire then
        -- Disparu sans nous : éviction ou extinction par le moteur.
        state.fires[key] = nil
        state.retryAt[key] = nowMs + EVICTED_RETRY_MS
    end
    if state.retryAt[key] and nowMs < state.retryAt[key] then return end
    -- Fumée de la sauvegarde (solo) ou d'une session précédente : minuteur de stade inconnu.
    local existing = square:getFire()
    if existing and existing:getModData()[MARK_KEY] == entry.id then
        existing:extinctFire()
    end
    createFire(state, entry, square, key, nowMs)
end

local function isNight()
    return getClimateManager():getDayLightStrength() < NIGHT_DAYLIGHT
end

local function removeLight(state)
    if state.light then
        getCell():removeLamppost(state.light)
        state.light = nil
    end
end

local function hasLight(state)
    return state.light ~= nil and getCell():getLamppostPositions():contains(state.light)
end

local function lightRadius(entry)
    if entry.lightRadius then return entry.lightRadius end
    if entry.kind == "flare" then return FLARE_LIGHT_RADIUS end
    if entry.kind == "chemlight" then return SignalSmoke.CHEMLIGHT_LIGHT_RADIUS end
    return SMOKE_LIGHT_RADIUS
end

local function ensureLight(state, entry)
    -- Fumée : la nuit seulement ; fusée et bâton lumineux : toujours.
    local wanted = entry.light and (entry.kind ~= "smoke" or isNight())
    if not wanted then
        removeLight(state)
        return
    end
    if hasLight(state) then return end
    removeLight(state)
    local factor = entry.kind == "chemlight" and CHEMLIGHT_COLOR_FACTOR or LIGHT_COLOR_FACTOR
    local c = entry.color
    state.light = getCell():addLamppost(entry.x, entry.y, entry.z, c.r * factor, c.g * factor, c.b * factor,
        lightRadius(entry))
end

local function stopSound(state)
    if state.emitter and state.soundId and state.soundId ~= 0 then
        state.emitter:stopSoundLocal(state.soundId)
    end
    state.emitter, state.soundId = nil, nil
end

-- Un joueur local (écran partagé compris) est-il à portée ?
local function isAnyPlayerNear(entry, range)
    for playerNum = 0, getNumActivePlayers() - 1 do
        local player = getSpecificPlayer(playerNum)
        if player and not player:isDead() then
            local dx, dy = player:getX() - entry.x, player:getY() - entry.y
            if dx * dx + dy * dy <= range * range then
                return true
            end
        end
    end
    return false
end

local function ensureSound(state, entry)
    if not entry.sound or not isAnyPlayerNear(entry, SOUND_RANGE) then
        stopSound(state)
        return
    end
    if state.emitter and state.soundId and state.soundId ~= 0 and state.emitter:isPlaying(state.soundId) then
        return
    end
    -- L'ancien émetteur a pu être rendu à la réserve et donné à un autre : on en prend un neuf.
    state.emitter = getWorld():getFreeEmitter(entry.x + 0.5, entry.y + 0.5, entry.z)
    state.soundId = state.emitter:playSoundLoopedImpl(entry.sound)
end

local function clear(state)
    for _, fire in pairs(state.fires) do
        if not isGone(fire) then
            fire:extinctFire()
        end
    end
    state.fires = {}
    state.retryAt = {}
    removeLight(state)
    stopSound(state)
end

local function onFlickerTick()
    local now = getTimestampMs()
    if now - lastFlickerMs < FLICKER_INTERVAL_MS then return end
    lastFlickerMs = now
    local entries = registryEntries()
    for id, state in pairs(live) do
        local entry = entries[id]
        if state.light and entry and entry.kind == "flare" then
            local k = LIGHT_COLOR_FACTOR * (FLICKER_MIN + ZombRandFloat(0, 1 - FLICKER_MIN))
            state.light:setR(entry.color.r * k)
            state.light:setG(entry.color.g * k)
            state.light:setB(entry.color.b * k)
        end
    end
end

local function setFlickering(wanted)
    if wanted and not isFlickering then
        Events.OnTick.Add(onFlickerTick)
    elseif not wanted and isFlickering then
        Events.OnTick.Remove(onFlickerTick)
    end
    isFlickering = wanted
end

local function update(entry, state, nowMs)
    local sign = signature(entry)
    if state.signature ~= sign then
        clear(state)
        state.signature = sign
    end
    local center = getCell():getGridSquare(entry.x, entry.y, entry.z)
    if not center then
        -- Case hors de la zone chargée : le moteur a déjà retiré objets et lampe.
        state.fires = {}
        state.retryAt = {}
        removeLight(state)
        stopSound(state)
        return false
    end
    if SignalSmoke.hasSmoke(entry) then
        for _, offset in ipairs(diskOffsets(entry.radius or 0)) do
            local square = getCell():getGridSquare(entry.x + offset.dx, entry.y + offset.dy, entry.z)
            if square then
                ensureFire(state, entry, square, nowMs)
            end
        end
    end
    ensureLight(state, entry)
    ensureSound(state, entry)
    return entry.kind == "flare" and state.light ~= nil
end

local function onTick()
    local now = getTimestampMs()
    if now - lastCheckMs < CHECK_INTERVAL_MS then return end
    lastCheckMs = now
    local entries = registryEntries()
    local nowH = getGameTime():getWorldAgeHours()
    local ended = {}
    for id, state in pairs(live) do
        if not SignalSmoke.isLive(entries[id], nowH) then
            clear(state)
            ended[#ended + 1] = id
        end
    end
    -- Kahlua : retraits après le pairs.
    for _, id in ipairs(ended) do
        live[id] = nil
    end
    local anyFlare = false
    for id, entry in pairs(entries) do
        if SignalSmoke.isLive(entry, nowH) then
            live[id] = live[id] or { fires = {}, retryAt = {} }
            if update(entry, live[id], now) then
                anyFlare = true
            end
        end
    end
    setFlickering(anyFlare)
end

-- Solo : fumée marquée restée dans la sauvegarde alors que son entrée a disparu (mod retiré puis remis,
-- entrée échue pendant l'absence) : éteinte quand sa case se charge (après la pose de ses objets,
-- IsoChunk.java:3475-3496).
local function onLoadGridsquare(square)
    local fire = square:getFire()
    local id = fire and fire:getModData()[MARK_KEY]
    if id and not SignalSmoke.isLive(registryEntries()[id], getGameTime():getWorldAgeHours()) then
        fire:extinctFire()
    end
end

local function onReceiveGlobalModData(key, data)
    if key == SignalSmoke.MODDATA_KEY and type(data) == "table" then
        SignalSmoke.setReceived(data)
    end
end

local function onGameStart()
    if isClient() then
        ModData.request(SignalSmoke.MODDATA_KEY)
    end
end

Events.OnTick.Add(onTick)
Events.OnReceiveGlobalModData.Add(onReceiveGlobalModData)
Events.OnGameStart.Add(onGameStart)
if not isClient() then
    Events.LoadGridsquare.Add(onLoadGridsquare)
end
