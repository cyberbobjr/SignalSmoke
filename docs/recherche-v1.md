# Signal Smoke — recherche de la v1 (Build 42.21)

Recherche Opus en lecture seule du 2026-09-30 (Java 42.21.0 décompilé, vanilla installé, base de connaissances). **Rien n'est testé en jeu.** Tout est confirmé statiquement sauf mention « hypothèse ».

## Décisions techniques

- **Chaque client fabrique la fumée lui-même, d'après un registre tenu par le serveur** (ModData globale `batman_SignalSmoke`, `ModData.transmit`). C'est le fonctionnement du vanilla : en MP, la fumée n'existe que chez les clients. `StartSmoke` sur le serveur n'envoie qu'un paquet aux clients proches (`IsoFireManager.java:226-229`, `UdpConnection.java:216-231`) ; chez un client MP, le paquet `StartFire` est ignoré par le serveur (`StartFirePacket` `handlingType = 2`, `PacketTypes.java:682`).
- **Grenades** : `OnThrowableExplode(trap, square)` (`LuaEventManager.java:875`), première ligne de `IsoTrap.triggerExplosion` (`IsoTrap.java:385-420`), avant toute fumée ; déclenché sur le serveur **et** chez chaque client MP (garder `if isClient() then return end`). Objet reconnu par `trap:getItem():getFullType()`. Script copié de `Base.SmokeBomb` avec `SmokeRange = 0` (pas de fumée grise) : le serveur ajoute la fumée colorée au registre.
- **Fusée de route** : action chronométrée « Allumer et poser », `complete()` exécuté sur le serveur (tout revérifier : `isValid` n'y est pas appelé), objet usagé posé au sol (`AddWorldInventoryItem`, `transmitCompleteItemToClients`), entrée `kind = "flare"` au registre ; lampe rouge qui scintille et son en boucle côté client.

## `Base.SmokeBomb` (vanilla)

- Script `scripts/generated/items/weapon.txt:941-971` : `SmokeRange = 5`, `ExplosionDuration = 10`, `ExplosionSound = SmokeBombLoop`, `NoiseRange = 10`, `NoiseDuration = 10`, `MaxRange = 10`, `SwingAnim = Throw`, `SwingSound = SmokeBombThrow`, `PhysicsObject = Base.SmokeBomb`, `PlacedSprite = constructedobjects_01_40`, `WorldStaticModel = SmokeBomb`, `UseSelf = true`, `CanBePlaced = true`, `triggerExplosionTimer = 50`. Pas de `ExplosionTimer` (champ distinct, `Item.java:3152` / `3176`) : explosion instantanée (`HandWeapon.java:2203-2205`).
- Chaîne : projectile `IsoMolotovCocktail` (`IsoGameCharacter.java:7555-7561`) ; impact (`IsoMolotovCocktail.java:118-138`) : solo → `IsoTrap` + `triggerExplosion()` ; client MP → `syncIsoTrap` (paquet `AddExplosiveTrap`) → serveur (`AddExplosiveTrapPacket.processServer:128-150`) renvoie à tous et déclenche ; chaque client recrée l'`IsoTrap` et déclenche aussi (`processClient:112-121`).
- `drawCircleExplosion` (`IsoTrap.java:724-757`) : rayon ≤ 15, ligne de vue, hors zone non-PvP, une chance sur deux par case de `StartSmoke`, zombies de la case sans cible. Fumée entretenue pendant `ExplosionDuration` (`refreshSmokeBombSmoke`, `:185-236`) : ≈ 25 s réelles quelle que soit la durée du jour, puis 5 à 20 s de dissipation.

## Fumée teintée durable (côté client)

- Recette (logique de `StartFirePacket.processClient`, précédent `SCampfireGlobalObject.lua:119-121`) : `local f = IsoFire.new(getCell(), sq, true, 100, LIFE, true)` ; `sq:AddTileObject(f)` ; `f:getModData().batmanSS = id` ; teinte de chaque sprite de `f:getAttachedAnimSprite()` par `getParentSprite():ChangeTintMod(ColorInfo.new(r, g, b, 1))` (`IsoSprite.java:183-186, 1262-1266`). Teinte vanilla 0,5 (`IsoFireManager.java:329`). Retrait : `f:extinctFire()` (`IsoFire.java:575-583`).
- `CanAddSmoke` échoue sur une case sans objet, sur l'eau, ou déjà `burning`/`smoke` (`IsoFire.java:266-286`) : reprendre alors `sq:getFire()`.
- Vie : ≈ 30 unités par seconde réelle (`GameTime.java:951`), ×200 pendant le sommeil en solo. Stade 4 = `vie / 4` ; au stade 5 l'animation est recréée grise (`:505-512`) puis s'efface (`:758-764`) ; `setLife` ne réarme pas les stades. Recette : `LIFE` élevé (144 000 ≈ 20 min de stade 4) ; sous 0,78 × `LIFE`, ou pour un feu non créé pendant la session (rechargement : `load()` ramène le minuteur à un tiers, `:122-200`), éteindre puis recréer et teindre.
- Sauvegarde : un `IsoFire` est sérialisé avec la case, ModData comprises (solo) : au chargement, éteindre un feu marqué dont l'id n'est plus au registre.
- Plafond de 75 feux par machine, éviction du plus ancien (`IsoFireManager.java:68-92, 323`) : rayon 0 à 2, peu de fumées simultanées.
- Case enfumée : un zombie ou un animal y perd sa cible (`IsoZombie.java:1705, 2010`) ; `haveFire()` vrai (`IsoGridSquare.java:8600-8609`) ; aucun son de feu.
- Risque (hypothèse) : un objet local ajouté à une case peut décaler les indices d'objets par rapport au serveur ; le vanilla prend le même risque avec sa fumée MP.

## Lampe colorée

- `getCell():addLamppost(x, y, z, r, g, b, rayon)` → `IsoLightSource` ; client seulement, non sauvegardée, rayon ≤ 20, `setRadius` sans effet après coup ; perdue hors de la zone chargée (recréer si `getCell():getLightSourceAt(x, y, z) ~= ref`) ; `removeLamppost(ref)`.
- Scintillement : faire varier `setR/G/B` (`IsoLightSource.java:157-189`), ≈ 10 Hz, `OnTick` seulement si une fusée est active (coût : hypothèse).
- Nuit : `getClimateManager():getDayLightStrength()` sous un seuil (à régler en jeu).

## Fusée tenue en main

- Un objet activé éclaire, mais **couleur figée** (1 ; 0,82 ; 0,71) (`IsoGameCharacter.java:15947-15957`) : pas de lumière rouge par le script. Un consommable activé s'éteint hors des mains (`DrainableComboItem.java:247-252`). Le vanilla éteint bougies et lanternes posées (`ISDropWorldItemAction.lua:50-79`). Un objet posé n'émet aucune lumière.

## Scripts, traductions, butin

- Objets : `module SignalSmoke { imports { Base } item SmokeGrenadeGreen { … } }` (copie de `SmokeBomb`, `SmokeRange = 0`, `PhysicsObject` non nul). Modèles déclarés dans `module Base` sous un nom préfixé (un modèle sans module est cherché dans `Base`). Maillage vanilla `WorldItems/SmokeBomb` réutilisable avec une texture du mod. Icônes : `Icon = X` → `media/textures/Item_X.png`.
- Traductions : `Translate/<LANG>/ItemName.json`, clés `SignalSmoke.SmokeGrenadeGreen` sans préfixe.
- Butin (`OnPostDistributionMerge`) : `ArmyStorageAmmunition`, `ArmyBunkerStorage`, `ArmySurplusMisc`, `PoliceLockers` ; fusées : `GasStoreEmergency`, `CarSupplyTools`, `FireDeptLockers`, `PoliceLockers` (coffres de véhicules de police : `VehicleDistributions.Police`, pas utilisé en v1).

## API retenue

```lua
local SignalSmoke = require "SignalSmoke/SignalSmoke"   -- mod.info du mod dépendant : require=\batman_SignalSmoke
SignalSmoke.COLORS  -- green, red, yellow, purple, orange, blue, white = { r, g, b }
local id = SignalSmoke.start{ x =, y =, z = 0, color = "green" | { r, g, b },
    minutes = 30 | realSeconds = 90, radius = 1, light = true, id = "artemis:extraction", owner = "OperationArtemis" }
SignalSmoke.stop(id)       -- booléen
SignalSmoke.isActive(id); SignalSmoke.list()
```
Serveur ou solo seulement (client MP : `nil, "server only"`). Même `id` : remplace. Temps en heures de monde (`getWorldAgeHours`) ; `realSeconds` converti par `s × 24 / (DayLengthMinutes × 60)`. Expiration serveur à la minute (comparer, jamais tester l'égalité), clients qui masquent toute entrée échue.

## À vérifier en jeu

Teinte de jour et de nuit ; recréation sans saut ; aller-retour hors zone chargée et rechargement en solo ; en MP, un joueur qui arrive voit la fumée et `OnThrowableExplode` n'agit qu'une fois sur le serveur ; arrêt des sons en boucle ; coût du scintillement ; ramassage d'une fusée allumée ; zombie aveuglé ; deux fumées de rayon 2 sans éviction.

## Relecture Opus du 2026-09-30 (corrigée)

- **Échelle des modèles** (bloquant) : le moteur ignore `UnitScaleFactor` et applique les transformations de nœud ; taille = étendue après nœud × `scale`. Export Blender en mètres → `Lcl Scaling = 100` → `scale ≈ 0.0066` pour 0,26 m (preuves : SmokeBomb vanilla 0,443 × 0,6 ; mods exportés depuis Blender à `scale` 0,0017 à 0,015). Réduit ensuite à `scale = 0.0033` (≈ 0,13 m, grenades et fusées de route) : taille vanilla jugée trop grosse en jeu.
- Lampes : `getLightSourceAt` ne renvoie que la première lampe de la case → présence testée par `getLamppostPositions():contains` ; couleur × 0,5 (le moteur envoie min(couleur × 2, 1)) ; scintillement ralenti.
- Entrée remplacée (même id, autre position ou couleur) : nettoyée d'abord (signature).
- Émetteur libre rendu à la réserve dès qu'il ne joue plus : on en reprend un neuf.
- Plafond de 75 feux (éviction du plus ancien) : au plus 40 feux du mod, et délai de 5 s avant de recréer un feu évincé.
- `triggerExplosionTimer = 50` rétabli ; souffle des grenades joué par les clients pendant toute la fumée ; fusée consumée retirée du sol ; `list`/`isActive` lisibles chez un client MP ; `setAnimVariable` et son d'allumage ; son pour tous les joueurs locaux.
- Reste une hypothèse à tester en MP : un `IsoFire` local durable peut décaler les indices d'objets de sa case.
