-- Signal Smoke : menu contextuel de l'inventaire.
-- - Fusée de route : « Allumer et poser au sol ».
-- - Bâton lumineux neuf : « Activer et poser au sol ». Un bâton déjà activé se pose par les gestes
--   vanilla (lâcher, poser, glisser vers le sol) : le serveur le repère et le rallume
--   (SignalSmoke_Server.lua).
-- L'objet est d'abord ramené dans l'inventaire principal (sac porté, sol…), puis l'action le pose.

require "TimedActions/ISTimedActionQueue"
require "TimedActions/SignalSmoke_LightFlareAction"
require "TimedActions/SignalSmoke_ActivateChemlightAction"

local SignalSmoke = require "SignalSmoke/SignalSmoke"

local function onLightFlare(player, item)
    ISInventoryPaneContextMenu.transferIfNeeded(player, item)
    ISTimedActionQueue.add(SignalSmoke_LightFlareAction:new(player, item))
end

local function onActivateChemlight(player, item)
    ISInventoryPaneContextMenu.transferIfNeeded(player, item)
    ISTimedActionQueue.add(SignalSmoke_ActivateChemlightAction:new(player, item))
end

local function onFillInventoryObjectContextMenu(playerNum, context, items)
    local player = getSpecificPlayer(playerNum)
    if not player then return end
    for _, entry in ipairs(items) do
        local item = entry
        if not instanceof(entry, "InventoryItem") then
            item = entry.items and entry.items[1]
        end
        local fullType = item and item:getFullType()
        if fullType == SignalSmoke_LightFlareAction.FLARE_TYPE then
            context:addOption(getText("ContextMenu_SignalSmoke_LightFlare"), player, onLightFlare, item)
            return
        end
        local color, isLit = SignalSmoke.chemlightOf(fullType)
        if color and not isLit then
            context:addOption(getText("ContextMenu_SignalSmoke_ActivateChemlight"), player, onActivateChemlight, item)
            return
        end
    end
end

Events.OnFillInventoryObjectContextMenu.Add(onFillInventoryObjectContextMenu)
