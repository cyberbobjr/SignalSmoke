# Spécifications techniques

Contrats de Signal Smoke 0.2.3, Build 42.21 (`versionMin=42.21`, seule variante `42.21/`). Vérifiés dans le code du dépôt le 2026-10-21. Le comportement vu du joueur est dans [specifications-fonctionnelles.md](specifications-fonctionnelles.md), l'organisation du code dans [architecture.md](architecture.md).

## Objets (`module SignalSmoke`, `imports { Base }`)

Les types complets portent le module `SignalSmoke.` : un type sans module n'est cherché que dans `Base` (42.21).

| Type complet | Catégorie | Poids | Rôle |
|---|---|---|---|
| `SignalSmoke.SmokeGrenadeGreen`, `…Red`, `…Yellow`, `…Purple` | `Explosives`, `base:weapon` | 0,6 | grenade : copie de `Base.SmokeBomb` avec `SmokeRange = 0`, `FireStartingChance = 0`, `MaxRange = 12`, `ExplosionSound = SmokeBombLoop`, `NoiseRange = 10`, tooltip `Tooltip_SignalSmoke_Grenade` |
| `SignalSmoke.ImprovisedSmokeGreen`, `…Red`, `…Yellow`, `…Purple` | `Explosives`, `base:weapon` | 0,5 | bombe artisanale : idem, `MaxRange = 10`, tooltip `Tooltip_SignalSmoke_ImprovisedSmoke` |
| `SignalSmoke.RoadFlare` | `LightSource` | 0,2 | fusée neuve (tooltip `Tooltip_SignalSmoke_RoadFlare`) |
| `SignalSmoke.RoadFlareLit` | `LightSource` | 0,2 | fusée allumée posée au sol |
| `SignalSmoke.ChemlightGreen`, `…Red`, `…Blue`, `…Yellow` | `LightSource` | 0,1 | bâton neuf (`Tooltip_SignalSmoke_Chemlight`) |
| `SignalSmoke.ChemlightGreenLit`, `…RedLit`, `…BlueLit`, `…YellowLit` | `LightSource` | 0,1 | bâton activé, porte `ModData.ssUntilH` (`Tooltip_SignalSmoke_ChemlightLit`) |
| `SignalSmoke.ChemlightUsed` | `Junk` | 0,1 | bâton usagé (`Tooltip_SignalSmoke_ChemlightUsed`) |

Icônes `media/textures/Item_SignalSmoke_<Nom>.png` ; modèles déclarés dans `module Base` sous des noms préfixés `SignalSmoke_` (`SignalSmoke_models.txt`), maillages `models_X/WorldItems/SignalSmoke_*.fbx`. Aucun objet n'émet de lumière par son script : toute lumière vient des lampes posées par le client.

## Recettes (`SignalSmoke_recipes.txt`)

`craftRecipe SignalSmoke_MakeImprovisedSmoke<Couleur>` pour `Green`, `Red`, `Yellow`, `Purple` : `timedAction = Making`, `time = 120`, `Tags = InHandCraft`, `category = Miscellaneous`, `SkillRequired = Cooking:2`, `xpAward = Cooking:5`.

```
inputs
{
    item 1 tags[base:emptycan] flags[IsEmpty;ItemCount],
    item 2 tags[base:sugar],
    item 1 [Base.Coldpack;Base.Fertilizer],
    item 1 [Base.Paint<Couleur>],
    item 1 [Base.Twine;Base.RippedSheets;Base.RippedSheetsDirty],
}
outputs { item 1 SignalSmoke.ImprovisedSmoke<Couleur>, }
```

Pour un consommable (sucre, engrais, peinture, ficelle), `item N` compte des utilisations, pas des objets.

## Actions chronométrées

| Classe (globale) | Paramètres de `new` | Durée | Animation, son | `complete()` (serveur ou solo) |
|---|---|---|---|---|
| `SignalSmoke_LightFlareAction` | `character, item` | 60 (1 si instantané) | `Loot`, `LootPosition = Low`, `UseLighter` | retire `RoadFlare`, pose `RoadFlareLit` (décalage aléatoire 0,3-0,7), `setIgnoreRemoveSandbox(true)`, `SignalSmoke.start{ kind = "flare", color = "red", radius = 0, minutes = FlareBurnMinutes, itemId, itemType, sound = "SmokeBombLoop", owner = "SignalSmoke:flare", source = "flare", player }` |
| `SignalSmoke_ActivateChemlightAction` | `character, item` | 40 (1 si instantané) | `Loot`, `LootPosition = Low`, `OpenPlasticBag` | retire le bâton neuf, crée le type `…Lit` (`instanceItem`), pose `ssUntilH = maintenant + ChemlightHours` **avant** `AddWorldInventoryItem(lit, …, true)`, puis `SignalSmoke.startChemlight(worldObject, character)` |

Constantes exposées : `SignalSmoke_LightFlareAction.FLARE_TYPE = "SignalSmoke.RoadFlare"`, `.LIT_TYPE = "SignalSmoke.RoadFlareLit"`, `.BURN_MINUTES = 60`.

## Commandes réseau

Aucune commande `sendClientCommand`/`sendServerCommand`. Les échanges passent par :

| Mécanisme | Sens | Contenu | Contrôle |
|---|---|---|---|
| Actions chronométrées vanilla | client → serveur | `character`, `item` | tout revérifié dans `complete()` (type, présence dans l'inventaire, case, personnage vivant) |
| `ModData.transmit("batman_SignalSmoke")` | serveur → tous les clients | registre complet | émis par le serveur seulement (`isServer()`) |
| `ModData.request("batman_SignalSmoke")` | client → serveur | demande du registre | à `OnGameStart`, client MP |
| `AddWorldInventoryItem`, `transmitRemoveItemFromSquare`, `sendAddItemToContainer`, `sendRemoveItemFromContainer` | serveur → clients | objets posés, retirés ou remplacés | moteur |

## Registre (ModData globale)

Clé `SignalSmoke.MODDATA_KEY = "batman_SignalSmoke"`, sauvegardée par le moteur.

```lua
{
  v = 1,                       -- SignalSmoke.VERSION
  entries = {
    [id] = {
      id = "auto:<minute>:<n>" | "<id fourni>",
      kind = "smoke" | "flare" | "chemlight",
      x = <int>, y = <int>, z = <int>,
      radius = 0..2,             -- cases de fumée (disque)
      lightRadius = 1..20 | nil, -- nil : 5 (smoke), 8 (flare), 3 (chemlight)
      color = { r = 0..1, g = 0..1, b = 0..1 },
      untilH = <heures de monde>,-- fin (getWorldAgeHours)
      light = <bool>,            -- smoke : la nuit seulement ; flare et chemlight : toujours
      smoke = <bool>,            -- facultatif (absent avant 0.2.0 = true) ; toujours false pour chemlight
      sound = <nom de son> | nil,
      itemId = <int> | nil,      -- objet posé suivi (getID)
      itemType = <type complet> | nil,
      spentType = <type complet> | nil, -- posé à la place de l'objet à la fin
      owner = <texte> | nil,
      source = "grenade" | "flare" | "chemlight" | "script" | <texte>,
    },
  },
}
```

Depuis 0.2.3, aucune entrée ne contient `username` (retiré au chargement et à chaque accès par `migrate`/`registry`). Valeurs `owner` du mod : `SignalSmoke:grenade`, `SignalSmoke:flare`, `SignalSmoke:chemlight`.

Autres clés ModData : `ssUntilH` (`SignalSmoke.CHEMLIGHT_UNTIL_KEY`) sur l'objet d'un bâton activé, heure de monde de son extinction ; `batmanSS` sur un `IsoFire` de fumée du mod, identifiant de l'entrée.

## Options sandbox (`media/sandbox-options.txt`)

Page `SignalSmoke`, `VERSION = 1`, aucune option `enum`. Lecture : `SignalSmoke.option(name)` ; les défauts sont recopiés dans `SignalSmoke.DEFAULTS` (contrôlé par `tests/run_tests.py`).

| Nom complet | Type | Défaut | Min | Max | Lu par |
|---|---|---|---|---|---|
| `SignalSmoke.GrenadeSmokeSeconds` | integer | 90 | 20 | 600 | `OnThrowableExplode` (secondes réelles) |
| `SignalSmoke.FlareBurnMinutes` | integer | 60 | 10 | 720 | `SignalSmoke_LightFlareAction:complete` (minutes de jeu) |
| `SignalSmoke.ChemlightHours` | integer | 8 | 1 | 48 | activation, `startChemlight` sans `ssUntilH` (heures de jeu) |
| `SignalSmoke.ImprovisedSmokeSeconds` | integer | 45 | 10 | 300 | `OnThrowableExplode` |
| `SignalSmoke.ImprovisedDudChance` | integer | 20 | 0 | 100 | `OnThrowableExplode` (`ZombRand(100) < valeur`) |
| `SignalSmoke.LootMultiplier` | double | 1.0 | 0.0 | 10.0 | distributions (0 : aucun objet) |
| `SignalSmoke.FlaresInPoliceCars` | boolean | true | — | — | distributions (`VehicleDistributions.PoliceTruckBed`, poids 6) |

## Butin (`SignalSmoke_Distributions.lua`)

Poids par objet (avant `LootMultiplier`) :

| Liste | Grenades (chaque couleur) | Fusée | Bâtons (chaque couleur) |
|---|---|---|---|
| `ArmyStorageAmmunition` | 1 | | |
| `ArmyStorageElectronics` | | | 2 |
| `ArmyBunkerStorage` | 1 | | 1 |
| `ArmySurplusMisc` | 2 | | 2 |
| `PoliceLockers` | 0,5 | 1 | 0,5 |
| `GasStoreEmergency` | | 4 | |
| `CarSupplyTools` | | 2 | |
| `FireDeptLockers` | | 2 | 0,5 |
| `CampingStoreLighting` | | | 3 |
| `CampingStoreGear` | | | 1 |
| `SurvivalGear` | | | 1 |
| `VehicleDistributions.PoliceTruckBed` | | 6 (si `FlaresInPoliceCars`) | |

Une liste introuvable écrit `[SignalSmoke] loot list not found: <liste>` dans le journal.

## Traductions

`media/lua/shared/Translate/<LANG>/` : `CN`, `DE`, `EN`, `ES`, `FR`, `JP`, `KO`, `PT`, `PTBR`, `RU` (10 langues), fichiers JSON plats sans BOM.

| Fichier | Clés |
|---|---|
| `ItemName.json` | `SignalSmoke.<Type>` (19 objets) |
| `ContextMenu.json` | `ContextMenu_SignalSmoke_LightFlare`, `ContextMenu_SignalSmoke_ActivateChemlight` |
| `Recipes.json` | `SignalSmoke_MakeImprovisedSmoke<Couleur>` |
| `Sandbox.json` | `Sandbox_SignalSmoke` (page), `Sandbox_SignalSmoke_<Option>` et `…_tooltip` (`%%` pour un signe pour cent) |
| `Tooltip.json` | `Tooltip_SignalSmoke_Grenade`, `_RoadFlare`, `_Chemlight`, `_ChemlightLit`, `_ChemlightUsed`, `_ImprovisedSmoke` |

Messages du journal en anglais, préfixe `[SignalSmoke]`.

## API publique Lua

### Accès

```lua
-- mod.info du mod appelant
require=\batman_SignalSmoke

-- fichier Lua (shared ou server de préférence)
local SignalSmoke = require "SignalSmoke/SignalSmoke"
```

Le module est un fichier `shared` : il est disponible sur toutes les machines, quel que soit l'ordre des mods. Les **écritures** et les **événements** ne fonctionnent que sur l'autorité (serveur dédié, hôte, ou solo, c'est-à-dire `not isClient()`) ; les **lectures** fonctionnent partout.

### Fonctions

| Fonction | Côté | Retour |
|---|---|---|
| `SignalSmoke.start(opts)` | autorité | identifiant (texte) ; `nil, "server only"` chez un client MP ; `nil, <message>` si `opts` est invalide (message aussi écrit au journal : `[SignalSmoke] start refused: …`) |
| `SignalSmoke.stop(id, reason)` | autorité | `true` si l'entrée existait, `false` sinon ; `nil, "server only"` chez un client MP |
| `SignalSmoke.isActive(id)` | partout | `true` si l'entrée existe et n'est pas échue |
| `SignalSmoke.list()` | partout | `{ [id] = entrée }` des entrées actives (ne pas modifier) |
| `SignalSmoke.registryData()` | partout | table brute `{ v, entries }` (ModData chez l'autorité, copie reçue chez un client MP, `nil` avant réception) |
| `SignalSmoke.onSignal(fn)` | autorité | `true` si ajouté, `false` si déjà abonné ou si `fn` n'est pas une fonction |
| `SignalSmoke.removeSignalListener(fn)` | autorité | `true` si retiré (possible depuis l'abonné lui-même) |
| `SignalSmoke.startChemlight(worldObject, player)` | autorité | inscrit un bâton activé posé (`IsoWorldInventoryObject`), id `chemlight:<id de l'objet>` ; `nil` si ce n'est pas un bâton activé ou s'il est échu (alors remplacé par un bâton usagé) |
| `SignalSmoke.startFlare(worldObject, player)` | autorité | inscrit une fusée allumée posée, id `flare:<id de l'objet>`, pour le temps restant (`ssUntilH`) et dans sa couleur (`ssColor`) ; `nil` si ce n'en est pas une, ou si elle est échue ou sans heure de fin (alors retirée du sol) |
| `SignalSmoke.placeFlare(opts)` | autorité | pose une `RoadFlareLit` sur la case `x, y, z` chargée et l'inscrit (options de `start`, `kind`/`itemId`/`itemType` imposés, `color` par défaut `red`, durée par défaut `FlareBurnMinutes`, `offX`/`offY`) ; rend `id, item`, ou `nil, erreur` sans rien laisser au sol (API 3) |
| `SignalSmoke.colorNameOf(entry)` | partout | `entry.colorName`, sinon le nom de `COLORS` le plus proche de `entry.color` (égalité : ordre alphabétique), `nil` sans couleur (API 3) |
| `SignalSmoke.markItemObject(entry, worldObject)` | autorité | fusée ou bâton : écrit `ssUntilH` (et `ssColor` d'une fusée) dans la ModData de l'objet et le protège du nettoyage ; appelé par `start` et par le contrôle de chaque minute |
| `SignalSmoke.findItemObject(entry)` | autorité | `(objet, true)` présent, `(nil, true)` absent, `(nil, false)` case non chargée ; alias `findFlareObject` (0.1.0) |
| `SignalSmoke.option(name)` | partout | valeur de l'option `SignalSmoke.<name>` |
| `SignalSmoke.chemlightOf(fullType)` | partout | `couleur, estActivé` ou `nil` |
| `SignalSmoke.resolveColor(color)` | partout | `{ r, g, b }` ou `nil` |

Fonctions internes, exposées pour les tests ou le mod lui-même, sans garantie de stabilité : `newEntry`, `isLive`, `hasSmoke`, `realSecondsToHours`, `isDud`, `rewriteLootItems`, `nowHours`, `migrate`, `expire`, `notify`, `setReceived`.

Constantes : `COLORS` (`green`, `red`, `yellow`, `purple`, `orange`, `blue`, `white`, valeurs `{ r, g, b }` de 0 à 1), `KINDS`, `MAX_RADIUS = 2`, `MAX_LIGHT_RADIUS = 20`, `DEFAULT_MINUTES = 30`, `GRENADES`, `CHEMLIGHTS`, `CHEMLIGHT_USED`, `CHEMLIGHT_UNTIL_KEY` (= `UNTIL_KEY`, `ssUntilH`), `COLOR_KEY` (`ssColor`), `FLARE_TYPE`, `FLARE_LIT_TYPE`, `FLARE_COLOR`, `FLARE_SOUND`, `CHEMLIGHT_LIGHT_RADIUS = 3`, `DEFAULTS`, `MODDATA_KEY`, `VERSION = 2` (schéma du registre, migration faite une fois par chargement du Lua), `API_VERSION = 3` (1 : 0.1.0 ; 2 : événements et bâtons lumineux ; 3 : `colorName`, `colorNameOf`, `placeFlare`).

Champ d'entrée `colorName` (API 3) : nom de `COLORS` quand `color` a été donnée par son nom (défaut `green`), `nil` pour une couleur libre.

### Options de `start(opts)`

| Clé | Type | Défaut | Règle |
|---|---|---|---|
| `x`, `y` | entier | **obligatoire** | sinon `"x and y must be integers"` |
| `z` | entier | 0 | sinon `"z must be an integer"` |
| `color` | nom de `COLORS` ou `{ r, g, b }` | `"green"` | composantes bornées à 0..1 ; nom inconnu : `"unknown color <nom>"` |
| `kind` | `"smoke"`, `"flare"`, `"chemlight"` | `"smoke"` | sinon erreur |
| `untilH` | heures de monde absolues | — | prioritaire sur les deux suivantes |
| `realSeconds` | secondes réelles | — | converties en heures avec la durée du jour **au moment de l'appel** |
| `minutes` | minutes de jeu | 30 | durée ≤ 0 : `"duration must be positive"` |
| `radius` | entier | 0 | borné à 0..2 ; disque de cases de fumée (1 : croix de 5 cases, 2 : 13 cases) |
| `lightRadius` | entier | selon `kind` | borné à 1..20 |
| `light` | booléen | `true` | `smoke` : lampe la nuit seulement |
| `smoke` | booléen | `true` | ignoré (faux) pour `chemlight` |
| `sound` | nom de son | aucun | joué en boucle par chaque client à moins de 40 cases |
| `itemId` | entier (`item:getID()`) | aucun | objet posé suivi : entrée arrêtée (`"pickedUp"`) s'il quitte sa case, objet retiré du sol à la fin |
| `itemType`, `spentType` | type complet | aucun | `spentType` est posé à la place de l'objet suivi à la fin |
| `id` | texte | `auto:<minute>:<n>` | un id déjà présent est **remplacé** (appel idempotent) |
| `owner` | texte | aucun | libre, conseillé pour reconnaître ses entrées |
| `source` | texte | `"script"` | transmis aux abonnés |
| `player` | `IsoPlayer` | aucun | transmis à `started` ; son `getUsername()` gardé en mémoire serveur |
| `username` | texte | aucun | utilisé si `player` est absent ; jamais écrit dans le registre |

Remplacer une entrée par le même `id` ne retire pas l'objet suivi de l'ancienne entrée et n'émet pas de `stopped` : seulement `started` avec `replaced = true`.

### Événements

`fn(event)` est appelé sur l'autorité, chacun sous `pcall` (erreur écrite au journal : `[SignalSmoke] signal listener failed on <type> <id>: <erreur>`). Inscrire l'abonné au chargement d'un fichier lu par le serveur (`shared` ou `server`) ; un abonné inscrit chez un client MP n'est jamais appelé.

| Champ | Valeur |
|---|---|
| `type` | `"started"`, `"stopped"` (par `stop`), `"expired"` (par l'expiration chaque minute de jeu) |
| `id` | identifiant de l'entrée |
| `entry` | entrée du registre (lecture seule) |
| `source` | `entry.source` ou `"script"` |
| `username` | compte du joueur à l'origine si connu (solo : nom du personnage) ; inconnu pour un signal posé avant le dernier chargement ou redémarrage |
| `player` | `IsoPlayer`, pour `started` seulement, si connu |
| `reason` | pour `stopped` : `"script"` (défaut) ou `"pickedUp"`, ou la raison passée à `stop` |
| `replaced` | pour `started` : `true` si une entrée de même id a été remplacée |

Une bombe artisanale ratée ne produit aucun événement. Un bâton lumineux reposé produit un nouveau `started` (même id `chemlight:<id>`, `replaced` faux après un `pickedUp`).

### Exemples (d'après les appels réels des mods dépendants)

Balise rafraîchie, puis retirée (Opération Artemis, `server/Artemis_BeaconDirector.lua`) :

```lua
local entry = SignalSmoke.list()[id]
if not (entry and entry.untilH - nowHours > REFRESH_BELOW_HOURS) then
    SignalSmoke.start{ id = id, owner = OWNER, color = "green", radius = 0, light = true,
        x = beacon.x, y = beacon.y, z = beacon.z, minutes = BEACON_MINUTES }
end
-- plus tard
if SignalSmoke.isActive(id) then SignalSmoke.stop(id) end
```

Fusée posée par un autre mod avec son propre objet (Opération Artemis, `server/Artemis/Artemis_Rendezvous.lua`) :

```lua
local flare = square:AddWorldInventoryItem("SignalSmoke.RoadFlareLit", 0.5, 0.5, 0)
SignalSmoke.start{ id = flareId, owner = SIGNAL_OWNER, kind = "flare", color = "green", radius = 0,
    x = x, y = y, z = z, minutes = minutes, light = true, sound = "SmokeBombLoop",
    itemId = flare and flare:getID() or nil }
```

Appel protégé et contrôle du module (Radio Survivor, `server/RadioSurvivor/RS_RescueVisit.lua`) :

```lua
local mod = require "SignalSmoke/SignalSmoke"
if type(mod) == "table" and type(mod.start) == "function" and type(mod.COLORS) == "table" then
    local ok, id, err = pcall(mod.start, { x = x, y = y, z = 0, color = color, minutes = Visit.CONFIG.SMOKE_MINUTES,
        id = "rs:rescue:" .. rec.id, owner = "RadioSurvivor" })
    if not ok or not id then log("Signal Smoke refused the smoke (" .. tostring(ok and err or id) .. ")") end
end
```

Abonné qui reconnaît la couleur (schéma simplifié de Radio Survivor, `RS_MissionSignal.lua` et `RS_TradeRun.lua`, qui comparent `event.entry.color` à `COLORS` avec une tolérance) :

```lua
SignalSmoke.onSignal(function(event)
    if event.type ~= "started" or not event.player then return end
    local ref = SignalSmoke.COLORS.red
    local c = event.entry.color
    if math.abs(c.r - ref.r) < 0.01 and math.abs(c.g - ref.g) < 0.01 and math.abs(c.b - ref.b) < 0.01 then
        -- signal rouge allumé par event.player en event.entry.x, event.entry.y, event.entry.z
    end
end)
```

## Compatibilités et contraintes

- Build 42.21 seulement (`versionMin=42.21`, aucune variante `42` ni `common` de code).
- Aucun fichier vanilla remplacé, aucune fonction vanilla enveloppée : seuls des abonnements à des événements et des ajouts aux listes de butin (retrait préalable des objets `SignalSmoke.` de chaque liste, donc idempotent).
- Partage du plafond de 75 `IsoFire` du moteur avec les feux réels ; 40 fumées au plus par client pour ne pas évincer les feux réels.
- Dépendants vérifiés statiquement : `batman_OperationArtemis`, `batman_RadioSurvivor` (voir [architecture.md](architecture.md#intégrations-avec-dautres-mods)).
