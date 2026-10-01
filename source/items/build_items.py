# Signal Smoke : modèles 3D et icônes des objets (recette Blender sans interface, originale).
#   blender -b --factory-startup -P build_items.py -- <racine du mod 42.21/media> [groupes]
# groupes (facultatif, séparés par des virgules) : grenade, flare, chemlight, improvised ; tous par défaut.
# Produit :
#   models_X/WorldItems/SignalSmoke_SmokeGrenade.fbx      grenade fumigène type M18 (une seule géométrie)
#   models_X/WorldItems/SignalSmoke_RoadFlare.fbx         fusée de route (debout)
#   models_X/WorldItems/SignalSmoke_RoadFlareLit.fbx      fusée de route allumée, couchée au sol
#   textures/WorldItems/SignalSmoke_SmokeGrenade<Couleur>.png, SignalSmoke_RoadFlare.png, SignalSmoke_RoadFlareLit.png
#   models_X/WorldItems/SignalSmoke_Chemlight.fbx         bâton lumineux couché (une géométrie, 9 textures)
#   models_X/WorldItems/SignalSmoke_ImprovisedSmoke.fbx   fumigène artisanal : boîte de conserve, mèche
#   textures/WorldItems/SignalSmoke_Chemlight<Couleur>[Lit].png, SignalSmoke_ChemlightUsed.png,
#   textures/WorldItems/SignalSmoke_ImprovisedSmoke<Couleur>.png
#   textures/Item_SignalSmoke_<Nom>.png                    icônes 64×64
# Dimensions : objets exagérés comme le vanilla, pour la lisibilité (grenade 0,40 m dans Blender). En jeu,
# taille = étendue après transformation de nœud × scale du script de modèle : l'export en mètres porte
# Lcl Scaling = 100, d'où scale = 0.0033 (scripts/SignalSmoke_models.txt, grenade ≈ 0,13 m). Le moteur ignore
# UnitScaleFactor ; la mesure après import dans Blender, elle, l'applique (trompeuse).
# Une seule matière et un seul canal UV par modèle ; textures dessinées ici (numpy + bpy.data.images).
import math
import os
import sys

import bpy
import bmesh
import numpy as np

ARGS = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
MEDIA = ARGS[0] if ARGS else os.path.join(os.path.dirname(os.path.abspath(__file__)), "out", "media")
ALL_GROUPS = ("grenade", "flare", "chemlight", "improvised")
GROUPS = ARGS[1].split(",") if len(ARGS) > 1 else list(ALL_GROUPS)

TEX_SIZE = 256
ICON_SIZE = 64
ICON_RENDER = 256

COLORS = {
    "Green": (0.30, 0.85, 0.30),
    "Red": (0.90, 0.18, 0.15),
    "Yellow": (1.00, 0.82, 0.00),
    "Purple": (0.50, 0.12, 0.80),
}
OLIVE = (0.42, 0.47, 0.28)
DARK = (0.12, 0.12, 0.11)
METAL = (0.55, 0.56, 0.55)
FLARE_RED = (0.78, 0.08, 0.06)
CAP_WHITE = (0.85, 0.85, 0.80)
# Bâtons lumineux (couleurs sRGB du plastique) et fumigène artisanal.
CHEMLIGHT_COLORS = {
    "Green": (0.35, 0.95, 0.30),
    "Red": (0.95, 0.20, 0.18),
    "Blue": (0.25, 0.55, 1.00),
    "Yellow": (1.00, 0.90, 0.20),
}
CHEMLIGHT_CAP = (0.20, 0.20, 0.21)
CHEMLIGHT_SPENT = (0.55, 0.57, 0.55)
TIN = (0.70, 0.71, 0.70)
TAPE = (0.32, 0.33, 0.34)
TWINE = (0.72, 0.60, 0.40)


def reset():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    scene = bpy.context.scene
    scene.unit_settings.system = "METRIC"
    scene.unit_settings.scale_length = 1.0
    return scene


# Textures ------------------------------------------------------------------------------------------
# Atlas de 256×256 découpé en bandes horizontales : v (0 en bas, 1 en haut) -> couleur. Les faces
# latérales d'un cylindre sont projetées par leur hauteur, les disques sur une case dédiée.

def srgb_to_linear(values):
    # Les couleurs sont pensées en sRGB (comme le PNG final) ; Blender attend des pixels linéaires et
    # les reconvertit en sRGB à l'enregistrement. Sans cette conversion, tout sort délavé.
    return np.where(values <= 0.04045, values / 12.92, ((values + 0.055) / 1.055) ** 2.4)


def make_image(name, rows, stencils=()):
    """rows : liste de (v0, v1, (r, g, b)) couvrant [0, 1] ; stencils : (v0, v1, couleur) d'inscriptions
    au pochoir (petits traits lisibles de loin, sans police). Renvoie une image Blender."""
    pixels = np.zeros((TEX_SIZE, TEX_SIZE, 4), dtype=np.float32)
    pixels[..., 3] = 1.0
    for v0, v1, color in rows:
        a, b = int(v0 * TEX_SIZE), int(math.ceil(v1 * TEX_SIZE))
        pixels[a:b, :, 0:3] = color
    # Léger grain, pour éviter un aplat plastique.
    for v0, v1, color in stencils:
        a, b = int(v0 * TEX_SIZE), int(v1 * TEX_SIZE)
        for x in range(20, TEX_SIZE - 20, 18):
            pixels[a:b, x:x + 10, 0:3] = color
    rng = np.random.default_rng(7)
    pixels[..., 0:3] *= 1.0 + rng.normal(0.0, 0.025, (TEX_SIZE, TEX_SIZE, 1))
    np.clip(pixels, 0.0, 1.0, out=pixels)
    pixels[..., 0:3] = srgb_to_linear(pixels[..., 0:3])
    image = bpy.data.images.new(name, TEX_SIZE, TEX_SIZE, alpha=False)
    image.pixels.foreach_set(pixels.ravel())
    return image


def save_image(image, path):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    image.filepath_raw = path
    image.file_format = "PNG"
    image.save()


# Géométrie -----------------------------------------------------------------------------------------

def cylinder(bm, radius, z0, z1, v0, v1, segments=24):
    """Cylindre fermé, UV : u autour, v de v0 à v1 sur la hauteur ; disques à la couleur du bord."""
    uv = bm.loops.layers.uv.verify()
    bottom, top = [], []
    for i in range(segments):
        angle = 2 * math.pi * i / segments
        x, y = radius * math.cos(angle), radius * math.sin(angle)
        bottom.append(bm.verts.new((x, y, z0)))
        top.append(bm.verts.new((x, y, z1)))
    for i in range(segments):
        j = (i + 1) % segments
        face = bm.faces.new((bottom[i], bottom[j], top[j], top[i]))
        u0, u1 = i / segments, (i + 1) / segments
        for loop, (u, v) in zip(face.loops, ((u0, v0), (u1, v0), (u1, v1), (u0, v1))):
            loop[uv].uv = (u, v)
    for ring, v in ((list(reversed(bottom)), v0), (top, v1)):
        face = bm.faces.new(ring)
        for loop in face.loops:
            loop[uv].uv = (0.5, v)


def box(bm, x0, x1, y0, y1, z0, z1, v):
    uv = bm.loops.layers.uv.verify()
    result = bmesh.ops.create_cube(bm, size=1.0)
    for vert in result["verts"]:
        vert.co.x = x0 if vert.co.x < 0 else x1
        vert.co.y = y0 if vert.co.y < 0 else y1
        vert.co.z = z0 if vert.co.z < 0 else z1
    for face in {f for vert in result["verts"] for f in vert.link_faces}:
        for loop in face.loops:
            loop[uv].uv = (0.5, v)


def mesh_object(name, build_fn, image):
    mesh = bpy.data.meshes.new(name)
    bm = bmesh.new()
    build_fn(bm)
    bm.normal_update()
    bm.to_mesh(mesh)
    bm.free()
    for poly in mesh.polygons:
        poly.use_smooth = True
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.scene.collection.objects.link(obj)
    material = bpy.data.materials.new(name)
    material.use_nodes = True
    nodes = material.node_tree.nodes
    bsdf = nodes.get("Principled BSDF")
    tex = nodes.new("ShaderNodeTexImage")
    tex.image = image
    material.node_tree.links.new(tex.outputs["Color"], bsdf.inputs["Base Color"])
    bsdf.inputs["Roughness"].default_value = 0.8
    obj.data.materials.append(material)
    return obj, material, bsdf


# Grenade type M18 : corps olive, bande de couleur en haut, inscriptions, tête métallique, levier.
# Hauteurs : 0,40 m au total (comme le modèle vanilla, avant le scale du script).
GRENADE_ROWS = lambda color: [
    (0.00, 0.08, METAL), (0.08, 0.50, OLIVE), (0.50, 0.80, color), (0.80, 0.84, OLIVE),
    (0.84, 1.00, METAL),
]


def build_grenade(bm):
    cylinder(bm, 0.058, 0.000, 0.330, 0.02, 0.80)   # corps (bandes jusqu'à la couleur)
    cylinder(bm, 0.040, 0.330, 0.375, 0.86, 0.95)   # tête (bouchon)
    cylinder(bm, 0.018, 0.375, 0.400, 0.90, 0.99)   # allumeur
    box(bm, 0.040, 0.052, -0.011, 0.011, 0.150, 0.380, 0.92)  # levier le long du corps
    cylinder_ring_pin(bm)


def cylinder_ring_pin(bm):
    # Goupille : petit anneau fait de 8 cubes, sur le côté de la tête.
    for i in range(8):
        angle = 2 * math.pi * i / 8
        cx, cz = 0.070 + 0.018 * math.cos(angle), 0.355 + 0.018 * math.sin(angle)
        box(bm, cx - 0.004, cx + 0.004, -0.004, 0.004, cz - 0.004, cz + 0.004, 0.97)


# Fusée de route : bâton rouge 0,58 m, capuchon blanc, pointe de frappe noire.
FLARE_ROWS = [(0.00, 0.06, DARK), (0.06, 0.84, FLARE_RED), (0.84, 1.00, CAP_WHITE)]


def build_flare(bm):
    cylinder(bm, 0.034, 0.000, 0.480, 0.03, 0.80)
    cylinder(bm, 0.038, 0.480, 0.580, 0.86, 0.99)


# Fusée allumée, couchée au sol : bâton rouge, bout incandescent (blanc chaud -> orange).
FLARE_LIT_ROWS = [(0.00, 0.10, (1.0, 0.97, 0.85)), (0.10, 0.18, (1.0, 0.55, 0.10)), (0.18, 0.24, DARK),
                  (0.24, 1.00, FLARE_RED)]


def build_flare_lit(bm):
    cylinder(bm, 0.034, 0.000, 0.500, 0.00, 1.00)
    # Couchée le long de X, posée sur le sol (z >= 0).
    bmesh.ops.rotate(bm, verts=bm.verts, cent=(0, 0, 0),
                     matrix=__import__("mathutils").Matrix.Rotation(math.radians(90), 3, "Y"))
    bmesh.ops.translate(bm, verts=bm.verts, vec=(-0.25, 0.0, 0.034))


# Bâton lumineux couché le long de X, posé au sol : bouchon sombre avec anneau d'accroche à une
# extrémité (v 0 à 0,12), tube de plastique translucide ensuite. 0,48 m dans Blender (≈ 0,16 m en jeu).
def mix(color, other, amount):
    return tuple(c * (1.0 - amount) + o * amount for c, o in zip(color, other))


def chemlight_rows(body):
    return [(0.00, 0.12, CHEMLIGHT_CAP), (0.12, 1.00, body)]


def build_chemlight(bm):
    import mathutils
    cylinder(bm, 0.050, 0.000, 0.060, 0.02, 0.10)    # bouchon
    cylinder(bm, 0.042, 0.060, 0.480, 0.14, 0.99)    # tube
    # Anneau d'accroche au bout du bouchon (8 cubes), dans le plan XZ une fois couché.
    for i in range(8):
        angle = 2 * math.pi * i / 8
        cx, cz = 0.022 * math.cos(angle), -0.028 + 0.022 * math.sin(angle)
        box(bm, cx - 0.005, cx + 0.005, -0.005, 0.005, cz - 0.005, cz + 0.005, 0.05)
    bmesh.ops.rotate(bm, verts=bm.verts, cent=(0, 0, 0),
                     matrix=mathutils.Matrix.Rotation(math.radians(90), 3, "Y"))
    bmesh.ops.translate(bm, verts=bm.verts, vec=(-0.24, 0.0, 0.050))


# Fumigène artisanal : boîte de conserve peinte d'une bande de couleur, couvercle de ruban adhésif,
# mèche de ficelle. 0,30 m de haut dans Blender (≈ 0,10 m en jeu).
def improvised_rows(color):
    return [(0.00, 0.05, METAL), (0.05, 0.30, TIN), (0.30, 0.72, color), (0.72, 0.86, TIN),
            (0.86, 0.94, TAPE), (0.94, 1.00, TWINE)]


def build_improvised(bm):
    cylinder(bm, 0.110, 0.000, 0.300, 0.02, 0.85)    # boîte
    cylinder(bm, 0.113, 0.300, 0.315, 0.88, 0.92)    # couvercle de ruban adhésif
    cylinder(bm, 0.012, 0.315, 0.400, 0.96, 0.99, segments=8)  # mèche


def set_glow(bsdf, image, strength):
    # Icône d'un bâton activé : la texture émet de la lumière (sans effet sur l'export FBX).
    tree = bsdf.id_data
    tex = next(node for node in tree.nodes if node.type == "TEX_IMAGE")
    tex.image = image
    tree.links.new(tex.outputs["Color"], bsdf.inputs["Emission Color"])
    bsdf.inputs["Emission Strength"].default_value = strength


def export_fbx(obj, path):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    bpy.ops.object.select_all(action="DESELECT")
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj
    # Export en mètres (Lcl Scaling = 100 dans le FBX) : voir l'en-tête pour l'échelle du script.
    bpy.ops.export_scene.fbx(filepath=path, use_selection=True, object_types={"MESH"},
                             global_scale=1.0, apply_unit_scale=True, bake_space_transform=False,
                             mesh_smooth_type="FACE", add_leaf_bones=False, path_mode="STRIP")


# Icônes ---------------------------------------------------------------------------------------------

def bounds(obj):
    import mathutils
    corners = [obj.matrix_world @ mathutils.Vector(c) for c in obj.bound_box]
    mins = [min(c[i] for c in corners) for i in range(3)]
    maxs = [max(c[i] for c in corners) for i in range(3)]
    center = [(mins[i] + maxs[i]) / 2 for i in range(3)]
    size = max(maxs[i] - mins[i] for i in range(3))
    return center, size


def setup_icon_camera(scene, obj):
    scene.render.engine = "BLENDER_EEVEE"
    scene.render.film_transparent = True
    # Transformation « Standard » : AgX (défaut de Blender) désature les couleurs vives des bandes.
    scene.view_settings.view_transform = "Standard"
    scene.render.resolution_x = ICON_RENDER
    scene.render.resolution_y = ICON_RENDER
    scene.render.image_settings.file_format = "PNG"
    scene.render.image_settings.color_mode = "RGBA"
    # Une seule caméra et un seul soleil : sinon chaque icône d'un même groupe ajoute un soleil et
    # éclaire davantage la suivante.
    for old in [o for o in scene.objects if o.name.startswith(("IconCamera", "IconSun"))]:
        bpy.data.objects.remove(old, do_unlink=True)
    camera_data = bpy.data.cameras.new("IconCamera")
    camera_data.type = "ORTHO"
    center, size = bounds(obj)
    camera_data.ortho_scale = size * 1.2
    camera = bpy.data.objects.new("IconCamera", camera_data)
    scene.collection.objects.link(camera)
    distance = 2.0
    elevation, azimuth = math.radians(25), math.radians(35)
    camera.location = (center[0] + distance * math.cos(elevation) * math.sin(azimuth),
                       center[1] - distance * math.cos(elevation) * math.cos(azimuth),
                       center[2] + distance * math.sin(elevation))
    direction = (center[0] - camera.location.x, center[1] - camera.location.y, center[2] - camera.location.z)
    import mathutils
    camera.rotation_euler = mathutils.Vector(direction).to_track_quat("-Z", "Y").to_euler()
    scene.camera = camera
    light_data = bpy.data.lights.new("IconSun", "SUN")
    light_data.energy = 3.5
    light = bpy.data.objects.new("IconSun", light_data)
    light.rotation_euler = (math.radians(40), 0, math.radians(30))
    scene.collection.objects.link(light)
    world = bpy.data.worlds.new("IconWorld")
    world.use_nodes = True
    world.node_tree.nodes["Background"].inputs["Strength"].default_value = 0.8
    scene.world = world
    return camera


def render_icon(scene, path, obj):
    tmp = path + ".big.png"
    setup_icon_camera(scene, obj)
    scene.render.filepath = tmp
    bpy.ops.render.render(write_still=True)
    big = bpy.data.images.load(tmp)
    big.scale(ICON_SIZE, ICON_SIZE)
    big.filepath_raw = path
    big.file_format = "PNG"
    big.save()
    os.remove(tmp)


def only(obj):
    for other in bpy.context.scene.objects:
        if other.type == "MESH":
            other.hide_render = other != obj


def main():
    textures = os.path.join(MEDIA, "textures")
    world_textures = os.path.join(textures, "WorldItems")
    models = os.path.join(MEDIA, "models_X", "WorldItems")

    if "grenade" in GROUPS:
        build_grenades(textures, world_textures, models)
    if "flare" in GROUPS:
        build_flares(textures, world_textures, models)
    if "chemlight" in GROUPS:
        build_chemlights(textures, world_textures, models)
    if "improvised" in GROUPS:
        build_improvised_smokes(textures, world_textures, models)
    print("SignalSmoke items OK ->", MEDIA, GROUPS)


def build_grenades(textures, world_textures, models):
    # Grenade : une géométrie, quatre textures ; les icônes montrent chaque couleur.
    scene = reset()
    first = None
    for color_name, color in COLORS.items():
        image = make_image("SignalSmoke_SmokeGrenade" + color_name, GRENADE_ROWS(color),
                           stencils=((0.30, 0.34, (0.85, 0.85, 0.75)),))
        save_image(image, os.path.join(world_textures, "SignalSmoke_SmokeGrenade%s.png" % color_name))
        if first is None:
            first, _, _ = mesh_object("SignalSmoke_SmokeGrenade", build_grenade, image)
            export_fbx(first, os.path.join(models, "SignalSmoke_SmokeGrenade.fbx"))
        else:
            first.data.materials[0].node_tree.nodes["Image Texture"].image = image
        only(first)
        render_icon(scene, os.path.join(textures, "Item_SignalSmoke_SmokeGrenade%s.png" % color_name), first)


def build_flares(textures, world_textures, models):
    for name, build_fn, rows in (
        ("SignalSmoke_RoadFlare", build_flare, FLARE_ROWS),
        ("SignalSmoke_RoadFlareLit", build_flare_lit, FLARE_LIT_ROWS),
    ):
        scene = reset()
        image = make_image(name, rows)
        save_image(image, os.path.join(world_textures, name + ".png"))
        obj, _, _ = mesh_object(name, build_fn, image)
        export_fbx(obj, os.path.join(models, name + ".fbx"))
        only(obj)
        render_icon(scene, os.path.join(textures, "Item_" + name + ".png"), obj)


def build_chemlights(textures, world_textures, models):
    # Une géométrie ; textures neuves (plastique pâle), activées (lumineuses) et usagée (grise).
    variants = []
    for color_name, color in CHEMLIGHT_COLORS.items():
        variants.append(("SignalSmoke_Chemlight" + color_name, mix(color, (1.0, 1.0, 1.0), 0.35), 0.0))
        variants.append(("SignalSmoke_Chemlight" + color_name + "Lit", mix(color, (1.0, 1.0, 1.0), 0.15), 2.5))
    variants.append(("SignalSmoke_ChemlightUsed", CHEMLIGHT_SPENT, 0.0))
    scene = reset()
    obj = bsdf = None
    for name, body, glow in variants:
        image = make_image(name, chemlight_rows(body))
        save_image(image, os.path.join(world_textures, name + ".png"))
        if obj is None:
            obj, _, bsdf = mesh_object("SignalSmoke_Chemlight", build_chemlight, image)
            export_fbx(obj, os.path.join(models, "SignalSmoke_Chemlight.fbx"))
        set_glow(bsdf, image, glow)
        only(obj)
        render_icon(scene, os.path.join(textures, "Item_" + name + ".png"), obj)


def build_improvised_smokes(textures, world_textures, models):
    scene = reset()
    obj = None
    for color_name, color in COLORS.items():
        name = "SignalSmoke_ImprovisedSmoke" + color_name
        image = make_image(name, improvised_rows(color))
        save_image(image, os.path.join(world_textures, name + ".png"))
        if obj is None:
            obj, _, _ = mesh_object("SignalSmoke_ImprovisedSmoke", build_improvised, image)
            export_fbx(obj, os.path.join(models, "SignalSmoke_ImprovisedSmoke.fbx"))
        else:
            obj.data.materials[0].node_tree.nodes["Image Texture"].image = image
        only(obj)
        render_icon(scene, os.path.join(textures, "Item_" + name + ".png"), obj)


main()
