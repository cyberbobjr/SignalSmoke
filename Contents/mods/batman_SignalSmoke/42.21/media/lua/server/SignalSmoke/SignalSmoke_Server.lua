-- Signal Smoke : partie serveur (et solo). Ce dossier est aussi chargé par les clients multijoueur :
-- rien n'y est fait côté client.
-- - Expiration des entrées du registre, chaque minute de jeu (des minutes peuvent être sautées en
--   vitesse accélérée : on compare les heures, jamais l'égalité).
-- - Grenades du mod : à l'éclatement (OnThrowableExplode, déclenché sur le serveur, docs/recherche-v1.md),
--   une fumée colorée est ajoutée au registre. Leur script a SmokeRange = 0 : pas de fumée grise vanilla.
-- - Fusées posées : si l'objet a disparu de sa case (ramassé), la fusée s'éteint ; consumée
--   (expiration) ou arrêtée, l'objet est retiré du sol (SignalSmoke.lua).
if isClient() then return end

local SignalSmoke = require "SignalSmoke/SignalSmoke"

-- Grenades du mod : type complet -> couleur.
local GRENADE_COLORS = {
    ["SignalSmoke.SmokeGrenadeGreen"] = "green",
    ["SignalSmoke.SmokeGrenadeRed"] = "red",
    ["SignalSmoke.SmokeGrenadeYellow"] = "yellow",
    ["SignalSmoke.SmokeGrenadePurple"] = "purple",
}
-- Durée d'une grenade (secondes réelles) et rayon de la fumée (cases).
local GRENADE_SECONDS = 90
local GRENADE_RADIUS = 1
-- Souffle de la grenade, joué par les clients pendant toute la fumée (celui de l'IsoTrap vanilla
-- s'arrête après ExplosionDuration, environ 25 s).
local GRENADE_SOUND = "SmokeBombLoop"

local function onThrowableExplode(trap, square)
    local item = trap and trap:getItem()
    local color = item and GRENADE_COLORS[item:getFullType()]
    if not color or not square then return end
    SignalSmoke.start{
        x = square:getX(), y = square:getY(), z = square:getZ(),
        color = color, realSeconds = GRENADE_SECONDS, radius = GRENADE_RADIUS, light = true,
        sound = GRENADE_SOUND,
        owner = "SignalSmoke:grenade",
    }
end

-- La fusée posée est-elle encore sur sa case ? nil si la case n'est pas chargée (on ne sait pas).
local function isFlareOnGround(entry)
    local worldObject, isKnown = SignalSmoke.findFlareObject(entry)
    if not isKnown then return nil end
    return worldObject ~= nil
end

-- Expiration (les fusées consumées quittent le sol, SignalSmoke.expire), puis fusées ramassées.
local function onEveryOneMinute()
    SignalSmoke.expire()
    local pickedUp = {}
    for id, entry in pairs(SignalSmoke.list()) do
        if entry.kind == "flare" and entry.itemId and isFlareOnGround(entry) == false then
            pickedUp[#pickedUp + 1] = id
        end
    end
    for _, id in ipairs(pickedUp) do
        SignalSmoke.stop(id)
    end
end

Events.OnThrowableExplode.Add(onThrowableExplode)
Events.EveryOneMinute.Add(onEveryOneMinute)
