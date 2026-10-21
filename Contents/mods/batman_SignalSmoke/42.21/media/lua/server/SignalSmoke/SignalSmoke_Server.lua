-- Signal Smoke : partie serveur (et solo). Ce dossier est aussi chargé par les clients multijoueur :
-- rien n'y est fait côté client.
-- - Expiration des entrées du registre, chaque minute de jeu (des minutes peuvent être sautées en
--   vitesse accélérée : on compare les heures, jamais l'égalité).
-- - Grenades du mod : à l'éclatement (OnThrowableExplode, déclenché sur le serveur, docs/annexes/recherches/recherche-v1.md),
--   une fumée colorée est ajoutée au registre. Leur script a SmokeRange = 0 : pas de fumée grise vanilla.
--   Le fumigène artisanal dure moins longtemps et peut rater (options sandbox) : il siffle sans fumer.
--   Le lanceur est connu par trap:getAttacker() (IsoTrap créé avec le joueur, AddExplosiveTrapPacket).
-- - Fusées et bâtons lumineux posés : si l'objet a disparu de sa case (ramassé), l'entrée s'arrête ;
--   consumée (expiration) ou arrêtée, la fusée quitte le sol, le bâton lumineux devient un bâton usagé.
--   Leur heure de fin est dans la ModData de l'objet (SignalSmoke.markItemObject), qui le suit.
-- - Fusées allumées et bâtons lumineux activés reposés par le joueur (lâcher, poser, glisser vers le
--   sol : plusieurs chemins vanilla, docs/annexes/recherches/recherche-v2.md) : repérés près des joueurs
--   chaque minute et réinscrits avec leur temps restant (SignalSmoke.startFlare, startChemlight). Le même
--   sondage rattrape un objet resté au sol parce que sa case n'était pas chargée à son expiration. Échus,
--   la fusée disparaît et le bâton devient un bâton usagé, au sol comme dans l'inventaire des joueurs
--   (sacs portés compris).
-- - Au chargement, migration du registre (SignalSmoke.migrate : comptes des joueurs retirés).
if isClient() then return end

local SignalSmoke = require "SignalSmoke/SignalSmoke"

-- Rayon de la fumée d'une grenade (cases).
local GRENADE_RADIUS = 1
-- Souffle de la grenade, joué par les clients pendant toute la fumée (celui de l'IsoTrap vanilla
-- s'arrête après ExplosionDuration, environ 25 s).
local GRENADE_SOUND = "SmokeBombLoop"
-- Fusées et bâtons lumineux : rayon de recherche autour des joueurs (cases) et période du contrôle des
-- inventaires (minutes de jeu).
local CHEMLIGHT_SCAN_RADIUS = 2
local INVENTORY_CHECK_MINUTES = 10

local minutesSinceInventoryCheck = 0

local function onThrowableExplode(trap, square)
    local item = trap and trap:getItem()
    local grenade = item and SignalSmoke.GRENADES[item:getFullType()]
    if not grenade or not square then return end
    local seconds = SignalSmoke.option("GrenadeSmokeSeconds")
    if grenade.improvised then
        if SignalSmoke.isDud(ZombRand(100), SignalSmoke.option("ImprovisedDudChance")) then
            return
        end
        seconds = SignalSmoke.option("ImprovisedSmokeSeconds")
    end
    local attacker = trap:getAttacker()
    SignalSmoke.start{
        x = square:getX(), y = square:getY(), z = square:getZ(),
        color = grenade.color, realSeconds = seconds, radius = GRENADE_RADIUS, light = true,
        sound = GRENADE_SOUND, itemType = item:getFullType(),
        owner = "SignalSmoke:grenade", source = "grenade",
        player = instanceof(attacker, "IsoPlayer") and attacker or nil,
    }
end

-- L'objet posé est-il encore sur sa case ? nil si la case n'est pas chargée (on ne sait pas). Sur sa
-- case, il reçoit son heure de fin (entrées posées avant 0.3.0 ou par un autre mod sans placeFlare).
local function isItemOnGround(entry)
    local worldObject, isKnown = SignalSmoke.findItemObject(entry)
    if not isKnown then return nil end
    if worldObject then
        SignalSmoke.markItemObject(entry, worldObject)
    end
    return worldObject ~= nil
end

-- Joueurs vivants gérés ici : connectés (serveur) ou locaux (solo, écran partagé compris).
local function players()
    local out = {}
    if isServer() then
        local online = getOnlinePlayers()
        for index = 0, online:size() - 1 do
            out[#out + 1] = online:get(index)
        end
    else
        for playerNum = 0, getNumActivePlayers() - 1 do
            out[#out + 1] = getSpecificPlayer(playerNum)
        end
    end
    local alive = {}
    for _, player in ipairs(out) do
        if player and not player:isDead() then
            alive[#alive + 1] = player
        end
    end
    return alive
end

local function itemUntil(item)
    return tonumber(item:getModData()[SignalSmoke.UNTIL_KEY])
end

-- Fusée allumée ou bâton activé, et la fonction qui l'inscrit au registre ; nil sinon.
local function trackedStarter(item)
    local fullType = item and item:getFullType()
    if fullType == SignalSmoke.FLARE_LIT_TYPE then
        return SignalSmoke.startFlare
    end
    local color, isLit = SignalSmoke.chemlightOf(fullType)
    if color and isLit then
        return SignalSmoke.startChemlight
    end
    return nil
end

-- Fusées allumées et bâtons activés posés près des joueurs mais absents du registre (reposés après un
-- ramassage, ou restés au sol après une expiration sur une case non chargée).
local function scanTrackedNear(player, liveItemIds)
    local square = player:getCurrentSquare()
    if not square then return end
    local cell = getCell()
    for dx = -CHEMLIGHT_SCAN_RADIUS, CHEMLIGHT_SCAN_RADIUS do
        for dy = -CHEMLIGHT_SCAN_RADIUS, CHEMLIGHT_SCAN_RADIUS do
            local near = cell:getGridSquare(square:getX() + dx, square:getY() + dy, square:getZ())
            local objects = near and near:getWorldObjects()
            if objects and objects:size() > 0 then
                local found = {}
                for index = 0, objects:size() - 1 do
                    local worldObject = objects:get(index)
                    local item = worldObject:getItem()
                    local starter = trackedStarter(item)
                    if starter and not liveItemIds[item:getID()] then
                        found[#found + 1] = { worldObject = worldObject, starter = starter }
                    end
                end
                -- Hors de la boucle : startFlare et startChemlight peuvent retirer un objet de la case.
                for _, tracked in ipairs(found) do
                    liveItemIds[tracked.worldObject:getItem():getID()] = true
                    tracked.starter(tracked.worldObject, player)
                end
            end
        end
    end
end

-- Objets de ce type échus dans l'inventaire d'un joueur (sacs compris) : retirés, et remplacés par
-- spentType s'il est donné. Ceux qui sont tenus en main ou accrochés attendent d'être rangés ou posés.
-- Sans heure de fin (unknownIsSpent) : fusée allumée avant 0.3.0, restée « allumée » pour toujours.
local function expireCarried(player, fullType, spentType, unknownIsSpent)
    local now = SignalSmoke.nowHours()
    local items = player:getInventory():getAllTypeRecurse(fullType)
    -- Liste à part : on retire des objets des conteneurs pendant le parcours.
    local spent = {}
    for index = 0, items:size() - 1 do
        local item = items:get(index)
        local untilH = itemUntil(item)
        local isSpent = (untilH and untilH <= now) or (untilH == nil and unknownIsSpent)
        if isSpent and item:getContainer() and not player:isEquipped(item) and not player:isAttachedItem(item) then
            spent[#spent + 1] = item
        end
    end
    for _, item in ipairs(spent) do
        local container = item:getContainer()
        container:Remove(item)
        sendRemoveItemFromContainer(container, item)
        if spentType then
            local used = container:AddItem(spentType)
            if used then
                sendAddItemToContainer(container, used)
            end
        end
    end
end

-- Expiration (les objets posés quittent le sol, SignalSmoke.expire), objets ramassés, puis fusées et
-- bâtons lumineux reposés ou restés au sol, et ceux qui sont échus dans les inventaires.
local function onEveryOneMinute()
    SignalSmoke.expire()
    local pickedUp = {}
    local liveItemIds = {}
    for id, entry in pairs(SignalSmoke.list()) do
        if entry.itemId then
            if isItemOnGround(entry) == false then
                pickedUp[#pickedUp + 1] = id
            else
                liveItemIds[entry.itemId] = true
            end
        end
    end
    for _, id in ipairs(pickedUp) do
        SignalSmoke.stop(id, "pickedUp")
    end
    local everyone = players()
    for _, player in ipairs(everyone) do
        scanTrackedNear(player, liveItemIds)
    end
    minutesSinceInventoryCheck = minutesSinceInventoryCheck + 1
    if minutesSinceInventoryCheck >= INVENTORY_CHECK_MINUTES then
        minutesSinceInventoryCheck = 0
        for _, player in ipairs(everyone) do
            for _, types in pairs(SignalSmoke.CHEMLIGHTS) do
                expireCarried(player, types.lit, SignalSmoke.CHEMLIGHT_USED, false)
            end
            expireCarried(player, SignalSmoke.FLARE_LIT_TYPE, nil, true)
        end
    end
end

-- Registre chargé : retire les comptes des joueurs sauvegardés par une version antérieure (0.2.3),
-- avant que les clients ne le demandent.
local function onInitGlobalModData()
    SignalSmoke.migrate()
end

Events.OnInitGlobalModData.Add(onInitGlobalModData)
Events.OnThrowableExplode.Add(onThrowableExplode)
Events.EveryOneMinute.Add(onEveryOneMinute)
