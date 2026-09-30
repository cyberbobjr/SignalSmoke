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
