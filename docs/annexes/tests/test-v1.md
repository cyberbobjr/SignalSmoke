# Signal Smoke — test de la v0.1.0

- Build : 42.21 — Rédigé le 2026-09-30 — Code contrôlé hors jeu (luacheck, 11 tests purs, relecture Opus corrigée). **Rien n'est encore testé en jeu.**
- Objets par la console Lua (mode debug) : `getPlayer():getInventory():AddItem("SignalSmoke.SmokeGrenadeGreen")` (aussi `Red`, `Yellow`, `Purple`), `AddItem("SignalSmoke.RoadFlare")`, et pour comparer la taille `AddItem("Base.SmokeBomb")`.

## Parcours nominal

| # | Action | Attendu | Résultat |
|---|---|---|---|
| S1 | Poser au sol une grenade du mod à côté d'une `Base.SmokeBomb`, puis la tenir en main | Taille comparable à la SmokeBomb (sinon noter « trop grande / trop petite » : `scale` à corriger), icône et nom corrects, bande de couleur visible | ☐ |
| S2 | Lancer une grenade verte de jour | Elle roule un peu puis siffle ; fumée **verte** sur une croix de cinq cases pendant environ 90 s réelles ; pas de fumée grise ; les zombies dans la fumée perdent leur cible | ☐ |
| S3 | Même chose de nuit | Fumée verte avec une lueur verte au sol | ☐ |
| S4 | Fusée de route : clic droit → « Allumer et poser au sol » | Animation accroupie, bruit de briquet ; fusée allumée au sol ; lumière rouge qui scintille, un peu de fumée rouge, grésillement ; s'éteint au bout d'une heure de jeu (l'objet disparaît) ou si on la ramasse | ☐ |
| S5 | Bilan du journal | Aucune erreur Lua de Signal Smoke | ☐ |

## Cas limites (reportés)

- Deux grenades sur la même case la nuit (nombre de lampes stable) ; fusée près d'un feu de camp.
- Aller-retour hors de la zone chargée ; sauvegarde et rechargement pendant une fumée (solo).
- Plus de 75 feux (bâtiment en feu) avec une fumée active.
- Multijoueur : un joueur qui arrive voit la fumée ; poser et ramasser des objets sur une case enfumée (hypothèse : décalage des indices d'objets).
- Écran partagé : son de la fusée pour le second joueur.
