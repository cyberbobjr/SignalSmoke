# Spécifications fonctionnelles

Ce que fait Signal Smoke 0.2.3 (Build 42.21) pour le joueur et l'administrateur. Les noms exacts des objets, options et fonctions sont dans [specifications-techniques.md](specifications-techniques.md) ; le fonctionnement interne dans [architecture.md](architecture.md).

## F01 — Grenades fumigènes colorées

- Quatre couleurs : verte, rouge, jaune, violette. Objet de 0,6 kg, catégorie « Explosifs », lancé comme la bombe fumigène vanilla (portée 12).
- À l'éclatement : fumée de la couleur de la grenade sur une croix de cinq cases (rayon 1) pendant **90 secondes réelles** par défaut (option `GrenadeSmokeSeconds`), avec un souffle en boucle entendu à moins de 40 cases. Pas de fumée grise, pas de feu, pas de dégâts.
- La nuit (lumière du jour inférieure à 0,45), une lueur de la même couleur (rayon 5) éclaire le sol sous la fumée.
- Les zombies qui se tiennent dans la fumée perdent leur cible (comportement vanilla de la fumée).
- Bruit pour les zombies : celui de la bombe fumigène vanilla (`NoiseRange = 10`).

## F02 — Bombes fumigènes artisanales

- Recette « Fabriquer une bombe fumigène artisanale (couleur) », une par couleur (verte, rouge, jaune, violette), fabriquée en main, sans apprentissage, **Cuisine 2** requise, 5 points d'expérience de Cuisine.
- Ingrédients : une boîte de conserve vide, deux utilisations de sucre, une utilisation de pain de glace (`Coldpack`) **ou** d'engrais, une utilisation de peinture de la couleur voulue, et une mèche (ficelle, bande de tissu propre ou sale).
- Lancée comme une grenade : fumée plus courte (**45 secondes réelles** par défaut, option `ImprovisedSmokeSeconds`), portée 10. Elle **rate** dans 20 % des cas par défaut (option `ImprovisedDudChance`) : elle siffle sans fumer.
- Elle ne se trouve pas dans le butin.

## F03 — Fusées de route

- Clic droit sur une fusée de route : **« Allumer et poser au sol »**. Le personnage s'accroupit, bruit de briquet, puis une fusée allumée est posée sur sa case.
- Pendant **60 minutes de jeu** par défaut (option `FlareBurnMinutes`) : lumière rouge qui scintille (rayon 8), un peu de fumée rouge sur la case, grésillement en boucle. Puis la fusée disparaît du sol.
- **Ramassée**, elle s'éteint (dans la minute de jeu qui suit) ; l'objet « Fusée de route (allumée) » reste dans l'inventaire mais ne se rallume pas.
- L'objet posé n'est pas retiré par l'option vanilla de nettoyage des objets au sol.

## F04 — Bâtons lumineux

- Quatre couleurs : vert, rouge, bleu, jaune (0,1 kg). Clic droit sur un bâton neuf : **« Activer et poser au sol »** (bruit d'emballage arraché).
- Au sol : petite lueur douce de la couleur du bâton (rayon 3), sans fumée ni son, pendant **8 heures de jeu** par défaut (option `ChemlightHours`). Un bâton activé ne s'éteint pas.
- Le temps continue de courir quand on le ramasse. Reposé au sol par n'importe quel geste vanilla (lâcher, poser, glisser vers le sol) à moins de deux cases d'un joueur vivant, il brille de nouveau dans la minute de jeu, pour le temps qui lui reste.
- Échu, il devient un **bâton lumineux usagé** (catégorie « Déchets »), au sol comme dans l'inventaire (contrôle toutes les 10 minutes de jeu, sacs portés compris ; un bâton tenu en main ou accroché attend d'être rangé ou posé).
- Un bâton activé tenu en main ou porté **n'éclaire pas** : seule la lueur au sol existe.

## F05 — Butin

| Objet | Où (listes vanilla) |
|---|---|
| Grenades fumigènes (4 couleurs) | réserves de munitions de l'armée, réserves du bunker, surplus militaire, casiers de police |
| Fusées de route | matériel d'urgence des stations-service, outils de garage, casiers de pompiers, casiers de police, coffres des voitures de police (option) |
| Bâtons lumineux (4 couleurs) | électronique de l'armée, réserves du bunker, surplus militaire, casiers de police et de pompiers, éclairage et matériel des magasins de camping, matériel de survie |

Les chances sont multipliées par l'option `LootMultiplier` (0 : aucun objet du mod dans le butin). Les bombes artisanales et les objets allumés ou usagés ne se trouvent pas.

## F06 — Options sandbox

Page « Signal Smoke » des options de partie :

| Option | Effet | Défaut | Bornes |
|---|---|---|---|
| Durée de la fumée des grenades | secondes réelles de fumée d'une grenade | 90 | 20 à 600 |
| Durée des fusées de route | minutes de jeu de combustion d'une fusée | 60 | 10 à 720 |
| Durée des bâtons lumineux | heures de jeu de lueur d'un bâton activé | 8 | 1 à 48 |
| Durée de la fumée des bombes artisanales | secondes réelles de fumée | 45 | 10 à 300 |
| Ratés des bombes fumigènes artisanales | pourcentage de bombes qui ratent | 20 | 0 à 100 |
| Multiplicateur de butin | multiplie les chances de trouver les objets du mod | 1,0 | 0 à 10 |
| Fusées de route dans les coffres des voitures de police | ajoute des fusées au coffre des voitures de police | oui | — |

Une option modifiée en cours de partie s'applique aux signaux suivants (durées, ratés) ; un signal déjà en cours garde sa durée. Les options de butin sont relues au chargement de la partie.

## F07 — Multijoueur

- Fumées, lueurs et sons sont vus et entendus de **tous les joueurs** proches, y compris ceux qui se connectent pendant qu'un signal est actif.
- Toutes les décisions (durée, raté d'une bombe artisanale, fin, ramassage) sont prises par le serveur.
- La liste des signaux envoyée aux joueurs ne dit pas qui a lancé ou posé quoi (depuis 0.2.3).
- Écran partagé : le son est joué si l'un des joueurs locaux est à portée ; les bâtons lumineux sont repérés autour de chaque joueur local.

## F08 — Sauvegarde et rechargement

- Les signaux actifs survivent à la sauvegarde, au rechargement et au redémarrage du serveur ; la fumée est recréée quand la zone est de nouveau chargée.
- Loin de tout joueur (zone non chargée), rien n'est dessiné, mais les signaux continuent de s'écouler et finissent à l'heure prévue.

## F09 — Bibliothèque pour les autres mods

Un autre mod qui déclare `require=\batman_SignalSmoke` peut poser et retirer des fumées, fusées et lueurs colorées (n'importe quelle couleur, rayon de fumée 0 à 2, durée libre), et être prévenu quand un signal commence, s'arrête ou expire, y compris ceux lancés par les joueurs. Contrat : [specifications-techniques.md, API publique](specifications-techniques.md#api-publique-lua) ; guide : [wiki, Developer API](wiki/en/06-developer-api.md).

## Limites connues

- Un client ne garde pas plus de 40 fumées du mod à la fois, et le moteur n'admet que 75 feux et fumées : au-delà, des cases de fumée manquent ou sont recréées avec un délai. La fumée ne se pose pas sur l'eau ni sur une case sans objet de sol.
- La durée des fumées en secondes réelles est convertie en heures de jeu au moment du lancer, d'après la durée du jour de la partie.
- Une fusée de route ramassée reste un objet inutile ; un bâton activé n'éclaire pas en main.
- Un bâton activé reposé loin de tout joueur (plus de deux cases) n'est rallumé que lorsqu'un joueur passe à proximité.
- Validation en jeu : voir les protocoles de [annexes/tests/](annexes/tests/) ; les cas limites qui y sont listés (aller-retour hors zone chargée, plus de 75 feux, objets posés sur une case enfumée en MP) restent à vérifier.
