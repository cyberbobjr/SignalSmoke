-- Signal Smoke : butin. Grenades fumigènes dans les stocks militaires et les casiers de police ;
-- fusées de route dans le matériel d'urgence des stations-service, les outils de garage, les casiers
-- de pompiers et de police. Écrit à OnPostDistributionMerge (les listes ne sont lues qu'ensuite, par
-- ItemPickerJava.Parse) : .claude/pz-knowledge/loot-distributions.md.
-- Objets du module SignalSmoke : type complet (sans module, seul Base serait cherché).

require "Items/ProceduralDistributions"

local GRENADES = {
    "SignalSmoke.SmokeGrenadeGreen", "SignalSmoke.SmokeGrenadeRed",
    "SignalSmoke.SmokeGrenadeYellow", "SignalSmoke.SmokeGrenadePurple",
}
local FLARE = "SignalSmoke.RoadFlare"

-- Poids par liste (échelle vanilla : pourcentage par tirage, avant le modificateur de rareté).
local GRENADE_WEIGHTS = {
    ArmyStorageAmmunition = 1,
    ArmyBunkerStorage = 1,
    ArmySurplusMisc = 2,
    PoliceLockers = 0.5,
}
local FLARE_WEIGHTS = {
    GasStoreEmergency = 4,
    CarSupplyTools = 2,
    FireDeptLockers = 2,
    PoliceLockers = 1,
}

local function addTo(listName, item, weight)
    local entry = ProceduralDistributions.list[listName]
    if type(entry) ~= "table" or type(entry.items) ~= "table" then
        print("[SignalSmoke] loot list not found: " .. listName)
        return
    end
    table.insert(entry.items, item)
    table.insert(entry.items, weight)
end

local function onPostDistributionMerge()
    for listName, weight in pairs(GRENADE_WEIGHTS) do
        for _, item in ipairs(GRENADES) do
            addTo(listName, item, weight)
        end
    end
    for listName, weight in pairs(FLARE_WEIGHTS) do
        addTo(listName, FLARE, weight)
    end
end

Events.OnPostDistributionMerge.Add(onPostDistributionMerge)
