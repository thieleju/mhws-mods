--
-- Split Damage Numbers
--
-- Colors damage numbers by what caused them and shows the physical and
-- element part of a hit as two separate numbers:
--   hard          physical hit on a hitzone below the physical limit (default 45)
--   soft          physical hit on a hitzone at or above that limit
--   element_hard  element damage on an element hitzone below the element limit (default 20)
--   element_soft  element damage at or above that limit (or ignoring hitzones)
--   fixed         hitzone-independent damage (hunting horn, gunlance shells, ...)
--   proc          numbers without a hit of our own: status/skill procs (blast, White Flame Torrent, ...)
--
---@diagnostic disable: undefined-global

local CONFIG_FILE = "split_damage_numbers.json"

local DEFAULT_HARD_HITZONE = 45
local DEFAULT_HARD_ELEMENT_HITZONE = 20
local DEFAULT_FONT_SIZE = 27
-- A group of numbers is shown once no new number joined it for GroupGap seconds, but at the latest
-- GroupMaxTime seconds after its first number
local DEFAULT_GROUP_GAP = 0.15
local DEFAULT_GROUP_MAX_TIME = 0.5
local FONT_SLOT = 0
local FONT_LANGUAGE = 1
local HIT_TTL = 2.0 -- seconds a queued hit or element part waits for its number
-- Smaller element parts are not split off but counted as physical: some attacks (shelling,
-- spread pellets with Burst, ...) carry a tiny bit of element that would only show as a "0".
local MIN_SPLIT_ELEMENT = 1.0

local REQUEST_DAMAGE_SIG =
"requestDamage(via.vec3, System.Single, app.GUI020020.State, app.TARGET_ACCESS_KEY.CATEGORY, app.GUI020020.DAMAGE_TYPE, app.GUI020020.CRITICAL_STATE, System.Boolean, System.Boolean, System.Action`1<app.GUI020020.DAMAGE_INFO>)"
local REQUEST_DAMAGE_GUI_SIG =
"requestDamageGUI(via.vec3, System.Single, app.GUI020020.State, System.Boolean, System.Nullable`1<app.TARGET_ACCESS_KEY>, System.Boolean, System.Boolean, app.GUI020020.CRITICAL_STATE, app.GUI020020.DAMAGE_TYPE, app.HitDef.COLLAB_DAMAGE_UI_TYPE)"
local CALC_STOCK_DAMAGE_SIG =
"calcStockDamage(app.cEnemyStockDamage.cCalcDamage, app.cEnemyStockDamage.cPreCalcDamage, app.cEnemyStockDamage.cDamageRate, System.Boolean)"

-------------------------------------------------------------------------------
-- Colors and config
-------------------------------------------------------------------------------

local KINDS = { "hard", "soft", "element_hard", "element_soft", "fixed", "proc" }
local KIND_LABELS = {
    hard = "Physical hard",
    soft = "Physical soft",
    element_hard = "Element hard",
    element_soft = "Element soft",
    fixed = "Fixed",
    proc = "Procs",
}
local KIND_HINTS = {
    hard = "physical damage on tough parts",
    soft = "physical damage on weak spots",
    element_hard = "element damage on tough parts",
    element_soft = "element damage on weak parts",
    fixed = "damage that ignores hitzones, e.g. gunlance shells, hunting horn bubble procs, ...",
    proc = "extra hits from skills and status procs, e.g. white flame torrent, scorcher, blast procs, ...",
}
local PHYSICAL_KINDS = { hard = true, soft = true, fixed = true }

local DEFAULT_COLORS = {
    hard = { Fill = 0xFF22699F, Glow = 0xE606151F },
    soft = { Fill = 0xFF63C6FF, Glow = 0xFF0A2B36 }, -- the game's own style for soft hits
    element_hard = { Fill = 0xFF1B1BB2, Glow = 0xE6050523 },
    element_soft = { Fill = 0xFF6E6EFD, Glow = 0xE6161632 },
    fixed = { Fill = 0xFFFBA7C5, Glow = 0xE6322127 },
    proc = { Fill = 0xFFFFBE6E, Glow = 0xE6321A0A },
}

-- Shared by all kinds, taken from the game's own styles
local TEXT_GLOW = 0xFFC0C0C0
local TEXT_SHADOW = 0x66000000
local DESIGN_SHADOW = 0xFF404040

-- A dark tint of the text color, like the glows of the game's own number styles
local function DeriveGlow(fill)
    local r, g, b = fill & 0xFF, (fill >> 8) & 0xFF, (fill >> 16) & 0xFF
    return 0xE6000000 | (math.floor(b * 0.2) << 16) | (math.floor(g * 0.2) << 8) | math.floor(r * 0.2)
end

local Config = {
    Enabled = true,
    Decimal = false,
    FontSize = DEFAULT_FONT_SIZE,
    -- hitzone values below these count as hard
    HardHitzone = DEFAULT_HARD_HITZONE,
    HardElementHitzone = DEFAULT_HARD_ELEMENT_HITZONE,
    Colors = {},
    Show = {},  -- kind -> false hides that kind's numbers
    Group = {}, -- kind -> true adds up that kind's numbers landing at once into one
    GroupGap = DEFAULT_GROUP_GAP,
    GroupMaxTime = DEFAULT_GROUP_MAX_TIME,
    GroupEnabled = false,
}

local function LoadConfig()
    local saved = json.load_file(CONFIG_FILE)
    if type(saved) ~= "table" then saved = {} end
    for _, key in ipairs({ "Enabled", "Decimal", "FontSize", "HardHitzone", "HardElementHitzone", "GroupGap", "GroupMaxTime", "GroupEnabled" }) do
        if type(saved[key]) == type(Config[key]) then
            Config[key] = saved[key]
        end
    end
    local colors = type(saved.Colors) == "table" and saved.Colors or {}
    local show = type(saved.Show) == "table" and saved.Show or {}
    local group = type(saved.Group) == "table" and saved.Group or {}
    for _, kind in ipairs(KINDS) do
        local c = colors[kind]
        if type(c) ~= "table" or type(c.Fill) ~= "number" or type(c.Glow) ~= "number" then
            c = { Fill = DEFAULT_COLORS[kind].Fill, Glow = DEFAULT_COLORS[kind].Glow }
        end
        Config.Colors[kind] = c
        Config.Show[kind] = show[kind] ~= false
        Config.Group[kind] = group[kind] == true
    end
end

-- Dragging a slider or picker changes the config every frame; it is written once the changes stop
local SAVE_DELAY = 0.5
local SaveDue = nil

local function RequestSave()
    SaveDue = os.clock() + SAVE_DELAY
end

local function FlushSave()
    if SaveDue then
        SaveDue = nil
        json.dump_file(CONFIG_FILE, Config)
    end
end

re.on_frame(function()
    if SaveDue and os.clock() >= SaveDue then FlushSave() end
end)
re.on_script_reset(FlushSave)

local ColorType = sdk.find_type_definition("via.Color")

local function NewColor(rgba)
    local color = ValueType.new(ColorType)
    sdk.set_native_field(color, ColorType, "rgba", rgba)
    return color
end

-- via.Color objects per kind, rebuilt whenever a color changes
local Styles = {}

local function BuildStyles()
    local textGlow, textShadow, designShadow = NewColor(TEXT_GLOW), NewColor(TEXT_SHADOW), NewColor(DESIGN_SHADOW)
    for _, kind in ipairs(KINDS) do
        local c = Config.Colors[kind]
        Styles[kind] = {
            fillRgba = c.Fill,
            fill = NewColor(c.Fill),
            glow = NewColor(c.Glow),
            textGlow = textGlow,
            textShadow = textShadow,
            designShadow = designShadow,
        }
    end
end

LoadConfig()
BuildStyles()

-------------------------------------------------------------------------------
-- Kind codes
-------------------------------------------------------------------------------

-- Game damage values are multiples of 0.1. The kind of an own hit is encoded by multiplying the
-- value with a tiny per-kind factor (1 + code * step), which also survives the game adding up
-- values. Decoding finds the factor that turns the value back into a multiple of 0.1; values that
-- already are one have no code and are procs. The shown text is set from that rounded value, so
-- the factor never shows. Exact for values up to about 9500.
local CODE_STEP = 2e-6
local KIND_CODES = { hard = 1, soft = 2, element_hard = 3, element_soft = 4, fixed = 5 }
local CODE_KINDS = {}
for kind, code in pairs(KIND_CODES) do
    CODE_KINDS[code] = kind
end

local function BaseValue(value)
    return math.floor(value * 10 + 0.5) / 10
end

local function EncodeKind(value, kind)
    return BaseValue(value) * (1 + KIND_CODES[kind] * CODE_STEP)
end

-- Returns the kind and the value to show
local function DecodeKind(value)
    local kind, shown, bestScore = "proc", BaseValue(value), nil
    for code = 0, 5 do
        local candidate = value / (1 + code * CODE_STEP)
        local base = BaseValue(candidate)
        -- a bit less than half the distance to the neighbouring code's value
        local tolerance = math.max(candidate * CODE_STEP * 0.4, 1e-7)
        local score = math.abs(candidate - base) / tolerance
        if score <= 1 and (bestScore == nil or score < bestScore) then
            kind, shown, bestScore = CODE_KINDS[code] or "proc", base, score
        end
    end
    return kind, shown
end

-------------------------------------------------------------------------------
-- Hits
-------------------------------------------------------------------------------

local function PhysicalKind(hit)
    if hit.ignoreMeat then return "fixed" end
    if hit.meat < Config.HardHitzone then return "hard" end
    return "soft"
end

local function ElementKind(hit)
    -- Element that ignores hitzones (no element hitzone value) counts as soft
    if hit.meatElem < Config.HardElementHitzone and not (hit.ignoreMeat and hit.meatElem <= 0) then
        return "element_hard"
    end
    return "element_soft"
end

local function HitKind(hit)
    if hit.elemental > 0 and hit.physical <= 0 then return ElementKind(hit) end
    return PhysicalKind(hit)
end

-- Own hits waiting for their number: value key -> FIFO list of { time, hit }
local HitQueue = {}
-- Element parts of split hits, waiting for their physical number
local PendingElement = {}
-- Element parts released by a physical number, requested on the next GUI update
local ElementOutbox = {}
-- Grouped numbers being collected: kind -> one request adding them all up; GroupOrder keeps the order
local Groups, GroupOrder = {}, {}
local FlushingGroups = false
local LastCleanup = 0

local function Key(value)
    return string.format("%0.2f", value)
end

local function TakeHit(key)
    local list = HitQueue[key]
    if not list then return nil end
    local now = os.clock()
    while #list > 0 and now - list[1].time > HIT_TTL do
        table.remove(list, 1)
    end
    local entry = table.remove(list, 1)
    if #list == 0 then
        HitQueue[key] = nil
    end
    return entry and entry.hit
end

-- Drops hits and element parts whose number never came (e.g. the game skipped it)
local function Cleanup()
    local now = os.clock()
    if now - LastCleanup < 1.0 then return end
    LastCleanup = now
    for key, list in pairs(HitQueue) do
        while #list > 0 and now - list[1].time > HIT_TTL do
            table.remove(list, 1)
        end
        if #list == 0 then
            HitQueue[key] = nil
        end
    end
    while #PendingElement > 0 and now - PendingElement[1].time > HIT_TTL do
        table.remove(PendingElement, 1)
    end
end

local function DerefPtr(ptr)
    local boxed = sdk.to_valuetype(ptr, "System.UInt64")
    return boxed and boxed:get_field("m_value")
end

local function ArgInt(arg)
    return sdk.to_int64(arg) & 0xFFFFFFFF
end

local function ArgBool(arg)
    return (sdk.to_int64(arg) & 0xFF) ~= 0
end

local function IsGrouped(kind)
    return Config.GroupEnabled and Config.Group[kind]
end

local function IsDefaultGUI(obj)
    return obj ~= nil and obj:get_type_definition():get_full_name() == "app.GUI020020"
end

local function LogError(where, err)
    log.info("[Split Damage Numbers] " .. where .. " failed: " .. tostring(err))
end

-------------------------------------------------------------------------------
-- Debug log: the last DEBUG_MAX events, newest first, recorded while switched on in the menu
-------------------------------------------------------------------------------

local DEBUG_MAX = 100
local DebugEnabled = false
local DebugLog = {}
local DebugSeq = 0
local DebugSlots = {} -- display slot -> last logged value

local function DebugAdd(fmt, ...)
    DebugSeq = DebugSeq + 1
    table.insert(DebugLog, 1, string.format("#%d %.2fs ", DebugSeq, os.clock()) .. string.format(fmt, ...))
    if #DebugLog > DEBUG_MAX then
        table.remove(DebugLog)
    end
end

-- Name of an enum value, e.g. ("app.GUI020020.State", 3) -> "HIGH(3)"
local EnumNames = {}
local function EnumName(typeName, value)
    local names = EnumNames[typeName]
    if not names then
        names = {}
        for _, field in ipairs(sdk.find_type_definition(typeName):get_fields()) do
            if field:is_static() then
                local ok, data = pcall(field.get_data, field, nil)
                if ok and type(data) == "number" then names[data] = field:get_name() end
            end
        end
        EnumNames[typeName] = names
    end
    return (names[value] or "?") .. "(" .. tostring(value) .. ")"
end

-------------------------------------------------------------------------------
-- 1. Collect own hits
-------------------------------------------------------------------------------

local GetHunterCharacter = sdk.find_type_definition("app.TargetAccessKeyUtil")
    :get_method("getHunterCharacter(app.TARGET_ACCESS_KEY)")

local function StoreHit(calcDamage, damageRate, preCalc)
    local final = calcDamage.FinalDamage
    if not final or final <= 0 then return end

    local attackerKey = calcDamage.Common.Attacker
    if not attackerKey or attackerKey.Category ~= 0 then return end
    local hunter = GetHunterCharacter:call(nil, attackerKey)
    if not hunter or not hunter:get_IsMaster() then return end

    -- Skill add-on damage (e.g. White Flame Torrent) is part of FinalDamage/Physical, but the game
    -- shows it as its own number. Strip it so the base number still finds this hit.
    local skillAdd = preCalc.Common.SkillAdditionalDamge or 0
    if skillAdd <= 0 or final <= skillAdd then
        skillAdd = 0
    end

    local fixedOnly = preCalc.Attack <= 0 and (preCalc.FixAttack > 0 or preCalc.AbsoluteAttack > 0)
    local hit = {
        physical = math.max(calcDamage.Physical - skillAdd, 0),
        elemental = calcDamage.Element,
        meat = math.ceil(damageRate.Meat * 100),
        meatElem = math.ceil(damageRate.MeatElem * 100),
        -- ActionType 0 ignores hitzones; a high stealth rate means a hitzone-independent sneak attack
        ignoreMeat = preCalc.ActionType == 0 or fixedOnly or damageRate.Hide > 1.1,
    }
    if hit.physical > 0 and hit.elemental < MIN_SPLIT_ELEMENT then
        hit.physical = hit.physical + hit.elemental
        hit.elemental = 0
    end
    if hit.physical <= 0 and hit.elemental <= 0 then
        hit.physical = final - skillAdd
    end

    local key = Key(final - skillAdd)
    local list = HitQueue[key] or {}
    list[#list + 1] = { time = os.clock(), hit = hit }
    HitQueue[key] = list

    if DebugEnabled then
        DebugAdd("HIT key=%s phys=%.2f elem=%.2f meat=%d meatElem=%d ignoreMeat=%s actionType=%s"
            .. " attack=%.1f fix=%.1f abs=%.1f attr=%.1f hide=%.2f skillAdd=%.2f -> %s%s",
            key, hit.physical, hit.elemental, hit.meat, hit.meatElem, tostring(hit.ignoreMeat),
            tostring(preCalc.ActionType), preCalc.Attack, preCalc.FixAttack, preCalc.AbsoluteAttack,
            preCalc.AttrValue, damageRate.Hide, skillAdd, HitKind(hit),
            (hit.physical > 0 and hit.elemental > 0) and (" + " .. ElementKind(hit)) or "")
    end
end

sdk.hook(sdk.find_type_definition("app.cEnemyStockDamage"):get_method(CALC_STOCK_DAMAGE_SIG),
    function(args)
        if not Config.Enabled then return end
        local ok, err = pcall(function()
            local stock = sdk.to_managed_object(args[2])
            local preCalc = stock and sdk.to_managed_object(DerefPtr(args[4]))
            if not preCalc then return end

            local category = preCalc.Common.Attacker.Category
            if category ~= 0 and category ~= 2 and category ~= 5 then return end
            if preCalc.Attack <= 0 and preCalc.FixAttack <= 0 and preCalc.AbsoluteAttack <= 0 and preCalc.AttrValue <= 0 then
                return
            end

            local storage = thread.get_hook_storage()
            storage.calcRef = args[3]
            storage.preCalc = preCalc
            storage.rate = sdk.to_managed_object(DerefPtr(args[5]))
        end)
        if not ok then LogError("calcStockDamage pre", err) end
    end,
    function(retval)
        local storage = thread.get_hook_storage()
        local calcRef, preCalc, rate = storage.calcRef, storage.preCalc, storage.rate
        storage.calcRef, storage.preCalc, storage.rate = nil, nil, nil
        if calcRef and preCalc and rate then
            local ok, err = pcall(function()
                local calcDamage = sdk.to_managed_object(DerefPtr(calcRef))
                if calcDamage and calcDamage:get_type_definition():get_full_name() == "app.cEnemyStockDamage.cCalcDamage" then
                    StoreHit(calcDamage, rate, preCalc)
                end
            end)
            if not ok then LogError("calcStockDamage post", err) end
        end
        return retval
    end)

-------------------------------------------------------------------------------
-- 2. Encode the kind into the game's number requests, splitting off the element part
-------------------------------------------------------------------------------

sdk.hook(sdk.find_type_definition("app.cEnemyStockDamage"):get_method(REQUEST_DAMAGE_GUI_SIG),
    function(args)
        if not Config.Enabled then return end
        local ok, err = pcall(function()
            local value = sdk.to_float(args[4])
            local hit = TakeHit(Key(value))
            if not hit then return end -- a proc, stays without a code

            if hit.physical > 0 and hit.elemental > 0 then
                -- The element part becomes its own number once the game really shows a physical
                -- number: it skips numbers e.g. on dead monsters
                local elementKind = ElementKind(hit)
                if Config.Show[elementKind] then
                    local pos = sdk.to_valuetype(args[3], "via.vec3")
                    PendingElement[#PendingElement + 1] = {
                        time = os.clock(),
                        value = EncodeKind(hit.elemental, elementKind),
                        pos = Vector3f.new(pos.x, pos.y, pos.z),
                        state = ArgInt(args[5]),
                        dmgType = ArgInt(args[11]),
                    }
                end
                value = EncodeKind(hit.physical, PhysicalKind(hit))
            else
                value = EncodeKind(value, HitKind(hit))
            end
            args[4] = sdk.float_to_ptr(value)
        end)
        if not ok then LogError("requestDamageGUI pre", err) end
    end)

-------------------------------------------------------------------------------
-- 3. Encode own hits that skipped step 2, release waiting element parts, drop hidden numbers
-------------------------------------------------------------------------------

sdk.hook(sdk.find_type_definition("app.GUI020020"):get_method(REQUEST_DAMAGE_SIG),
    function(args)
        if not Config.Enabled then return end
        local ok, result = pcall(function()
            if not IsDefaultGUI(sdk.to_managed_object(args[2])) then return end

            local value = sdk.to_float(args[4])
            local kind = DecodeKind(value)
            if kind == "proc" then
                local hit = TakeHit(Key(value))
                if hit then
                    kind = HitKind(hit)
                    value = EncodeKind(value, kind)
                    args[4] = sdk.float_to_ptr(value)
                end
            end

            -- Element parts are requested on the next update, not from inside this request, with
            -- the same flags as the physical number
            if PHYSICAL_KINDS[kind] and #PendingElement > 0 then
                local flag1, flag2 = ArgBool(args[9]), ArgBool(args[10])
                for _, element in ipairs(PendingElement) do
                    element.flag1, element.flag2 = flag1, flag2
                    ElementOutbox[#ElementOutbox + 1] = element
                end
                PendingElement = {}
            end

            if DebugEnabled then
                DebugAdd("REQ value=%.4f shown=%.1f -> %s%s | state=%s crit=%s flags=%s/%s", value,
                    BaseValue(value), kind, Config.Show[kind] and "" or " (hidden)",
                    EnumName("app.GUI020020.State", ArgInt(args[5])),
                    EnumName("app.GUI020020.CRITICAL_STATE", ArgInt(args[8])),
                    tostring(ArgBool(args[9])), tostring(ArgBool(args[10])))
            end
            if not Config.Show[kind] then
                return sdk.PreHookResult.SKIP_ORIGINAL
            end

            -- Grouped kinds are collected and requested later as one sum (the kind factor survives it)
            if IsGrouped(kind) and not FlushingGroups then
                local now = os.clock()
                local group = Groups[kind]
                if not group then
                    local pos = sdk.to_valuetype(args[3], "via.vec3")
                    group = {
                        first = now,
                        value = 0,
                        pos = Vector3f.new(pos.x, pos.y, pos.z),
                        state = ArgInt(args[5]),
                        category = ArgInt(args[6]),
                        dmgType = ArgInt(args[7]),
                        crit = 0,
                        flag1 = ArgBool(args[9]),
                        flag2 = ArgBool(args[10]),
                    }
                    Groups[kind] = group
                    GroupOrder[#GroupOrder + 1] = kind
                end
                group.last = now
                group.value = group.value + value
                group.crit = math.max(group.crit, ArgInt(args[8]))
                return sdk.PreHookResult.SKIP_ORIGINAL
            end
        end)
        if not ok then
            LogError("requestDamage", result)
            return
        end
        return result
    end)

-------------------------------------------------------------------------------
-- 4. Request the element parts and grouped numbers, and style the numbers on screen
-------------------------------------------------------------------------------

local function ApplyStyle(style, text, design)
    text:set_Color(style.fill)
    text:set_GlowColor(style.textGlow)
    text:set_ShadowColor(style.textShadow)
    design:set_Color(style.fill)
    design:set_GlowColor(style.glow)
    design:set_ShadowColor(style.designShadow)

    for _, t in ipairs({ text, design }) do
        t:set_FontSlot(FONT_SLOT)
        local size = t:get_FontSize()
        size.w = Config.FontSize
        size.h = Config.FontSize
        t:set_FontSize(size)
        t:set_Language(FONT_LANGUAGE)
    end
end

-- The numbers on screen are the slots of the _DamageInfo array (_DamageInfoList only queues
-- delayed numbers). DAMAGE_INFO is a struct, so these are copies, but their Text objects are the
-- real ones. The game may overwrite the style (e.g. with the wound color), so it is re-applied
-- whenever it differs.
local function StyleNumbers(gui)
    local slots = gui._DamageInfo
    if not slots then return end
    for i = 0, slots:get_size() - 1 do
        local info = slots:get_element(i)
        local value = info and info:get_field("<DamageValue>k__BackingField")
        if value and value > 0 then
            local kind, shown = DecodeKind(value)
            local style = Styles[kind]
            local text = info:get_field("<TextDamage>k__BackingField")
            local design = info:get_field("<DesignTextDamage>k__BackingField")
            if DebugEnabled and DebugSlots[i] ~= value then
                DebugAdd("SHOW slot=%d value=%.4f shown=%.1f -> %s gameColor=%08X state=%s crit=%s", i, value,
                    shown, kind, text:get_Color().rgba,
                    EnumName("app.GUI020020.State", info:get_field("<State>k__BackingField")),
                    EnumName("app.GUI020020.CRITICAL_STATE", info:get_field("<criticalState>k__BackingField")))
            end
            DebugSlots[i] = value
            if text:get_Color().rgba ~= style.fillRgba or text:get_FontSize().w ~= Config.FontSize then
                ApplyStyle(style, text, design)
            end
            local message = string.format(Config.Decimal and "%.1f" or "%.0f", shown)
            if text:get_Message() ~= message then
                text:call("set_Message(System.String)", message)
                design:call("set_Message(System.String)", message)
            end
        end
    end
end

sdk.hook(sdk.find_type_definition("app.GUI020020"):get_method("guiLateUpdate()"),
    function(args)
        if not Config.Enabled then return end
        local gui = sdk.to_managed_object(args[2])
        if not IsDefaultGUI(gui) then return end
        thread.get_hook_storage().gui = gui

        -- These go through the requestDamage hook, so grouped element parts land in Groups
        local outbox = ElementOutbox
        ElementOutbox = {}
        for _, element in ipairs(outbox) do
            local ok, err = pcall(function()
                -- category 0 = player, critical state 0 = no crit marker on the element part
                gui:call(REQUEST_DAMAGE_SIG, element.pos, element.value, element.state, 0, element.dmgType, 0,
                    element.flag1, element.flag2, nil)
            end)
            if not ok then LogError("element number request", err) end
        end

        -- Groups that are done collecting are shown, the others keep waiting
        local now, order = os.clock(), GroupOrder
        GroupOrder = {}
        FlushingGroups = true
        for _, kind in ipairs(order) do
            local g = Groups[kind]
            if not IsGrouped(kind) or now - g.last >= Config.GroupGap or now - g.first >= Config.GroupMaxTime then
                Groups[kind] = nil
                local ok, err = pcall(function()
                    gui:call(REQUEST_DAMAGE_SIG, g.pos, g.value, g.state, g.category, g.dmgType, g.crit,
                        g.flag1, g.flag2, nil)
                end)
                if not ok then LogError("grouped number request", err) end
            else
                GroupOrder[#GroupOrder + 1] = kind
            end
        end
        FlushingGroups = false
    end,
    function(retval)
        local storage = thread.get_hook_storage()
        local gui = storage.gui
        storage.gui = nil
        if gui then
            local ok, err = pcall(function()
                Cleanup()
                StyleNumbers(gui)
            end)
            if not ok then LogError("styling", err) end
        end
        return retval
    end)

do
    local guiSystem = sdk.get_native_singleton("via.gui.GUISystem")
    if guiSystem then
        sdk.call_native_func(guiSystem, sdk.find_type_definition("via.gui.GUISystem"), "loadFont(via.Language)",
            FONT_LANGUAGE)
    end
end

-------------------------------------------------------------------------------
-- Menu
-------------------------------------------------------------------------------

local BOX_PADDING = 8
local SLIDER_WIDTH = 220
local HINT_COLOR = 0xFFA0A0A0

-- imgui flags
-- RowBg, BordersInnerH, BordersOuterH, SizingFixedFit, NoHostExtendX (as wide as its columns)
local TABLE_FLAGS = (1 << 6) | (1 << 7) | (1 << 8) | (1 << 13) | (1 << 16)
local COLOR_SWATCH_FLAGS = (1 << 5) | (1 << 7) -- NoInputs, NoLabel: a swatch that opens a picker

-- A border around a block of the menu, with some room between border and content
local function BeginBox()
    imgui.begin_rect()
    imgui.spacing()
    imgui.indent(BOX_PADDING)
end

local function EndBox()
    imgui.unindent(BOX_PADDING)
    imgui.spacing()
    imgui.end_rect(BOX_PADDING / 2)
end

local function Hint(text)
    imgui.text_colored(text, HINT_COLOR)
end

-- Shows `text` while the mouse is over the previous item
local function Tooltip(text)
    if imgui.is_item_hovered() then imgui.set_tooltip(text) end
end

-- A block title with its hint next to it. No imgui.separator: like table rows it would run past
-- the box border to the window edge.
local function Heading(title, hint)
    imgui.spacing()
    imgui.spacing()
    imgui.text(title)
    if hint then
        imgui.same_line()
        Hint("- " .. hint)
    end
end

local function SliderInt(label, value, min, max, format, tooltip)
    imgui.set_next_item_width(SLIDER_WIDTH)
    local changed, v = imgui.slider_int(label, value, min, max, format)
    Tooltip(tooltip)
    return changed, v
end

local function SliderFloat(label, value, min, max, format, tooltip)
    imgui.set_next_item_width(SLIDER_WIDTH)
    local changed, v = imgui.slider_float(label, value, min, max, format)
    Tooltip(tooltip)
    return changed, v
end

local function ResetAll()
    Config.Decimal = false
    Config.FontSize = DEFAULT_FONT_SIZE
    Config.HardHitzone = DEFAULT_HARD_HITZONE
    Config.HardElementHitzone = DEFAULT_HARD_ELEMENT_HITZONE
    Config.GroupEnabled = false
    Config.GroupGap = DEFAULT_GROUP_GAP
    Config.GroupMaxTime = DEFAULT_GROUP_MAX_TIME
    for _, kind in ipairs(KINDS) do
        Config.Show[kind] = true
        Config.Group[kind] = false
        Config.Colors[kind] = { Fill = DEFAULT_COLORS[kind].Fill, Glow = DEFAULT_COLORS[kind].Glow }
    end
end

local function DrawGeneral()
    Heading("General")
    local changed, c = false, false
    c, Config.Decimal = imgui.checkbox("Show decimal", Config.Decimal)
    Tooltip("e.g. 27.4 instead of 27")
    changed = changed or c
    c, Config.FontSize = SliderInt("Font size", Config.FontSize, 10, 60, "%d px",
        "size of the damage numbers, the game's default is " .. DEFAULT_FONT_SIZE)
    return changed or c
end

local function DrawHitzones()
    Heading("Hitzones", "hitzone values below these count as hard")
    local changed, c = false, false
    c, Config.HardHitzone = SliderInt("Physical##hard_hitzone", Config.HardHitzone, 0, 100, "%d",
        "physical hitzones go up to about 100, minds eye works on hitzones below 45")
    changed = changed or c
    c, Config.HardElementHitzone = SliderInt("Element##hard_element_hitzone", Config.HardElementHitzone, 0, 50,
        "%d", "element hitzones are usually 0 to 30")
    return changed or c
end

local function DrawGrouping()
    Heading("Grouping", "numbers of the same type landing close together are added up into one")
    local changed, c = false, false
    c, Config.GroupEnabled = imgui.checkbox("Enabled##group_enabled", Config.GroupEnabled)
    Tooltip("pick the grouped types in the Group column below")
    changed = changed or c
    if Config.GroupEnabled then
        c, Config.GroupGap = SliderFloat("Gap##group_gap", Config.GroupGap, 0.05, 1.0, "%.2f s",
            "a group is shown once no new number joined it for this long")
        changed = changed or c
        c, Config.GroupMaxTime = SliderFloat("Max time##group_max_time", Config.GroupMaxTime, 0.1, 3.0, "%.2f s",
            "a group is shown at the latest this long after its first number")
        changed = changed or c
    end
    return changed
end

-- One row per number type: show, group, text and glow color
local function DrawNumberTypes()
    Heading("Number types", "hover a type for what it covers, click a color to change it")
    if not imgui.begin_table("number_types", 5, TABLE_FLAGS) then return false end
    local changed, c = false, false
    imgui.table_setup_column("Type")
    imgui.table_setup_column("Show")
    imgui.table_setup_column("Group")
    imgui.table_setup_column("Text")
    imgui.table_setup_column("Glow")
    imgui.table_headers_row()

    for _, kind in ipairs(KINDS) do
        local colors = Config.Colors[kind]
        imgui.table_next_row()

        imgui.table_next_column()
        imgui.text(KIND_LABELS[kind])
        Tooltip(KIND_HINTS[kind])

        imgui.table_next_column()
        c, Config.Show[kind] = imgui.checkbox("##show_" .. kind, Config.Show[kind])
        Tooltip("show these numbers")
        changed = changed or c

        imgui.table_next_column()
        imgui.begin_disabled(not Config.GroupEnabled)
        c, Config.Group[kind] = imgui.checkbox("##group_" .. kind, Config.Group[kind])
        imgui.end_disabled()
        Tooltip(Config.GroupEnabled and "add up these numbers when they land close together"
            or "enable grouping above to use this")
        changed = changed or c

        imgui.table_next_column()
        local fill, glow
        c, fill = imgui.color_edit("##fill_" .. kind, colors.Fill, COLOR_SWATCH_FLAGS)
        Tooltip("text color, click to change; the glow follows it")
        if c then
            colors.Fill = fill
            colors.Glow = DeriveGlow(fill)
            changed = true
        end

        imgui.table_next_column()
        c, glow = imgui.color_edit("##glow_" .. kind, colors.Glow, COLOR_SWATCH_FLAGS)
        Tooltip("glow color, click to change")
        if c then
            colors.Glow = glow
            changed = true
        end
    end
    imgui.end_table()
    return changed
end

local function DrawDebug()
    if not imgui.tree_node("Debug") then return end
    BeginBox()
    Hint("HIT = own hit, REQ = number requested, SHOW = a number appears on screen")
    imgui.spacing()
    local _
    _, DebugEnabled = imgui.checkbox("Record the last " .. DEBUG_MAX .. " events", DebugEnabled)
    if imgui.button("Clear##debug") then
        DebugLog = {}
    end
    imgui.same_line()
    if imgui.button("Write to REFramework log##debug") then
        for i = #DebugLog, 1, -1 do
            log.info("[Split Damage Numbers debug] " .. DebugLog[i])
        end
    end
    imgui.spacing()
    for _, line in ipairs(DebugLog) do
        imgui.text(line)
    end
    EndBox()
    imgui.tree_pop()
end

re.on_draw_ui(function()
    if not imgui.tree_node("Split Damage Numbers") then return end
    BeginBox()
    local changed, c = false, false

    c, Config.Enabled = imgui.checkbox("Enabled", Config.Enabled)
    changed = changed or c

    if Config.Enabled then
        changed = DrawGeneral() or changed
        changed = DrawHitzones() or changed
        changed = DrawGrouping() or changed
        changed = DrawNumberTypes() or changed

        imgui.spacing()
        if imgui.button("Reset all") then
            ResetAll()
            changed = true
        end
        Tooltip("puts every setting and color back to its default")

        imgui.spacing()
        imgui.spacing()
        DrawDebug()
    end

    if changed then
        BuildStyles()
        RequestSave()
    end
    EndBox()
    imgui.tree_pop()
end)
