# API pour les développeurs

Signal Smoke est une bibliothèque : votre mod peut poser des fumées, fusées et lueurs colorées vues de tous les joueurs et restaurées après chargement, et être prévenu des signaux lancés par les joueurs ou par d'autres mods. Contrat complet : [specifications-techniques.md](../../specifications-techniques.md#api-publique-lua).

## Mise en place

```
# mod.info de votre mod
require=\batman_SignalSmoke
```

```lua
local SignalSmoke = require "SignalSmoke/SignalSmoke"
```

Le module est un fichier `shared` : il est disponible quel que soit l'ordre des mods. **Écritures et événements ne fonctionnent que sur l'autorité** (serveur dédié, hôte ou solo : `not isClient()`). Les lectures fonctionnent partout.

## Poser et retirer un signal

```lua
local id, err = SignalSmoke.start{
    x = 100, y = 200, z = 0,        -- entiers, x et y obligatoires
    color = "green",                -- nom de SignalSmoke.COLORS ou { r = 0.2, g = 0.8, b = 1 }
    kind = "smoke",                 -- "smoke" (défaut), "flare" ou "chemlight"
    minutes = 30,                   -- minutes de jeu (défaut 30) ; ou realSeconds = 90 ; ou untilH = <heures de monde>
    radius = 1,                     -- cases de fumée, 0 à 2 (1 = croix de 5 cases)
    light = true,                   -- fumée : la nuit seulement ; fusée et bâton : toujours
    id = "monmod:zone1",            -- facultatif ; le même id remplace l'entrée
    owner = "MonMod",               -- facultatif, pour reconnaître ses entrées
}
if not id then print("[MyMod] Signal Smoke refused: " .. tostring(err)) end

SignalSmoke.stop(id)                -- true si l'entrée existait
```

| Fonction | Côté | Retour |
|---|---|---|
| `start(opts)` | autorité | id, ou `nil, "server only"` chez un client MP, ou `nil, message` si les options sont invalides |
| `stop(id, reason)` | autorité | `true` / `false` ; `nil, "server only"` chez un client MP |
| `isActive(id)` | partout | `true` tant que l'entrée existe et n'est pas échue |
| `list()` | partout | `{ [id] = entrée }` des entrées actives (lecture seule) |
| `onSignal(fn)` / `removeSignalListener(fn)` | autorité | `true` si ajouté / retiré |

Autres options de `start` : `lightRadius` (1 à 20), `smoke = false`, `sound` (nom d'un son joué en boucle, entendu à moins de 40 cases), `itemId` (objet posé à suivre : le signal s'arrête s'il est ramassé, l'objet est retiré à la fin), `spentType` (type posé à sa place à la fin), `source`, `player` (`IsoPlayer`) ou `username`.

Couleurs : `green`, `red`, `yellow`, `purple`, `orange`, `blue`, `white`.

Chez un client MP, `list()` et `isActive()` lisent la copie reçue du serveur : vide tant qu'elle n'est pas arrivée après la connexion.

## Écouter les signaux

```lua
local function onSignal(event)
    -- event.type : "started", "stopped" ou "expired"
    -- event.id, event.entry (lecture seule), event.source ("grenade", "flare", "chemlight", "script"…)
    -- event.username : compte du joueur à l'origine, si connu (solo : nom du personnage)
    -- event.player : IsoPlayer, pour "started" seulement, si connu
    -- event.reason : pour "stopped" ("script", "pickedUp") ; event.replaced : pour "started"
end
SignalSmoke.onSignal(onSignal)
```

Inscrire l'abonné au chargement d'un fichier `shared` ou `server`. Chaque abonné est appelé dans son propre `pcall` : son erreur est écrite au journal sans arrêter les autres. Une bombe artisanale ratée ne lance aucun signal. Le compte du joueur n'est gardé qu'en mémoire du serveur : inconnu pour un signal posé avant le dernier chargement.

Pour retrouver le nom de la couleur d'un signal, utiliser `SignalSmoke.colorNameOf(event.entry)` (API 3) : elle rend `entry.colorName` (posé quand la couleur est donnée par son nom) ou le nom le plus proche de `SignalSmoke.COLORS`. Tester `(SignalSmoke.API_VERSION or 1) >= 3` avant de l'utiliser.

Pour poser une fusée allumée par script (serveur ou solo), appeler `SignalSmoke.placeFlare{ x = 100, y = 200, z = 0, color = "green", minutes = 20, id = "monmod:fusee", owner = "MonMod" }` (API 3) : elle pose la fusée sur la case chargée, la protège du nettoyage du sol et l'inscrit ; elle rend `id, item` ou `nil, erreur`. Ramassée, la fusée se consume sans éclairer et se rallume une fois reposée.

`SignalSmoke.API_VERSION` : 1 (0.1.0), 2 (événements et bâtons lumineux, 0.2.0), 3 (`colorName`, `colorNameOf`, `placeFlare`). Absente : version 1 ou 2, tester les fonctions utilisées.

## Conseils

- Utiliser son propre `id` et rafraîchir le signal avant sa fin (comparer `list()[id].untilH` à `getGameTime():getWorldAgeHours()`) plutôt que d'en poser un nouveau à chaque fois.
- Garder des durées de fumée en minutes plutôt qu'en heures : la fumée est un objet local de chaque client.
- Remplacer une entrée par le même `id` ne retire pas l'objet suivi par l'ancienne entrée.
