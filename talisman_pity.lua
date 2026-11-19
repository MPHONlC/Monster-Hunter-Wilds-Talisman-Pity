local CONF = "talisman_pity.json"
local DATA = json.load_file(CONF) or {}
if type(DATA.sett) ~= "table" then DATA.sett = {} end
if type(DATA.history) ~= "table" then DATA.history = {} end
if type(DATA.pool) ~= "table" then DATA.pool = {} end
local S = DATA.sett

local function default(key, value)
    if S[key] == nil then S[key] = value end
end
default("enabled", true)
default("threshold", 2)
default("window_hours", 24)
default("arm_seconds", 600)
default("watch_always", false)
default("min_skills", 2)

local TALISMAN_CATEGORY = 2
local SKILL_COUNT = 3
local HISTORY_LIMIT = 1000
local HISTORY_MAX_AGE = 14 * 24 * 3600
local POLL_ARMED = 0.5
local POLL_IDLE = 5

math.randomseed(os.time())

local config_dirty = false
local config_save_at = 0
local function markDirty()
    config_dirty = true
    config_save_at = os.clock() + 0.6
end

local skill_methods = nil
local function skillName(id)
    if skill_methods == nil then
        skill_methods = false
        local mu = sdk.find_type_definition("app.MessageUtil")
        local gm = sdk.find_type_definition("via.gui.message")
        if mu and gm then
            skill_methods = {
                name = mu:get_method("getHunterSkillName(app.HunterDef.Skill)"),
                get  = gm:get_method("get(System.Guid, via.Language)"),
            }
        end
    end
    if skill_methods and skill_methods.name and skill_methods.get then
        local ok, res = pcall(function()
            local guid = skill_methods.name:call(nil, id)
            if not guid then return nil end
            local text = skill_methods.get:call(nil, guid, 1)
            return text and tostring(text) or nil
        end)
        if ok and res and res ~= "" then return res end
    end
    return "Skill " .. tostring(id)
end

local function slotText(value)
    local d1 = math.floor(value / 1000) % 10
    local d2 = math.floor(value / 100) % 10
    local d3 = math.floor(value / 10) % 10
    local flag = value % 10
    if flag == 1 then return string.format("Weapon %d + Armor %d-%d", d1, d2, d3) end
    if flag == 3 then return string.format("Weapon %d", d1) end
    return string.format("Armor %d-%d-%d", d1, d2, d3)
end

local function describe(t)
    local parts = {}
    for _, raw in ipairs(t.skills) do
        parts[#parts + 1] = string.format("%s Lv%d", skillName(raw % 1000), math.floor(raw / 1000))
    end
    return string.format("%s | %s", table.concat(parts, ", "), slotText(t.slots))
end

local function makeTalisman(raws, slots)
    local skills = {}
    for _, raw in ipairs(raws) do
        if raw and raw ~= 0 then skills[#skills + 1] = raw end
    end
    table.sort(skills, function(a, b) return a > b end)
    return { skills = skills, slots = slots or 0 }
end

local function signature(t)
    return table.concat(t.skills, ",") .. "|" .. tostring(t.slots)
end

local function readWork(work)
    if not work then return nil end
    if work:get_Category() ~= TALISMAN_CATEGORY then return nil end
    local list = work.BowgunCustomizeId
    if not list then return nil end
    local raws = { list:get_Item(0), list:get_Item(1), list:get_Item(2) }
    local t = makeTalisman(raws, list:get_Item(3))
    t.list = list
    t.rawkey = string.format("%d:%d:%d:%d", raws[1] or 0, raws[2] or 0, raws[3] or 0, t.slots)
    return t
end

local function setValue(list, index, value)
    local ok = pcall(function() list:set_Item(index, value) end)
    if not ok then
        ok = pcall(function() list[index] = value end)
    end
    return ok
end

local function getBox()
    local sd = sdk.get_managed_singleton("app.SaveDataManager")
    if not sd then return nil end
    local ok, box = pcall(function()
        local ud = sd:getCurrentUserSaveData()
        return ud and ud._Equip and ud._Equip._EquipBox or nil
    end)
    if ok then return box end
    return nil
end

local function scanBox(box)
    local result = {}
    local count = box:get_Count()
    for i = 0, count - 1 do
        local t = readWork(box:get_Item(i))
        if t then result[i] = t end
    end
    return result
end

local function windowStart()
    local hours = tonumber(S.window_hours) or 24
    if hours <= 0 then
        local d = os.date("*t")
        d.hour, d.min, d.sec = 0, 0, 0
        return os.time(d)
    end
    return os.time() - hours * 3600
end

local function countInWindow(sig)
    local since = windowStart()
    local n = 0
    for _, h in ipairs(DATA.history) do
        if h.sig == sig and h.t >= since then n = n + 1 end
    end
    return n
end

local function recordHistory(t, swapped)
    DATA.history[#DATA.history + 1] = {
        sig = signature(t), t = os.time(), swapped = swapped or false,
        skills = t.skills, slots = t.slots,
    }
    local cutoff = os.time() - HISTORY_MAX_AGE
    local kept = {}
    for _, h in ipairs(DATA.history) do
        if h.t >= cutoff then kept[#kept + 1] = h end
    end
    while #kept > HISTORY_LIMIT do table.remove(kept, 1) end
    DATA.history = kept
    markDirty()
end

local function candidatePool(box_talismans)
    local pool, seen = {}, {}
    local function add(t)
        local sig = signature(t)
        if not seen[sig] and #t.skills >= (tonumber(S.min_skills) or 2) then
            seen[sig] = true
            pool[#pool + 1] = t
        end
    end
    for _, t in pairs(box_talismans) do add(t) end
    for _, c in ipairs(DATA.pool) do
        if type(c) == "table" and type(c.raw) == "table" then
            add(makeTalisman(c.raw, tonumber(c.slots) or 0))
        end
    end
    return pool
end

local function pickReplacement(box_talismans, current_sig)
    local pool = candidatePool(box_talismans)
    local unseen, fewest, fewest_n = {}, nil, math.huge
    for _, t in ipairs(pool) do
        local sig = signature(t)
        if sig ~= current_sig then
            local n = countInWindow(sig)
            if n == 0 then
                unseen[#unseen + 1] = t
            elseif n < fewest_n then
                fewest, fewest_n = t, n
            end
        end
    end
    if #unseen > 0 then return unseen[math.random(#unseen)], "unseen" end
    if fewest then return fewest, "least seen" end
    return nil, nil
end

local swap_log = {}
local function logSwap(msg)
    table.insert(swap_log, 1, os.date("%H:%M:%S") .. "  " .. msg)
    while #swap_log > 30 do table.remove(swap_log) end
    log.info("[TalismanPity] " .. msg)
end

local function handleNew(idx, t, box_talismans)
    local sig = signature(t)
    local seen = countInWindow(sig)
    local threshold = math.max(1, tonumber(S.threshold) or 2)

    if S.enabled and seen >= threshold then
        local replacement, how = pickReplacement(box_talismans, sig)
        if replacement then
            local ok = true
            for i = 0, SKILL_COUNT - 1 do
                ok = setValue(t.list, i, replacement.skills[i + 1] or 0) and ok
            end
            ok = setValue(t.list, 3, replacement.slots) and ok

            local check = {}
            for i = 0, SKILL_COUNT - 1 do check[#check + 1] = t.list:get_Item(i) end
            local now = makeTalisman(check, t.list:get_Item(3))
            if ok and signature(now) == signature(replacement) then
                logSwap(string.format("#%d seen %dx in window: %s  ->  %s (%s)",
                    idx, seen, describe(t), describe(replacement), how))
                now.list = t.list
                now.rawkey = string.format("%d:%d:%d:%d", check[1] or 0, check[2] or 0, check[3] or 0, now.slots)
                recordHistory(now, true)
                return now
            end
            logSwap(string.format("#%d swap FAILED, write did not stick (%s)", idx, describe(t)))
        else
            logSwap(string.format("#%d seen %dx but no replacement available (%s)", idx, seen, describe(t)))
        end
    end

    recordHistory(t, false)
    return t
end

local baseline = nil
local armed_until = 0
local armed = false
local next_poll = 0
local last_box_id = nil
local last_scan_count = 0

local function boxId(box)
    local ok, addr = pcall(function() return box:get_address() end)
    if ok and addr then return addr end
    return tostring(box)
end

local function poll(box)
    local current = scanBox(box)
    last_scan_count = 0
    local new_idx = {}
    for idx, t in pairs(current) do
        if baseline == nil or baseline[idx] == nil then
            if #t.skills >= (tonumber(S.min_skills) or 2) then new_idx[#new_idx + 1] = idx end
        end
    end
    table.sort(new_idx)
    for _, idx in ipairs(new_idx) do
        current[idx] = handleNew(idx, current[idx], current)
        last_scan_count = last_scan_count + 1
    end
    baseline = current
end

local function arm()
    if not S.enabled then return end
    armed = true
    armed_until = os.clock() + (tonumber(S.arm_seconds) or 600)
    next_poll = 0
end

local hooked = false
local qm = sdk.find_type_definition("app.MissionMusicManager.QuestMusicManager")
local clear_method = qm and qm:get_method("onQuestClear")
if clear_method then
    sdk.hook(clear_method, function(args) end, function(retval)
        arm()
        return retval
    end)
    hooked = true
end

re.on_frame(function()
    local now = os.clock()
    if config_dirty and now >= config_save_at then
        config_dirty = false
        json.dump_file(CONF, DATA)
    end
    if not S.enabled then return end

    local box = getBox()
    if not box then
        baseline = nil
        return
    end
    local id = boxId(box)
    if id ~= last_box_id then
        last_box_id = id
        baseline = nil
        armed = false
    end

    local watching = S.watch_always or armed
    if watching then
        if now >= next_poll then
            next_poll = now + POLL_ARMED
            local ok, err = pcall(poll, box)
            if not ok then log.error("[TalismanPity] poll failed: " .. tostring(err)) end
        end
        if armed and not S.watch_always and now > armed_until then armed = false end
    elseif now >= next_poll then
        next_poll = now + POLL_IDLE
        local ok, res = pcall(scanBox, box)
        if ok then baseline = res end
    end
end)

re.on_draw_ui(function()
    if not imgui.tree_node("Talisman Pity") then return end
    local changed

    changed, S.enabled = imgui.checkbox("Enable", S.enabled)
    if changed then markDirty() end

    changed, S.threshold = imgui.slider_int("Swap after this many repeats", S.threshold, 1, 10)
    if changed then markDirty() end

    changed, S.window_hours = imgui.slider_int("Window in hours (0 = today)", S.window_hours, 0, 168)
    if changed then markDirty() end

    changed, S.arm_seconds = imgui.slider_int("Watch seconds after quest clear", S.arm_seconds, 30, 1800)
    if changed then markDirty() end

    changed, S.min_skills = imgui.slider_int("Minimum skills to count", S.min_skills, 1, 3)
    if changed then markDirty() end

    changed, S.watch_always = imgui.checkbox("Watch all the time (also catches melding results)", S.watch_always)
    if changed then markDirty() end

    imgui.text(hooked and "Quest clear hook: active" or "Quest clear hook: NOT found, enable 'Watch all the time'")
    imgui.text(armed and "Status: watching for quest rewards" or "Status: idle")

    local window_total = 0
    local since = windowStart()
    for _, h in ipairs(DATA.history) do
        if h.t >= since then window_total = window_total + 1 end
    end
    imgui.text(string.format("Received in window: %d   Logged total: %d   Custom pool: %d",
        window_total, #DATA.history, #DATA.pool))

    if imgui.button("Clear history") then
        DATA.history = {}
        markDirty()
    end

    if imgui.tree_node("Recent swaps (this session)") then
        if #swap_log == 0 then imgui.text("None yet") end
        for _, line in ipairs(swap_log) do imgui.text(line) end
        imgui.tree_pop()
    end

    imgui.tree_pop()
end)
