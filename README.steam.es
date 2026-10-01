[h1]Signal Smoke — Granadas de humo de colores, bengalas de carretera y barras luminosas[/h1]

[b]Build 42.21 · Un jugador y multijugador[/b]

¿Un helicóptero tiene que ver tu tejado, un amigo tiene que encontrar tu campamento o quieres marcar el camino de vuelta? Suelta humo de color, enciende una bengala de carretera o deja una barra luminosa: visible para todos.

[h2]De un vistazo[/h2]

[list]
[*][b]Cuatro granadas de humo[/b]: verde, roja, amarilla y morada, con sus propios modelos 3D e iconos.
[*][b]Bengalas de carretera[/b] que arden en rojo en el suelo durante una hora de juego aproximadamente.
[*][b]Barras luminosas[/b] de cuatro colores: un brillo discreto que dura horas, para marcar un camino o un sótano.
[*][b]Bombas de humo caseras[/b]: fabrica tu propio humo de color.
[*][b]Opciones de sandbox[/b]: duraciones, probabilidad de fallo, botín.
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

[h2]Barras luminosas[/h2]

[list]
[*]Verde, roja, azul o amarilla. Clic derecho, [b]Activar y dejar en el suelo[/b].
[*]Un pequeño brillo de color (unas 3 casillas), sin humo ni sonido, durante 8 horas de juego.
[*]Una vez activada no se puede apagar: recógela y déjala en otro sitio, sigue brillando hasta agotarse.
[*]Se encuentran en almacenes y tiendas de excedentes del ejército, taquillas de policía y bomberos, y material de acampada y supervivencia.
[/list]

[h2]Bombas de humo caseras[/h2]

[list]
[*]Receta [b]Hacer bomba de humo casera[/b] (Cocina 2): una lata vacía, azúcar, una compresa fría o abono ecológico, pintura del color que quieras (verde, roja, amarilla o morada) y una mecha (cordel o retales de tela).
[*]Se lanza como una granada de humo, pero es menos fiable: el humo dura menos y 1 de cada 5 falla.
[/list]

[h2]Opciones de sandbox[/h2]

Duración del humo, de las bengalas y de las barras luminosas, duración y probabilidad de fallo de las bombas caseras, multiplicador de botín, bengalas en los maleteros de la policía.

[h2]Multijugador[/h2]

El servidor lleva la lista del humo y las bengalas activos y la envía a cada cliente: los jugadores que llegan después también los ven, y vuelven al cargar una partida.

[h2]Para modders[/h2]

Añade [b]require=\batman_SignalSmoke[/b] a tu mod.info y después, en el servidor o en un jugador:
[code]
local SignalSmoke = require "SignalSmoke/SignalSmoke"
local id = SignalSmoke.start{ x = 100, y = 200, z = 0, color = "green", minutes = 30 }
SignalSmoke.stop(id)
[/code]
Colores con nombre: green, red, yellow, purple, orange, blue, white, o cualquier tabla { r, g, b }. Usa kind = "flare" para una bengala de carretera y kind = "chemlight" para una barra luminosa.
[b]Eventos[/b]: SignalSmoke.onSignal(function(event) ... end) se llama en el servidor cuando una granada, una bengala, una barra luminosa o una señal de script empieza, se detiene o caduca (type, id, entry, source, username). API completa en GitHub.

[h2]Apoya el proyecto[/h2]

¿Te gusta el mod? Un café ayuda a financiar nuevas funciones y traducciones.
[url=https://ko-fi.com/Z8Z8QJV31][img]https://storage.ko-fi.com/cdn/kofi6.png?v=6[/img][/url]

[h2]Créditos[/h2]

Modelos, texturas e iconos originales hechos con Blender. Humo y sonidos del juego base. Código fuente bajo licencia MIT: [url=https://github.com/cyberbobjr/SignalSmoke]GitHub[/url].
