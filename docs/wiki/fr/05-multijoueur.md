# Multijoueur

- Tous les joueurs proches voient les fumées et les lueurs et entendent les sons, y compris ceux qui se connectent pendant qu'un signal est actif.
- Le serveur décide de tout : durées, ratés, fusée ramassée, bâton échu.
- La liste des signaux actifs envoyée aux joueurs ne dit pas qui a lancé ou posé quoi (depuis 0.2.3).
- Écran partagé : le son est joué dès qu'un joueur local est proche ; les bâtons lumineux sont repérés autour de chaque joueur local.
- Les signaux survivent au redémarrage du serveur. Loin de tout joueur (zone non chargée), rien n'est dessiné, mais les signaux continuent de s'écouler et finissent à l'heure prévue.

## Pour les administrateurs

- Ajouter `batman_SignalSmoke` à `Mods=` et `3811010882` à `WorkshopItems=`.
- Aucune commande d'administration ni fichier à configurer : seulement les [options sandbox](04-options-sandbox.md).
- Chaque client dessine au plus 40 cases de fumée du mod à la fois, pour laisser de la place aux vrais feux (le jeu plafonne à 75 feux et fumées).
