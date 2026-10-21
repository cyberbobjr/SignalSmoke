# Signal Smoke — scénario automatique pz-autotest

- Build : 42.21 — Rédigé le 2026-10-21 — Points C12 et C14 de [ameliorations-et-idees.md](../../ameliorations-et-idees.md).
- Fichiers : [`autotest.json`](../../../autotest.json) (configuration) et [`autotest/ss_hooks.lua`](../../../autotest/ss_hooks.lua) (hooks). Outil générique : `C:\Users\cyber\Zomboid\Workshop\.claude\tools\pz-autotest` (`README.md`).
- **État** : premier passage `sp` le 2026-10-21 (`runs/20261021-155307-sp-417ac6746cae`) : 40 PASS, 1 FAIL (`sp.expiries.visual`). Le FAIL venait de la sonde et non du mod : le joueur se tenait à côté d'une fenêtre, et le moteur pose une lumière de bâtiment sur la case extérieure de chaque fenêtre et de chaque porte (`IsoBuilding.java:373/394`, rangée dans `getLamppostPositions`). Cette lumière était comptée comme une lampe du mod (« 2 lamp(s) » sur la case de la fusée) et ne partait jamais. Les sondes ne comptent plus que les lampes simples (`getLocalToBuilding()` nul, sans interrupteur, non hydro) ; à 11 s, l'étape écrit en `INFO` les feux marqués et les lampes restants. Correction à confirmer par un nouveau passage `sp`, puis `mp` jamais lancé.

## Commandes

Depuis `C:\Users\cyber\Zomboid\Workshop` :

```powershell
python .claude/tools/pz-autotest/pz_autotest.py check SignalSmoke
python .claude/tools/pz-autotest/pz_autotest.py sp    SignalSmoke --wait-idle 3600
python .claude/tools/pz-autotest/pz_autotest.py mp    SignalSmoke --clients 1 --wait-idle 3600
```

- `sp` copie la sauvegarde `Sandbox/2026-10-17_17-50-04` (celle de Live Wire) avec le seul mod `batman_SignalSmoke` et le pilote.
- `mp` lance un serveur (`pzat_signalsmoke_mp`, port 17401, apparition fixe à Muldraugh 10656,10137,0) et un client ; `clientRun` est vrai : le client 1 exécute ses hooks.
- Paramètre facultatif : `-P expiryTimeout=<s>` (solo, attente des expirations, 240 s par défaut).
- Résultats : `SignalSmoke/runs/<date>-<mode>-<jeton>/summary.txt` ; lignes `PASS`, `FAIL` et `INFO`. Code 0 = tout vert.

## Parcours nominal déroulé

Toutes les poses se font sur l'autorité (solo, ou serveur en MP), à côté du joueur (`P` = sa case).

| # | Étape | Contrôles |
|---|---|---|
| 1 | Abonné `SignalSmoke.onSignal` | ajouté une fois (`true` puis `false`) ; `start{}` refusé avec un message |
| 2 | `start{ id = "pzat:smoke", color = "green", radius = 1 }` à 3-8 cases à l'est | `start` rend l'id, `isActive`, `list()[id]` (rayon 1), événement `started` ; côté client : `IsoFire` marqués (`batmanSS`) sur la croix |
| 3 | `stop("pzat:smoke")` | `true`, plus actif ni listé, second `stop` = `false`, événement `stopped` (`reason = "script"`) ; côté client : plus aucun feu marqué (MP : vérifié à la fin) |
| 4 | Grenade verte : vrai `IsoTrap` (jamais ajouté au monde) passé à `OnThrowableExplode` | entrée de source `grenade`, rayon 1, son, compte du lanceur ; côté client : fumée marquée |
| 5 | Fusée routière par l'action réelle (`SignalSmoke_LightFlareAction:complete()`) | entrée `flare`, `RoadFlareLit` au sol sur `P`, fusée neuve retirée ; côté client : fumée (rayon 0) et lampe sur `P` |
| 6 | **C12** : ramassage de la fusée qui fume, par l'action vanilla `ISGrabItemAction` (client) | liste des objets de `P` et indice de la fusée relevés côté serveur et côté client (lignes `INFO C12`, « identical » ou « SHIFTED ») ; ramassage réussi ; événement `stopped` `reason = "pickedUp"` ; fusée dans l'inventaire du serveur et plus sur la case |
| 7 | Bâton lumineux vert par l'action réelle, puis durée raccourcie à 15 s (ModData + `startChemlight`, même id, `replaced`) | entrée `chemlight` sans fumée, `spentType` ; côté client : lampe, aucun feu |
| 8 | Fusée de script `SignalSmoke.placeFlare{ id = "pzat:flare2", realSeconds = 15 }` à 3 cases au sud | objet au sol suivi |
| 9 | Expirations par la boucle serveur (`EveryOneMinute`) | événements `expired` de la grenade (90 s), du bâton et de `pzat:flare2` ; `ChemlightUsed` au sol à la place du bâton ; `pzat:flare2` retirée du sol ; registre vidé des ids du test |
| 10 | Fin | côté client : aucun feu marqué ni lampe restants, `ChemlightUsed` reçu, `flare2` absente ; `removeSignalListener` ; aucune erreur Lua de plus (`getLuaDebuggerErrorCount`) |

En MP, le client vérifie aussi que `start` et `stop` lui rendent `nil, "server only"` et que la copie reçue du registre ne contient pas de compte (`username`). Serveur et client se coordonnent par des commandes `SSAutoTest` (`hello`, `plan`, `report`, `phase2`, `ended`, `final`) ; le serveur reprend le résultat final du client dans ses propres contrôles.

## Lecture du point C12

- `INFO C12 … identical` et ramassage réussi : l'hypothèse du décalage d'indices ne se vérifie pas pour la fusée (la prise passe par une transaction d'objet par identifiant).
- `SHIFTED` mais ramassage réussi : décalage réel, sans effet sur le ramassage ; rester attentif aux autres interactions par indice (meubles, portes dans la croix d'une grenade), non couvertes ici.
- Ramassage en échec (`mp.client.grab` en délai, `flare.pickedUp` absent) : C12 confirmé, correction à prévoir (fumée de la fusée sur une case voisine).

## Limites

- Rendu, couleur, scintillement et son ne sont pas jugés : seuls la présence des objets marqués et des lampes simples (`addLamppost`) est contrôlée ; les lumières de bâtiment (fenêtres, portes) et des interrupteurs sur les mêmes cases sont écartées. La lampe d'une fumée n'existe que la nuit (ligne `INFO night=`).
- Le lancer réel d'une grenade (animation, `IsoTrap` posé par le moteur) n'est pas rejoué : seul l'événement l'est.
- Un seul client actif en MP : la vue d'un second client et la reconnexion ne sont pas couvertes.
- Les meubles et portes dans la croix d'une grenade (seconde moitié de C12) ne sont pas testés.
