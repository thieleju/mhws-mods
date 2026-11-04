-- MonsterHuntCounterFork for Monster Hunter Wilds
-- Fork of Monster Hunt Counter v1.0.1: renders the counts natively in the game GUI (no d2d).
-- Quest grid: show verified species hunt totals beside monster icons.
-- Hunt totals are captured once when the quest list opens (or changes category).
local TAG = '[MonsterHuntCounterFork] '
local SETTINGS_PATH = 'MonsterHuntCounterFork.json'
local LEGACY_SETTINGS_PATH = 'Monster_Hunt_Counter.json'
local POLL_FRAMES = 24
local MAX_GUI = 600
local MAX_QUESTS, MAX_ICONS = 200, 300
local SAVED_CATEGORY, HISTORY_CATEGORY = 5, 4

-- Visual preferences are persisted in reframework/data/MonsterHuntCounterFork.json.
local enabled = true
local text_size = 2               -- small / normal / large
local offset_x, offset_y = 0, 0    -- relative to the icon's bottom-right
local font_sizes = { 14, 18, 22 }  -- native GUI font size

-- Reject invalid or untrusted JSON values rather than passing them to drawing APIs.
local function setting_number(value, lo, hi)
    if type(value) == 'number' and value == value and value >= lo and value <= hi then
        return value
    end
    return nil
end
local function load_settings()
    if not json or type(json.load_file) ~= 'function' then return end
    local ok, values = pcall(json.load_file, SETTINGS_PATH)
    if not ok or type(values) ~= 'table' then
        -- First run: take over the settings of the original mod.
        ok, values = pcall(json.load_file, LEGACY_SETTINGS_PATH)
    end
    if not ok or type(values) ~= 'table' then return end
    if type(values.enabled) == 'boolean' then enabled = values.enabled end
    local n = setting_number(values.text_size, 1, 3)
    if n and n == math.floor(n) then text_size = n end
    offset_x = setting_number(values.offset_x, -80, 80) or offset_x
    offset_y = setting_number(values.offset_y, -50, 50) or offset_y
end
load_settings()

local settings_dirty, settings_frames, settings_save_error = false, 0, nil
local frame = 0
local function settings_changed()
    settings_dirty, settings_frames = true, 0
    frame = POLL_FRAMES  -- rescan next frame so font size applies
end
local function save_settings()
    if not json or type(json.dump_file) ~= 'function' then
        return false, 'JSON API unavailable'
    end
    local ok, result = pcall(json.dump_file, SETTINGS_PATH, {
        enabled = enabled, text_size = text_size,
        offset_x = offset_x, offset_y = offset_y,
    })
    if ok and result ~= false then
        settings_dirty, settings_frames, settings_save_error = false, 0, nil
        return true, nil
    end
    return false, tostring(result)
end
local function save_settings_later()
    if not settings_dirty then return end
    settings_frames = settings_frames + 1
    if settings_frames < 90 then return end
    settings_frames = 0
    local ok, err = save_settings()
    if not ok and err ~= settings_save_error then
        settings_save_error = err
        log.error(TAG .. 'SETTINGS_SAVE_ERROR ' .. err)
    end
end

local gui_ref, parts_ref, root_ref = nil, nil, nil
local icons = {}
local nav_root, nav_groups, nav_ready, nav_status = nil, {}, false, 'NOT_SCANNED'
local gui_field_cache = {}
local counts = {}
local count_method = nil
local category_seen, grid_was_open = nil, false
local last_scan_error = nil

local function safe(fn)
    local ok, value = pcall(fn)
    if ok then return value end
    return nil
end
local function get(obj, name, ...)
    if not obj then return nil end
    local args = { ... }
    return safe(function() return obj:call(name, table.unpack(args)) end)
end
local function type_def(obj)
    return obj and safe(function() return obj:get_type_definition() end) or nil
end
local function full_name(td)
    return td and safe(function() return td:get_full_name() end) or nil
end
local function type_name(obj)
    return full_name(type_def(obj))
end
local function field(obj, name)
    if not obj then return nil end
    local result = safe(function() return obj:get_field(name) end)
    if result ~= nil then return result end
    local td = type_def(obj)
    for _ = 1, 7 do
        if not td then break end
        local key = (full_name(td) or '?') .. '/' .. name
        local descriptor = gui_field_cache[key]
        if descriptor == nil then
            descriptor = safe(function() return td:get_field(name) end) or false
            gui_field_cache[key] = descriptor
        end
        if descriptor ~= false then
            result = safe(function() return descriptor:get_data(obj) end)
            if result ~= nil then return result end
        end
        td = safe(function() return td:get_parent_type() end)
    end
    return nil
end
local function num(v)
    if type(v) == 'number' then return v end
    if type(v) == 'string' then return tonumber(v) end
    if v == nil then return nil end
    local n = field(v, 'm_value') or field(v, 'value__')
    if type(n) == 'number' then return n end
    -- Never call System.ValueType.ToString on RE Engine values: it can
    -- trigger a native access violation for non-numeric structs/enums.
    return nil
end
local function integer(v)
    v = num(v)
    if type(v) ~= 'number' or v ~= math.floor(v) then return nil end
    return math.tointeger(v) or math.floor(v)
end
local function count(a)
    if not a then return 0 end
    local n = num(safe(function() return a:get_size() end))
        or num(get(a, 'get_Count')) or num(field(a, '_size'))
    if n and n >= 0 and n <= 1500 then return math.floor(n) end
    return 0
end
local function element(a, i)
    if type(a) == 'table' and type(a.get_element) ~= 'function' then return a[i + 1] end
    return a and (safe(function() return a:get_element(i) end)
        or safe(function() return a:call('get_Item', i) end)) or nil
end
local function name(node)
    local value = get(node, 'get_Name')
    return type(value) == 'string' and value or '?'
end
local function children(node)
    local found, visited = {}, {}
    local child = get(node, 'get_Child')
    for _ = 1, 64 do
        if not child or child == node or visited[child] then break end
        visited[child] = true
        found[#found + 1] = child
        child = get(child, 'get_Next')
    end
    return found
end
local function named(node, wanted)
    if not node then return nil end
    for _, child in ipairs(children(node)) do
        if name(child) == wanted then return child end
    end
    return nil
end
local function visible(node)
    local visited = {}
    for _ = 1, 13 do
        if not node or visited[node] then break end
        visited[node] = true
        if get(node, 'get_Visible') == false then return false end
        node = get(node, 'get_Parent')
    end
    return true
end
local function xy(v)
    if not v then return nil, nil end
    local x = safe(function() return v.x end)
    local y = safe(function() return v.y end)
    if type(x) == 'number' and type(y) == 'number' then return x, y end
    return nil, nil
end

-- Enemy ID is stored as a Mandrake ratio (v/m) in cTargetEm._EmId.
local function target_id(raw)
    local direct = integer(raw)
    if direct then return direct end
    local a, b = field(raw, 'v'), field(raw, 'm')
    if type(a) ~= 'number' or type(b) ~= 'number' or b == 0 then return nil end
    local result = a / b
    if result ~= math.floor(result) or result * b ~= a
        or result < 0 or result > 200 then return nil end
    return integer(result)
end
local function get_keep(view)
    local active = field(view, '<ActiveQuestData>k__BackingField')
    return (active and field(active, '_KeepQuestData')) or get(view, 'get_KeepQuestData')
end
-- Only cKeepQuestData._TargetEmArray is a verified target-to-icon mapping.
-- Searching arbitrary Boss/Target-labelled fields on normal QuestData
-- can misinterpret supplementary quest data as monster targets.
-- Normal quests use their independently validated clear-condition fixed-ID path.
local function decode_id_entry(entry)
    if not entry then return nil end
    local raw = field(entry, '_EmId')
    return raw and target_id(raw) or nil
end
local function target_array(view)
    local keep = get_keep(view)
    if not keep or type_name(keep) ~= 'app.cKeepQuestData' then return nil, 0 end
    local arr = field(keep, '_TargetEmArray')
    local capacity = count(arr)
    local declared = integer(field(keep, '_TargetEmNum'))
    if not arr or not declared or declared < 1 or declared > 6
        or declared > capacity then return nil, 0 end
    if not decode_id_entry(element(arr, 0)) then return nil, 0 end
    return arr, declared
end

-- app.user_data.QuestData.cClearCondition.cTargetInfo._TargetIDValue
-- is an app.EnemyDef.ID_Fixed, NOT an app.EnemyDef.ID (hunt record key).
-- Explicit correspondence verified against MonsterHunterWildsModding/Monster-IDs.
-- Specific species mappings were cross-checked against modding resources. Unknown/new IDs intentionally fail closed.
-- Small monster, endemic life, and event dummy IDs are intentionally omitted.
local FIXED_TO_ENEMY = {
    [26] = 0, [1965232896] = 1, [1411933184] = 2,
    [-535078400] = 3, [402056736] = 4, [1049705664] = 5,
    [-1440201088] = 6, [2129596800] = 7, [-1083842944] = 8,
    [-1363370496] = 9, [-758250816] = 10, [25] = 11,
    [13052] = 12, [32634] = 13, [107194928] = 14,
    [1663995904] = 15, [15] = 16, [-1916429696] = 17,
    [16] = 18, [33] = 19, [-34937520] = 20,
    [-1528962176] = 21, [567628288] = 22,
    [-1547364608] = 23, [1467998976] = 24,
    [1657778432] = 25, [777460864] = 26,
    [746996864] = 27, [-283654400] = 28,
    [222933952] = 29, [1553456768] = 30,
    [1401863296] = 31, [-2003468672] = 32,
    [21849] = 34, -- Omega Planetes; no label unless hunting record exists.
}
-- Confirmed non-large quest targets from free-quest observations.
-- These have no large-monster hunting record. Do not treat them as
-- unsupported large species or query getBossParam for their IDs.
local SMALL_TARGETS = {
    [-643207680] = true,  -- Guardian Seikret
    [580794112] = true,   -- Vespoid/Langosta quest target
    [-37537660] = true,   -- Piragill
    [1097544832] = true,  -- Kranodath
    [827389184] = true,   -- Komotchi
    [71428824] = true,    -- Bulaqchi
    [838] = true,         -- Non-large quest target (exact species unconfirmed)
    [34] = true,          -- Talioth
}
local function fixed_enemy_id(target)
    local fixed = integer(field(target, '_TargetIDValue'))
    return fixed and FIXED_TO_ENEMY[fixed] or nil, fixed
end

-- Exact mission signatures with known target-array order. No other scrambled order is accepted.
local SOURCE_ORDER_PROBES = {
    [20376] = { category=3, quest_type=6, clear_type=2,
        ids={23,24,25,27}, refs={101,103,102,104} },
    [28671] = { category=3, quest_type=0, clear_type=1,
        ids={4,4,7,9,9}, refs={101,104,102,103,105} },
}
local function is_source_order_probe(quest, clear, arr, n, c)
    if c ~= 3 then return false, nil end
    local mission = integer(field(field(quest, '_MissionId'), '_Value'))
    local signature = mission and SOURCE_ORDER_PROBES[mission]
    if not signature or n ~= #signature.ids
        or integer(field(quest, '_QuestType')) ~= signature.quest_type
        or integer(field(clear, '_TargetType')) ~= signature.clear_type then
        return false, nil
    end
    for j = 0, n - 1 do
        local target = element(arr, j)
        local id = fixed_enemy_id(target)
        local ref = integer(field(target, '_EmTargetID'))
        if id ~= signature.ids[j+1] or ref ~= signature.refs[j+1] then
            return false, nil
        end
    end
    return true, mission
end

-- Only grant a normal quest a target-to-icon mapping if every visible icon
-- corresponds to exactly one confirmed large-monster target. _EmTargetID is
-- a quest-local target reference (101/102/etc.), not the enemy species ID.
-- Multiple-target order must match the target entry order; for scrambled
-- order we suppress labels until icon ordering is verified. Single targets
-- are independent of this local reference number.
local function normal_target_array(view, group, c)
    local active = field(view, '<ActiveQuestData>k__BackingField')
    local quest = field(active, '_QuestData')
    if type_name(quest) ~= 'app.user_data.QuestData' then return nil, 0, 'quest' end
    local condition = field(quest, '_ClearCondition')
    local arr = field(condition, '_TargetInfoArray')
    local n = count(arr)
    if n < 1 or n > 6 then return nil, 0, 'entries' end
    local previous, reference_mode = nil, nil
    local order_scrambled = false
    for j = 0, n - 1 do
        local target = element(arr, j)
        local id, fixed = fixed_enemy_id(target)
        -- A small monster may coexist with large monsters in the same
        -- quest. Validate all icon slots, but draw only the large entries.
        if not id and not SMALL_TARGETS[fixed] then
            return nil, 0, 'unknown:' .. tostring(fixed)
        end
        local reference = integer(field(target, '_EmTargetID'))
        -- For a one-target quest the GUI cannot permute the species: only the
        -- known fixed species ID and a single visible icon matter. _EmTargetID
        -- may be zero or nonstandard on certain quest variants.
        if n > 1 then
            -- Some free quests use 0,1,... rather than 101,102,... .
            -- Zero-based refs must match GUI slot ordinals exactly.
            if j == 0 then
                if reference == 0 then
                    reference_mode = 'zero_based'
                elseif reference and reference >= 100 and reference <= 199 then
                    reference_mode = 'hundred_series'
                else
                    return nil, 0, 'target_ref'
                end
            end
            if reference_mode == 'zero_based' then
                if reference ~= j then return nil, 0, 'target_ref' end
            else
                if not reference or reference < 100 or reference > 199 then
                    return nil, 0, 'target_ref'
                end
                if previous and reference <= previous then order_scrambled = true end
            end
            previous = reference
        end
    end
    local visible_count = 0
    for j = 0, 5 do
        local panel = named(group, string.format('PNL_ref_icon%02d', j))
        if panel and get(panel, 'get_Visible') == true and visible(panel) then
            visible_count = visible_count + 1
            -- Do not accept a sparse set of visible icon slots.
            if j >= n then return nil, 0, 'extra_icon' end
        elseif j < n then
            return nil, 0, 'missing_icon'
        end
    end
    if visible_count ~= n then return nil, 0, 'icon_count' end
    if order_scrambled then
        local allowed, mission = is_source_order_probe(quest, condition, arr, n, c)
        if not allowed then return nil, 0, 'order' end
        return arr, n, nil, mission
    end
    return arr, n
end

-- getBossParam(app.EnemyDef.ID, System.Boolean), validated in previous versions.
local function find_count_method()
    if count_method then return count_method end
    local td = safe(function() return sdk.find_type_definition('app.savedata.cEnemyReportParam') end)
    local method = td and safe(function() return td:get_method('getBossParam') end)
    if not method or safe(function() return method:is_static() end) ~= false
        or safe(function() return method:get_num_params() end) ~= 2
        or full_name(safe(function() return method:get_return_type() end))
            ~= 'app.savedata.cBossReportParam' then
        return nil
    end
    local types = safe(function() return method:get_param_types() end)
    local p = {}
    if not types or not pcall(function()
        for index, descriptor in pairs(types) do
            if type(index) == 'number' then p[index] = full_name(descriptor) end
        end
    end) then
        return nil
    end
    local a, b = p[0] ~= nil and p[0] or p[1], p[0] ~= nil and p[1] or p[2]
    if a ~= 'app.EnemyDef.ID' or b ~= 'System.Boolean' then
        return nil
    end
    count_method = method
    return method
end
local function enemy_report()
    local manager = safe(function() return sdk.get_managed_singleton('app.SaveDataManager') end)
    local save = get(manager, 'getCurrentUserSaveData')
        or get(manager, 'getCurrentUserSaveData()')
    return field(save, '_EnemyReport')
end
local function hunt_count(report, method, id)
    id = integer(id)
    if not id or id < 0 or id > 200 then return nil end
    local boss = safe(function() return method:call(report, id, false) end)
    if not boss then return nil end
    local hunted = integer(get(boss, 'getHuntingNum'))
    -- Never replace missing data with a fabricated x0.
    return hunted and hunted >= 0 and hunted or nil
end

-- Locate the GUI component used by both investigation categories.
local function find_gui()
    local manager = safe(function() return sdk.get_managed_singleton('app.GUIManager') end)
    local all = field(manager, '_AllGUI')
    for i = 0, math.min(count(all), MAX_GUI) - 1 do
        local gui = element(all, i)
        if type_name(gui) == 'app.GUI050000' then return gui end
    end
    return nil
end
local function category()
    return integer(field(parts_ref, '<ViewCategory>k__BackingField'))
end
local function supported_category()
    local c = category()
    -- Every category uses this quest grid, but normal and investigation
    -- quests have different, independently validated target-ID formats.
    return c ~= nil and c >= 0 and c <= 15
end
local function grid_active()
    if not gui_ref or not parts_ref or not root_ref then return false end
    if get(gui_ref, 'get_IsActive') == false then return false end
    if field(parts_ref, '<IsActive>k__BackingField') ~= true then return false end
    if integer(field(parts_ref, 'ViewDispType')) ~= 1 then return false end
    return visible(root_ref)
end

-- The category menu and the quest grid share a visible GUI hierarchy.
-- This gate avoids drawing labels on the category screen itself.
local function discover_nav()
    nav_root, nav_groups, nav_ready = root_ref, {}, true
    nav_status = 'NOT_FOUND'
    if not root_ref then return end
    local top = root_ref
    for _ = 1, 16 do
        local parent = get(top, 'get_Parent')
        if not parent or parent == top then break end
        top = parent
    end
    local queue, visited, cursor, menu = { { top, 0 } }, {}, 1, nil
    while cursor <= #queue and cursor <= 2300 do
        local node, depth = queue[cursor][1], queue[cursor][2]
        cursor = cursor + 1
        if node and not visited[node] then
            visited[node] = true
            if name(node) == 'FSL_MenuList00'
                and type_name(node) == 'via.gui.FluentScrollList' then
                menu = node
                break
            end
            if depth < 17 then
                for _, child in ipairs(children(node)) do
                    if not visited[child] then queue[#queue + 1] = { child, depth + 1 } end
                end
            end
        end
    end
    if not menu then return end
    for _, item in ipairs(children(menu)) do
        local index = tonumber(name(item):match('^Item_(%d+)$'))
        if index and index >= 0 and index <= 7 then
            local panel = named(item, 'PNL_category00')
            if panel then
                local texts = {}
                for _, child in ipairs(children(panel)) do
                    if name(child) == 'txt_category' and type_name(child) == 'via.gui.Text' then
                        texts[#texts + 1] = child
                    end
                end
                if #texts > 0 then nav_groups[#nav_groups + 1] = { texts = texts } end
            end
        end
    end
    nav_status = #nav_groups >= 5 and 'READY' or 'INCOMPLETE'
end
local function previous_menu()
    if nav_root ~= root_ref or not nav_ready then discover_nav() end
    -- Fail closed until category-menu detection has been proven.
    if nav_status ~= 'READY' then return true end
    local n = 0
    for _, group in ipairs(nav_groups) do
        for _, node in ipairs(group.texts) do
            if get(node, 'get_Visible') == true and visible(node) then
                n = n + 1
                break
            end
        end
        if n >= 4 then return true end
    end
    return false
end

-- Native labels ------------------------------------------------------------
-- A pool of game Text elements lives in the quest list panel (_RootPanel,
-- PNL_List00_Grid), which is not recycled while scrolling. Each frame the
-- labels are moved to their monster icon. Texts are cloned from the cell's
-- level number: blank instance + copyProperties + duplicate, then the native
-- block at 0x28 is reset so the clone shares nothing with the recycled source.
-- All GUI changes run inside the GUI's own lateUpdate (see the hook below).
local LABEL_PREFIX = 'MonsterHuntCounterFork_label'
local LEVEL_TEXT_PATH = { 'PNL_icon', 'PNL_Level', 'PNL_LevelTag', 'txt_Num' }
local MAX_LABELS = 120
local RIGHT_TOP = 2   -- via.gui.ControlPoint/PageAlignment/LetterAlignment.RightTop
-- addChild puts labels before the scroll grid; a higher priority draws them on top of the cards.
local LABEL_PRIORITY = 500
local labels, label_visible, labels_parent = {}, {}, nil
local label_failed = nil  -- set after a failed creation; no further attempts
local last_update_error = nil
local labels_dirty, rescan_requested = false, false

local function addr(obj)
    return obj and safe(function() return obj:get_address() end) or nil
end
local function child_by_name(parent, child_name)
    return parent and safe(function() return parent:call('getObject(System.String)', child_name) end) or nil
end
local function set_color(node, property, rgba)
    local c = node:call('get_' .. property .. '()')
    sdk.set_native_field(c, sdk.find_type_definition('via.Color'), 'rgba', rgba)
    node:call('set_' .. property .. '(via.Color)', c)
end
local function set_size(node, property, w, h)
    local v = node:call('get_' .. property .. '()')
    v.w, v.h = w, h
    node:call('set_' .. property .. '(via.Size)', v)
end
local function set_position(node, x, y)
    local p = node:call('get_Position()')
    p.x, p.y, p.z = x, y, 0
    node:call('set_Position(via.vec3)', p)
end
local function show_label(i, value)
    if label_visible[i] ~= value and labels[i] then
        labels[i]:call('set_Visible(System.Boolean)', value)
        label_visible[i] = value
    end
end
local function hide_labels()
    for i in pairs(labels) do pcall(show_label, i, false) end
end

local function create_label(parent, source, label_name)
    local template = sdk.create_instance('via.gui.Text')
    if not template then error('create_instance failed') end
    if not parent:call('addChild(via.gui.PlayObject)', template) then error('addChild(template) failed') end
    local blank = template:read_qword(0x28)
    if blank ~= 0 then
        template:call('remove()')
        error('unexpected template block')
    end
    source:call('copyProperties(via.gui.PlayObject)', template)
    template:call('set_Visible(System.Boolean)', false)
    local ok, label = pcall(template.call, template, 'duplicate(System.String)', label_name)
    if not ok or not label then label = child_by_name(parent, label_name) end
    if not label then
        template:write_qword(0x28, blank)
        template:call('remove()')
        error('duplicate produced no named clone')
    end
    if addr(label:call('get_Parent()')) ~= addr(parent) then
        if not parent:call('addChild(via.gui.PlayObject)', label) then error('addChild(label) failed') end
    end
    label:write_qword(0x28, blank)
    template:write_qword(0x28, blank)
    template:call('remove()')
    label:call('set_Visible(System.Boolean)', false)
    label:call('set_ForceInvisible(System.Boolean)', false)
    label:call('set_ControlPoint(via.gui.ControlPoint)', RIGHT_TOP)
    label:call('set_PageAlignment(via.gui.PageAlignment)', RIGHT_TOP)
    label:call('set_LetterAlignment(via.gui.LetterAlignment)', RIGHT_TOP)
    label:call('set_AutoRegionFit(via.gui.RegionFitType)', 0)
    set_size(label, 'RegionSize', 120, 40)
    set_color(label, 'Color', 0xFFFFFFFF)
    set_color(label, 'ShadowColor', 0xFF000000)
    label:call('set_ShadowStrength(System.Single)', 2)
    return label
end

-- Label i of the pool: reuse one from an earlier run (found by name) or create it.
local function ensure_label(i, cell)
    if labels[i] then return labels[i] end
    if label_failed or i > MAX_LABELS then return nil end
    local label_name = LABEL_PREFIX .. i
    local label = child_by_name(root_ref, label_name)
    if not label then
        local source = cell
        for _, part in ipairs(LEVEL_TEXT_PATH) do source = named(source, part) end
        if not source or type_name(source) ~= 'via.gui.Text' then return nil end
        local ok, result = pcall(create_label, root_ref, source, label_name)
        if not ok then
            label_failed = tostring(result)
            log.error(TAG .. 'LABEL_ERROR ' .. label_failed)
            return nil
        end
        label = result
    end
    label:call('set_Priority(System.UInt16)', LABEL_PRIORITY)
    labels[i], label_visible[i] = label, false
    return label
end

-- After each scan: give every validated icon a label and its message.
local function assign_labels()
    if addr(root_ref) ~= labels_parent then
        labels, label_visible, labels_parent = {}, {}, addr(root_ref)
    end
    local font = font_sizes[text_size]
    for i, icon in ipairs(icons) do
        local label = ensure_label(i, icon.cell)
        icon.label = label
        if label then
            label:call('set_Message(System.String)', 'x' .. tostring(icon.hunted))
            set_size(label, 'FontSize', font, font)
        end
    end
end

-- Every frame: move labels onto their icons; hide anything not valid.
-- Returns true when a recycled cell was detected (rescan soon).
local function update_labels()
    local shown, stale = {}, false
    if enabled and #icons > 0 and grid_active() and supported_category() and not previous_menu() then
        local px, py = xy(get(root_ref, 'get_GlobalPosition'))
        local views = field(parts_ref, '<ViewQuestDataList>k__BackingField')
        local font = font_sizes[text_size]
        for i, icon in ipairs(icons) do
            local label = icon.label
            if label and px then
                if integer(get(icon.cell, 'get_ListIndex')) ~= icon.listIndex
                    or addr(element(views, icon.listIndex)) ~= icon.view_addr then
                    stale = true
                elseif get(icon.cell, 'get_Visible') ~= false
                    and get(icon.panel, 'get_Visible') ~= false
                    and get(icon.mat, 'get_Visible') ~= false then
                    -- Only inside the visible quest list area (1920x1080 GUI space).
                    local gx, gy = xy(get(icon.mat, 'get_GlobalPosition'))
                    local width = (#tostring(icon.hunted) + 1) * font * 0.6
                    local right, top = gx and gx + 18 + offset_x, gy and gy + 15 + offset_y
                    if right and right - width >= 128 and right <= 1169 and top >= 164 and top + font <= 940 then
                        set_position(label, gx - px + 18 + offset_x, gy - py + 15 + offset_y)
                        shown[i] = true
                    end
                end
            end
        end
    end
    for i in pairs(labels) do show_label(i, shown[i] == true) end
    return stale
end

local function clear_ui()
    gui_ref, parts_ref, root_ref = nil, nil, nil
    icons, counts = {}, {}
    nav_root, nav_groups, nav_ready, nav_status = nil, {}, false, 'NOT_SCANNED'
    category_seen = nil
    grid_was_open = false
    -- The GUI is gone; its labels went with it.
    labels, label_visible, labels_parent = {}, {}, nil
end

-- Capture a single hunting-stat snapshot when the quest list becomes visible.
-- Collect species IDs from all quest entries (not only onscreen icons), so
-- scrolling and sorting do not read fresh counts at a different time.
-- The draw path still independently validates target-to-icon correspondence.
local function snapshot_counts(views, total, is_investigation)
    local report = enemy_report()
    local method = report and find_count_method() or nil
    if not report or not method then return false end

    local species = {}
    for i = 0, math.min(total, MAX_QUESTS) - 1 do
        local view = element(views, i)
        local arr, n
        if is_investigation then
            arr, n = target_array(view)
        else
            local active = field(view, '<ActiveQuestData>k__BackingField')
            local quest = field(active, '_QuestData')
            if type_name(quest) == 'app.user_data.QuestData' then
                arr = field(field(quest, '_ClearCondition'), '_TargetInfoArray')
                n = count(arr)
            end
        end
        if arr and n and n >= 1 and n <= 6 then
            for j = 0, n - 1 do
                local entry = element(arr, j)
                local id
                if is_investigation then
                    id = decode_id_entry(entry)
                else
                    id = fixed_enemy_id(entry)
                end
                if id and id >= 0 and id <= 200 then species[id] = true end
            end
        end
    end

    local fresh = {}
    for id in pairs(species) do
        local value = hunt_count(report, method, id)
        if value ~= nil then fresh[id] = value end
    end
    counts = fresh
    return true
end

-- Scan only actual visible monster icon GUI nodes, never guess card positions.
local function scan_icons()
    local gui = find_gui()
    if not gui then clear_ui(); return end
    local parts = field(gui, '_QuestListParts')
    local root = field(field(parts, '_GridViweParts'), '_RootPanel')
    if gui ~= gui_ref or root ~= root_ref then nav_ready = false end
    gui_ref, parts_ref, root_ref = gui, parts, root
    if not grid_active() then
        icons, counts = {}, {}
        grid_was_open, category_seen = false, nil
        return
    end
    if nav_status ~= 'READY' then nav_ready = false end
    if previous_menu() then
        icons, counts = {}, {}
        grid_was_open = false
        return
    end
    local c = category()
    local views = field(parts, '<ViewQuestDataList>k__BackingField')
        or get(parts, 'get_ViewQuestDataList')
    local total = count(views)
    if total < 1 or total > MAX_QUESTS or not supported_category() then
        icons = {}
        return
    end
    local is_investigation = c == SAVED_CATEGORY or c == HISTORY_CATEGORY
    if not grid_was_open or c ~= category_seen then
        icons, counts = {}, {}
        if not snapshot_counts(views, total, is_investigation) then return end
        grid_was_open, category_seen = true, c
    end

    local queue, visited, raw, cursor = { { root, 0 } }, {}, {}, 1
    while cursor <= #queue and cursor <= 2200 do
        local node, depth = queue[cursor][1], queue[cursor][2]
        cursor = cursor + 1
        if node and not visited[node] then
            visited[node] = true
            if type_name(node) == 'via.gui.SelectItem'
                and name(node):match('^Item_%d+_%d+$') then
                local ix = integer(get(node, 'get_ListIndex'))
                local group = named(named(node, 'PNL_icon'), 'PNL_icon_monster')
                if ix and ix >= 0 and ix < total and group and visible(node) then
                    local array, slots, _, source_mission
                    if is_investigation then
                        array, slots = target_array(element(views, ix))
                    else
                        array, slots, _, source_mission = normal_target_array(element(views, ix), group, c)
                    end
                    for ordinal = 0, math.min(slots, 6) - 1 do
                        local panel = named(group, string.format('PNL_ref_icon%02d', ordinal))
                        if panel and get(panel, 'get_Visible') == true and visible(panel) then
                            local mat = named(named(named(panel, 'PNL_ref_icon00'), 'PNL_icon'), 'mat_icon')
                            local x, y = xy(get(mat, 'get_GlobalPosition'))
                            local record = element(array, ordinal)
                            local id, fixed = nil, nil
                            if is_investigation then
                                id = decode_id_entry(record)
                            else
                                id, fixed = fixed_enemy_id(record)
                            end
                            if x and y and x > -10000 and y > -10000 and x < 15000 and y < 15000
                                and id and id >= 0 and id <= 200 then
                                local hunted = counts[id]
                                if hunted ~= nil then
                                    raw[#raw + 1] = {
                                        listIndex = ix, ordinal = ordinal, id = id,
                                        hunted = hunted, mat = mat, panel = panel, cell = node,
                                        array = array, is_normal = not is_investigation,
                                        fixed = fixed,
                                        source_mission = source_mission,
                                        view_addr = addr(element(views, ix)),
                                    }
                                end
                            end
                        end
                    end
                end
            end
            if depth < 9 then
                for _, child in ipairs(children(node)) do
                    queue[#queue + 1] = { child, depth + 1 }
                end
            end
        end
    end
    table.sort(raw, function(a,b)
        if a.listIndex ~= b.listIndex then return a.listIndex < b.listIndex end
        return a.ordinal < b.ordinal
    end)
    icons = {}
    for i = 1, math.min(#raw, MAX_ICONS) do icons[i] = raw[i] end
    labels_dirty = true
end


re.on_frame(function()
    save_settings_later()
    frame=frame+1
    if rescan_requested then
        -- Recycled cell: rescan soon, but not every frame while scrolling.
        rescan_requested=false
        frame=math.max(frame,POLL_FRAMES-4)
    end
    if frame<POLL_FRAMES then return end
    frame=0
    local ok,err=pcall(scan_icons)
    if not ok then
        icons={}
        if tostring(err)~=last_scan_error then
            last_scan_error=tostring(err)
            log.error(TAG..'SCAN_ERROR '..last_scan_error)
        end
    else
        last_scan_error=nil
    end
end)

if re.on_draw_ui and imgui then
    re.on_draw_ui(function()
        if not imgui.tree_node('MonsterHuntCounterFork') then return end
        if imgui.button(enabled and 'Quest icon counts: ON' or 'Quest icon counts: OFF') then
            enabled=not enabled; settings_changed()
        end
        if imgui.button('Font size: '..({'Small','Normal','Large'})[text_size]) then
            text_size=text_size%3+1; settings_changed()
        end
        if label_failed then imgui.text('Label error: '..label_failed:sub(1,200)) end
        if type(imgui.slider_float)=='function' then
            local ok,changed,v=pcall(imgui.slider_float,'Label X offset',offset_x,-80,80)
            if ok and changed==true and setting_number(v,-80,80) then
                offset_x=v; settings_changed()
            end
            ok,changed,v=pcall(imgui.slider_float,'Label Y offset',offset_y,-50,50)
            if ok and changed==true and setting_number(v,-50,50) then
                offset_y=v; settings_changed()
            end
        end
        imgui.tree_pop()
    end)
end

-- All GUI changes happen inside app.GUI050000's own lateUpdate (post-hook):
-- editing the GUI tree from re.on_frame crashes the game.
local function gui_work()
    if labels_dirty then
        labels_dirty = false
        assign_labels()
    end
    if update_labels() then rescan_requested = true end
end
-- app.GUI050000 inherits lateUpdate() from ace.GUIBase`2; the hook is shared by
-- all GUIs, so only calls on the quest counter GUI do any work.
local function install_gui_hook()
    local td, method = sdk.find_type_definition('app.GUI050000'), nil
    while td and not method do
        for _, m in ipairs(td:get_methods()) do
            if m:get_name() == 'lateUpdate' and m:get_num_params() == 0 then method = m; break end
        end
        td = td:get_parent_type()
    end
    if not method then error('lateUpdate() not found') end
    sdk.hook(method, function(args)
        local obj = sdk.to_managed_object(args[2])
        if obj and obj:get_type_definition():get_full_name() == 'app.GUI050000' then
            thread.get_hook_storage().mhc_gui = true
        end
    end, function(retval)
        local storage = thread.get_hook_storage()
        if not storage.mhc_gui then return retval end
        storage.mhc_gui = nil
        local ok, err = pcall(gui_work)
        if not ok and tostring(err) ~= last_update_error then
            last_update_error = tostring(err)
            log.error(TAG .. 'UPDATE_ERROR ' .. last_update_error)
        end
        return retval
    end)
end
local hooked, hook_err = pcall(install_gui_hook)
if not hooked then log.error(TAG .. 'GUI_HOOK_ERROR ' .. tostring(hook_err)) end

re.on_script_reset(function() hide_labels() end)

log.info(TAG .. 'Loaded: quest list only; hunt totals refresh on list open.')
