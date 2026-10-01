-- Signal Smoke : butin. Grenades fumigènes dans les stocks militaires et les casiers de police ;
-- fusées de route dans le matériel d'urgence des stations-service, les outils de garage, les casiers
-- de pompiers et de police, et (option) les coffres des voitures de police ; bâtons lumineux dans le
-- matériel militaire, de police, de pompiers, de camping et de survie. Le fumigène artisanal ne se
-- trouve pas : il se fabrique (scripts/SignalSmoke_recipes.txt).
-- Écrit à OnPostDistributionMerge (les listes ne sont lues qu'ensuite, par ItemPickerJava.Parse) :
-- .claude/pz-knowledge/loot-distributions.md. Poids × option LootMultiplier (0 : rien).
-- En solo, les options sandbox de la partie ne sont chargées qu'après la fusion (IsoWorld.init) :
-- à OnInitGlobalModData, si les options lues diffèrent de celles appliquées, les listes sont réécrites
-- (SignalSmoke.rewriteLootItems est idempotente) puis relues par ItemPickerJava.Parse().
-- Objets du module SignalSmoke : type complet (sans module, seul Base serait cherché).

require "Items/ProceduralDistributions"
require "Vehicles/VehicleDistributions"

local SignalSmoke = require "SignalSmoke/SignalSmoke"

local GRENADES = {
    "SignalSmoke.SmokeGrenadeGreen", "SignalSmoke.SmokeGrenadeRed",
    "SignalSmoke.SmokeGrenadeYellow", "SignalSmoke.SmokeGrenadePurple",
}
local FLARE = "SignalSmoke.RoadFlare"
local CHEMLIGHTS = {
    SignalSmoke.CHEMLIGHTS.green.item, SignalSmoke.CHEMLIGHTS.red.item,
    SignalSmoke.CHEMLIGHTS.blue.item, SignalSmoke.CHEMLIGHTS.yellow.item,
}

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
-- Poids de chaque couleur de bâton lumineux.
local CHEMLIGHT_WEIGHTS = {
    ArmyStorageElectronics = 2,
    ArmyBunkerStorage = 1,
    ArmySurplusMisc = 2,
    PoliceLockers = 0.5,
    FireDeptLockers = 0.5,
    CampingStoreLighting = 3,
    CampingStoreGear = 1,
    SurvivalGear = 1,
}
-- Coffre des voitures de police (partagé par plusieurs véhicules de police vanilla).
local POLICE_TRUNK_FLARE_WEIGHT = 6

-- Options appliquées en dernier : { multiplier, police }.
local applied = nil

-- Ajouts par liste procédurale : { [liste] = { { type, poids }, … } }.
local function proceduralAdditions()
    local additions = {}
    local function add(listName, item, weight)
        additions[listName] = additions[listName] or {}
        table.insert(additions[listName], { item, weight })
    end
    for listName, weight in pairs(GRENADE_WEIGHTS) do
        for _, item in ipairs(GRENADES) do
            add(listName, item, weight)
        end
    end
    for listName, weight in pairs(FLARE_WEIGHTS) do
        add(listName, FLARE, weight)
    end
    for listName, weight in pairs(CHEMLIGHT_WEIGHTS) do
        for _, item in ipairs(CHEMLIGHTS) do
            add(listName, item, weight)
        end
    end
    return additions
end

local function rewrite(listName, entry, additions, multiplier)
    if type(entry) ~= "table" or type(entry.items) ~= "table" then
        print("[SignalSmoke] loot list not found: " .. listName)
        return
    end
    SignalSmoke.rewriteLootItems(entry.items, additions, multiplier)
end

local function apply(multiplier, police)
    for listName, additions in pairs(proceduralAdditions()) do
        rewrite(listName, ProceduralDistributions.list[listName], additions, multiplier)
    end
    local policeAdditions = police and { { FLARE, POLICE_TRUNK_FLARE_WEIGHT } } or {}
    rewrite("VehicleDistributions.PoliceTruckBed", VehicleDistributions.PoliceTruckBed, policeAdditions, multiplier)
    applied = { multiplier = multiplier, police = police }
end

local function readOptions()
    return math.max(0, SignalSmoke.option("LootMultiplier")), SignalSmoke.option("FlaresInPoliceCars")
end

local function onPostDistributionMerge()
    apply(readOptions())
end

-- Solo (et serveur, sans effet si rien n'a changé) : options de la partie enfin chargées.
local function onInitGlobalModData()
    if isClient() then return end
    local multiplier, police = readOptions()
    if applied and applied.multiplier == multiplier and applied.police == police then return end
    apply(multiplier, police)
    ItemPickerJava.Parse()
end

Events.OnPostDistributionMerge.Add(onPostDistributionMerge)
Events.OnInitGlobalModData.Add(onInitGlobalModData)
