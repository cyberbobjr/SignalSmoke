# Architecture

Version décrite : 0.2.3 (`modversion` de `mod.info`), Build 42.21. Les détails des contrats (formats, options, API) sont dans [specifications-techniques.md](specifications-techniques.md) ; les preuves Java et vanilla des choix ci-dessous dans [annexes/recherches/](annexes/recherches/).

## Vue d'ensemble

Le principe central : **le serveur décide, chaque client dessine**. En multijoueur, la fumée vanilla (`IsoFire` de fumée) n'existe que chez les clients ; le mod reproduit ce fonctionnement.

```
 Autorité (serveur dédié, ou jeu solo)                        Chaque client (et le solo)
 ───────────────────────────────────────                      ─────────────────────────────
 Grenade qui éclate (OnThrowableExplode) ─┐
 Action « Allumer et poser » (complete) ──┤                    SignalSmoke_Client.lua, une fois
 Action « Activer et poser » (complete) ──┼─> SignalSmoke.start  par seconde réelle, pour chaque
 Bâton activé reposé (EveryOneMinute) ────┤      │              entrée active dont la case est
 Autre mod (API publique) ────────────────┘      v              chargée :
                                  registre = ModData globale     - fumée : IsoFire teint, local
                                  "batman_SignalSmoke"           - lampe colorée (addLamppost)
                                         │ ModData.transmit      - son en boucle près du joueur
                                         └──────────────────────> copie reçue (OnReceiveGlobalModData)
 Abonnés onSignal (started / stopped / expired) <── notify
 EveryOneMinute : expire, objets ramassés, bâtons lumineux
```

En solo, la même machine est à la fois l'autorité et le client : le registre est lu directement dans la ModData globale.

## Arborescence du mod

```
Contents/mods/batman_SignalSmoke/
├── common/README.txt                 dossier common exigé en Build 42 (vide de code)
└── 42.21/                            seule variante : versionMin=42.21
    ├── mod.info                      id=batman_SignalSmoke, aucun require, aucun loadModAfter
    ├── icon.png, poster.png
    └── media/
        ├── sandbox-options.txt       7 options, page SignalSmoke
        ├── scripts/
        │   ├── SignalSmoke_items.txt    module SignalSmoke : 19 objets
        │   ├── SignalSmoke_models.txt   modèles (déclarés dans module Base, noms préfixés)
        │   └── SignalSmoke_recipes.txt  4 craftRecipe de bombes artisanales
        ├── models_X/WorldItems/      5 FBX (grenade, fusée, fusée allumée, bâton lumineux, bombe artisanale)
        ├── textures/                 icônes Item_SignalSmoke_*.png et textures WorldItems/
        └── lua/
            ├── shared/SignalSmoke/SignalSmoke.lua               module public (registre, API, événements)
            ├── shared/TimedActions/SignalSmoke_LightFlareAction.lua
            ├── shared/TimedActions/SignalSmoke_ActivateChemlightAction.lua
            ├── shared/Translate/<LANG>/*.json                   10 langues
            ├── client/SignalSmoke/SignalSmoke_Client.lua        rendu local
            ├── client/SignalSmoke/SignalSmoke_Menu.lua          menu contextuel
            ├── server/SignalSmoke/SignalSmoke_Server.lua        autorité : grenades, expiration, bâtons
            └── server/Items/SignalSmoke_Distributions.lua       butin
```

`mod.info` : `id=batman_SignalSmoke`, `versionMin=42.21`, `modversion=0.2.3`. Le mod ne dépend d'aucun autre ; deux mods de l'auteur le déclarent en `require` (voir [Intégrations](#intégrations-avec-dautres-mods)).

## Modules Lua

### `shared/SignalSmoke/SignalSmoke.lua` — module public

Renvoyé par `require "SignalSmoke/SignalSmoke"`. Aucun abonnement à un événement : il ne fait rien tant qu'on ne l'appelle pas.

- Constantes : couleurs nommées, types d'objets du mod (grenades, bâtons lumineux), bornes, valeurs par défaut des options sandbox.
- Fonctions pures (testées hors jeu) : `newEntry`, `resolveColor`, `isLive`, `hasSmoke`, `realSecondsToHours`, `isDud`, `chemlightOf`, `rewriteLootItems`.
- Registre de l'autorité : `start`, `stop`, `expire`, `migrate`, `startChemlight`, `findItemObject` (refusés ou sans effet chez un client MP : `isClient()`).
- Lecture valable partout : `registryData`, `list`, `isActive` (copie reçue chez un client MP).
- Événements : `onSignal`, `removeSignalListener`, `notify` (abonnés appelés chacun sous `pcall`).
- Options sandbox : `option(name)` lit d'abord `getSandboxOptions():getOptionByName("SignalSmoke.<name>")` (à jour après un changement en cours de partie), puis `SandboxVars.SignalSmoke`, puis `DEFAULTS`.

### `shared/TimedActions/*` — actions chronométrées

`SignalSmoke_LightFlareAction` (fusée de route, 60 unités) et `SignalSmoke_ActivateChemlightAction` (bâton lumineux, 40 unités) dérivent d'`ISBaseTimedAction` sur le modèle vanilla `ISRepairClothing`. En multijoueur, le serveur reconstruit l'action à partir des noms des paramètres de `new(character, item)` et n'appelle jamais `isValid` : `complete()`, exécuté sur le serveur ou en solo, revérifie tout (type de l'objet, présence dans l'inventaire, case, personnage vivant), retire l'objet, pose l'objet allumé au sol par `AddWorldInventoryItem` et appelle `SignalSmoke.start` / `startChemlight`.

### `client/SignalSmoke/SignalSmoke_Menu.lua`

Abonné à `OnFillInventoryObjectContextMenu` : option « Allumer et poser au sol » sur `SignalSmoke.RoadFlare`, « Activer et poser au sol » sur un bâton lumineux neuf. L'objet est d'abord ramené dans l'inventaire principal (`ISInventoryPaneContextMenu.transferIfNeeded`), puis l'action est mise en file.

### `client/SignalSmoke/SignalSmoke_Client.lua` — rendu local

Abonnés : `OnTick` (contrôle une fois par seconde réelle, `getTimestampMs`), `OnReceiveGlobalModData` (copie du registre), `OnGameStart` (client MP : `ModData.request`), `LoadGridsquare` (hors client MP seulement). Pour chaque entrée active dont la case centrale est chargée :

- **Fumée** (si `SignalSmoke.hasSmoke(entry)`) : un `IsoFire` de fumée (`IsoFire.new(cell, sq, true, 100, 144000, true)`) par case d'un disque de rayon `radius`, marqué `ModData.batmanSS = id`, reteint à chaque passage (`ChangeTintMod` des sprites attachés), recréé quand sa vie passe sous 78 %. Un feu disparu sans le mod (éviction au-delà de 75 feux par `IsoFireManager`) n'est recréé qu'après 5 s, et le mod ne garde pas plus de 40 feux par client.
- **Lampe** (`getCell():addLamppost`) : la nuit seulement pour une fumée (lumière du jour < 0,45), toujours pour une fusée ou un bâton lumineux. Présence testée par `getLamppostPositions():contains`. Les fusées scintillent : un abonnement `OnTick` supplémentaire module la couleur toutes les 220 ms tant qu'une fusée brûle.
- **Son** en boucle (`getFreeEmitter` + `playSoundLoopedImpl`) si un joueur local est à moins de 40 cases ; nouvel émetteur à chaque reprise.

Un changement de position, de rayon, de type, de couleur, de lumière, de son ou de fumée d'une entrée (même identifiant) efface d'abord l'état local (`signature`). Une entrée échue ou retirée est nettoyée (feux éteints, lampe retirée, son arrêté). En solo, `LoadGridsquare` éteint une fumée marquée restée dans la sauvegarde alors que son entrée n'existe plus.

### `server/SignalSmoke/SignalSmoke_Server.lua` — autorité

Chargé aussi par les clients MP (dossier `server`), mais sort aussitôt (`if isClient() then return end`). Abonnés :

- `OnThrowableExplode(trap, square)` : une grenade ou bombe artisanale du mod (`SignalSmoke.GRENADES`) ajoute une fumée au registre (rayon 1, son `SmokeBombLoop`, source `grenade`, lanceur `trap:getAttacker()`). Une bombe artisanale peut rater (`ZombRand(100)` < `ImprovisedDudChance`) : aucun signal.
- `EveryOneMinute` : `SignalSmoke.expire()` ; arrêt (`reason = "pickedUp"`) des entrées dont l'objet suivi a quitté sa case chargée ; recherche, dans un carré de 5 × 5 cases autour de chaque joueur vivant, des bâtons lumineux activés posés au sol et absents du registre (`startChemlight`) ; toutes les 10 minutes, remplacement des bâtons activés échus portés dans l'inventaire (sacs compris, hors objets en main ou accrochés) par un bâton usagé.
- `OnInitGlobalModData` : `SignalSmoke.migrate()` (migration 0.2.3).

### `server/Items/SignalSmoke_Distributions.lua` — butin

`OnPostDistributionMerge` : ajoute les objets aux listes `ProceduralDistributions` et à `VehicleDistributions.PoliceTruckBed`, poids × `LootMultiplier`. `OnInitGlobalModData` (hors client MP) : si les options lues diffèrent de celles appliquées (en solo, les options de la partie arrivent après la fusion), réécrit les listes (`rewriteLootItems`, idempotente) puis `ItemPickerJava.Parse()`.

### Ordre de chargement et `require`

`SignalSmoke.lua` est un fichier `shared`, exécuté au démarrage avant tout fichier `server` : un mod qui le requiert depuis `shared` ou `server` l'obtient quel que soit l'ordre des mods. Les fichiers du mod le chargent tous par `require "SignalSmoke/SignalSmoke"` ; `SignalSmoke_Menu.lua` requiert aussi les deux actions et `TimedActions/ISTimedActionQueue`.

## Flux de données et réseau

- **Aucune commande réseau propre** (`sendClientCommand`/`sendServerCommand` ne sont pas utilisés). Les gestes du joueur passent par les actions chronométrées vanilla (réseau du moteur) ; l'état passe par la ModData globale.
- À chaque `start`, `stop`, `expire` ou migration qui change le registre, le serveur appelle `ModData.transmit("batman_SignalSmoke")` (sur un serveur seulement, `isServer()`). Les clients reçoivent la table entière par `OnReceiveGlobalModData` et la gardent (`SignalSmoke.setReceived`). À l'entrée en jeu, un client MP la demande (`ModData.request`).
- Objets au sol : posés par `AddWorldInventoryItem` (envoyés aux clients par le moteur), retirés par `transmitRemoveItemFromSquare` + `removeWorldObject`. Inventaire : `sendRemoveItemFromContainer` / `sendAddItemToContainer`.
- Fumée, lampe et son sont des objets **locaux** de chaque client, jamais envoyés.

## Persistance

| Donnée | Où | Contenu |
|---|---|---|
| Registre | ModData globale `batman_SignalSmoke` (`global_mod_data.bin`) | `{ v = 1, entries = { [id] = entrée } }` |
| Fin d'un bâton lumineux activé | ModData de l'objet, clé `ssUntilH` | heure de monde de l'extinction |
| Marque d'une fumée | ModData de l'`IsoFire`, clé `batmanSS` | identifiant de l'entrée (solo : sauvegardée avec le chunk) |
| Compte du joueur à l'origine | mémoire du serveur seulement | `id -> username`, perdu au redémarrage |

Migration : depuis 0.2.3, `migrate()` (au chargement) et chaque accès au registre retirent le champ `username` des entrées sauvegardées par une version antérieure, le gardent en mémoire pour les événements et retransmettent le registre. Les champs ajoutés en 0.2.0 (`smoke`, `lightRadius`, `source`, `itemType`, `spentType`) sont facultatifs. Format exact : [specifications-techniques.md](specifications-techniques.md#registre-moddata-globale).

## Intégrations avec d'autres mods

Points d'extension : l'API publique (`start`, `stop`, `list`, `isActive`) et les événements (`onSignal`). Contrat complet : [specifications-techniques.md, API publique](specifications-techniques.md#api-publique-lua).

Utilisateurs connus (relevé du 2026-10-21, lecture seule) :

- **Opération Artemis** (`batman_OperationArtemis`, `require=\batman_SignalSmoke,\batman_BeltRadio`) : balises de fumée verte (`start` avec `id` et `owner`, rafraîchies d'après `list()[id].untilH`, arrêtées par `isActive` + `stop`) ; zone d'atterrissage marquée de fumées vertes et d'une fusée verte posée par le mod lui-même (`SignalSmoke.RoadFlareLit` + `kind = "flare"`, `itemId`, `sound = "SmokeBombLoop"`).
- **Radio Survivor** (`batman_RadioSurvivor`, `require=\batman_BeltRadio,\batman_SignalSmoke`) : abonnés `onSignal` (missions « signal » et rendez-vous de troc : couleur retrouvée en comparant `event.entry.color` à `SignalSmoke.COLORS`) et fumée de secours posée par `start` sous `pcall` (`id = "rs:rescue:<id>"`).

## Outillage

- `python tests/run_tests.py` : tests des fonctions pures du module public sous `lupa` (avec `next` retiré, absent de Kahlua), cohérence scripts / traductions / ressources (noms, icônes, modèles, recettes, options et leurs défauts Lua), traductions (mêmes fichiers et clés que `EN`, JSON plat sans BOM), descriptions Steam (taille, BBCode, liens, `workshop.txt` = `README.steam`), puis `luacheck` (`.luacheckrc`).
- `source/items/build_items.py` : recette Blender sans interface qui produit les modèles FBX, les textures et les icônes 64 × 64.
- Pas de CI dans le dépôt.
- Protocoles de test en jeu : [annexes/tests/](annexes/tests/).
