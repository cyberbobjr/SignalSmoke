"""Tests hors jeu de Signal Smoke : fonctions pures du module public (lupa), traductions (mêmes
fichiers et clés que EN, JSON plat sans BOM), descriptions Steam (8 000 octets UTF-8 moins le bloc
« Workshop ID / Mod ID » ajouté à chaque langue, BBCode équilibré, mêmes liens que l'anglais,
workshop.txt identique à README.steam), puis luacheck.
Usage : python tests/run_tests.py"""
import json
import pathlib
import re
import subprocess
import sys
from collections import Counter

import lupa

ROOT = pathlib.Path(__file__).resolve().parents[1]
SHARED = ROOT / "Contents" / "mods" / "batman_SignalSmoke" / "42.21" / "media" / "lua" / "shared"

lua = lupa.LuaRuntime(unpack_returned_tuples=True)
lua.execute(f'package.path = "{SHARED.as_posix()}/?.lua;" .. package.path')
# Kahlua n'a pas next() : le retirer fait échouer tout usage dans le code testé.
lua.execute("next = nil")
result = lua.execute(r'''
local S = require "SignalSmoke/SignalSmoke"
local checks = {}
local function check(name, cond) checks[#checks + 1] = (cond and "OK   " or "ECHEC ") .. name end

check("couleur nommée", S.resolveColor("green").g == 1.0 and S.resolveColor("nope") == nil)
check("couleur libre bornée", S.resolveColor({ r = 2, g = -1, b = 0.5 }).r == 1 and S.resolveColor({ r = 2, g = -1, b = 0.5 }).g == 0)
local e = S.newEntry({ x = 10, y = 20, color = "red", minutes = 30, radius = 5 }, 100, 60)
check("entrée : défauts et bornes", e.z == 0 and e.kind == "smoke" and e.radius == S.MAX_RADIUS
    and math.abs(e.untilH - 100.5) < 1e-9 and e.light == true and e.id == nil)
check("entrée : identifiant et propriétaire", S.newEntry({ x = 1, y = 2, id = 7, owner = "M" }, 0, 60).id == "7")
local r = S.newEntry({ x = 1, y = 2, realSeconds = 150 }, 0, 60)
check("durée en secondes réelles (journée de 60 min)", math.abs(r.untilH - 1.0) < 1e-9)
check("refus : coordonnées", select(2, S.newEntry({ x = 1.5, y = 2 }, 0, 60)) ~= nil)
check("refus : couleur", select(2, S.newEntry({ x = 1, y = 2, color = "rose" }, 0, 60)) ~= nil)
check("refus : type", select(2, S.newEntry({ x = 1, y = 2, kind = "fire" }, 0, 60)) ~= nil)
check("refus : durée nulle", select(2, S.newEntry({ x = 1, y = 2, minutes = 0 }, 0, 60)) ~= nil)
check("fusée : objet suivi", S.newEntry({ x = 1, y = 2, kind = "flare", itemId = 42 }, 0, 60).itemId == 42)
check("actif / échu", S.isLive({ untilH = 10 }, 9.9) and not S.isLive({ untilH = 10 }, 10) and not S.isLive(nil, 0))

-- 0.2.0 : bâtons lumineux, champs ajoutés, fumée facultative.
local c = S.newEntry({ x = 1, y = 2, kind = "chemlight", color = "blue", untilH = 108, lightRadius = 99, smoke = true }, 100, 60)
check("bâton lumineux : sans fumée, rayon borné, fin absolue", c.smoke == false and c.lightRadius == S.MAX_LIGHT_RADIUS
    and c.untilH == 108 and not S.hasSmoke(c) and c.source == "script")
check("refus : fin absolue passée", select(2, S.newEntry({ x = 1, y = 2, untilH = 99 }, 100, 60)) ~= nil)
check("entrée 0.1.0 sans champ smoke : fumée", S.hasSmoke({ kind = "smoke" }) and S.hasSmoke({ kind = "flare" }))
check("fumée désactivée", not S.hasSmoke(S.newEntry({ x = 1, y = 2, smoke = false }, 0, 60)))
check("source, joueur, objets", (function()
    local e2 = S.newEntry({ x = 1, y = 2, source = "grenade", username = "bob", itemType = "A.B", spentType = "A.C" }, 0, 60)
    return e2.source == "grenade" and e2.username == "bob" and e2.itemType == "A.B" and e2.spentType == "A.C"
end)())
check("bâton lumineux reconnu", S.chemlightOf("SignalSmoke.ChemlightRed") == "red"
    and select(2, S.chemlightOf("SignalSmoke.ChemlightRedLit")) == true and S.chemlightOf("Base.Torch") == nil)
check("raté du fumigène artisanal", S.isDud(19, 20) and not S.isDud(20, 20) and not S.isDud(0, 0))

-- Options sandbox : défaut sans jeu, puis SandboxVars, puis options Java.
check("option : défaut", S.option("ChemlightHours") == 8 and S.option("FlaresInPoliceCars") == true)
SandboxVars = { SignalSmoke = { ChemlightHours = 3, FlaresInPoliceCars = false, LootMultiplier = "x" } }
check("option : SandboxVars, type contrôlé", S.option("ChemlightHours") == 3 and S.option("FlaresInPoliceCars") == false
    and S.option("LootMultiplier") == 1.0)
getSandboxOptions = function()
    return { getOptionByName = function(_, name)
        if name == "SignalSmoke.ChemlightHours" then return { getValue = function() return 12 end } end
        return nil
    end, getDayLengthMinutes = function() return 60 end }
end
check("option : options Java prioritaires", S.option("ChemlightHours") == 12 and S.option("FlaresInPoliceCars") == false)
SandboxVars = nil

-- Butin : réécriture idempotente.
local items = { "Base.A", 1, "SignalSmoke.RoadFlare", 4, "Base.B", 2 }
S.rewriteLootItems(items, { { "SignalSmoke.RoadFlare", 3 }, { "SignalSmoke.ChemlightRed", 1 } }, 2)
check("butin : multiplicateur", #items == 8 and items[1] == "Base.A" and items[3] == "Base.B" and items[6] == 6 and items[8] == 2)
S.rewriteLootItems(items, { { "SignalSmoke.RoadFlare", 3 } }, 1)
check("butin : idempotent", #items == 6 and items[5] == "SignalSmoke.RoadFlare" and items[6] == 3)
S.rewriteLootItems(items, { { "SignalSmoke.RoadFlare", 3 } }, 0)
check("butin : multiplicateur nul", #items == 4 and items[4] == 2)

-- Abonnés : sans doublon, isolés, retrait pendant l'appel.
local seen = {}
local function a(event) seen[#seen + 1] = "a:" .. event.type end
local function boom() error("abonné fautif") end
local function once(event) seen[#seen + 1] = "once"; S.removeSignalListener(once) end
check("abonnement sans doublon", S.onSignal(a) and not S.onSignal(a) and not S.onSignal("x"))
S.onSignal(boom); S.onSignal(once)
local printed = {}
local realPrint = print
print = function(text) printed[#printed + 1] = text end
S.notify({ type = "started", id = "t" })
S.notify({ type = "expired", id = "t" })
print = realPrint
check("abonné fautif isolé et journalisé", seen[1] == "a:started" and seen[2] == "once" and seen[3] == "a:expired"
    and #seen == 3 and #printed == 2 and string.find(printed[1], "abonné fautif", 1, true) ~= nil)
check("désabonnement", S.removeSignalListener(boom) and not S.removeSignalListener(boom))

-- Registre et événements (jeu simulé : solo).
local store, now = {}, 100
isClient = function() return false end
isServer = function() return false end
ModData = { getOrCreate = function(k) store[k] = store[k] or {}; return store[k] end,
    get = function(k) return store[k] end, transmit = function() end }
getGameTime = function() return { getWorldAgeHours = function() return now end } end
instanceof = function(o, class) return type(o) == "table" and o.class == class end
local events = {}
local function record(event) events[#events + 1] = event end
S.removeSignalListener(a)
S.onSignal(record)
local player = { class = "IsoPlayer", getUsername = function() return "alice" end }
local id = S.start({ x = 5, y = 6, id = "e1", minutes = 60, source = "flare", player = player })
check("start : événement started", id == "e1" and events[1].type == "started" and events[1].source == "flare"
    and events[1].username == "alice" and events[1].player == player and events[1].replaced == false
    and store[S.MODDATA_KEY].entries.e1.username == "alice")
S.start({ x = 5, y = 6, id = "e1", minutes = 60 })
check("start : remplacement signalé", events[2].replaced == true and events[2].source == "script" and events[2].player == nil)
check("stop : raison", S.stop("e1", "pickedUp") == true and events[3].type == "stopped" and events[3].reason == "pickedUp"
    and S.stop("e1") == false)
S.start({ x = 1, y = 1, id = "e2", minutes = 30 })
now = 101
local expired = S.expire()
check("expire : événement expired", #expired == 1 and events[5].type == "expired" and events[5].id == "e2"
    and store[S.MODDATA_KEY].entries.e2 == nil)
isClient = function() return true end
check("client MP : start refusé", select(2, S.start({ x = 1, y = 1 })) == "server only")
return table.concat(checks, "\n")
''')
print(result)
failed = "ECHEC" in result

TRANSLATE = SHARED / "Translate"
STEAM_MAX_BYTES = 8000
STEAM_TAGS = ("h1", "h2", "h3", "b", "i", "u", "list", "url", "img", "code")
STEAM_URL = re.compile(r"https?://[^\s\[\]]+")


def report(ok, message):
    global failed
    print(("OK   " if ok else "ECHEC ") + message)
    failed = failed or not ok


def load_json(path):
    raw = path.read_bytes()
    try:
        data = json.loads(raw.decode("utf-8"))
    except (UnicodeDecodeError, json.JSONDecodeError) as error:
        report(False, f"{path.relative_to(ROOT)} : JSON invalide ({error})")
        return {}
    report(not raw.startswith(b"\xef\xbb\xbf"), f"{path.relative_to(ROOT)} : sans BOM")
    report(isinstance(data, dict) and all(isinstance(v, str) and "%" not in v.replace("%%", "")
                                          for v in data.values()),
           f"{path.relative_to(ROOT)} : objet plat de chaînes, sans % seul")
    return data if isinstance(data, dict) else {}


reference = {p.name: load_json(p) for p in sorted((TRANSLATE / "EN").glob("*.json"))}
for folder in sorted(p for p in TRANSLATE.iterdir() if p.is_dir() and p.name != "EN"):
    names = {p.name for p in folder.glob("*.json")}
    report(names == set(reference), f"traductions {folder.name} : mêmes fichiers que EN")
    for name in sorted(names & set(reference)):
        report(set(load_json(folder / name)) == set(reference[name]), f"traductions {folder.name}/{name} : mêmes clés que EN")

# Cohérence scripts / traductions / ressources : chaque objet du module SignalSmoke a un nom traduit,
# son icône et ses modèles ; chaque recette, un nom ; chaque option sandbox, un libellé et une aide ;
# chaque clé citée par un script ou par getText existe en anglais ; les défauts Lua = sandbox-options.
MEDIA = SHARED.parents[1]
english_keys = {key for data in reference.values() for key in data}
recipes_en = load_json(TRANSLATE / "EN" / "Recipes.json") if (TRANSLATE / "EN" / "Recipes.json").exists() else {}
scripts = "\n".join(p.read_text(encoding="utf-8") for p in sorted((MEDIA / "scripts").glob("*.txt")))
models = dict(re.findall(r"model\s+(\w+)\s*\{(.*?)\n    \}", scripts, re.S))
for name, body in re.findall(r"\n    item\s+(\w+)\s*\{(.*?)\n    \}", scripts, re.S):
    report(f"SignalSmoke.{name}" in english_keys, f"objet {name} : nom traduit")
    icon = re.search(r"Icon\s*=\s*(\w+)", body)
    report(bool(icon) and (MEDIA / "textures" / f"Item_{icon.group(1)}.png").exists(), f"objet {name} : icône")
    for key in re.findall(r"(?:WorldStaticModel|StaticModel)\s*=\s*(\w+)", body):
        report(key in models, f"objet {name} : modèle {key} déclaré")
    for key in re.findall(r"Tooltip\s*=\s*(\w+)", body):
        report(key in english_keys, f"objet {name} : {key} traduit")
for name, body in models.items():
    mesh = re.search(r"mesh\s*=\s*([\w/]+)", body).group(1)
    texture = re.search(r"texture\s*=\s*([\w/]+)", body).group(1)
    report((MEDIA / "models_X" / f"{mesh}.fbx").exists() and (MEDIA / "textures" / f"{texture}.png").exists(),
           f"modèle {name} : maillage et texture")
for name in re.findall(r"craftRecipe\s+(\w+)", scripts):
    report(name in recipes_en, f"recette {name} : nom traduit")
sandbox_file = (MEDIA / "sandbox-options.txt").read_text(encoding="utf-8")
lua_source = (SHARED / "SignalSmoke" / "SignalSmoke.lua").read_text(encoding="utf-8")
for option, body in re.findall(r"option\s+SignalSmoke\.(\w+)\s*\{(.*?)\}", sandbox_file, re.S):
    translation = re.search(r"translation\s*=\s*(\w+)", body).group(1)
    report({f"Sandbox_{translation}", f"Sandbox_{translation}_tooltip"} <= english_keys, f"option {option} : traduite")
    default = re.search(r"default\s*=\s*([\w.]+)", body).group(1)
    lua_default = re.search(rf"\b{option}\s*=\s*([\w.]+),", lua_source)
    report(bool(lua_default) and (lua_default.group(1) == default or
                                  (default.replace(".", "", 1).isdigit() and float(lua_default.group(1)) == float(default))),
           f"option {option} : défaut Lua = {default}")
for page in set(re.findall(r"page\s*=\s*(\w+)", sandbox_file)):
    report(f"Sandbox_{page}" in english_keys, f"page sandbox {page} : traduite")
lua_files = list((ROOT / "Contents").rglob("*.lua"))
for key in sorted({k for p in lua_files for k in re.findall(r'getText\("(\w+)"\)', p.read_text(encoding="utf-8"))}):
    report(key in english_keys, f"getText {key} : traduit")
uses_next = [p.name for p in lua_files if re.search(r"(?<![.:\w])next\(", p.read_text(encoding="utf-8"))]
report(not uses_next, f"pas de next() (absent de Kahlua) {uses_next or ''}")

workshop = (ROOT / "workshop.txt").read_text(encoding="utf-8").splitlines()
workshop_id = next((line[3:] for line in workshop if line.startswith("id=")), "")
mod_ids = [line[3:].strip() for info in sorted((ROOT / "Contents" / "mods").glob("*/*/mod.info"))
           for line in info.read_text(encoding="utf-8").splitlines() if line.startswith("id=")]
# Bloc ajouté en bas de chaque langue à l'envoi (.claude/tools/pz_workshop_project.py, upload_suffix) ;
# avant la création de l'objet, un identifiant de 10 chiffres fictif en réserve la place.
suffix = "\n\nWorkshop ID: " + (workshop_id or "0000000000") + "".join("\nMod ID: " + m for m in mod_ids)
english = (ROOT / "README.steam").read_text(encoding="utf-8")
for path in sorted(ROOT.glob("README.steam*")):
    text = path.read_text(encoding="utf-8")
    size = len(text.rstrip("\n").encode("utf-8")) + len(suffix.encode("utf-8"))
    report(size <= STEAM_MAX_BYTES, f"{path.name} : {size} octets avec le bloc d'identifiants")
    for tag in STEAM_TAGS:
        opened = len(re.findall(r"\[" + tag + r"(?:=[^\]]*)?\]", text))
        if opened:
            report(opened == text.count(f"[/{tag}]"), f"{path.name} : [{tag}] équilibré")
    report(Counter(STEAM_URL.findall(text)) == Counter(STEAM_URL.findall(english)), f"{path.name} : mêmes liens que README.steam")
description = [line[len("description="):] for line in workshop if line.startswith("description=")]
report(description == english.splitlines(), "workshop.txt : description identique à README.steam")

lint = subprocess.run(["luacheck", "--config", str(ROOT / ".luacheckrc"),
                       *[str(p) for p in (ROOT / "Contents").rglob("*.lua")]],
                      capture_output=True, text=True)
print(lint.stdout.strip().splitlines()[-1] if lint.stdout else lint.stderr)
failed = failed or lint.returncode != 0
print("RESULTAT :", "KO" if failed else "OK")
sys.exit(1 if failed else 0)
