# Signal Smoke — documentation

Mod Project Zomboid Build 42.21 (`batman_SignalSmoke`, Workshop 3811010882) : grenades fumigènes colorées, fusées de route, bâtons lumineux, bombes fumigènes artisanales, et une petite bibliothèque Lua qui permet aux autres mods de poser des signaux colorés décidés par le serveur et vus de tous les joueurs.

La présentation GitHub (anglais) est dans le [README](../README.md) du dépôt, les notes de version dans le [CHANGELOG](../CHANGELOG.md).

## Documents

| Document | Rôle |
|---|---|
| [architecture.md](architecture.md) | Architecture logicielle : fichiers du mod, modules Lua par côté, flux serveur → clients, persistance, intégrations, outillage. |
| [specifications-fonctionnelles.md](specifications-fonctionnelles.md) | Ce que fait le mod pour le joueur et l'administrateur (fonctionnalités `F01`…), options sandbox, solo et multijoueur, limites connues. |
| [specifications-techniques.md](specifications-techniques.md) | Contrats précis : objets et recettes, registre et ModData, options sandbox, traductions, **API publique Lua** pour les autres mods, compatibilités. |
| [ameliorations-et-idees.md](ameliorations-et-idees.md) | Améliorations de code proposées et idées de fonctionnalités (propositions, rien n'est validé). |
| [wiki/en/](wiki/en/Home.md) | Source du wiki GitHub en anglais (guides joueur, administrateur et développeur). |
| [wiki/fr/](wiki/fr/Home.md) | Même wiki en français. |
| [images/](images/) | Images de la documentation ; captures en jeu dans [images/screenshots/](images/screenshots/). |
| [annexes/recherches/](annexes/recherches/) | Recherches techniques de la v1 ([recherche-v1.md](annexes/recherches/recherche-v1.md)) et de la v2 ([recherche-v2.md](annexes/recherches/recherche-v2.md)) : preuves Java et vanilla des choix faits. |
| [annexes/tests/](annexes/tests/) | Protocoles de test en jeu de la v0.1.0 ([test-v1.md](annexes/tests/test-v1.md)) et de la v0.2.0 ([test-v2.md](annexes/tests/test-v2.md)). |

## Captures disponibles

| Fichier | Contenu |
|---|---|
| [shot1.png](images/screenshots/shot1.png) | De nuit : fumées et lueurs colorées (vert, jaune, rouge, violet) près d'une route. |
| [shot2.png](images/screenshots/shot2.png) | De nuit sous la pluie : petits objets lumineux posés au sol (lueurs rouge, verte et bleue) autour d'un personnage. |
