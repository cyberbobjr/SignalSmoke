-- Signal Smoke : fumée colorée, fusées et bâtons lumineux posés par le serveur, vus de tous les joueurs.
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
-- Options de start (toutes facultatives sauf x et y) :
--   x, y, z (entiers), color (nom de SignalSmoke.COLORS ou { r, g, b } de 0 à 1), kind = "smoke"
--   (défaut) | "flare" | "chemlight" ; durée : untilH (heure de monde absolue), sinon realSeconds,
--   sinon minutes (défaut 30) ; radius (0 à 2, cases de fumée), lightRadius (1 à 20), light (défaut
--   true), smoke (défaut true ; toujours false pour "chemlight" : ni fumée ni feu), sound (son en boucle
--   joué près des joueurs), itemId (objet posé au sol suivi : retiré à la fin), spentType (type posé à
--   sa place quand l'entrée échue ou est arrêtée), id (même id : remplace), owner, source ("grenade",
--   "flare", "chemlight", défaut "script"), player (IsoPlayer à l'origine du signal) ou username.
--
-- Entrée du registre : { id, kind, x, y, z, radius, lightRadius, color = { r, g, b }, untilH (heures de
-- monde), light, smoke, sound, itemId, itemType, spentType, owner, source, username }. Les champs
-- ajoutés en 0.2.0 (smoke, lightRadius, source, username, itemType, spentType) sont facultatifs : une
-- entrée sans smoke a de la fumée, sauf pour "chemlight".
--
-- Événements (serveur ou solo seulement ; un abonné inscrit chez un client multijoueur n'est jamais
-- appelé) :
--
--   local function onSignal(event) ... end
--   SignalSmoke.onSignal(onSignal)               -- true si ajouté (pas de doublon)
--   SignalSmoke.removeSignalListener(onSignal)   -- true si retiré
--
-- event = { type = "started" | "stopped" | "expired", id, entry (entrée du registre, à ne pas modifier),
-- source ("grenade", "flare", "chemlight", "script"…), username (compte du joueur à l'origine, si connu :
-- getUsername(), stable en multijoueur ; en solo, c'est le nom du personnage), player (IsoPlayer,
-- seulement pour "started" quand il est connu), reason ("stopped" : "script" ou "pickedUp"),
-- replaced (true si "started" remplace une entrée de même id) }.
-- Chaque abonné est appelé dans un pcall : son erreur est écrite dans le journal et n'empêche pas les
-- autres. Inscrire l'abonné au chargement d'un fichier lu par le serveur (shared ou server).
-- Durées : garder des minutes plutôt que des heures pour la fumée ; en multijoueur, la fumée est un
-- objet local de chaque client (comme la fumée vanilla), ajouté à la liste d'objets de sa case.

local SignalSmoke = {}

SignalSmoke.MODDATA_KEY = "batman_SignalSmoke"
SignalSmoke.VERSION = 1
SignalSmoke.MAX_RADIUS = 2
SignalSmoke.MAX_LIGHT_RADIUS = 20
SignalSmoke.DEFAULT_MINUTES = 30
SignalSmoke.KINDS = { smoke = true, flare = true, chemlight = true }

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

-- Objets du mod ----------------------------------------------------------------------------------

-- Grenades lancées : type complet -> couleur ; improvised = fumigène artisanal (plus court, peut rater).
SignalSmoke.GRENADES = {
    ["SignalSmoke.SmokeGrenadeGreen"] = { color = "green" },
    ["SignalSmoke.SmokeGrenadeRed"] = { color = "red" },
    ["SignalSmoke.SmokeGrenadeYellow"] = { color = "yellow" },
    ["SignalSmoke.SmokeGrenadePurple"] = { color = "purple" },
    ["SignalSmoke.ImprovisedSmokeGreen"] = { color = "green", improvised = true },
    ["SignalSmoke.ImprovisedSmokeRed"] = { color = "red", improvised = true },
    ["SignalSmoke.ImprovisedSmokeYellow"] = { color = "yellow", improvised = true },
    ["SignalSmoke.ImprovisedSmokePurple"] = { color = "purple", improvised = true },
}

-- Bâtons lumineux : couleur -> types éteint (neuf) et activé. Usagé : CHEMLIGHT_USED.
SignalSmoke.CHEMLIGHTS = {
    green = { item = "SignalSmoke.ChemlightGreen", lit = "SignalSmoke.ChemlightGreenLit" },
    red = { item = "SignalSmoke.ChemlightRed", lit = "SignalSmoke.ChemlightRedLit" },
    blue = { item = "SignalSmoke.ChemlightBlue", lit = "SignalSmoke.ChemlightBlueLit" },
    yellow = { item = "SignalSmoke.ChemlightYellow", lit = "SignalSmoke.ChemlightYellowLit" },
}
SignalSmoke.CHEMLIGHT_USED = "SignalSmoke.ChemlightUsed"
-- ModData d'un bâton activé : heure de monde de son extinction (il continue de briller ramassé).
SignalSmoke.CHEMLIGHT_UNTIL_KEY = "ssUntilH"
SignalSmoke.CHEMLIGHT_LIGHT_RADIUS = 3

-- Couleur d'un bâton lumineux d'après son type complet, et s'il est activé ; nil si ce n'en est pas un.
function SignalSmoke.chemlightOf(fullType)
    for color, types in pairs(SignalSmoke.CHEMLIGHTS) do
        if types.item == fullType then return color, false end
        if types.lit == fullType then return color, true end
    end
    return nil
end

-- Options sandbox -------------------------------------------------------------------------------

-- Valeurs par défaut, identiques à media/sandbox-options.txt.
SignalSmoke.DEFAULTS = {
    GrenadeSmokeSeconds = 90,
    FlareBurnMinutes = 60,
    ChemlightHours = 8,
    ImprovisedSmokeSeconds = 45,
    ImprovisedDudChance = 20,
    LootMultiplier = 1.0,
    FlaresInPoliceCars = true,
}

-- Valeur d'une option sandbox « SignalSmoke.<name> ». Lue dans les options Java (à jour même après un
-- changement en cours de partie, que SandboxVars ignore : .claude/pz-knowledge/load-warnings.md), puis
-- SandboxVars, puis la valeur par défaut. Le type est celui de la valeur par défaut.
function SignalSmoke.option(name)
    local default = SignalSmoke.DEFAULTS[name]
    local value
    local options = getSandboxOptions and getSandboxOptions()
    local option = options and options:getOptionByName("SignalSmoke." .. name)
    if option then
        value = option:getValue()
    end
    if value == nil then
        local vars = SandboxVars and SandboxVars.SignalSmoke
        value = vars and vars[name]
    end
    if type(default) == "boolean" then
        if type(value) == "boolean" then return value end
        return default
    end
    return tonumber(value) or default
end

-- Le fumigène artisanal rate-t-il ? roll : tirage de 0 à 99 ; chance : pourcentage de ratés.
function SignalSmoke.isDud(roll, chancePercent)
    return roll < (tonumber(chancePercent) or 0)
end

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

local function optionalString(value)
    return value ~= nil and tostring(value) or nil
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
    if not SignalSmoke.KINDS[kind] then
        return nil, "kind must be smoke, flare or chemlight"
    end
    local hours
    if type(opts.untilH) == "number" then
        hours = opts.untilH - nowH
    elseif type(opts.realSeconds) == "number" then
        hours = SignalSmoke.realSecondsToHours(opts.realSeconds, dayLengthMinutes)
    else
        hours = (tonumber(opts.minutes) or SignalSmoke.DEFAULT_MINUTES) / 60
    end
    if hours <= 0 then
        return nil, "duration must be positive"
    end
    local radius = math.floor(tonumber(opts.radius) or 0)
    local lightRadius = tonumber(opts.lightRadius)
    if lightRadius then
        lightRadius = math.max(1, math.min(SignalSmoke.MAX_LIGHT_RADIUS, math.floor(lightRadius)))
    end
    return {
        id = optionalString(opts.id),
        kind = kind,
        x = opts.x, y = opts.y, z = z,
        radius = math.max(0, math.min(SignalSmoke.MAX_RADIUS, radius)),
        lightRadius = lightRadius,
        color = color,
        untilH = nowH + hours,
        light = opts.light ~= false,
        smoke = kind ~= "chemlight" and opts.smoke ~= false,
        sound = type(opts.sound) == "string" and opts.sound or nil,
        itemId = isInteger(opts.itemId) and opts.itemId or nil,
        itemType = type(opts.itemType) == "string" and opts.itemType or nil,
        spentType = type(opts.spentType) == "string" and opts.spentType or nil,
        owner = optionalString(opts.owner),
        source = optionalString(opts.source) or "script",
        username = type(opts.username) == "string" and opts.username or nil,
    }
end

-- Une entrée est-elle encore active à cette heure de monde ?
function SignalSmoke.isLive(entry, nowH)
    return type(entry) == "table" and type(entry.untilH) == "number" and entry.untilH > nowH
end

-- L'entrée produit-elle de la fumée ? (entrées antérieures à 0.2.0 : pas de champ smoke)
function SignalSmoke.hasSmoke(entry)
    return entry.smoke ~= false and entry.kind ~= "chemlight"
end

-- Événements -----------------------------------------------------------------------------------

local listeners = {}

-- Abonne fn(event) aux signaux (serveur ou solo). Renvoie true si ajouté, false si déjà abonné.
function SignalSmoke.onSignal(fn)
    if type(fn) ~= "function" then
        return false
    end
    for _, listener in ipairs(listeners) do
        if listener == fn then return false end
    end
    listeners[#listeners + 1] = fn
    return true
end

-- Désabonne fn ; renvoie true s'il était abonné. Possible depuis l'abonné lui-même.
function SignalSmoke.removeSignalListener(fn)
    for index, listener in ipairs(listeners) do
        if listener == fn then
            table.remove(listeners, index)
            return true
        end
    end
    return false
end

-- Prévient chaque abonné, isolé par pcall (erreur journalisée). Copie de la liste : un abonné peut se
-- désabonner ou en abonner un autre pendant l'appel.
function SignalSmoke.notify(event)
    local snapshot = {}
    for index, listener in ipairs(listeners) do
        snapshot[index] = listener
    end
    for _, listener in ipairs(snapshot) do
        local ok, err = pcall(listener, event)
        if not ok then
            print("[SignalSmoke] signal listener failed on " .. tostring(event.type) .. " " .. tostring(event.id)
                .. ": " .. tostring(err))
        end
    end
end

local function notifyEntry(eventType, entry, extra)
    local event = { type = eventType, id = entry.id, entry = entry, source = entry.source or "script",
        username = entry.username }
    if extra then
        for key, value in pairs(extra) do
            event[key] = value
        end
    end
    SignalSmoke.notify(event)
end

-- Butin -----------------------------------------------------------------------------------------

-- Réécrit sur place une liste de butin { nom, poids, nom, poids… } : retire les objets du module
-- SignalSmoke, puis ajoute additions = { { type, poids }, … } avec les poids × multiplier (rien si
-- multiplier <= 0). Idempotent : on peut la rappeler après un changement d'option. Renvoie le nombre
-- d'objets ajoutés.
function SignalSmoke.rewriteLootItems(items, additions, multiplier)
    local kept = {}
    local index = 1
    while index <= #items do
        local name = items[index]
        if not (type(name) == "string" and string.sub(name, 1, 12) == "SignalSmoke.") then
            kept[#kept + 1] = name
            kept[#kept + 1] = items[index + 1]
        end
        index = index + 2
    end
    local added = 0
    if (tonumber(multiplier) or 0) > 0 then
        for _, addition in ipairs(additions) do
            kept[#kept + 1] = addition[1]
            kept[#kept + 1] = addition[2] * multiplier
            added = added + 1
        end
    end
    for i = #items, 1, -1 do
        items[i] = nil
    end
    for i, value in ipairs(kept) do
        items[i] = value
    end
    return added
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
SignalSmoke.nowHours = nowHours

local function dayLengthMinutes()
    local options = getSandboxOptions()
    return options and options:getDayLengthMinutes() or 60
end

-- Objet posé d'une entrée (IsoWorldInventoryObject) : (objet, true) s'il est sur sa case, (nil, true)
-- s'il n'y est plus, (nil, false) si la case n'est pas chargée (on ne sait pas). Serveur ou solo.
function SignalSmoke.findItemObject(entry)
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
-- Nom de la 0.1.0, gardé pour les mods qui l'utilisent.
SignalSmoke.findFlareObject = SignalSmoke.findItemObject

-- Fin d'une entrée (stop ou expiration) : son objet quitte le sol (même retrait que le vanilla,
-- ISMoveableSpriteProps.lua:2013-2014) ; spentType, s'il est donné, est posé à sa place (bâton
-- lumineux usagé). Sans effet si la case n'est pas chargée ou si l'objet a été ramassé.
local function removeItemObject(entry)
    if not entry.itemId then return end
    local worldObject = SignalSmoke.findItemObject(entry)
    if not worldObject then return end
    local square = worldObject:getSquare()
    local offX, offY, offZ = worldObject:getOffX(), worldObject:getOffY(), worldObject:getOffZ()
    square:transmitRemoveItemFromSquare(worldObject)
    square:removeWorldObject(worldObject)
    if entry.spentType then
        -- Posé et envoyé aux clients par AddWorldInventoryItem (IsoGridSquare.java:5159-5178).
        square:AddWorldInventoryItem(entry.spentType, offX, offY, offZ)
    end
end

-- Pose une fumée (ou une fusée, un bâton lumineux) ; renvoie son identifiant, ou nil et un message
-- d'erreur. Un identifiant déjà présent est remplacé (appel idempotent).
function SignalSmoke.start(opts)
    if not isAuthority() then
        return nil, "server only"
    end
    local entry, err = SignalSmoke.newEntry(opts, nowHours(), dayLengthMinutes())
    if not entry then
        print("[SignalSmoke] start refused: " .. tostring(err))
        return nil, err
    end
    local player = opts.player
    if player ~= nil and not instanceof(player, "IsoPlayer") then
        player = nil
    end
    if not entry.username and player then
        entry.username = player:getUsername()
    end
    if not entry.id then
        entry.id = "auto:" .. tostring(math.floor(nowHours() * 60)) .. ":" .. tostring(nextAutoId)
        nextAutoId = nextAutoId + 1
    end
    local entries = registry().entries
    local replaced = entries[entry.id] ~= nil
    entries[entry.id] = entry
    publish()
    notifyEntry("started", entry, { player = player, replaced = replaced })
    return entry.id
end

-- Bâton lumineux activé posé au sol (IsoWorldInventoryObject) : inscrit au registre (id
-- "chemlight:<id de l'objet>", idempotent) pour le temps qui lui reste (ModData de l'objet, posée à
-- l'activation ; à défaut, durée pleine à partir de maintenant). Échu : remplacé au sol par un bâton
-- usagé. Serveur ou solo. Renvoie l'identifiant de l'entrée, ou nil.
function SignalSmoke.startChemlight(worldObject, player)
    if not isAuthority() then return nil end
    local item = worldObject and worldObject:getItem()
    local color, isLit = SignalSmoke.chemlightOf(item and item:getFullType())
    if not color or not isLit then return nil end
    local square = worldObject:getSquare()
    local modData = item:getModData()
    local untilH = tonumber(modData[SignalSmoke.CHEMLIGHT_UNTIL_KEY])
    if not untilH then
        untilH = nowHours() + SignalSmoke.option("ChemlightHours")
        modData[SignalSmoke.CHEMLIGHT_UNTIL_KEY] = untilH
    end
    if untilH <= nowHours() then
        local offX, offY, offZ = worldObject:getOffX(), worldObject:getOffY(), worldObject:getOffZ()
        square:transmitRemoveItemFromSquare(worldObject)
        square:removeWorldObject(worldObject)
        square:AddWorldInventoryItem(SignalSmoke.CHEMLIGHT_USED, offX, offY, offZ)
        return nil
    end
    -- Pas de retrait par l'option vanilla de nettoyage du sol (comme ISDropWorldItemAction).
    worldObject:setIgnoreRemoveSandbox(true)
    return SignalSmoke.start{
        id = "chemlight:" .. tostring(item:getID()),
        kind = "chemlight", color = color, untilH = untilH,
        x = square:getX(), y = square:getY(), z = square:getZ(),
        light = true, lightRadius = SignalSmoke.CHEMLIGHT_LIGHT_RADIUS,
        itemId = item:getID(), itemType = item:getFullType(), spentType = SignalSmoke.CHEMLIGHT_USED,
        owner = "SignalSmoke:chemlight", source = "chemlight", player = player,
    }
end

-- Retire une entrée ; renvoie true si elle existait. Son objet posé quitte le sol (remplacé par
-- spentType s'il est donné). reason (facultatif, transmis aux abonnés) : "script" par défaut.
function SignalSmoke.stop(id, reason)
    if not isAuthority() then
        return nil, "server only"
    end
    local data = registry()
    local entry = id ~= nil and data.entries[id] or nil
    if entry == nil then
        return false
    end
    removeItemObject(entry)
    data.entries[id] = nil
    publish()
    notifyEntry("stopped", entry, { reason = reason or "script" })
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
        removeItemObject(entry)
        data.entries[entry.id] = nil
    end
    if #expired > 0 then
        publish()
    end
    for _, entry in ipairs(expired) do
        notifyEntry("expired", entry)
    end
    return expired
end

return SignalSmoke
