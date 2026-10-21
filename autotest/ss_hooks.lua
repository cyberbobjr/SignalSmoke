-- Signal Smoke in-game test (pz-autotest): nominal path, single player and multiplayer.
-- Single player (sp): the client hooks play both sides on the same machine.
-- Multiplayer (mp, clientRun): the server hooks place the signals next to the first player, the client 1 hooks
-- check what the client draws (marked IsoFire, lamps), compare the object indices of the burning flare square
-- with the server (risk C12: the local smoke is added to the object list of the square) and pick the flare up
-- with the vanilla grab action. Server and client talk through server/client commands (module SSAutoTest).
-- Public API used: start, stop, isActive, list, onSignal, removeSignalListener, startChemlight, the timed
-- actions SignalSmoke_LightFlareAction and SignalSmoke_ActivateChemlightAction, and OnThrowableExplode for
-- the grenade (real IsoTrap, never added to the world).
local SignalSmoke = require "SignalSmoke/SignalSmoke"

local H = { client = {}, server = {} }

local CMD = "SSAutoTest"
local MARK_KEY = "batmanSS" -- ModData mark of the client smoke (SignalSmoke_Client.lua)
local SHORT_SECONDS = 15    -- real seconds of the entries that must expire during the test
local GRAB_TIME = 10

-- ------------------------------------------------------------------------------------------- helpers

local function nowMs() return getTimestampMs() end

local function errorCount()
    if type(getLuaDebuggerErrorCount) ~= "function" then return nil end
    local ok, n = pcall(getLuaDebuggerErrorCount)
    return ok and n or nil
end

local function newRun()
    return { lines = {}, ok = true, step = 1, finished = false, events = {}, errors0 = errorCount(), inbox = {} }
end

local function rec(R, ok, name, detail)
    if not ok then R.ok = false end
    R.lines[#R.lines + 1] = (ok and "PASS " or "FAIL ") .. name .. (detail ~= nil and (" - " .. tostring(detail)) or "")
end

local function info(R, text)
    R.lines[#R.lines + 1] = "INFO " .. text
end

local function check(R, name, cond, detail)
    rec(R, cond and true or false, name, detail)
end

-- Runs the current step: fn(R) returns true when the step is over. A step error or timeout is a FAIL and the
-- run goes on with the next step (later steps guard their own inputs).
local function runSteps(R, steps)
    if R.finished then return true end
    local step = steps[R.step]
    if not step then
        R.finished = true
        return true
    end
    R.stepAt = R.stepAt or nowMs()
    local ok, over = pcall(step.fn, R)
    local limit = (step.timeout or 15) * 1000
    if not ok then
        rec(R, false, step.name, "error: " .. tostring(over))
        over = true
    elseif not over and nowMs() - R.stepAt > limit then
        rec(R, false, step.name, "timeout after " .. tostring(step.timeout or 15) .. " s")
        over = true
    end
    if over then
        R.step = R.step + 1
        R.stepAt = nil
    end
    return false
end

local function finish(R, label)
    local e1 = errorCount()
    if R.errors0 and e1 then
        check(R, label .. ".luaErrors", e1 == R.errors0, "Lua errors during the run: " .. tostring(e1 - R.errors0))
    end
    local pass, fail = 0, 0
    for _, line in ipairs(R.lines) do
        if line:sub(1, 5) == "PASS " then pass = pass + 1 elseif line:sub(1, 5) == "FAIL " then fail = fail + 1 end
    end
    return { ok = R.ok and fail == 0, summary = label .. " " .. pass .. " PASS, " .. fail .. " FAIL", lines = R.lines }
end

local function square(x, y, z) return getCell():getGridSquare(x, y, z) end

-- First square in direction (dx, dy), 3 to 8 squares away, where smoke can be added.
local function smokeSquare(px, py, pz, dx, dy)
    for d = 3, 8 do
        local sq = square(px + dx * d, py + dy * d, pz)
        if sq and sq:isSolidFloor() and IsoFire.CanAddSmoke(sq, true) then return sq end
    end
    return square(px + dx * 3, py + dy * 3, pz)
end

-- IsoFire marked with this entry id around (x, y, z).
local function markedFires(id, x, y, z, radius)
    local count = 0
    for dx = -radius, radius do
        for dy = -radius, radius do
            local sq = square(x + dx, y + dy, z)
            local objects = sq and sq:getObjects()
            if objects then
                for i = 0, objects:size() - 1 do
                    local o = objects:get(i)
                    if instanceof(o, "IsoFire") and o:getModData()[MARK_KEY] == id then count = count + 1 end
                end
            end
        end
    end
    return count
end

-- Vanilla lights also live in getLamppostPositions, on the very squares the test uses:
-- - IsoBuilding puts one on the outside square of each window and door (IsoBuilding.java:358-395,
--   getLocalToBuilding() set);
-- - room lights hang on their switches (CellLoader.java:146-160, IsoLightSwitch.java:130-134: getSwitches()
--   not empty, hydro powered);
-- - a tile object whose sprite has lightR/G/B owns one, built like a plain lamp (IsoObject.java:5998-6036:
--   no building, no switch, not hydro), reached by IsoObject:getLightSource(). Seen in game on the spawn
--   square: 0.45/0.51/0.51, radius 6 = lightR 115, lightG 130, lightB 130, LightRadius 6
--   (lighting_indoor_02_44-47 or _80-83, newtiledefinitions.tiles.txt).
-- A lamp from getCell():addLamppost(x, y, z, r, g, b, rad) is none of these: only those are counted.
local function tileLights(sq)
    local owned = {}
    local objects = sq and sq:getObjects()
    if objects then
        for i = 0, objects:size() - 1 do
            local o = objects:get(i)
            local light = not instanceof(o, "IsoFire") and o:getLightSource() or nil
            if light then
                local sprite = o:getSprite()
                owned[#owned + 1] = { light = light, name = sprite and sprite:getName() or "?" }
            end
        end
    end
    return owned
end

-- Owner of a lamp of (x, y, z): nil for a plain addLamppost lamp, otherwise a short label.
local function lampOwner(l, owned)
    if l:getLocalToBuilding() ~= nil then return "building" end
    if not l:getSwitches():isEmpty() or l:isHydroPowered() then return "switch" end
    for _, t in ipairs(owned) do
        if t.light == l then return "tile " .. t.name end
    end
    return nil
end

-- Plain lamps on (x, y, z); second value: the count of vanilla building, switch and tile lights left aside.
local function lampsAt(x, y, z)
    local list, count, foreign = getCell():getLamppostPositions(), 0, 0
    local owned = tileLights(square(x, y, z))
    for i = 0, list:size() - 1 do
        local l = list:get(i)
        if l:getX() == x and l:getY() == y and l:getZ() == z then
            if lampOwner(l, owned) == nil then count = count + 1 else foreign = foreign + 1 end
        end
    end
    return count, foreign
end

-- Readable list of what is left around (x, y, z): marked IsoFire (with their mark) and every lamp.
local function describeArea(label, x, y, z, radius)
    local parts = {}
    local list = getCell():getLamppostPositions()
    for dx = -radius, radius do
        for dy = -radius, radius do
            local sx, sy = x + dx, y + dy
            local sq = square(sx, sy, z)
            local objects = sq and sq:getObjects()
            if objects then
                for i = 0, objects:size() - 1 do
                    local o = objects:get(i)
                    if instanceof(o, "IsoFire") and o:getModData()[MARK_KEY] ~= nil then
                        parts[#parts + 1] = "IsoFire@" .. sx .. "," .. sy .. "(mark=" .. tostring(o:getModData()[MARK_KEY])
                            .. ", life=" .. tostring(o:getLife()) .. ")"
                    end
                end
            end
            local owned = tileLights(sq)
            for i = 0, list:size() - 1 do
                local l = list:get(i)
                if l:getX() == sx and l:getY() == sy and l:getZ() == z then
                    parts[#parts + 1] = string.format("lamp@%d,%d(%s, rgb=%.2f/%.2f/%.2f, radius=%d, active=%s)",
                        sx, sy, lampOwner(l, owned) or "plain", l:getR(), l:getG(), l:getB(),
                        l:getRadius(), tostring(l:isActive()))
                end
            end
        end
    end
    return label .. " " .. x .. "," .. y .. "," .. z .. ": " .. (#parts > 0 and table.concat(parts, "; ") or "nothing")
end

local function worldItemOn(sq, itemId)
    local objects = sq and sq:getWorldObjects()
    if not objects then return nil end
    for i = 0, objects:size() - 1 do
        local wo = objects:get(i)
        local item = wo:getItem()
        if item and item:getID() == itemId then return wo end
    end
    return nil
end

local function worldTypeOn(sq, fullType)
    local objects = sq and sq:getWorldObjects()
    if not objects then return false end
    for i = 0, objects:size() - 1 do
        local item = objects:get(i):getItem()
        if item and item:getFullType() == fullType then return true end
    end
    return false
end

-- Object classes of a square, in list order (C12 report).
local function objectList(sq)
    local out = {}
    local objects = sq and sq:getObjects()
    if objects then
        for i = 0, objects:size() - 1 do
            local o = objects:get(i)
            local name = instanceof(o, "IsoFire") and "IsoFire"
                or instanceof(o, "IsoWorldInventoryObject") and ("WorldItem:" .. tostring(o:getItem() and o:getItem():getID()))
                or (o:getObjectName() or "?")
            out[#out + 1] = name
        end
    end
    return table.concat(out, ",")
end

local function event(R, eventType, pred)
    for _, e in ipairs(R.events) do
        if e.type == eventType and (pred == nil or pred(e)) then return e end
    end
    return nil
end

local function hoursFor(seconds)
    local options = getSandboxOptions()
    return SignalSmoke.realSecondsToHours(seconds, options and options:getDayLengthMinutes() or 60)
end

-- ----------------------------------------------------------------------- authority (SP or MP server)

-- Listener and API refusals. Returns the listener function.
local function setupListener(R)
    R.listener = function(e)
        R.events[#R.events + 1] = { type = e.type, id = e.id, source = e.source, reason = e.reason,
            replaced = e.replaced, username = e.username, kind = e.entry and e.entry.kind,
            itemId = e.entry and e.entry.itemId }
    end
    check(R, "api.onSignal", SignalSmoke.onSignal(R.listener) == true, "listener added")
    check(R, "api.onSignal.noDuplicate", SignalSmoke.onSignal(R.listener) == false)
    local id, err = SignalSmoke.start{}
    check(R, "api.start.refused", id == nil and type(err) == "string", tostring(err))
end

local function startApiSmoke(R)
    local s = R.smokeSq
    local id = SignalSmoke.start{ id = "pzat:smoke", color = "green", radius = 1, minutes = 30, light = true,
        x = s:getX(), y = s:getY(), z = s:getZ(), owner = "pzat" }
    R.smokeId = id
    check(R, "api.start", id == "pzat:smoke", tostring(id))
    check(R, "api.isActive", SignalSmoke.isActive("pzat:smoke") == true)
    local entry = SignalSmoke.list()["pzat:smoke"]
    check(R, "api.list", entry ~= nil and entry.radius == 1 and entry.kind == "smoke",
        entry and ("radius=" .. tostring(entry.radius)) or "missing")
    check(R, "api.event.started", event(R, "started", function(e) return e.id == "pzat:smoke" end) ~= nil)
end

local function stopApiSmoke(R)
    check(R, "api.stop", SignalSmoke.stop("pzat:smoke") == true)
    check(R, "api.stop.inactive", SignalSmoke.isActive("pzat:smoke") == false
        and SignalSmoke.list()["pzat:smoke"] == nil)
    check(R, "api.stop.again", SignalSmoke.stop("pzat:smoke") == false)
    check(R, "api.event.stopped", event(R, "stopped", function(e)
        return e.id == "pzat:smoke" and e.reason == "script" end) ~= nil)
end

-- Grenade: real IsoTrap (not added to the world) given to the OnThrowableExplode subscribers.
local function explodeGrenade(R, player)
    local g = R.grenadeSq
    local weapon = instanceItem("SignalSmoke.SmokeGrenadeGreen")
    local trap = IsoTrap.new(player, weapon, getCell(), g)
    triggerEvent("OnThrowableExplode", trap, g)
    local e = event(R, "started", function(ev) return ev.source == "grenade" end)
    R.grenadeId = e and e.id
    check(R, "grenade.started", e ~= nil, e and e.id)
    local entry = R.grenadeId and SignalSmoke.list()[R.grenadeId]
    check(R, "grenade.entry", entry ~= nil and entry.radius == 1 and entry.x == g:getX() and entry.sound ~= nil,
        entry and ("radius=" .. tostring(entry.radius) .. " sound=" .. tostring(entry.sound)) or "missing")
    check(R, "grenade.username", e ~= nil and e.username == player:getUsername(), e and tostring(e.username))
end

-- Flare lit by the real action (complete() runs on the authority).
local function lightFlare(R, player)
    local inv = player:getInventory()
    local item = inv:AddItem("SignalSmoke.RoadFlare")
    if isServer() then sendAddItemToContainer(inv, item) end
    local done = SignalSmoke_LightFlareAction:new(player, item):complete()
    check(R, "flare.action", done == true)
    local e = event(R, "started", function(ev) return ev.source == "flare" end)
    R.flareId = e and e.id
    R.flareItemId = e and e.itemId
    R.flareSq = player:getCurrentSquare()
    local wo = R.flareItemId and worldItemOn(R.flareSq, R.flareItemId)
    check(R, "flare.started", e ~= nil and e.kind == "flare" and SignalSmoke.isActive(R.flareId), e and e.id)
    check(R, "flare.onGround", wo ~= nil and wo:getItem():getFullType() == "SignalSmoke.RoadFlareLit")
    check(R, "flare.inventory", not inv:contains(item), "unlit flare removed")
    R.flareIndex = wo and wo:getObjectIndex() or -1
    R.flareObjects = objectList(R.flareSq)
end

local function activateChemlight(R, player)
    local inv = player:getInventory()
    local item = inv:AddItem("SignalSmoke.ChemlightGreen")
    if isServer() then sendAddItemToContainer(inv, item) end
    local done = SignalSmoke_ActivateChemlightAction:new(player, item):complete()
    check(R, "chemlight.action", done == true)
    local e = event(R, "started", function(ev) return ev.source == "chemlight" end)
    R.chemId = e and e.id
    R.chemItemId = e and e.itemId
    R.chemSq = player:getCurrentSquare()
    local entry = R.chemId and SignalSmoke.list()[R.chemId]
    check(R, "chemlight.started", entry ~= nil and entry.kind == "chemlight" and entry.smoke == false
        and entry.spentType == SignalSmoke.CHEMLIGHT_USED, e and e.id)
end

-- The chemlight ends in SHORT_SECONDS: ModData of the world item shortened, then registered again (same id).
local function shortenChemlight(R)
    local wo = R.chemItemId and worldItemOn(R.chemSq, R.chemItemId)
    check(R, "chemlight.onGround", wo ~= nil)
    if not wo then return end
    wo:getItem():getModData()[SignalSmoke.CHEMLIGHT_UNTIL_KEY] = SignalSmoke.nowHours() + hoursFor(SHORT_SECONDS)
    local id = SignalSmoke.startChemlight(wo, nil)
    check(R, "chemlight.restart", id == R.chemId and event(R, "started", function(e)
        return e.id == R.chemId and e.replaced == true end) ~= nil, tostring(id))
end

-- Scripted flare placed by the public API (SignalSmoke.placeFlare, 0.3.0), ending in SHORT_SECONDS.
local function startFlare2(R)
    local f = R.flare2Sq
    local id, item = SignalSmoke.placeFlare{ id = "pzat:flare2", color = "red", light = true,
        realSeconds = SHORT_SECONDS, x = f:getX(), y = f:getY(), z = f:getZ(), owner = "pzat", source = "script" }
    R.flare2ItemId = type(item) ~= "string" and item and item:getID() or nil
    check(R, "flare2.started", id == "pzat:flare2" and R.flare2ItemId ~= nil
        and worldItemOn(f, R.flare2ItemId) ~= nil, tostring(id) .. " " .. tostring(type(item) == "string" and item))
end

local function expiriesSeen(R)
    local function expired(id) return id ~= nil and event(R, "expired", function(e) return e.id == id end) ~= nil end
    return expired(R.grenadeId) and expired(R.chemId) and expired("pzat:flare2")
end

local function checkExpiries(R)
    check(R, "grenade.expired", event(R, "expired", function(e) return e.id == R.grenadeId end) ~= nil)
    check(R, "chemlight.expired", event(R, "expired", function(e) return e.id == R.chemId end) ~= nil)
    check(R, "flare2.expired", event(R, "expired", function(e) return e.id == "pzat:flare2" end) ~= nil)
    check(R, "chemlight.spent", worldTypeOn(R.chemSq, SignalSmoke.CHEMLIGHT_USED)
        and worldItemOn(R.chemSq, R.chemItemId) == nil, "ChemlightUsed on the ground")
    local wo, known = SignalSmoke.findItemObject{ x = R.flare2Sq:getX(), y = R.flare2Sq:getY(),
        z = R.flare2Sq:getZ(), itemId = R.flare2ItemId }
    check(R, "flare2.removed", wo == nil and known == true)
    local left = {}
    for id in pairs(SignalSmoke.list()) do
        if id == R.grenadeId or id == R.chemId or id == "pzat:flare2" or id == R.flareId or id == "pzat:smoke" then
            left[#left + 1] = id
        end
    end
    check(R, "registry.cleared", #left == 0, table.concat(left, ","))
end

local function endListener(R)
    check(R, "api.removeSignalListener", SignalSmoke.removeSignalListener(R.listener) == true)
end

-- --------------------------------------------------------------------------------- single player

local function spSteps(P)
    local p
    return {
        { name = "sp.setup", fn = function(R)
            p = getPlayer()
            local x, y, z = math.floor(p:getX()), math.floor(p:getY()), math.floor(p:getZ())
            R.smokeSq = smokeSquare(x, y, z, 1, 0)
            R.grenadeSq = smokeSquare(x, y, z, -1, 0)
            R.flare2Sq = square(x, y + 3, z) or square(x, y - 3, z)
            setupListener(R)
            return true
        end },
        { name = "sp.apiSmoke", fn = function(R) startApiSmoke(R); return true end },
        { name = "sp.apiSmoke.visual", timeout = 12, fn = function(R)
            local n = markedFires("pzat:smoke", R.smokeSq:getX(), R.smokeSq:getY(), R.smokeSq:getZ(), 1)
            if n < 1 then return false end
            check(R, "smoke.fires", n >= 1, n .. " marked IsoFire (5 expected for radius 1)")
            info(R, "night=" .. tostring(getClimateManager():getDayLightStrength() < 0.45) .. " smoke lamps="
                .. lampsAt(R.smokeSq:getX(), R.smokeSq:getY(), R.smokeSq:getZ()))
            return true
        end },
        { name = "sp.apiStop", fn = function(R) stopApiSmoke(R); return true end },
        { name = "sp.apiStop.visual", timeout = 12, fn = function(R)
            if markedFires("pzat:smoke", R.smokeSq:getX(), R.smokeSq:getY(), R.smokeSq:getZ(), 1) > 0 then
                return false
            end
            check(R, "smoke.cleared", true, "no marked IsoFire left")
            return true
        end },
        { name = "sp.grenade", fn = function(R) explodeGrenade(R, p); return true end },
        { name = "sp.grenade.visual", timeout = 12, fn = function(R)
            if not R.grenadeId then return true end
            local n = markedFires(R.grenadeId, R.grenadeSq:getX(), R.grenadeSq:getY(), R.grenadeSq:getZ(), 1)
            if n < 1 then return false end
            check(R, "grenade.fires", true, n .. " marked IsoFire")
            return true
        end },
        { name = "sp.flare", fn = function(R) lightFlare(R, p); return true end },
        { name = "sp.flare.visual", timeout = 12, fn = function(R)
            if not R.flareId then return true end
            local sq = R.flareSq
            local n = markedFires(R.flareId, sq:getX(), sq:getY(), sq:getZ(), 0)
            local lamps = lampsAt(sq:getX(), sq:getY(), sq:getZ())
            if n < 1 or lamps < 1 then return false end
            check(R, "flare.visual", true, n .. " IsoFire, " .. lamps .. " lamp(s) on the flare square")
            info(R, describeArea("flare square", sq:getX(), sq:getY(), sq:getZ(), 0))
            local wo = worldItemOn(sq, R.flareItemId)
            info(R, "C12 sp flare square objects: " .. objectList(sq) .. " (flare index "
                .. tostring(wo and wo:getObjectIndex()) .. ")")
            return true
        end },
        { name = "sp.flare.pickup", timeout = 90, fn = function(R)
            if not R.flareId then return true end
            if not R.grabQueued then
                local wo = worldItemOn(R.flareSq, R.flareItemId)
                if not wo then return false end
                ISTimedActionQueue.add(ISGrabItemAction:new(p, wo, GRAB_TIME))
                R.grabQueued = true
                return false
            end
            local e = event(R, "stopped", function(ev) return ev.id == R.flareId end)
            if not e then return false end
            check(R, "flare.pickedUp", e.reason == "pickedUp", tostring(e.reason))
            check(R, "flare.inInventory", p:getInventory():containsID(R.flareItemId))
            check(R, "flare.inactive", not SignalSmoke.isActive(R.flareId))
            return true
        end },
        { name = "sp.chemlight", fn = function(R) activateChemlight(R, p); return true end },
        { name = "sp.chemlight.visual", timeout = 12, fn = function(R)
            if lampsAt(R.chemSq:getX(), R.chemSq:getY(), R.chemSq:getZ()) < 1 then return false end
            check(R, "chemlight.lamp", true)
            check(R, "chemlight.noSmoke", markedFires(R.chemId, R.chemSq:getX(), R.chemSq:getY(),
                R.chemSq:getZ(), 0) == 0)
            shortenChemlight(R)
            startFlare2(R)
            return true
        end },
        { name = "sp.expiries", timeout = tonumber(P.expiryTimeout) or 240, fn = function(R)
            if not expiriesSeen(R) then return false end
            checkExpiries(R)
            return true
        end },
        { name = "sp.expiries.visual", timeout = 12, fn = function(R)
            local g = R.grenadeSq
            local fires = (R.grenadeId and markedFires(R.grenadeId, g:getX(), g:getY(), g:getZ(), 1) or 0)
                + markedFires("pzat:flare2", R.flare2Sq:getX(), R.flare2Sq:getY(), R.flare2Sq:getZ(), 0)
            local chemLamps, chemForeign = lampsAt(R.chemSq:getX(), R.chemSq:getY(), R.chemSq:getZ())
            local flare2Lamps, flare2Foreign = lampsAt(R.flare2Sq:getX(), R.flare2Sq:getY(), R.flare2Sq:getZ())
            local lamps = chemLamps + flare2Lamps
            if fires > 0 or lamps > 0 then
                -- Just before the 12 s timeout: say what is left, so that a FAIL can be read.
                if not R.leftoverLogged and nowMs() - (R.stepAt or nowMs()) > 11000 then
                    R.leftoverLogged = true
                    if R.grenadeId then info(R, describeArea("left at grenade", g:getX(), g:getY(), g:getZ(), 1)) end
                    info(R, describeArea("left at chemlight", R.chemSq:getX(), R.chemSq:getY(), R.chemSq:getZ(), 0))
                    info(R, describeArea("left at flare2", R.flare2Sq:getX(), R.flare2Sq:getY(), R.flare2Sq:getZ(), 0))
                end
                return false
            end
            check(R, "expired.cleared", true, "no marked IsoFire, no plain lamp left (vanilla building/switch/tile lights: "
                .. (chemForeign + flare2Foreign) .. ")")
            return true
        end },
        { name = "sp.end", fn = function(R) endListener(R); return true end },
    }
end

-- ------------------------------------------------------------------------------- multiplayer server

local S -- server run

local function serverSend(player, command, args)
    sendServerCommand(player, CMD, command, args or {})
end

local function onClientCommand(module, command, player, args)
    if module ~= CMD or not S then return end
    S.inbox[command] = args or {}
    S.clientPlayer = player
end

local function mpServerSteps()
    local p
    return {
        { name = "mp.server.join", timeout = 180, fn = function(R)
            p = R.clientPlayer or nil
            if not (p and R.inbox.hello and p:getCurrentSquare()) then return false end
            local x, y, z = math.floor(p:getX()), math.floor(p:getY()), math.floor(p:getZ())
            R.smokeSq = smokeSquare(x, y, z, 1, 0)
            R.grenadeSq = smokeSquare(x, y, z, -1, 0)
            R.flare2Sq = square(x, y + 3, z) or square(x, y - 3, z)
            setupListener(R)
            return true
        end },
        { name = "mp.server.place", fn = function(R)
            startApiSmoke(R)
            explodeGrenade(R, p)
            lightFlare(R, p)
            activateChemlight(R, p)
            local f, s, g = R.flareSq, R.smokeSq, R.grenadeSq
            serverSend(p, "plan", { smokeId = R.smokeId, sx = s:getX(), sy = s:getY(), sz = s:getZ(),
                grenadeId = R.grenadeId, gx = g:getX(), gy = g:getY(), gz = g:getZ(),
                flareId = R.flareId, flareItemId = R.flareItemId, fx = f:getX(), fy = f:getY(), fz = f:getZ(),
                flareIndex = R.flareIndex, flareObjects = R.flareObjects, chemId = R.chemId,
                chemItemId = R.chemItemId })
            info(R, "C12 server flare square objects: " .. tostring(R.flareObjects) .. " (flare index "
                .. tostring(R.flareIndex) .. ")")
            return true
        end },
        { name = "mp.server.clientReport", timeout = 150, fn = function(R)
            local report = R.inbox.report
            if not report then return false end
            check(R, "mp.client.reported", report.grabbed == true, "client grab=" .. tostring(report.grabbed))
            info(R, "C12 client flare square objects: " .. tostring(report.objects) .. " (flare index "
                .. tostring(report.index) .. ")")
            return true
        end },
        { name = "mp.server.pickedUp", timeout = 30, fn = function(R)
            local e = event(R, "stopped", function(ev) return ev.id == R.flareId end)
            if not e then return false end
            check(R, "flare.pickedUp", e.reason == "pickedUp", tostring(e.reason))
            check(R, "flare.inServerInventory", p:getInventory():containsID(R.flareItemId))
            check(R, "flare.removedFromSquare", worldItemOn(R.flareSq, R.flareItemId) == nil)
            return true
        end },
        { name = "mp.server.phase2", fn = function(R)
            stopApiSmoke(R)
            shortenChemlight(R)
            startFlare2(R)
            local f = R.flare2Sq
            serverSend(p, "phase2", { f2x = f:getX(), f2y = f:getY(), f2z = f:getZ(), flare2ItemId = R.flare2ItemId })
            return true
        end },
        { name = "mp.server.expiries", timeout = 240, fn = function(R)
            if not expiriesSeen(R) then return false end
            checkExpiries(R)
            serverSend(p, "ended", {})
            return true
        end },
        { name = "mp.server.clientFinal", timeout = 60, fn = function(R)
            local final = R.inbox.final
            if not final then return false end
            check(R, "mp.client.final", final.ok == true, tostring(final.summary))
            return true
        end },
        { name = "mp.server.end", fn = function(R) endListener(R); return true end },
    }
end

-- ------------------------------------------------------------------------------- multiplayer client

local C -- client run

local function onServerCommand(module, command, args)
    if module ~= CMD or not C then return end
    C.inbox[command] = args or {}
end

local function clientSend(command, args)
    sendClientCommand(getPlayer(), CMD, command, args or {})
end

local function mpClientSteps()
    local p
    local plan, phase2
    return {
        { name = "mp.client.refusals", fn = function(R)
            p = getPlayer()
            local id, err = SignalSmoke.start{ x = 1, y = 1 }
            check(R, "mp.client.start.serverOnly", id == nil and err == "server only", tostring(err))
            local ok, err2 = SignalSmoke.stop("pzat:smoke")
            check(R, "mp.client.stop.serverOnly", ok == nil and err2 == "server only", tostring(err2))
            return true
        end },
        { name = "mp.client.plan", timeout = 180, fn = function(R)
            if R.inbox.plan then
                plan = R.inbox.plan
                return true
            end
            if not R.helloAt or nowMs() - R.helloAt > 2000 then
                R.helloAt = nowMs()
                clientSend("hello", {})
            end
            return false
        end },
        { name = "mp.client.registry", timeout = 20, fn = function(R)
            if not (SignalSmoke.isActive(plan.smokeId) and SignalSmoke.isActive(plan.flareId)
                    and SignalSmoke.isActive(plan.grenadeId) and SignalSmoke.isActive(plan.chemId)) then
                return false
            end
            local list = SignalSmoke.list()
            check(R, "mp.client.registry", list[plan.smokeId] ~= nil and list[plan.flareId] ~= nil
                and list[plan.flareId].username == nil, "received copy, no username")
            return true
        end },
        { name = "mp.client.visual", timeout = 15, fn = function(R)
            local smoke = markedFires(plan.smokeId, plan.sx, plan.sy, plan.sz, 1)
            local grenade = markedFires(plan.grenadeId, plan.gx, plan.gy, plan.gz, 1)
            local flare = markedFires(plan.flareId, plan.fx, plan.fy, plan.fz, 0)
            local lamps = lampsAt(plan.fx, plan.fy, plan.fz)
            if smoke < 1 or grenade < 1 or flare < 1 or lamps < 1 then return false end
            check(R, "mp.client.fires", true, "smoke " .. smoke .. ", grenade " .. grenade .. ", flare " .. flare)
            check(R, "mp.client.lamps", true, lamps .. " lamp(s) on the flare square (flare + chemlight)")
            return true
        end },
        { name = "mp.client.c12", fn = function(R)
            local sq = square(plan.fx, plan.fy, plan.fz)
            local wo = worldItemOn(sq, plan.flareItemId)
            R.flareWo = wo
            R.c12Objects = objectList(sq)
            R.c12Index = wo and wo:getObjectIndex() or -1
            check(R, "mp.client.flareOnGround", wo ~= nil)
            info(R, "C12 server flare square objects: " .. tostring(plan.flareObjects) .. " (index "
                .. tostring(plan.flareIndex) .. ")")
            info(R, "C12 client flare square objects: " .. R.c12Objects .. " (index " .. tostring(R.c12Index) .. ")")
            info(R, "C12 flare index " .. (R.c12Index == plan.flareIndex and "identical" or "SHIFTED")
                .. " on the client")
            return true
        end },
        { name = "mp.client.grab", timeout = 90, fn = function(R)
            if not R.flareWo then
                clientSend("report", { grabbed = false, objects = R.c12Objects, index = R.c12Index })
                return true
            end
            if not R.grabQueued then
                ISTimedActionQueue.add(ISGrabItemAction:new(p, R.flareWo, GRAB_TIME))
                R.grabQueued = true
                return false
            end
            if not p:getInventory():containsID(plan.flareItemId) then return false end
            check(R, "mp.client.flareInInventory", true, "flare picked up from the smoke square")
            clientSend("report", { grabbed = true, objects = R.c12Objects, index = R.c12Index })
            return true
        end },
        { name = "mp.client.phase2", timeout = 90, fn = function(R)
            if not R.inbox.phase2 then return false end
            phase2 = R.inbox.phase2
            check(R, "mp.client.flareStopped", not SignalSmoke.isActive(plan.flareId)
                and not SignalSmoke.isActive(plan.smokeId), "flare and API smoke left the registry")
            return true
        end },
        { name = "mp.client.ended", timeout = 300, fn = function(R)
            return R.inbox.ended ~= nil
        end },
        { name = "mp.client.cleared", timeout = 15, fn = function(R)
            local fires = markedFires(plan.smokeId, plan.sx, plan.sy, plan.sz, 1)
                + markedFires(plan.grenadeId, plan.gx, plan.gy, plan.gz, 1)
                + markedFires(plan.flareId, plan.fx, plan.fy, plan.fz, 0)
                + (phase2 and markedFires("pzat:flare2", phase2.f2x, phase2.f2y, phase2.f2z, 0) or 0)
            local lamps = lampsAt(plan.fx, plan.fy, plan.fz)
                + (phase2 and lampsAt(phase2.f2x, phase2.f2y, phase2.f2z) or 0)
            local spent = worldTypeOn(square(plan.fx, plan.fy, plan.fz), SignalSmoke.CHEMLIGHT_USED)
            if fires > 0 or lamps > 0 or not spent then return false end
            check(R, "mp.client.cleared", true, "no marked IsoFire, no lamp, ChemlightUsed received")
            if phase2 then
                check(R, "mp.client.flare2Removed",
                    worldItemOn(square(phase2.f2x, phase2.f2y, phase2.f2z), phase2.flare2ItemId) == nil)
            end
            return true
        end },
        { name = "mp.client.final", fn = function(R)
            local res = finish(R, "client")
            R.final = res
            clientSend("final", { ok = res.ok, summary = res.summary })
            return true
        end },
    }
end

-- ------------------------------------------------------------------------------------------- hooks

local steps

function H.client.start(ctx)
    C = newRun()
    if isClient() then
        steps = mpClientSteps()
        Events.OnServerCommand.Add(onServerCommand)
    else
        steps = spSteps(ctx.params or {})
    end
    return true
end

function H.client.done(ctx)
    return runSteps(C, steps)
end

function H.client.result(ctx)
    if isClient() then
        Events.OnServerCommand.Remove(onServerCommand)
        return C.final or finish(C, "client")
    end
    return finish(C, "sp")
end

local serverSteps

function H.server.start(ctx)
    S = newRun()
    serverSteps = mpServerSteps()
    Events.OnClientCommand.Add(onClientCommand)
    return true
end

function H.server.done(ctx)
    return runSteps(S, serverSteps)
end

function H.server.result(ctx)
    Events.OnClientCommand.Remove(onClientCommand)
    if S.listener then SignalSmoke.removeSignalListener(S.listener) end
    return finish(S, "server")
end

return H
