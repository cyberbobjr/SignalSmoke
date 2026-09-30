-- Signal Smoke : fumée colorée et fusées posées par le serveur, vues de tous les joueurs.
-- Module public, à utiliser depuis un autre mod (mod.info : require=\batman_SignalSmoke) :
--
--   local SignalSmoke = require "SignalSmoke/SignalSmoke"
--   local id = SignalSmoke.start{ x = 100, y = 200, z = 0, color = "green", minutes = 30,
--       radius = 1, light = true, id = "monmod:zone", owner = "MonMod" }
--   SignalSmoke.stop(id)
--
-- Serveur ou solo seulement : chez un client multijoueur, start et stop renvoient nil, "server only".
-- Le serveur tient un registre dans une ModData globale, transmise aux clients ; chaque client crée
-- et entretient la fumée, la lampe et le son localement (en multijoueur, la fumée vanilla n'existe
-- que chez les clients : docs/recherche-v1.md). Le registre survit au rechargement.
--
-- Entrée du registre : { id, kind = "smoke" | "flare", x, y, z, radius, color = { r, g, b },
-- untilH (heures de monde), light, sound (son en boucle joué près des joueurs, facultatif),
-- itemId (fusée : objet posé au sol, retiré à l'expiration), owner }.
-- Durées : garder des minutes plutôt que des heures ; en multijoueur, la fumée est un objet local de
-- chaque client (comme la fumée vanilla), ajouté à la liste d'objets de sa case (docs/recherche-v1.md).

local SignalSmoke = {}

SignalSmoke.MODDATA_KEY = "batman_SignalSmoke"
SignalSmoke.VERSION = 1
SignalSmoke.MAX_RADIUS = 2
SignalSmoke.DEFAULT_MINUTES = 30

-- Couleurs nommées (0 à 1). La fumée vanilla est teintée à 0,5 : des couleurs vives restent lisibles.
SignalSmoke.COLORS = {
    green = { r = 0.3, g = 1.0, b = 0.3 },
    red = { r = 1.0, g = 0.25, b = 0.2 },
    yellow = { r = 1.0, g = 0.95, b = 0.25 },
    purple = { r = 0.75, g = 0.3, b = 1.0 },
    orange = { r = 1.0, g = 0.6, b = 0.15 },
    blue = { r = 0.3, g = 0.55, b = 1.0 },
    white = { r = 1.0, g = 1.0, b = 1.0 },
}

local nextAutoId = 1
-- Copie du registre reçue du serveur (client multijoueur), posée par SignalSmoke_Client.
local received = nil

local function clamp01(value)
    return math.max(0, math.min(1, tonumber(value) or 0))
end

-- Couleur { r, g, b } d'après un nom ou une table ; nil si inconnue.
function SignalSmoke.resolveColor(color)
    if type(color) == "string" then
        local named = SignalSmoke.COLORS[color]
        return named and { r = named.r, g = named.g, b = named.b } or nil
    end
    if type(color) == "table" then
        return { r = clamp01(color.r), g = clamp01(color.g), b = clamp01(color.b) }
    end
    return nil
end

local function isInteger(value)
    return type(value) == "number" and value == math.floor(value)
end

-- Heures de monde correspondant à des secondes réelles, pour une journée de dayLengthMinutes minutes
-- réelles (même conversion que le vanilla).
function SignalSmoke.realSecondsToHours(seconds, dayLengthMinutes)
    return seconds * 24 / (math.max(1, dayLengthMinutes) * 60)
end

-- Construit une entrée du registre (fonction pure). nowH : heures de monde ; dayLengthMinutes :
-- durée réelle d'une journée. Renvoie l'entrée, ou nil et un message d'erreur.
function SignalSmoke.newEntry(opts, nowH, dayLengthMinutes)
    if type(opts) ~= "table" then
        return nil, "options must be a table"
    end
    if not (isInteger(opts.x) and isInteger(opts.y)) then
        return nil, "x and y must be integers"
    end
    local z = opts.z or 0
    if not isInteger(z) then
        return nil, "z must be an integer"
    end
    local color = SignalSmoke.resolveColor(opts.color or "green")
    if not color then
        return nil, "unknown color " .. tostring(opts.color)
    end
    local kind = opts.kind or "smoke"
    if kind ~= "smoke" and kind ~= "flare" then
        return nil, "kind must be smoke or flare"
    end
    local hours
    if type(opts.realSeconds) == "number" then
        hours = SignalSmoke.realSecondsToHours(opts.realSeconds, dayLengthMinutes)
    else
        hours = (tonumber(opts.minutes) or SignalSmoke.DEFAULT_MINUTES) / 60
    end
    if hours <= 0 then
        return nil, "duration must be positive"
    end
    local radius = math.floor(tonumber(opts.radius) or 0)
    return {
        id = opts.id and tostring(opts.id) or nil,
        kind = kind,
        x = opts.x, y = opts.y, z = z,
        radius = math.max(0, math.min(SignalSmoke.MAX_RADIUS, radius)),
        color = color,
        untilH = nowH + hours,
        light = opts.light ~= false,
        sound = type(opts.sound) == "string" and opts.sound or nil,
        itemId = isInteger(opts.itemId) and opts.itemId or nil,
        owner = opts.owner and tostring(opts.owner) or nil,
    }
end

-- Une entrée est-elle encore active à cette heure de monde ?
function SignalSmoke.isLive(entry, nowH)
    return type(entry) == "table" and type(entry.untilH) == "number" and entry.untilH > nowH
end

-- Registre (serveur ou solo) ------------------------------------------------------------------

local function isAuthority()
    return not isClient()
end

local function registry()
    local data = ModData.getOrCreate(SignalSmoke.MODDATA_KEY)
    if type(data.entries) ~= "table" then
        data.entries = {}
    end
    data.v = SignalSmoke.VERSION
    return data
end

local function publish()
    if isServer() then
        ModData.transmit(SignalSmoke.MODDATA_KEY)
    end
end

local function nowHours()
    return getGameTime():getWorldAgeHours()
end

local function dayLengthMinutes()
    local options = getSandboxOptions()
    return options and options:getDayLengthMinutes() or 60
end

-- Objet posé d'une fusée (IsoWorldInventoryObject) : (objet, true) s'il est sur sa case, (nil, true)
-- s'il n'y est plus, (nil, false) si la case n'est pas chargée (on ne sait pas). Serveur ou solo.
function SignalSmoke.findFlareObject(entry)
    local square = getCell():getGridSquare(entry.x, entry.y, entry.z)
    if not square then return nil, false end
    local objects = square:getWorldObjects()
    for index = 0, objects:size() - 1 do
        local worldObject = objects:get(index)
        local item = worldObject:getItem()
        if item and item:getID() == entry.itemId then
            return worldObject, true
        end
    end
    return nil, true
end

-- Fusée éteinte (stop ou expiration) : son objet quitte le sol (même retrait que le vanilla,
-- ISMoveableSpriteProps.lua:2013-2014). Sans effet si la case n'est pas chargée.
local function removeFlareObject(entry)
    if entry.kind ~= "flare" or not entry.itemId then return end
    local worldObject = SignalSmoke.findFlareObject(entry)
    if worldObject then
        local square = worldObject:getSquare()
        square:transmitRemoveItemFromSquare(worldObject)
        square:removeWorldObject(worldObject)
    end
end

-- Pose une fumée (ou une fusée) ; renvoie son identifiant, ou nil et un message d'erreur.
-- Un identifiant déjà présent est remplacé (appel idempotent).
function SignalSmoke.start(opts)
    if not isAuthority() then
        return nil, "server only"
    end
    local entry, err = SignalSmoke.newEntry(opts, nowHours(), dayLengthMinutes())
    if not entry then
        print("[SignalSmoke] start refused: " .. tostring(err))
        return nil, err
    end
    if not entry.id then
        entry.id = "auto:" .. tostring(math.floor(nowHours() * 60)) .. ":" .. tostring(nextAutoId)
        nextAutoId = nextAutoId + 1
    end
    registry().entries[entry.id] = entry
    publish()
    return entry.id
end

-- Retire une fumée ; renvoie true si elle existait. Une fusée quitte aussi le sol.
function SignalSmoke.stop(id)
    if not isAuthority() then
        return nil, "server only"
    end
    local data = registry()
    if id == nil or data.entries[id] == nil then
        return false
    end
    removeFlareObject(data.entries[id])
    data.entries[id] = nil
    publish()
    return true
end

-- Registre lisible ici : la ModData en solo et sur le serveur, la copie reçue chez un client MP.
function SignalSmoke.registryData()
    if isClient() then
        return received
    end
    return ModData.get(SignalSmoke.MODDATA_KEY)
end

function SignalSmoke.setReceived(data)
    received = data
end

function SignalSmoke.isActive(id)
    local data = SignalSmoke.registryData()
    local entry = type(data) == "table" and type(data.entries) == "table" and data.entries[id] or nil
    return SignalSmoke.isLive(entry, nowHours())
end

-- Entrées actives : { [id] = entrée } (ne pas les modifier).
function SignalSmoke.list()
    local data = SignalSmoke.registryData()
    local out, now = {}, nowHours()
    if type(data) == "table" and type(data.entries) == "table" then
        for id, entry in pairs(data.entries) do
            if SignalSmoke.isLive(entry, now) then
                out[id] = entry
            end
        end
    end
    return out
end

-- Retire les entrées échues (serveur). Renvoie la liste des entrées retirées.
function SignalSmoke.expire()
    if not isAuthority() then return {} end
    local data, now, expired = registry(), nowHours(), {}
    for _, entry in pairs(data.entries) do
        if not SignalSmoke.isLive(entry, now) then
            expired[#expired + 1] = entry
        end
    end
    -- Kahlua : ne pas retirer de clés pendant un pairs.
    for _, entry in ipairs(expired) do
        removeFlareObject(entry)
        data.entries[entry.id] = nil
    end
    if #expired > 0 then
        publish()
    end
    return expired
end

return SignalSmoke
