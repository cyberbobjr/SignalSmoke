-- Signal Smoke : action « Activer et poser au sol » un bâton lumineux.
-- Même modèle que SignalSmoke_LightFlareAction (ISRepairClothing, 42.21) : en multijoueur, le serveur
-- reconstruit l'action à partir des noms des paramètres de new() (character, item) et n'appelle jamais
-- isValid ; tout est revérifié dans complete(), exécuté sur le serveur (ou en solo). complete() retire
-- le bâton neuf de l'inventaire, pose au sol un bâton activé qui porte son heure d'extinction (ModData)
-- et l'inscrit au registre : chaque client dessine une petite lumière colorée, sans fumée ni son.
-- Ramassé, le bâton reste activé (le temps continue de courir) ; reposé, il brille de nouveau
-- (SignalSmoke_Server.lua) ; échu, il devient un bâton usagé.

require "TimedActions/ISBaseTimedAction"

local SignalSmoke = require "SignalSmoke/SignalSmoke"

SignalSmoke_ActivateChemlightAction = ISBaseTimedAction:derive("SignalSmoke_ActivateChemlightAction")

local DURATION = 40
-- Emballage arraché avant de plier le bâton.
local START_SOUND = "OpenPlasticBag"

-- Couleur d'un bâton neuf (non activé), sinon nil.
local function unlitColor(item)
    local color, isLit = SignalSmoke.chemlightOf(item and item:getFullType())
    if color and not isLit then
        return color
    end
    return nil
end

local function hasItem(character, item)
    local inventory = character:getInventory()
    if isClient() then
        return inventory:containsID(item:getID())
    end
    return inventory:contains(item)
end

function SignalSmoke_ActivateChemlightAction:isValid()
    if unlitColor(self.item) == nil then
        return false
    end
    if isClient() and self.started then
        return true
    end
    return hasItem(self.character, self.item) and self.character:getCurrentSquare() ~= nil
end

function SignalSmoke_ActivateChemlightAction:start()
    if isClient() and self.item then
        self.item = self.character:getInventory():getItemById(self.item:getID())
        self.started = true
    end
    self:setActionAnim("Loot")
    -- Variable d'animation remise à zéro par l'action à la fin (contrairement à SetVariable).
    self:setAnimVariable("LootPosition", "Low")
    self.character:playSound(START_SOUND)
end

function SignalSmoke_ActivateChemlightAction:stop()
    self.started = false
    ISBaseTimedAction.stop(self)
end

function SignalSmoke_ActivateChemlightAction:perform()
    self.started = false
    ISBaseTimedAction.perform(self)
end

-- Serveur ou solo : revérifie tout, puis pose le bâton activé.
function SignalSmoke_ActivateChemlightAction:complete()
    local character, item = self.character, self.item
    local color = unlitColor(item)
    if color == nil then return false end
    local inventory = character:getInventory()
    local square = character:getCurrentSquare()
    if not inventory:contains(item) or square == nil or character:isDead() then return false end
    inventory:Remove(item)
    sendRemoveItemFromContainer(inventory, item)
    local lit = instanceItem(SignalSmoke.CHEMLIGHTS[color].lit)
    if lit == nil then return true end
    -- ModData posée avant la pose : AddWorldInventoryItem envoie l'objet complet aux clients
    -- (.claude/pz-knowledge/world-placement.md, « objet déjà préparé »).
    lit:getModData()[SignalSmoke.CHEMLIGHT_UNTIL_KEY] = SignalSmoke.nowHours() + SignalSmoke.option("ChemlightHours")
    local placed = square:AddWorldInventoryItem(lit, ZombRandFloat(0.3, 0.7), ZombRandFloat(0.3, 0.7), 0, true)
    local worldObject = placed and placed:getWorldItem()
    if worldObject then
        SignalSmoke.startChemlight(worldObject, character)
    end
    return true
end

function SignalSmoke_ActivateChemlightAction:getDuration()
    if self.character:isTimedActionInstant() then
        return 1
    end
    return DURATION
end

function SignalSmoke_ActivateChemlightAction:new(character, item)
    local o = ISBaseTimedAction.new(self, character)
    o.character = character
    o.item = item
    o.maxTime = o:getDuration()
    o.started = false
    return o
end
