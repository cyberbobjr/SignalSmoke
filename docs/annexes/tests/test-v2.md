# Signal Smoke — test de la v2 (bâtons lumineux, fumigène artisanal, options, événements)

- Build : 42.21 — Rédigé le 2026-10-01 — Code contrôlé hors jeu (`python tests/run_tests.py` : luacheck, 32 tests Lua purs ou simulés, cohérence scripts / traductions / ressources). **Rien n'est encore testé en jeu.** Le parcours de la v1 reste valable : [test-v1.md](test-v1.md).
- Partie solo de test, mode debug. Objets par la console Lua : `getPlayer():getInventory():AddItem("SignalSmoke.ChemlightGreen")` (aussi `Red`, `Blue`, `Yellow`), `AddItem("SignalSmoke.ImprovisedSmokeGreen")`.

## Parcours nominal

| # | Action | Attendu | Résultat |
|---|---|---|---|
| N1 | Nouvelle partie : page « Signal Smoke » des options sandbox | 7 options traduites (durées, ratés, butin, coffres de police), valeurs par défaut 90 / 60 / 8 / 45 / 20 / 1,0 / oui | ☐ |
| N2 | Clic droit sur un bâton lumineux vert → « Activer et poser au sol » | Bruit d'emballage, animation accroupie ; bâton vert lumineux posé au sol ; de nuit, petite lueur verte (environ 3 cases), sans fumée ni son | ☐ |
| N3 | Ramasser le bâton, attendre, le lâcher ailleurs | Ramassé : la lueur disparaît (au plus une minute de jeu) et l'objet reste « activé » ; lâché : la lueur revient en moins d'une minute de jeu | ☐ |
| N4 | Option `ChemlightHours` = 1, activer un bâton, attendre une heure de jeu | Le bâton au sol devient « bâton lumineux usagé », la lueur s'éteint | ☐ |
| N5 | Menu d'artisanat avec Cuisine ≥ 2, une boîte de conserve vide, 2 doses de sucre, un pain de glace (ou de l'engrais), un pot de peinture verte, de la ficelle | Recette « Fabriquer une bombe fumigène artisanale (verte) » disponible ; une seule dose de peinture et d'engrais consommée ; un peu d'XP de Cuisine | ☐ |
| N6 | Lancer quelques bombes fumigènes artisanales | En général fumée verte plus courte (≈ 45 s réelles) ; de temps en temps (≈ 1 sur 5), sifflement sans fumée | ☐ |
| N7 | Bilan du journal (`console.txt`) | Aucune erreur Lua de Signal Smoke, aucun `failed to parse custom sandbox option`, aucun `loot list not found` | ☐ |

## Événements (mod de test ou console Lua en solo)

```lua
local S = require "SignalSmoke/SignalSmoke"
S.onSignal(function(e) print("SignalSmoke event", e.type, e.id, e.source, e.username, e.reason) end)
```

Lancer une grenade, poser une fusée, activer un bâton, le ramasser : lignes `started` (source et nom), `stopped … pickedUp`, puis `expired` à la fin.

## Cas limites (reportés)

- Multijoueur : options lues sur le serveur, joueur qui arrive voit les bâtons, événements côté serveur avec le bon compte (`getUsername`), bâton lâché par un client.
- Butin : `LootMultiplier` = 0 puis 3 sur une nouvelle partie solo (relecture `ItemPickerJava.Parse` à `OnInitGlobalModData`) ; coffres de voitures de police avec et sans l'option.
- Bâton activé échu dans un sac porté (converti au contrôle des 10 minutes), tenu en main (attend), rangé dans un meuble (jamais converti : limite).
- Taille et orientation des modèles au sol et en main (bâton couché, boîte de conserve), icônes.
- Deux joueurs près d'un bâton reposé : `player` de l'événement = joueur près duquel il est trouvé.
