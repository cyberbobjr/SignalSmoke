# Signal Smoke — recherche de la v2 (Build 42.21)

Recherche et développement du 2026-10-01 (Java 42.21.0 décompilé, vanilla installé, base de connaissances). **Rien n'est testé en jeu.** Tout est confirmé statiquement sauf mention « hypothèse ». Suite de [recherche-v1.md](recherche-v1.md).

## Événements pour les mods dépendants

- API Lua du module (`SignalSmoke.onSignal(fn)`, `SignalSmoke.removeSignalListener(fn)`), pas un événement `Events.X` : la bibliothèque est déjà un `require` obligatoire, et une liste Lua permet le dédoublonnage (`Events.X.Add` n'en fait pas, `Event.java:29-63`) et un `pcall` par abonné avec une ligne de journal propre au mod.
- Déclenchés sur l'autorité seulement (serveur, solo), après l'écriture au registre et la transmission : `started` (dans `start`, avec `replaced`), `stopped` (dans `stop`, `reason` = `script` ou `pickedUp`), `expired` (dans `expire`).
- Copie de la liste avant l'appel : un abonné peut se retirer pendant l'événement.
- Joueur à l'origine : `username` (`getUsername()`, clé stable en MP ; en solo, nom du personnage, voir `multiplayer.md`), stocké dans l'entrée pour `stopped`/`expired` ; `player` (`IsoPlayer`) seulement pour `started`.
  - Grenade : `trap:getAttacker()`. Sur le serveur, l'`IsoTrap` est créé avec le joueur du paquet (`AddExplosiveTrapPacket.java:134`) ; en solo, avec le lanceur (`IsoMolotovCocktail.java:132`).
  - Fusée, bâton lumineux : personnage de l'action (`complete()` serveur).
  - Bâton lumineux reposé (repéré par sondage) : joueur près duquel il est trouvé (pas forcément celui qui l'a posé, si plusieurs joueurs sont proches).
- Nouveaux champs d'entrée (facultatifs, rétrocompatibles) : `smoke`, `lightRadius`, `source`, `username`, `itemType`, `spentType`. `findFlareObject` reste un alias de `findItemObject`. `start` accepte aussi `untilH` (heure de fin absolue).

## Bâtons lumineux

- Aucun bâton lumineux vanilla en 42.21 (`media/scripts` : ni `Glow`, ni `Chemlight`, ni `Lightstick`).
- Objet neuf `SignalSmoke.Chemlight<Couleur>` (vert, rouge, bleu, jaune) → action « Activer et poser au sol » (`SignalSmoke_ActivateChemlightAction`, modèle de la fusée, `complete()` serveur) → objet `Chemlight<Couleur>Lit` posé avec son heure d'extinction en ModData (`ssUntilH`), créé par `instanceItem` et posé par `AddWorldInventoryItem(item, x, y, z, true)` **après** la ModData (envoyé complet aux clients, `IsoGridSquare.java:5200-5265`).
- Entrée `kind = "chemlight"`, id `chemlight:<id de l'objet>` (idempotent), `smoke = false` : aucun `IsoFire`, donc aucun des 75 feux du plafond (`IsoFireManager.java:68-92`) ; lampe `addLamppost` de rayon 3, couleur × 0,35, toujours allumée, sans scintillement ni son.
- **Ramassage : le bâton reste activé** (choix : un bâton chimique ne s'éteint pas, et le vanilla ne garde éteints que les objets qu'on peut rallumer, `ISDropWorldItemAction.lua:50-79`). Le sondage par minute existant (fusée) arrête l'entrée (`reason = "pickedUp"`) ; l'objet garde sa ModData.
- **Reposer** : le vanilla a plusieurs chemins vers le sol. « Lâcher » passe par `ISInventoryPaneContextMenu.onDropItems` (transfert vers le conteneur du sol), seule la pose 3D (`ISPlace3DItemCursor.lua:30-41`) passe par `ISDropWorldItemAction`. Plutôt que d'envelopper ces chemins, le serveur cherche chaque minute, sur 5 × 5 cases autour de chaque joueur, les bâtons activés absents du registre et les réinscrit avec leur temps restant (`SignalSmoke.startChemlight`). Délai : au plus une minute de jeu.
- Fin : à l'expiration (ou `stop`), l'objet posé est remplacé par `SignalSmoke.ChemlightUsed` (champ générique `spentType`). Un bâton échu porté (inventaire et sacs, hors mains et accroches) devient usagé au contrôle des inventaires (toutes les 10 minutes) ; un bâton échu retrouvé au sol devient usagé quand un joueur passe à côté. Un bâton activé rangé dans un meuble ou un véhicule n'est jamais converti (reste activé, invisible : limite acceptée).
- API vérifiées : `getAllTypeRecurse` (`ItemContainer.java:1870`), `isEquipped`/`isAttachedItem` (`IsoGameCharacter.java:9420-9430`), `sendAddItemToContainer` (`LuaManager.java:9700`), `instanceItem(String)` (`:4675`), `IsoWorldInventoryObject:getOffX/Y/Z` (`:827-835`), `setIgnoreRemoveSandbox` (`:678`).
- Son d'activation : `OpenPlasticBag` (emballage). Aucun son vanilla de bâton plié.

## Fumigène artisanal

- Modèle vanilla : `MakeSmokeBomb` (`recipes_traps.txt:335-352`) : pain de glace (nitrate d'ammonium), bande de tissu, 2 journaux, appris par magazine (`EngineerMagazine2`) ou métier.
- Recettes `SignalSmoke_MakeImprovisedSmoke<Couleur>` (vert, rouge, jaune, violet), `InHandCraft`, `Miscellaneous` (catégorie traduite par le vanilla), 120 unités de temps, **sans apprentissage**, `SkillRequired = Cooking:2`, `xpAward = Cooking:5` (mélange sucre et oxydant fondu ; le vanilla de la bombe fumigène ne demande aucune compétence).
- Ingrédients vérifiés dans `scripts/generated/items` : `tags[base:emptycan]` (`TinCanEmpty`, `normal.txt:7599`, comme `MakeCraftedGasMaskFilter` avec `flags[IsEmpty;ItemCount]`), `tags[base:sugar]` ×2 (`Sugar`, `SugarBrown`, `SugarCubes`, `SugarPacket`, `SugarBeetSugarPot`, comme les recettes de pâtisserie), `[Base.Coldpack;Base.Fertilizer]`, `[Base.Paint<Couleur>]` (drainables, `UseDelta = 0.1`, tag `base:paint`), `[Base.Twine;Base.RippedSheets;Base.RippedSheetsDirty]`.
- Quantités : pour un objet drainable ou un aliment à plusieurs portions, `item N` compte des **utilisations**, sauf `ItemCount`, `mode:destroy` ou `mode:keep` (`InputScript.isUsesPartialItem`, `InputScript.java:187-198`) : une recette prend une dose de peinture, pas le pot.
- Nom affiché : `Recipes.json`, clé = nom de la recette (`Translator.getRecipeName(name)`, `CraftRecipe.java:380`).
- Objets `ImprovisedSmoke<Couleur>` : copie du script des grenades (`SmokeRange = 0`, portée 10). Au lancer, le serveur tire `ZombRand(100) < ImprovisedDudChance` : raté = aucune entrée (l'`IsoTrap` vanilla siffle quand même, sans fumée) ; sinon fumée de `ImprovisedSmokeSeconds` secondes réelles, rayon 1. Aucun événement pour un raté.

## Options sandbox

- Fichier `42.21/media/sandbox-options.txt`, lu dans le dossier de version puis, à défaut, dans `common` (`CustomSandboxOptions.java:33-48`). Les lignes sont concaténées **sans saut de ligne** avant l'analyse (`readFile`) : seuls les commentaires `/* */` sont sûrs.
- Types utilisés : `integer` et `double` (exigent `min`, `max`, `default`), `boolean` (`default`) ; aucun `enum` (format strict en 42.21, `load-warnings.md`).
- Traductions : `Sandbox_<translation>` et `Sandbox_<translation>_tooltip` (`SandboxOptions.java:1296-1302`), page `Sandbox_<page>` (`ServerSettingsScreen.lua:5151`), dans `Sandbox.json`. `%%` pour un pourcentage (`getText` formate toujours).
- Lecture : `SignalSmoke.option(nom)` → `getSandboxOptions():getOptionByName("SignalSmoke.<nom>"):getValue()` (à jour après un changement en cours de partie), puis `SandboxVars.SignalSmoke`, puis `SignalSmoke.DEFAULTS` (contrôlé par les tests contre `sandbox-options.txt`).

| Option | Type | Défaut | Bornes | Lue par |
|---|---|---|---|---|
| `GrenadeSmokeSeconds` | entier | 90 | 20-600 | serveur, éclatement |
| `FlareBurnMinutes` | entier | 60 | 10-720 | serveur, `complete()` |
| `ChemlightHours` | entier | 8 | 1-48 | serveur, activation |
| `ImprovisedSmokeSeconds` | entier | 45 | 10-300 | serveur, éclatement |
| `ImprovisedDudChance` | entier (%) | 20 | 0-100 | serveur, éclatement |
| `LootMultiplier` | réel | 1,0 | 0-10 | fusion du butin |
| `FlaresInPoliceCars` | booléen | vrai | | fusion du butin |

- **Butin** : `OnPostDistributionMerge` réécrit les listes (`SignalSmoke.rewriteLootItems`, idempotente : retire les objets `SignalSmoke.*` puis ajoute les poids × multiplicateur). En solo, les options de la partie ne sont lues qu'après la fusion (`IsoWorld.java:1791-1809`) : à `OnInitGlobalModData`, si elles diffèrent de celles appliquées, réécriture puis `ItemPickerJava.Parse()`. Sur un serveur, déjà lues (`GameServer.java:1421`) : pas de relecture.
- Coffres de police : `VehicleDistributions.PoliceTruckBed` (partagé par `Police` et trois autres véhicules, `VehicleDistributions.lua:3567, 3661, 8415, 8476, 8522`), relu par `ItemPickerJava.ParseVehicleDistributions` (`ItemPickerJava.java:170, 287-330`) avec le même lecteur que les listes procédurales (types complets acceptés).
- Bâtons lumineux (poids par couleur) : `ArmyStorageElectronics` 2, `ArmyBunkerStorage` 1, `ArmySurplusMisc` 2, `PoliceLockers` 0,5, `FireDeptLockers` 0,5, `CampingStoreLighting` 3, `CampingStoreGear` 1, `SurvivalGear` 1 (listes vérifiées dans `ProceduralDistributions.lua`). Fusées dans les coffres de police : 6.

### Option demandée non réalisée : « zombies aveuglés dans la fumée (oui/non) »

Impossible proprement sans retirer la fumée elle-même :
- Un zombie perd sa cible si **sa** case porte le drapeau `IsoFlagType.smoke` (`IsoZombie.java:1705, 1918, 2010, 2292`, même test pour les animaux `BaseAnimalBehavior.java:1322`).
- `IsoFire.update()` repose ce drapeau **à chaque image** pour toute fumée au stade 4 ou plus (`IsoFire.java:402-406`), dans `IsoFireManager.Update()` (`IngameState.java:594`), avant la mise à jour des personnages (`IsoWorld.update`, `:1543`) et avant `OnTick` (`:1681`). Le repérage des joueurs se fait dans `IsoPlayer.updateLOS` (`IsoPlayer.java:2028`), avant `OnPlayerUpdate` (`:2198`). Aucun moment Lua ne s'intercale entre la pose du drapeau et le test.
- Sortir le feu de `IsoFireManager` (plus de mise à jour) supprimerait le drapeau mais figerait l'animation : la trame n'avance que dans `IsoFire.update` et `IsoSpriteInstance` n'expose pas `setFrame`.
- Pistes, à décider : fumée sans `IsoFire` (aucune autre fumée vanilla), ou laisser le comportement vanilla (choisi).

## Modèles et icônes

- Blender 5.2.2 sans interface : `source/items/build_items.py` (groupes `chemlight,improvised`). Bâton : une géométrie couchée (0,48 m dans Blender ≈ 0,16 m en jeu à `scale = 0.0033`), 9 textures (neuf pâle, activé lumineux, usagé gris). Fumigène : boîte de conserve 0,30 m (≈ 0,10 m), bande de couleur, couvercle de ruban adhésif, mèche, 4 textures.
- Correctif de la recette : chaque icône ajoutait un soleil à la scène (icônes de plus en plus claires dans un même groupe) ; caméra et soleil sont maintenant remplacés. Les icônes existantes (grenades, fusées) n'ont pas été régénérées.

## À vérifier en jeu

Taille et orientation des nouveaux modèles au sol et en main ; recette visible avec Cuisine 2 et consommation d'une seule dose de peinture et d'engrais ; raté du fumigène artisanal ; bâton lumineux : lueur de nuit, ramassage puis lâcher (rallumage en moins d'une minute de jeu), conversion en bâton usagé ; options sandbox affichées et appliquées en solo (butin relu) et sur serveur ; événements reçus par un mod de test.
