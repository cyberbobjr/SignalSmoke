[h1]Signal Smoke — Granadas de humo de colores y bengalas de carretera[/h1]

[b]Build 42.21 · Un jugador y multijugador[/b]

¿Un helicóptero tiene que ver tu tejado, un amigo tiene que encontrar tu campamento o quieres marcar el camino de vuelta? Suelta humo de color o enciende una bengala de carretera: visible desde lejos, para todos.

[h2]De un vistazo[/h2]

[list]
[*][b]Cuatro granadas de humo[/b]: verde, roja, amarilla y morada, con sus propios modelos 3D e iconos.
[*][b]Bengalas de carretera[/b] que arden en rojo en el suelo durante una hora de juego aproximadamente.
[*][b]Se encuentran en el mundo[/b]: no hace falta fabricarlas.
[*][b]Multijugador[/b]: el servidor decide y todos los jugadores ven el mismo humo y las mismas bengalas.
[*][b]Una pequeña biblioteca para otros mods[/b]: humo de color y bengalas colocados por script.
[/list]

[h2]Granadas de humo[/h2]

[list]
[*]Se lanza como la bomba de humo del juego: un humo de color se eleva sobre una pequeña cruz de casillas durante un minuto y medio aproximadamente, visible desde lejos. De noche brilla con su color.
[*]Los zombis dentro del humo pierden de vista su objetivo.
[*]Sin humo gris, sin fuego, sin daño: es una señal, no un arma.
[*]Se encuentran en almacenes del ejército, tiendas de excedentes militares y taquillas de policía.
[/list]

[h2]Bengalas de carretera[/h2]

[list]
[*]Clic derecho en la bengala, [b]Encender y dejar en el suelo[/b].
[*]Arde con una luz roja parpadeante, algo de humo rojo y un chisporroteo durante una hora de juego aproximadamente, y después se consume.
[*]Recógela para apagarla.
[*]Se encuentran en el material de emergencia de las gasolineras, las herramientas de automóvil y las taquillas de bomberos y de policía.
[/list]

[h2]Multijugador[/h2]

El servidor lleva la lista del humo y las bengalas activos y la envía a cada cliente: los jugadores que llegan después también los ven, y vuelven al cargar una partida.

[h2]Para modders[/h2]

Añade [b]require=\batman_SignalSmoke[/b] a tu mod.info y después, en el servidor o en un jugador:
[code]
local SignalSmoke = require "SignalSmoke/SignalSmoke"
local id = SignalSmoke.start{ x = 100, y = 200, z = 0, color = "green", minutes = 30 }
SignalSmoke.stop(id)
[/code]
Colores con nombre: green, red, yellow, purple, orange, blue, white, o cualquier tabla { r, g, b }. Usa kind = "flare" para una bengala de carretera.

[h2]Apoya el proyecto[/h2]

¿Te gusta el mod? Un café ayuda a financiar nuevas funciones y traducciones.
[url=https://ko-fi.com/Z8Z8QJV31][img]https://storage.ko-fi.com/cdn/kofi6.png?v=6[/img][/url]

[h2]Créditos[/h2]

Modelos y texturas originales hechos con Blender. Humo y sonidos del juego base. Código fuente bajo licencia MIT: [url=https://github.com/cyberbobjr/SignalSmoke]GitHub[/url].
