# Signal Smoke : améliorations et idées

- **Mod** : Signal Smoke, `id=batman_SignalSmoke`, version `0.2.3` (`Contents/mods/batman_SignalSmoke/42.21/mod.info:2,7`), Workshop 3811010882.
- **Date** : 2026-10-21. Cible : Build 42.21 (`versionMin=42.21`).
- **Périmètre lu** : tout le Lua (`shared/SignalSmoke/SignalSmoke.lua`, `server/SignalSmoke/SignalSmoke_Server.lua`, `server/Items/SignalSmoke_Distributions.lua`, `client/SignalSmoke/SignalSmoke_Client.lua`, `client/SignalSmoke/SignalSmoke_Menu.lua`, les deux actions chronométrées), les scripts (objets, recettes, modèles), `sandbox-options.txt`, les traductions EN/FR (les autres langues ont les mêmes clés, contrôlées par `tests/run_tests.py`), `README.md`, `CHANGELOG.md`, `docs/annexes/recherches/recherche-v1.md` et `recherche-v2.md`, `docs/annexes/tests/test-v1.md` et `test-v2.md`, `tests/run_tests.py`, `.luacheckrc`. Appels de l'API par les mods dépendants : `OperationArtemis` (`Artemis_Rendezvous.lua`, `Artemis_BeaconDirector.lua`) et `RadioSurvivor` (`RS_MissionSignal.lua`, `RS_RescueVisit.lua`, `RS_TradeRun.lua`). Base moteur : `.claude/pz-knowledge/staging-effects.md` (fumée, fusées, bâtons lumineux, sirène), `multiplayer.md`, `world-placement.md`, `sounds-and-noise.md`.
- **Statut** : analyse statique seulement. Aucun test en jeu n'a été fait pour ce document. Les deux protocoles de test existants (`test-v1.md`, `test-v2.md`) ont encore toutes leurs cases vides (☐).
- Les chemins Lua ci-dessous partent de `Contents/mods/batman_SignalSmoke/42.21/media/lua/`.

### API publique réellement utilisée

| Élément | Utilisé par | Remarque |
|---|---|---|
| `start{…}`, `stop(id)` | Artemis (4 appels), RadioSurvivor (`RS_RescueVisit`) | cœur de l'API, stable depuis 0.1.0 |
| `list()`, `isActive(id)` | Artemis `BeaconDirector:56-65` | lit aussi `entry.untilH` : ce champ fait partie du contrat |
| `onSignal(fn)` | RadioSurvivor (`RS_MissionSignal`, `RS_TradeRun`) | lit `entry.color`, `x/y/z`, `kind`, `source`, `player`, `username` |
| `COLORS` | RadioSurvivor (2 fichiers) | sert à **retrouver le nom de la couleur** à partir du RGB (voir C04) |
| type d'objet `SignalSmoke.RoadFlareLit` | Artemis `Rendezvous:28,85` | Artemis pose lui-même l'objet (voir C06) |

Les mods consommateurs testent la présence des fonctions par leur type (`type(mod.onSignal) == "function"`) : aucun numéro de version d'API n'est lu (voir C05).

---

## Partie 1 : améliorations du code

Légende. **Statut** : *confirmé statiquement* (lu dans le code) ou *à vérifier en jeu*. **Priorité** : P1 (à faire en premier) à P3. **Effort** : S (moins d'une heure), M (une demi-journée), L (plus).

### C01 : une fusée allumée qu'on ramasse reste « Fusée de route (allumée) » pour toujours

- **Problème** : ramasser une fusée qui brûle arrête l'entrée (`reason = "pickedUp"`), mais l'objet `RoadFlareLit` reste dans l'inventaire tel quel. Le menu ne propose « Allumer » que pour `RoadFlare` et ne propose rien pour `RoadFlareLit`. Le serveur ne cherche que les bâtons lumineux, jamais les fusées. Une fusée reposée ne se rallume donc pas, et l'objet ne se consume jamais. L'objet `RoadFlareLit` n'a ni `Tooltip` ni `StaticModel` (rien ne s'affiche en main). Le README dit « Pick it up to put it out », mais l'objet garde son nom « (allumée) ».
- **Preuve** : `server/SignalSmoke/SignalSmoke_Server.lua:142-155` (arrêt au ramassage) ; `client/SignalSmoke/SignalSmoke_Menu.lua:33` (seul `FLARE_TYPE` a une option) ; `SignalSmoke_Server.lua:87-113` (le sondage ne connaît que `chemlightOf`) ; `scripts/SignalSmoke_items.txt:150-157` (objet `RoadFlareLit` sans `Tooltip` ni `StaticModel`). Artemis pose aussi des `RoadFlareLit` que les joueurs peuvent ramasser (`Artemis_Rendezvous.lua:85`).
- **Risque** : bug de jeu visible (un objet mort qui se présente comme allumé) ; incohérence avec les bâtons lumineux.
- **Correction** : reprendre le modèle des bâtons lumineux. Option A : à l'allumage, écrire l'heure de fin dans la ModData de l'objet ; reposée, la fusée se rallume pour le temps qui lui reste (sondage générique sur une liste de types « suivis », pas seulement les bâtons) ; échue, elle devient `RoadFlareUsed` (nouvel objet « fusée consumée », type `Junk`). Option B, plus simple : au ramassage, la fusée devient tout de suite `RoadFlareUsed` (« une fusée ne se rallume pas »). Dans les deux cas : ajouter `Tooltip` et `StaticModel` à `RoadFlareLit`, passer `spentType` à l'entrée de la fusée et l'utiliser aussi chez Artemis.
- **Statut** : confirmé statiquement ; ce qui se passe à l'écran est à vérifier en jeu. **Priorité** : P1. **Effort** : M (A) / S (B).
- **Statut : corrigé (commit 4215b9a), à vérifier en jeu** — option A : heure de fin et couleur dans la ModData de l'objet (`markItemObject`), rallumage au sol par `startFlare` (sondage commun avec les bâtons), fusée consumée retirée de l'inventaire (pas d'objet `RoadFlareUsed` : elle disparaît comme au sol) ; `Tooltip` et `StaticModel` ajoutés à `RoadFlareLit`. Une fusée tenue en main ou accrochée attend d'être rangée.

### C02 : un objet suivi dont l'entrée échoit sur une case non chargée n'est jamais retiré

- **Problème** : `removeItemObject` ne fait rien si la case n'est pas chargée, mais `expire()` et `stop()` retirent quand même l'entrée du registre. Pour un bâton lumineux, le sondage près des joueurs rattrape plus tard l'objet échu (`startChemlight` le convertit). Pour une fusée, rien ne le rattrape : un `RoadFlareLit` reste au sol pour toujours, sans lumière ni fumée. Cela arrive aussi avec la fusée d'Artemis si personne n'est à proximité à la fin.
- **Preuve** : `shared/SignalSmoke/SignalSmoke.lua:426-438` (sortie silencieuse si `findItemObject` rend `nil, false`) ; `:570-573` (entrée retirée quand même) ; `:520-521` (même chose dans `stop`) ; le rattrapage n'existe que pour les bâtons lumineux (`SignalSmoke_Server.lua:87-113`, `SignalSmoke.lua:490-496`).
- **Risque** : objets fantômes qui s'accumulent ; incohérence entre la sauvegarde et le registre.
- **Correction** : garder dans la ModData une petite liste `pending = { [itemId] = { x, y, z, spentType } }` des retraits ratés, puis la retraiter au chargement de la case (`LoadGridsquare` côté serveur ou solo) ou au sondage des joueurs. Autre solution : étendre le sondage générique de C01 à tout type « allumé » sans entrée active. Une seule correction couvre C01 (option A) et C02.
- **Statut** : confirmé statiquement. **Priorité** : P1. **Effort** : M.
- **Statut : corrigé (commit 4215b9a), à vérifier en jeu** — rattrapage par le sondage près des joueurs (fusée échue ou sans heure de fin retirée). Les objets suivis d'un autre type (ni fusée ni bâton) n'ont toujours pas de liste `pending`.

### C03 : les infobulles annoncent des durées fixes que les options sandbox changent

- **Problème** : « environ une minute et demie » (grenade), « environ une heure de jeu » (fusée), « plusieurs heures » (bâton) sont écrits en dur dans les 10 langues. Avec `GrenadeSmokeSeconds = 600` ou `FlareBurnMinutes = 10`, le texte est faux.
- **Preuve** : `shared/Translate/EN/Tooltip.json:2-3`, `FR/Tooltip.json:2-3` (même chose dans toutes les langues) ; options lues dans `SignalSmoke_Server.lua:36-41` et `SignalSmoke_LightFlareAction.lua:232`, bornes dans `sandbox-options.txt:378-394`.
- **Risque** : traduction et confiance du joueur.
- **Correction** : soit des textes neutres (« pendant un moment, selon les réglages du serveur »), soit une infobulle dynamique avec une clé `%1` remplie par l'option (enveloppe de `ISToolTipInv:render`, technique décrite dans `ui-windows.md`). Le passage aux textes neutres reste une simple traduction (dix fichiers).
- **Statut** : confirmé statiquement. **Priorité** : P2. **Effort** : S (textes neutres) / M (dynamique).
- **Statut : corrigé (commit 4215b9a), à vérifier en jeu** — textes « par défaut, réglable par les options » dans les 10 langues (pas d'infobulle dynamique).

### C04 : la couleur nommée n'est pas dans l'entrée, et les mods dépendants la retrouvent par tolérance RGB

- **Problème** : `newEntry` ne garde que `{ r, g, b }`. RadioSurvivor retrouve donc « rouge » ou « vert » en comparant le RGB à `SignalSmoke.COLORS` avec une tolérance. Une simple retouche de teinte dans `COLORS` (par exemple pour rendre une fumée plus lisible) casserait en silence les missions de RadioSurvivor.
- **Preuve** : `SignalSmoke.lua:200, 230` (seul le RGB est gardé) ; `RadioSurvivor/.../RS_TradeRun.lua:225-233` (`isColor`, `COLOR_TOLERANCE`) ; `RS_MissionSignal.lua:15` (« The colour name is found back by comparing the entry colour to SignalSmoke.COLORS »).
- **Risque** : stabilité de l'API publique (couplage caché à des valeurs internes).
- **Correction** : ajouter un champ facultatif `colorName` (le nom si `opts.color` est une chaîne, sinon `nil`) et une fonction `SignalSmoke.colorNameOf(entry)` qui rend `colorName` ou, à défaut, le nom le plus proche (pour les entrées sauvegardées avant). Le changement est rétrocompatible. Il faut le documenter dans l'en-tête et le README, puis faire passer RadioSurvivor à `colorNameOf`.
- **Statut** : confirmé statiquement. **Priorité** : P1. **Effort** : S.
- **Statut : corrigé (commit 4215b9a), à vérifier en jeu** — champ `colorName` et `SignalSmoke.colorNameOf(entry)` ; RadioSurvivor n'est pas encore passé à `colorNameOf`.

### C05 : aucune version d'API ; `VERSION` (schéma) n'a pas bougé à la migration 0.2.3

- **Problème** : `SignalSmoke.VERSION = 1` désigne la version du registre, mais la 0.2.3 a changé le schéma (retrait de `username`) sans l'incrémenter, et `registry()` réécrit `data.v = 1` à chaque appel. Les mods dépendants ne peuvent pas savoir si `onSignal`, `kind = "chemlight"` ou un futur `colorName` sont disponibles autrement qu'en testant chaque fonction.
- **Preuve** : `SignalSmoke.lua:61, 380` ; tests de présence dans `RS_MissionSignal.lua:70`, `RS_RescueVisit.lua:262`, `RS_TradeRun.lua:214`.
- **Risque** : stabilité de l'API et maintenance des migrations futures.
- **Correction** : `SignalSmoke.API_VERSION = 3` (1 : 0.1.0, 2 : événements et bâtons lumineux, 3 : `colorName` et `placeFlare`), plus un tableau des ajouts par version dans le README. Passer le schéma à `VERSION = 2` et ne migrer que si `data.v < 2` (voir C07).
- **Statut** : confirmé statiquement. **Priorité** : P2. **Effort** : S.
- **Statut : corrigé (commit 4215b9a), à vérifier en jeu** — `API_VERSION = 3`, schéma `VERSION = 2`.

### C06 : la pose d'une fusée par script est recopiée dans Artemis

- **Problème** : Artemis refait à la main ce que fait `SignalSmoke_LightFlareAction:complete()` : `AddWorldInventoryItem("SignalSmoke.RoadFlareLit")`, `setIgnoreRemoveSandbox(true)`, puis `start{ kind = "flare", itemId = … }`. Toute correction de la fusée (C01, C02, `spentType`) devra donc être faite deux fois. De plus, Artemis demande une fusée **verte** : la lumière sera verte, mais le modèle `RoadFlareLit` reste rouge.
- **Preuve** : `OperationArtemis/.../Artemis_Rendezvous.lua:28, 84-92` contre `shared/TimedActions/SignalSmoke_LightFlareAction.lua:221-235`.
- **Risque** : maintenance ; incohérence visuelle.
- **Correction** : ajouter à l'API `SignalSmoke.placeFlare{ x, y, z, color, minutes, id, owner, source, player }`. Côté autorité, la fonction pose l'objet, le protège du nettoyage, inscrit l'entrée avec `itemId` et `spentType`, puis rend l'identifiant. `LightFlareAction` et Artemis l'appellent tous les deux. Plus tard, éventuellement : des variantes `RoadFlareLit<Couleur>` ou une fusée verte.
- **Statut** : confirmé statiquement. **Priorité** : P2. **Effort** : S à M.
- **Statut : corrigé (commit 4215b9a), à vérifier en jeu** — `SignalSmoke.placeFlare` ajouté et utilisé par `LightFlareAction` ; Artemis ne l'a pas encore adopté (sa fusée verte posée à la main reçoit déjà heure de fin et couleur via `start`). Modèle vert non traité.

### C07 : `registry()` relance la migration à chaque appel

- **Problème** : chaque `start`, `stop` et `expire` (donc au moins une fois par minute de jeu) parcourt tout le registre pour retirer d'éventuels `username`. Pourtant, la migration n'a d'intérêt qu'une fois, au chargement.
- **Preuve** : `SignalSmoke.lua:375-387` (appel à `stripUsernames(data)` à chaque `registry()`), `:359-372`.
- **Risque** : coût linéaire inutile (faible tant que le registre reste petit), et une migration difficile à lire.
- **Correction** : un indicateur local `migrated` dans une table d'état (pas sur la fonction), posé par `SignalSmoke.migrate()` ; garder `registry()` en simple `getOrCreate`. À combiner avec la version de schéma de C05.
- **Statut** : confirmé statiquement. **Priorité** : P3. **Effort** : S.
- **Statut : corrigé (commit 4215b9a), à vérifier en jeu** — migration une seule fois par chargement du Lua (table d'état `state.migrated`).

### C08 : les identifiants automatiques peuvent entrer en collision après un rechargement

- **Problème** : `nextAutoId` repart à 1 à chaque chargement du Lua, et l'identifiant vaut `auto:<minute de monde>:<compteur>`. Une entrée sans `id` créée juste avant une sauvegarde, puis une autre créée dans la même minute de jeu après le rechargement, portent le même identifiant : la seconde **remplace** la première sans erreur (avec `replaced = true`).
- **Preuve** : `SignalSmoke.lua:153, 461-464, 466-467`.
- **Risque** : bug rare, perte silencieuse d'un signal (une grenade lancée juste après un chargement).
- **Correction** : garder le compteur dans le registre (`data.nextId`), ou ajouter un suffixe tiré au hasard. Le changement est rétrocompatible.
- **Statut** : confirmé statiquement (collision rare). **Priorité** : P3. **Effort** : S.

### C09 : le registre complet part à tous les clients à chaque changement

- **Problème** : (a) chaque `start` ou `stop` lance un `ModData.transmit` du registre entier ; le ramassage de N objets dans la même minute en lance N (`stop` dans une boucle). Les bâtons lumineux restent 8 h de jeu au registre, qui peut grossir sur un serveur actif. (b) Depuis la 0.2.3, les noms des joueurs ne partent plus, mais les **positions** de tous les bâtons et fusées, y compris ceux posés dans les bases, sont envoyées à tous les clients. Une ModData globale est en outre lisible par tout client qui la demande (`multiplayer.md`, « Aucune donnée secrète dans une ModData globale »).
- **Preuve** : `SignalSmoke.lua:351-355, 469, 522, 575` ; `SignalSmoke_Server.lua:153-155` ; `.claude/pz-knowledge/multiplayer.md:110-112`.
- **Risque** : réseau (faible) ; confidentialité des bases en MP (faible sur un serveur entre amis, comme le note la préférence « anti-triche peu prioritaire »).
- **Correction** : (a) marquer le registre comme modifié et ne transmettre qu'une fois par minute, à la fin de `onEveryOneMinute`, avec un envoi immédiat seulement pour `start` (pour que la fumée apparaisse tout de suite). (b) Plus tard, si besoin : n'envoyer à chaque client que les entrées proches de lui (`sendServerCommand` par joueur, rayon de 150 cases), au prix d'un protocole plus complexe ; ce n'est pas indispensable.
- **Statut** : confirmé statiquement. **Priorité** : P3. **Effort** : S (a) / L (b).

### C10 : un bâton reposé n'est repéré que dans les 5 × 5 cases du joueur et à son étage

- **Problème** : le sondage ne regarde que 2 cases autour de chaque joueur, à son étage. Dans ces cas, un bâton posé ne se rallume qu'au prochain passage d'un joueur : posé avec le curseur 3D à la limite de portée, lâché juste avant de s'éloigner (le sondage passe une fois par minute), ou posé en haut d'un escalier. `event.player` désigne alors le joueur qui passe, pas celui qui a posé le bâton (limite déjà notée dans `recherche-v2.md`).
- **Preuve** : `SignalSmoke_Server.lua:27, 87-113, 156-159`.
- **Risque** : un bâton posé dans le noir reste éteint, ce qui ressemble à un bug pour le joueur.
- **Correction** : rayon 4 et étages z−1 à z+1 (coût : 9 × 9 × 3 cases par joueur et par minute, négligeable), ou mémoriser pour chaque joueur la dernière case examinée. Mieux encore : déclencher aussi le sondage pour ce joueur quand le serveur reçoit le transfert vers le sol (enveloppe légère de `ISDropWorldItemAction:complete` et du transfert vers le conteneur du sol), en gardant le sondage comme filet de sécurité.
- **Statut** : à vérifier en jeu (portée réelle du curseur 3D). **Priorité** : P2. **Effort** : S (rayon) / M (déclenchement).

### C11 : l'infobulle du bâton activé promet une lumière qu'il ne donne pas une fois ramassé

- **Problème** : « ramassé, il continue de briller jusqu'à épuisement ». En réalité, un objet tenu ou porté n'émet aucune lumière : l'objet `Chemlight*Lit` n'a aucune propriété de lumière, et le client ne dessine de lampe que pour les entrées du registre, donc pour les objets posés au sol.
- **Preuve** : `Translate/FR/Tooltip.json:5`, `EN/Tooltip.json:5` ; `scripts/SignalSmoke_items.txt` (objets `Chemlight*Lit`) ; `SignalSmoke_Client.lua:355-368`. Une lumière en main garde la couleur fixe du moteur (`recherche-v1.md`, « Fusée tenue en main »).
- **Risque** : texte trompeur.
- **Correction** : reformuler (« ramassé, il reste activé et se rallume dès qu'on le repose ») ou réaliser I02.
- **Statut** : confirmé statiquement. **Priorité** : P2. **Effort** : S.

### C12 : risque MP non testé, la fumée locale décale peut-être les indices d'objets de sa case

- **Problème** : en MP, chaque client ajoute un `IsoFire` local à la liste d'objets de la case. La recherche v1 note comme hypothèse que les indices d'objets locaux peuvent alors différer de ceux du serveur. Pour la **fusée**, la fumée (rayon 0) est posée **sur la case même** de l'objet suivi, que les joueurs viennent justement ramasser. Pour les grenades, la croix de 5 cases peut couvrir des meubles, des portes ou des cadavres. Le vanilla prend le même risque avec sa propre fumée, mais pour environ 25 s seulement, alors que les fumées du mod durent jusqu'à 10 min (grenade) ou 12 h de jeu (fusée).
- **Preuve** : `docs/annexes/recherches/recherche-v1.md` (« Risque (hypothèse) ») ; `SignalSmoke_Client.lua:292-303` (`AddTileObject`) ; `SignalSmoke_LightFlareAction.lua:229-235` (`radius = 0` sur la case de l'objet).
- **Risque** : MP, interactions qui échouent ou visent le mauvais objet (ramassage, conteneur, porte).
- **Correction** : d'abord un test MP ciblé (ramasser la fusée qui brûle, ouvrir un meuble et une porte dans la croix d'une grenade, depuis deux clients). Si le décalage est confirmé : poser la fumée de la fusée sur une case voisine libre, et la fumée des grenades seulement sur des cases sans objet interactif.
- **Statut** : à vérifier en jeu. **Priorité** : P1 (test) / P2 (correction éventuelle). **Effort** : S (test) / M.

### C13 : le client refait chaque seconde des calculs qui pourraient être gardés

- **Problème** : `diskOffsets(radius)` reconstruit une table neuve pour chaque entrée à chaque seconde ; `countOwnFires()` parcourt tous les feux du mod à chaque création ; `signature()` concatène 12 champs par entrée et par seconde.
- **Preuve** : `SignalSmoke_Client.lua:237-247, 457` ; `:280-293` ; `:249-254, 442`.
- **Risque** : coût faible (rayon ≤ 2, au plus 40 feux), mais du travail pour le ramasse-miettes sur un client qui a déjà fort à faire.
- **Correction** : garder les décalages par rayon (3 tables fixes), tenir à jour un compteur de feux (création +1, extinction ou disparition −1), ne recalculer la signature que lorsqu'une nouvelle copie du registre arrive (`setReceived`) ou qu'une entrée change en solo.
- **Statut** : confirmé statiquement. **Priorité** : P3. **Effort** : S.

### C14 : rien n'a été testé en jeu, et il n'existe aucun scénario automatique

- **Problème** : tous les parcours de `test-v1.md` et `test-v2.md` sont encore à ☐ (taille des modèles, fumée colorée, bâtons, recettes, options, événements, MP). La bibliothèque est pourtant exigée (`require=`) par Artemis et RadioSurvivor. L'outil générique `pz-autotest` (solo, serveur, MP sans personne) existe dans le workspace.
- **Preuve** : `docs/annexes/tests/test-v1.md:9-15`, `test-v2.md:9-17` ; `tests/run_tests.py` (Lua pur avec `lupa`, cohérence, luacheck : rien dans le moteur).
- **Risque** : les régressions passent inaperçues chez les mods dépendants ; les hypothèses MP (C12) restent sans réponse.
- **Correction** : un scénario `pz-autotest` minimal, d'abord le parcours nominal : `start` vert de rayon 1 → présence d'`IsoFire` marqués et d'une lampe la nuit → `stop` → plus aucun feu ; fusée allumée par l'action → ramassage → événement `pickedUp` ; bâton activé → `expire` → `ChemlightUsed`. Ensuite le même scénario en MP avec deux clients (`autoclient --mp`), en comptant les erreurs avec `getLuaDebuggerErrorCount`.
- **Statut** : confirmé statiquement (absence de tests). **Priorité** : P1. **Effort** : M.

### C15 : `list()` et `event.entry` rendent les tables vivantes du registre, et il n'existe pas de `get(id)`

- **Problème** : `list()` construit à chaque appel une table de toutes les entrées actives, alors qu'Artemis ne veut qu'une entrée (`list()[id]`). Les entrées rendues sont celles du registre lui-même : un mod qui les modifie (« à ne pas modifier », simple consigne) change l'état du serveur sans transmission ni signature.
- **Preuve** : `SignalSmoke.lua:546-558, 300-302` ; `OperationArtemis/.../Artemis_BeaconDirector.lua:56-57`.
- **Risque** : stabilité de l'API (corruption par un consommateur), petit coût.
- **Correction** : ajouter `SignalSmoke.get(id)`, qui rend une **copie** de l'entrée active ou `nil`, et le documenter comme le moyen conseillé. Pour `event.entry`, garder la table actuelle (compatibilité) mais documenter `get` ou une copie. Plus tard, éventuellement : `extend(id, minutes)` pour prolonger une balise sans redéclencher `started` (Artemis rappelle `start` toutes les heures pour la même balise).
- **Statut** : confirmé statiquement. **Priorité** : P3. **Effort** : S.

### C16 : luacheck ne contrôle aucune globale

- **Problème** : `global = false` désactive la détection des globales accidentelles (faute de frappe dans un nom local, `local` oublié). Le mod n'a que deux globales voulues : `SignalSmoke_LightFlareAction` et `SignalSmoke_ActivateChemlightAction`.
- **Preuve** : `.luacheckrc:4-6`.
- **Risque** : maintenance, car une variable globale créée par erreur peut entrer en collision avec un autre mod.
- **Correction** : `allow_defined_top = false`, `globals = { "SignalSmoke_LightFlareAction", "SignalSmoke_ActivateChemlightAction" }`, `read_globals` alimenté par une liste des globales du jeu (une liste du même genre existe peut-être dans un autre dépôt de l'utilisateur, à réutiliser), ou au minimum `ignore = { "113" }` limité aux accès en lecture (code 113) pour garder l'alerte sur les écritures (code 111).
- **Statut** : confirmé statiquement. **Priorité** : P3. **Effort** : S.

---

## Partie 2 : idées de fonctionnalités

Rien de ce qui suit n'est décidé. **Effort** : S / M / L comme plus haut.

### I01 : pistolet lance-fusées (fusée éclairante dans le ciel)

- **Description** : un pistolet de détresse (objet de mod, arme à une munition) et des cartouches rouges ou vertes. Tirée vers le haut, la fusée éclaire et colore une large zone pendant quelques dizaines de secondes.
- **Intérêt** : signal visible de très loin, de nuit ; donne un vrai sens au mot « signal », qu'aucun objet vanilla ne propose.
- **Faisabilité moteur** : `WorldFlares.launchFlare(durée, x, y, portée, vent, r, g, b, ri, gi, bi)` est exposé, avec scintillement et décroissance (`staging-effects.md`, « Fusée éclairante »). L'effet est purement local et non sauvegardé, ce qui convient à un effet court.
- **Impact MP** : nouvelle entrée `kind = "skyflare"` au registre ; chaque client dans la portée appelle `launchFlare` une seule fois par identifiant. Pas de restauration après un chargement (durée courte).
- **Dépendances** : modèle, icône et son de tir (recette Blender existante) ; butin (marine, police, armée).
- **Effort** : M.

### I02 : bâton lumineux tenu en main ou accroché qui éclaire

- **Description** : un bâton activé, en main ou accroché à la ceinture ou au sac, donne une petite lueur de sa couleur autour de son porteur, vue de tous.
- **Intérêt** : se repérer entre coéquipiers dans le noir, explorer un sous-sol sans lampe torche ; corrige aussi l'infobulle de C11.
- **Faisabilité moteur** : une lumière d'objet tenu garde la couleur fixe du moteur (1 ; 0,82 ; 0,71), donc ne convient pas. À la place : chaque client cherche, chaque seconde, les joueurs proches qui tiennent ou portent un `Chemlight*Lit` (objets en main et accrochés, déjà visibles chez les autres clients) et pose ou déplace une lampe `addLamppost` à leur case (recréée à chaque changement de case, puisque le rayon et la position sont fixés à la création).
- **Impact MP** : aucun nouveau paquet si les objets accrochés sont bien connus des autres clients (à vérifier en jeu) ; coût d'une lampe recréée à chaque pas.
- **Dépendances** : C11.
- **Effort** : M.

### I03 : fusée et grenade qui attirent les zombies (leurre), en option

- **Description** : option sandbox « Les fusées attirent les zombies » (et une autre pour les grenades) : une fusée qui brûle émet un bruit répété qui attire les zombies proches.
- **Intérêt** : vrai choix tactique, entre éloigner une horde et attirer l'attention ; complète l'aveuglement dans la fumée.
- **Faisabilité moteur** : `getWorldSoundManager():addSoundRepeating(nil, x, y, z, rayon, volume, false, true)` une fois par seconde, sur le modèle de la sirène vanilla (`staging-effects.md`, « Sirène qui attire les zombies ») ; un bruit répété est ignoré à moins de 5 cases en vue, ce qui évite l'empilement ; un rayon ≥ 50 touche les zombies virtuels.
- **Impact MP** : bruit émis par le serveur (déjà l'autorité du registre) ; envoyé par le moteur aux connexions concernées.
- **Dépendances** : options sandbox et traductions ; serveur, case chargée.
- **Effort** : S.

### I04 : infobulle avec le temps restant

- **Description** : l'infobulle d'un bâton activé ou d'une fusée affiche « encore environ 3 h » ; celle des grenades donne la durée réglée par le serveur.
- **Intérêt** : savoir quand reposer un nouveau bâton ; règle aussi C03.
- **Faisabilité moteur** : ModData `ssUntilH` déjà posée sur l'objet ; `getWorldAgeHours` côté client ; ligne ajoutée par enveloppe de `ISToolTipInv:render` (penser au cas où `item` est un `FluidContainer`, `ui-windows.md`).
- **Impact MP** : la ModData de l'objet est envoyée avec l'objet ; aucun nouveau paquet.
- **Dépendances** : C01 (heure de fin des fusées).
- **Effort** : S.

### I05 : grenades orange, bleue et blanche

- **Description** : les couleurs `orange`, `blue` et `white` existent déjà dans `COLORS` mais n'ont pas de grenade. La blanche serait une fumée d'écran (rayon 2) plutôt qu'un signal.
- **Intérêt** : plus de codes couleur entre joueurs ; la fumée blanche sert à couvrir une fuite.
- **Faisabilité moteur** : copie des scripts et des textures (recette `build_items.py`) ; `GRENADES` dans `SignalSmoke.lua:81-90` ; aucune nouvelle mécanique.
- **Impact MP** : aucun (même chemin).
- **Dépendances** : 3 × 10 traductions, icônes, butin.
- **Effort** : S.

### I06 : outil d'administration pour poser ou arrêter des signaux

- **Description** : un bouton dans le panneau debug ou admin qui ouvre une petite fenêtre : couleur, type, durée, rayon, « ici » ou case cliquée, et liste des signaux actifs avec un bouton « arrêter ».
- **Intérêt** : animateurs de serveur (événements, chasses au trésor), tests des mods dépendants, nettoyage d'un signal resté bloqué.
- **Faisabilité moteur** : bouton dans `ISDebugMenu:setupButtons` ou `ISAdminPanelUI` (`ui-windows.md`) ; commande client → serveur avec contrôle `checkPermissions` et `getRole():hasCapability` (`multiplayer.md`, rôles).
- **Impact MP** : une commande `sendClientCommand` réservée aux administrateurs.
- **Dépendances** : traductions de l'interface.
- **Effort** : M.

### I07 : flèche de direction vers les signaux d'équipe

- **Description** : quand une fumée ou une fusée posée par un membre de sa faction ou de son refuge s'allume à moins de N cases, une flèche discrète au bord de l'écran indique sa direction pendant quelques secondes.
- **Intérêt** : la fumée PZ est un décor au sol, invisible hors de l'écran ; la flèche lui donne une vraie portée de signal.
- **Faisabilité moteur** : `addDirectionArrow`, déjà décrit pour l'hélicoptère simulé (`staging-effects.md`) ; faction ou refuge connus côté serveur.
- **Impact MP** : le serveur envoie `{ id, x, y }` aux seuls membres concernés (`sendServerCommand` par joueur), ce qui ne fuit rien de plus que C09.
- **Dépendances** : option sandbox (désactivable) ; nom du lanceur gardé en mémoire côté serveur (déjà fait depuis la 0.2.3).
- **Effort** : M.

### I08 : fusée de route jetable (lancée allumée)

- **Description** : « Allumer et lancer » : la fusée part comme une grenade et brûle là où elle tombe.
- **Intérêt** : baliser une zone à distance, éclairer une rue avant d'y entrer, servir de leurre avec I03.
- **Faisabilité moteur** : une seconde variante d'objet `RoadFlareThrown` en arme jetable (copie de la grenade, `SmokeRange = 0`) ; à l'éclatement (`OnThrowableExplode`, serveur), pose d'un `RoadFlareLit` au sol et inscription comme une fusée posée (`placeFlare` de C06).
- **Impact MP** : même chemin que les grenades (événement sur le serveur, déjà filtré).
- **Dépendances** : C06.
- **Effort** : M.

### I09 : allumer un feu de camp ou un poêle avec une fusée

- **Description** : une fusée de route sert d'allume-feu (elle est consommée).
- **Intérêt** : réaliste, et donne une seconde utilité à un objet de butin courant.
- **Faisabilité moteur** : ajout de la fusée aux listes d'allume-feu vanilla (tag ou liste utilisés par le feu de camp en 42.21, à relever dans `ISCampingMenu` et `ISFireplaceMenu`) ; sinon une option de menu contextuel qui consomme la fusée et appelle l'action vanilla.
- **Impact MP** : celui de l'action vanilla.
- **Dépendances** : aucune.
- **Effort** : S à M (selon que le vanilla lit un tag ou non : à vérifier).

### I10 : balise stroboscopique à piles

- **Description** : petit objet électronique, à poser et allumer, qui clignote (blanc ou rouge) en usant ses piles. On peut l'éteindre et le ramasser.
- **Intérêt** : marquer une base ou un point de ralliement durablement, sans consommer de bâtons.
- **Faisabilité moteur** : réutilise le scintillement des fusées (`onFlickerTick`, `SignalSmoke_Client.lua:416-430`) avec un motif marche/arrêt ; usure de la pile par la ModData de l'objet, comme pour les objets à pile (`power-and-lights.md`).
- **Impact MP** : entrée du registre `kind = "strobe"` ; pile décomptée par le serveur.
- **Dépendances** : modèle, butin (magasins d'électronique, chantiers).
- **Effort** : M.

### I11 : événements `dud` et `refreshed` pour les mods dépendants

- **Description** : `onSignal` reçoit aussi `type = "dud"` (fumigène artisanal raté, avec position et joueur) et `type = "refreshed"` quand `extend` ou un `start` de même identifiant ne change que la durée.
- **Intérêt** : une mission de RadioSurvivor peut alors répondre « ta fumée n'a pas pris » ; Artemis cesse de faire passer un simple prolongement pour un nouveau signal.
- **Faisabilité moteur** : pur Lua (`SignalSmoke_Server.lua:38-40`, `SignalSmoke.lua:466-470`).
- **Impact MP** : aucun (événements sur l'autorité).
- **Dépendances** : C05 (version d'API), C15 (`extend`).
- **Effort** : S.

### I12 : requête spatiale `SignalSmoke.findNear(x, y, rayon, filtre)`

- **Description** : fonction de bibliothèque qui rend les signaux actifs autour d'un point, filtrés par couleur, type, source.
- **Intérêt** : les mods dépendants n'ont plus à refaire leur propre test de distance dans `onSignal` (`RS_TradeRun` le fait) ; un futur mod de largage peut demander « y a-t-il une fumée verte à moins de 30 cases ? ».
- **Faisabilité moteur** : pur Lua, sur l'autorité comme chez le client (copie reçue).
- **Impact MP** : aucun.
- **Dépendances** : C04 (`colorName`).
- **Effort** : S.

### I13 : fumée qui dérive avec le vent

- **Description** : en vent fort, les cases enfumées glissent lentement dans le sens du vent (au plus 2 cases).
- **Intérêt** : effet visuel plus vivant ; renseigne aussi sur le vent avant de lancer.
- **Faisabilité moteur** : direction et force du vent lues dans le `ClimateManager` (synchronisé) ; décalage calculé de façon déterministe à partir de l'heure de début de l'entrée et du vent, pour que tous les clients tombent d'accord ; recréation des `IsoFire` à la nouvelle case (même chemin que le changement de signature).
- **Impact MP** : aucun paquet si le calcul est déterministe ; il faut surtout vérifier que le vent est le même chez tous les clients (à vérifier en jeu).
- **Dépendances** : C12 (fumée sur des cases variées).
- **Effort** : M à L.

### I14 : fumigènes et bâtons sur les zombies militaires et policiers

- **Description** : un zombie en tenue de soldat ou de policier porte parfois une grenade fumigène ou un bâton lumineux.
- **Intérêt** : le butin suit le personnage, ce qui donne des trouvailles plus crédibles que les seuls casiers.
- **Faisabilité moteur** : ajout de l'objet à l'inventaire du zombie à sa mort (`OnZombieDead`, avant le cadavre), filtré par `getOutfitName()` ; attention au cas du feu (`quest-building-blocks.md`, objet dans le cadavre).
- **Impact MP** : à faire sur le serveur ; le cadavre reçoit l'inventaire du serveur (`zombies-as-npc-bodies.md`).
- **Dépendances** : option `LootMultiplier`.
- **Effort** : S.

### I15 : couleurs « daltonisme » et intensité de lampe côté client

- **Description** : options de mod (`PZAPI.ModOptions`) propres à chaque joueur : palette adaptée (rouge et vert remplacés par orange et bleu à l'affichage seulement), intensité des lueurs, coupure du scintillement (confort visuel).
- **Intérêt** : accessibilité ; le scintillement des fusées peut gêner.
- **Faisabilité moteur** : le client calcule déjà couleur et lampe localement (`SignalSmoke_Client.lua:355-368, 416-430`) : une table de correspondance à l'affichage suffit, sans toucher au registre.
- **Impact MP** : aucun (affichage local seulement ; la couleur logique reste la même pour les missions).
- **Dépendances** : traductions des options.
- **Effort** : S.

### I16 : fabriquer une fusée de route

- **Description** : recette artisanale (tube de carton ou papier, soufre ou allumettes, cire), avec une fusée de moins bonne qualité qui brûle moins longtemps.
- **Intérêt** : donne une issue aux longues parties où le butin est épuisé, comme le fumigène artisanal le fait pour la fumée.
- **Faisabilité moteur** : `craftRecipe`, sur le modèle de `SignalSmoke_recipes.txt` ; objets vanilla à relever dans `scripts/generated/items`.
- **Impact MP** : aucun.
- **Dépendances** : C01 (durée portée par l'objet), traductions.
- **Effort** : S.

---

## Partie 3 : priorisation

Les cinq actions qui rapportent le plus, dans l'ordre :

1. **C01 + C02 : cycle de vie des fusées** (fusée consumée `RoadFlareUsed`, heure de fin sur l'objet, retraits ratés repris au chargement de la case). C'est le seul bug que les joueurs voient vraiment, et il touche aussi Artemis. Effort M.
2. **C04 + C05 : `colorName`, `colorNameOf` et `API_VERSION`**. Pour un coût minime, ces ajouts suppriment le couplage caché qui lie RadioSurvivor aux valeurs RGB de `COLORS`, et donnent une base saine aux évolutions de l'API (C06, I11, I12). Effort S.
3. **C14 + C12 : scénario `pz-autotest` nominal, en solo puis en MP**, qui tranche en particulier l'hypothèse du décalage d'indices sous la fusée. La bibliothèque est requise par deux autres mods et n'a jamais tourné sous test. Effort M.
4. **C06 : `SignalSmoke.placeFlare`**, adopté par `LightFlareAction` et par Artemis, pour qu'une correction de la fusée ne soit faite qu'une fois. Effort S à M.
5. **C03 + C11 (textes) puis I04 (temps restant)** : rendre les infobulles justes quelles que soient les options, puis afficher la durée restante. C'est le gain le plus visible pour le joueur au moindre coût. Effort S.

Ensuite, au choix de l'utilisateur : I03 (leurre, très court à faire) et I01 (pistolet lance-fusées, la fonctionnalité la plus « signal »).

---

> **Note** : ce document propose des pistes et ne décide rien. Rien n'y est implémenté. Chaque correction (Partie 1) et chaque fonctionnalité (Partie 2) attend une validation explicite de l'utilisateur avant d'être codée, et aucune option ou fonctionnalité citée ici ne doit être livrée sans cet accord.
