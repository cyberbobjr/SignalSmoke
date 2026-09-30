-- Signal Smoke : menu contextuel « Allumer et poser » sur une fusée de route de l'inventaire.
-- La fusée est d'abord ramenée dans l'inventaire principal (sac porté, sol…), puis l'action la pose.

require "TimedActions/ISTimedActionQueue"
require "TimedActions/SignalSmoke_LightFlareAction"

local function onLight(player, item)
    ISInventoryPaneContextMenu.transferIfNeeded(player, item)
    ISTimedActionQueue.add(SignalSmoke_LightFlareAction:new(player, item))
end

local function onFillInventoryObjectContextMenu(playerNum, context, items)
    local player = getSpecificPlayer(playerNum)
    if not player then return end
    for _, entry in ipairs(items) do
        local item = entry
        if not instanceof(entry, "InventoryItem") then
            item = entry.items and entry.items[1]
        end
        if item and item:getFullType() == SignalSmoke_LightFlareAction.FLARE_TYPE then
            context:addOption(getText("ContextMenu_SignalSmoke_LightFlare"), player, onLight, item)
            return
        end
    end
end

Events.OnFillInventoryObjectContextMenu.Add(onFillInventoryObjectContextMenu)
