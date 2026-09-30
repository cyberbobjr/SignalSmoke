-- Signal Smoke : action « Allumer et poser » une fusée de route.
-- Modèle vanilla : ISRepairClothing (42.21). En multijoueur, le serveur reconstruit l'action à partir
-- des noms des paramètres de new() (character, item) et n'appelle jamais isValid : tout est revérifié
-- dans complete(), exécuté sur le serveur (ou en solo). complete() retire la fusée de l'inventaire, pose
-- une fusée entamée au sol (envoyée aux clients par AddWorldInventoryItem) et l'inscrit au registre :
-- chaque client dessine la lumière rouge qui scintille, un peu de fumée rouge et le son.

require "TimedActions/ISBaseTimedAction"

local SignalSmoke = require "SignalSmoke/SignalSmoke"

SignalSmoke_LightFlareAction = ISBaseTimedAction:derive("SignalSmoke_LightFlareAction")

SignalSmoke_LightFlareAction.FLARE_TYPE = "SignalSmoke.RoadFlare"
SignalSmoke_LightFlareAction.LIT_TYPE = "SignalSmoke.RoadFlareLit"
-- Durée de combustion, en minutes de jeu.
SignalSmoke_LightFlareAction.BURN_MINUTES = 60

local DURATION = 60
-- Grésillement de la fusée allumée, joué par les clients tant qu'elle brûle.
local BURN_SOUND = "SmokeBombLoop"

local function hasFlare(character, item)
    local inventory = character:getInventory()
    if isClient() then
        return inventory:containsID(item:getID())
    end
    return inventory:contains(item)
end

function SignalSmoke_LightFlareAction:isValid()
    if self.item == nil or self.item:getFullType() ~= SignalSmoke_LightFlareAction.FLARE_TYPE then
        return false
    end
    if isClient() and self.started then
        return true
    end
    return hasFlare(self.character, self.item) and self.character:getCurrentSquare() ~= nil
end

function SignalSmoke_LightFlareAction:start()
    if isClient() and self.item then
        self.item = self.character:getInventory():getItemById(self.item:getID())
        self.started = true
    end
    self:setActionAnim("Loot")
    -- Variable d'animation remise à zéro par l'action à la fin (contrairement à SetVariable).
    self:setAnimVariable("LootPosition", "Low")
    self.character:playSound("UseLighter")
end

function SignalSmoke_LightFlareAction:stop()
    self.started = false
    ISBaseTimedAction.stop(self)
end

function SignalSmoke_LightFlareAction:perform()
    self.started = false
    ISBaseTimedAction.perform(self)
end

-- Serveur ou solo : revérifie tout, puis pose la fusée allumée.
function SignalSmoke_LightFlareAction:complete()
    local character, item = self.character, self.item
    if item == nil or item:getFullType() ~= SignalSmoke_LightFlareAction.FLARE_TYPE then return false end
    local inventory = character:getInventory()
    local square = character:getCurrentSquare()
    if not inventory:contains(item) or square == nil or character:isDead() then return false end
    inventory:Remove(item)
    sendRemoveItemFromContainer(inventory, item)
    local lit = square:AddWorldInventoryItem(SignalSmoke_LightFlareAction.LIT_TYPE, ZombRandFloat(0.3, 0.7),
        ZombRandFloat(0.3, 0.7), 0)
    if lit then
        -- Pas de retrait par l'option vanilla de nettoyage du sol (comme ISDropWorldItemAction).
        local worldItem = lit:getWorldItem()
        if worldItem then
            worldItem:setIgnoreRemoveSandbox(true)
        end
        SignalSmoke.start{
            kind = "flare", color = "red", radius = 0, light = true,
            x = square:getX(), y = square:getY(), z = square:getZ(),
            minutes = SignalSmoke_LightFlareAction.BURN_MINUTES, itemId = lit:getID(),
            sound = BURN_SOUND, owner = "SignalSmoke:flare",
        }
    end
    return true
end

function SignalSmoke_LightFlareAction:getDuration()
    if self.character:isTimedActionInstant() then
        return 1
    end
    return DURATION
end

function SignalSmoke_LightFlareAction:new(character, item)
    local o = ISBaseTimedAction.new(self, character)
    o.character = character
    o.item = item
    o.maxTime = o:getDuration()
    o.started = false
    return o
end
