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
-- With separate element colors on, element damage uses fire_hard, fire_soft, water_hard, ...
-- instead of element_hard/element_soft.
--
---@diagnostic disable: undefined-global

-------------------------------------------------------------------------------
-- Constants
-------------------------------------------------------------------------------

local CONFIG_FILE = "split_damage_numbers.json"
-- The game never resets the style of the slots' Text objects, not even after a script reset, so
-- their style from before first change is kept here to put back when disabled
local ORIGINALS_FILE = "split_damage_numbers_originals.json"

local DEFAULT_HARD_HITZONE = 45
local DEFAULT_HARD_ELEMENT_HITZONE = 20
local DEFAULT_FONT_SIZE = 27
local DEFAULT_GROUP_GAP = 0.15
local DEFAULT_GROUP_MAX_TIME = 0.5
-- Larger sums could no longer be decoded reliably (see CODE_STEP)
local GROUP_LIMIT = 6000
local FONT_SLOT = 0
local FONT_LANGUAGE = 1
local HIT_TTL = 2.0
-- Some attacks (shelling, spread pellets with Burst, ...) carry a tiny bit of element that would
-- only show as a "0", so it is counted as physical
local MIN_SPLIT_ELEMENT = 1.0
local SAVE_DELAY = 0.5
local DEBUG_MAX = 100

local REQUEST_DAMAGE_SIG =
"requestDamage(via.vec3, System.Single, app.GUI020020.State, app.TARGET_ACCESS_KEY.CATEGORY, app.GUI020020.DAMAGE_TYPE, app.GUI020020.CRITICAL_STATE, System.Boolean, System.Boolean, System.Action`1<app.GUI020020.DAMAGE_INFO>)"
local REQUEST_DAMAGE_GUI_SIG =
"requestDamageGUI(via.vec3, System.Single, app.GUI020020.State, System.Boolean, System.Nullable`1<app.TARGET_ACCESS_KEY>, System.Boolean, System.Boolean, app.GUI020020.CRITICAL_STATE, app.GUI020020.DAMAGE_TYPE, app.HitDef.COLLAB_DAMAGE_UI_TYPE)"
local CALC_STOCK_DAMAGE_SIG =
"calcStockDamage(app.cEnemyStockDamage.cCalcDamage, app.cEnemyStockDamage.cPreCalcDamage, app.cEnemyStockDamage.cDamageRate, System.Boolean)"

-- app.HitDef.ATTR values
local ELEMENTS = { [1] = "fire", [2] = "water", [3] = "thunder", [4] = "ice", [5] = "dragon" }
local ELEMENT_LABELS = { fire = "Fire", water = "Water", thunder = "Thunder", ice = "Ice", dragon = "Dragon" }

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
local ELEMENT_KINDS = {}
for _, element in ipairs(ELEMENTS) do
    for _, zone in ipairs({ "hard", "soft" }) do
        local kind = element .. "_" .. zone
        ELEMENT_KINDS[kind] = true
        KINDS[#KINDS + 1] = kind
        KIND_LABELS[kind] = ELEMENT_LABELS[element] .. " " .. zone
        KIND_HINTS[kind] = element .. " damage on " .. (zone == "hard" and "tough parts" or "weak parts")
    end
end
local PHYSICAL_KINDS = { hard = true, soft = true, fixed = true }

local DEFAULT_COLORS = {
    hard = { Fill = 0xFF22699F, Glow = 0xE606151F },
    soft = { Fill = 0xFF63C6FF, Glow = 0xFF0A2B36 }, -- the game's own style for soft hits
    element_hard = { Fill = 0xFF1B1BB2, Glow = 0xE6050523 },
    element_soft = { Fill = 0xFF6E6EFD, Glow = 0xE6161632 },
    fixed = { Fill = 0xFFFBA7C5, Glow = 0xE6322127 },
    proc = { Fill = 0xFFFFBE6E, Glow = 0xE6321A0A },
    fire_hard = { Fill = 0xFF1437B9, Glow = 0xE6040B25 },
    fire_soft = { Fill = 0xFF3C78FF, Glow = 0xE60C1833 },
    water_hard = { Fill = 0xFFAA4114, Glow = 0xE6220D04 },
    water_soft = { Fill = 0xFFFF8C3C, Glow = 0xE6331C0C },
    thunder_hard = { Fill = 0xFF1496B4, Glow = 0xE6041E24 },
    thunder_soft = { Fill = 0xFF46E6FF, Glow = 0xE60E2E33 },
    ice_hard = { Fill = 0xFFAA963C, Glow = 0xE6221E0C },
    ice_soft = { Fill = 0xFFF0F0A0, Glow = 0xE6303020 },
    dragon_hard = { Fill = 0xFF961E73, Glow = 0xE61E0617 },
    dragon_soft = { Fill = 0xFFFF5AC8, Glow = 0xE6331228 },
}

-- Taken from the game's own styles
local TEXT_GLOW = 0xFFC0C0C0
local TEXT_SHADOW = 0x66000000
local DESIGN_SHADOW = 0xFF404040

-- Game damage values are multiples of 0.1. The kind of an own hit is encoded by multiplying the
-- value with a tiny per-kind factor (1 + code * step), which also survives the game adding up
-- values. Decoding finds the factor that turns the value back into a multiple of 0.1; values that
-- already are one have no code and are procs. The shown text is set from that rounded value, so
-- the factor never shows. Exact for values up to about 0.1 / (MAX_CODE * CODE_STEP), i.e. 6500.
local CODE_STEP = 1e-6
local KIND_CODES = { hard = 1, soft = 2, element_hard = 3, element_soft = 4, fixed = 5 }
local MAX_CODE = 5
for _, kind in ipairs(KINDS) do
    if ELEMENT_KINDS[kind] then
        MAX_CODE = MAX_CODE + 1
        KIND_CODES[kind] = MAX_CODE
    end
end
local CODE_KINDS = {}
for kind, code in pairs(KIND_CODES) do
    CODE_KINDS[code] = kind
end

local BOX_PADDING = 8
local SLIDER_WIDTH = 220
local HINT_COLOR = 0xFFA0A0A0
-- RowBg, BordersInnerH, BordersOuterH, SizingFixedFit, NoHostExtendX
local TABLE_FLAGS = (1 << 6) | (1 << 7) | (1 << 8) | (1 << 13) | (1 << 16)
-- NoInputs, NoLabel: a swatch that opens a picker
local COLOR_SWATCH_FLAGS = (1 << 5) | (1 << 7)

local DEBUG_PARTS = { "physical", "element", "fixed", "proc" }

-------------------------------------------------------------------------------
-- Game types
-------------------------------------------------------------------------------

local ColorType = sdk.find_type_definition("via.Color")
local GetHunterCharacter = sdk.find_type_definition("app.TargetAccessKeyUtil")
    :get_method("getHunterCharacter(app.TARGET_ACCESS_KEY)")

-------------------------------------------------------------------------------
-- State
-------------------------------------------------------------------------------

local Config = {
    Enabled = true,
    Decimal = false,
    FontSize = DEFAULT_FONT_SIZE,
    HardHitzone = DEFAULT_HARD_HITZONE,
    HardElementHitzone = DEFAULT_HARD_ELEMENT_HITZONE,
    Colors = {},
    Show = {},
    Group = {},
    GroupGap = DEFAULT_GROUP_GAP,
    GroupMaxTime = DEFAULT_GROUP_MAX_TIME,
    GroupEnabled = false,
    ElementColors = false,
}
local SaveDue = nil

local Styles = {}
-- Raised whenever the styles or settings change, so every slot is styled again
local StyleVersion = 0
-- slot -> value, kind and shown value of its number, and the StyleVersion it was last styled with
local SlotValues, SlotKinds, SlotShown, SlotVersions = {}, {}, {}, {}
-- Kept so its type is not looked up every frame; holding it also keeps its address from being reused
local DefaultGUI, DefaultGUIAddress = nil, nil
-- slot -> { Text = style, Design = style }
local Originals = {}
local RestorePending = false

-- value key -> FIFO list of { time, hit }
local HitQueue = {}
-- Element parts of split hits, waiting for their physical number
local PendingElement = {}
-- Element parts released by a physical number, requested on the next GUI update
local ElementOutbox = {}
-- group key -> open group; GroupList also keeps groups closed at GROUP_LIMIT until they are shown
local Groups, GroupList = {}, {}
local FlushingGroups = false
local LastCleanup = 0

local DebugEnabled = false
local DebugLog = {}
local DebugSeq = 0
local DebugTotals
local EnumNames = {}

-------------------------------------------------------------------------------
-- Config and colors
-------------------------------------------------------------------------------

-- A dark tint of the text color, like the glows of the game's own number styles
local function DeriveGlow(fill)
    local r, g, b = fill & 0xFF, (fill >> 8) & 0xFF, (fill >> 16) & 0xFF
    return 0xE6000000 | (math.floor(b * 0.2) << 16) | (math.floor(g * 0.2) << 8) | math.floor(r * 0.2)
end

local function LoadConfig()
    local saved = json.load_file(CONFIG_FILE)
    if type(saved) ~= "table" then saved = {} end
    for _, key in ipairs({ "Enabled", "Decimal", "FontSize", "HardHitzone", "HardElementHitzone", "GroupGap", "GroupMaxTime", "GroupEnabled", "ElementColors" }) do
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

-- Sliders and pickers change the config every frame while dragged, so it is written once they stop
local function RequestSave()
    SaveDue = os.clock() + SAVE_DELAY
end

local function FlushSave()
    if SaveDue then
        SaveDue = nil
        json.dump_file(CONFIG_FILE, Config)
    end
end

local function NewColor(rgba)
    local color = ValueType.new(ColorType)
    sdk.set_native_field(color, ColorType, "rgba", rgba)
    return color
end

local function BuildStyles()
    StyleVersion = StyleVersion + 1
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

-------------------------------------------------------------------------------
-- Kind codes
-------------------------------------------------------------------------------

local function BaseValue(value)
    return math.floor(value * 10 + 0.5) / 10
end

local function EncodeKind(value, kind)
    return BaseValue(value) * (1 + KIND_CODES[kind] * CODE_STEP)
end

-- Returns the kind and the value to show
local function DecodeKind(value)
    local kind, shown, bestScore = "proc", BaseValue(value), nil
    for code = 0, MAX_CODE do
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
    local element = Config.ElementColors and ELEMENTS[hit.attr] or "element"
    -- Element without an element hitzone value counts as soft
    if hit.meatElem < Config.HardElementHitzone and not (hit.ignoreMeat and hit.meatElem <= 0) then
        return element .. "_hard"
    end
    return element .. "_soft"
end

local function HitKind(hit)
    if hit.elemental > 0 and hit.physical <= 0 then return ElementKind(hit) end
    return PhysicalKind(hit)
end

local function Key(value)
    return string.format("%0.2f", value)
end

local function DropExpired(list, now)
    while #list > 0 and now - list[1].time > HIT_TTL do
        table.remove(list, 1)
    end
end

local function TakeHit(key)
    local list = HitQueue[key]
    if not list then return nil end
    DropExpired(list, os.clock())
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
        DropExpired(list, now)
        if #list == 0 then
            HitQueue[key] = nil
        end
    end
    DropExpired(PendingElement, now)
end

local function ClearQueues()
    HitQueue, PendingElement, ElementOutbox = {}, {}, {}
    Groups, GroupList = {}, {}
end

local function IsGrouped(kind)
    return Config.GroupEnabled and Config.Group[kind]
end

-------------------------------------------------------------------------------
-- Helpers
-------------------------------------------------------------------------------

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

local function IsDefaultGUI(obj)
    return obj ~= nil and obj:get_type_definition():get_full_name() == "app.GUI020020"
end

-- The default GUI behind a hook's this argument, or nil for its subclasses
local function DefaultGUIFromArg(arg)
    local address = sdk.to_int64(arg)
    if address == DefaultGUIAddress then return DefaultGUI end
    local obj = sdk.to_managed_object(arg)
    if not IsDefaultGUI(obj) then return nil end
    DefaultGUI, DefaultGUIAddress = obj, address
    return obj
end

local function LogError(where, err)
    log.info("[Split Damage Numbers] " .. where .. " failed: " .. tostring(err))
end

-------------------------------------------------------------------------------
-- Debug
-------------------------------------------------------------------------------

local function NewDebugTotals()
    return {
        hits = 0,
        passed = { physical = 0, element = 0, fixed = 0, proc = 0 },
        shown = { physical = 0, element = 0, fixed = 0, proc = 0 },
    }
end
DebugTotals = NewDebugTotals()

local function DebugCount(totals, kind, value)
    local part = kind
    if kind == "hard" or kind == "soft" then
        part = "physical"
    elseif kind == "element_hard" or kind == "element_soft" or ELEMENT_KINDS[kind] then
        part = "element"
    end
    totals[part] = totals[part] + value
end

-- e.g. "120.5 (physical 100.0, element 20.5, fixed 0.0, procs 0.0)"
local function DebugPartsText(totals)
    local sum, parts = 0, {}
    for _, part in ipairs(DEBUG_PARTS) do
        sum = sum + totals[part]
        parts[#parts + 1] = string.format("%s %.1f", part == "proc" and "procs" or part, totals[part])
    end
    return string.format("%.1f (%s)", sum, table.concat(parts, ", "))
end

local function DebugAdd(fmt, ...)
    DebugSeq = DebugSeq + 1
    local line = string.format("#%d %.2fs ", DebugSeq, os.clock()) .. string.format(fmt, ...)
    log.info("[Split Damage Numbers debug] " .. line)
    table.insert(DebugLog, 1, line)
    if #DebugLog > DEBUG_MAX then
        table.remove(DebugLog)
    end
end

-- e.g. ("app.GUI020020.State", 3) -> "HIGH(3)"
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
-- Number styles
-------------------------------------------------------------------------------

local function ReadStyle(t)
    local size = t:get_FontSize()
    return {
        Color = t:get_Color().rgba,
        Glow = t:get_GlowColor().rgba,
        Shadow = t:get_ShadowColor().rgba,
        FontSlot = t:get_FontSlot(),
        FontW = size.w,
        FontH = size.h,
        Language = t:get_Language(),
    }
end

local function WriteStyle(t, s)
    t:set_Color(NewColor(s.Color))
    t:set_GlowColor(NewColor(s.Glow))
    t:set_ShadowColor(NewColor(s.Shadow))
    t:set_FontSlot(s.FontSlot)
    local size = t:get_FontSize()
    size.w = s.FontW
    size.h = s.FontH
    t:set_FontSize(size)
    t:set_Language(s.Language)
end

local function SaveOriginal(slot, text, design)
    local key = tostring(slot)
    if Originals[key] then return end
    Originals[key] = { Text = ReadStyle(text), Design = ReadStyle(design) }
    json.dump_file(ORIGINALS_FILE, Originals)
end

local function RestoreOriginals(gui)
    local slots = gui._DamageInfo
    if not slots then return end
    for i = 0, slots:get_size() - 1 do
        local original = Originals[tostring(i)]
        local info = original and slots:get_element(i)
        if info then
            WriteStyle(info:get_field("<TextDamage>k__BackingField"), original.Text)
            WriteStyle(info:get_field("<DesignTextDamage>k__BackingField"), original.Design)
        end
    end
end

local function ApplyStyle(slot, style, text, design)
    SaveOriginal(slot, text, design)
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

-- The numbers on screen are the slots of _DamageInfo (_DamageInfoList only queues delayed
-- numbers). DAMAGE_INFO is a struct, so these are copies, but their Text objects are the real
-- ones. The game may overwrite the style (e.g. with the wound color), so it is re-applied
-- whenever it differs. Font size and text only need a check for a new number, new settings or
-- a style the game overwrote, so a number that is already done costs a single color read.
local function StyleNumbers(gui)
    local slots = gui._DamageInfo
    if not slots then return end
    for i = 0, slots:get_size() - 1 do
        local info = slots:get_element(i)
        -- A free slot has state DEFAULT but keeps the value of its last number
        local value = info and info:get_field("<State>k__BackingField") ~= 0
            and info:get_field("<DamageValue>k__BackingField")
        if value and value > 0 then
            local text = info:get_field("<TextDamage>k__BackingField")
            local design = info:get_field("<DesignTextDamage>k__BackingField")
            if SlotValues[i] ~= value then
                local kind, shown = DecodeKind(value)
                SlotValues[i], SlotKinds[i], SlotShown[i], SlotVersions[i] = value, kind, shown, nil
                if DebugEnabled then
                    DebugAdd("SHOW slot=%d value=%.4f shown=%.1f -> %s gameColor=%08X state=%s crit=%s", i, value,
                        shown, kind, text:get_Color().rgba,
                        EnumName("app.GUI020020.State", info:get_field("<State>k__BackingField")),
                        EnumName("app.GUI020020.CRITICAL_STATE", info:get_field("<criticalState>k__BackingField")))
                    DebugCount(DebugTotals.shown, kind, shown)
                end
            end
            local style = Styles[SlotKinds[i]]
            local stale = SlotVersions[i] ~= StyleVersion
            local overwritten = text:get_Color().rgba ~= style.fillRgba
            if overwritten or (stale and text:get_FontSize().w ~= Config.FontSize) then
                ApplyStyle(i, style, text, design)
            end
            if stale or overwritten then
                local message = string.format(Config.Decimal and "%.1f" or "%.0f", SlotShown[i])
                if text:get_Message() ~= message then
                    text:call("set_Message(System.String)", message)
                    design:call("set_Message(System.String)", message)
                end
                SlotVersions[i] = StyleVersion
            end
        else
            SlotValues[i], SlotVersions[i] = nil, nil
        end
    end
end

-------------------------------------------------------------------------------
-- Init
-------------------------------------------------------------------------------

LoadConfig()
BuildStyles()

do
    local saved = json.load_file(ORIGINALS_FILE)
    if type(saved) == "table" then Originals = saved end
end
-- Also when loaded disabled: the numbers may still carry the style of an earlier script run
RestorePending = not Config.Enabled

do
    local guiSystem = sdk.get_native_singleton("via.gui.GUISystem")
    if guiSystem then
        sdk.call_native_func(guiSystem, sdk.find_type_definition("via.gui.GUISystem"), "loadFont(via.Language)",
            FONT_LANGUAGE)
    end
end

-------------------------------------------------------------------------------
-- 1. Collect own hits
-------------------------------------------------------------------------------

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
        attr = preCalc.AttackAttr,
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
        DebugTotals.hits = DebugTotals.hits + final
        DebugAdd("HIT key=%s phys=%.2f elem=%.2f meat=%d meatElem=%d element=%s ignoreMeat=%s actionType=%s"
            .. " attack=%.1f fix=%.1f abs=%.1f attr=%.1f hide=%.2f skillAdd=%.2f -> %s%s",
            key, hit.physical, hit.elemental, hit.meat, hit.meatElem,
            EnumName("app.HitDef.ATTR", hit.attr), tostring(hit.ignoreMeat),
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
            if not hit then return end

            if hit.physical > 0 and hit.elemental > 0 then
                -- The element part only becomes a number once the game really shows the physical
                -- one: it skips numbers e.g. on dead monsters
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
-- 3. Encode own hits that skipped step 2, release waiting element parts, drop hidden numbers,
--    collect grouped numbers
-------------------------------------------------------------------------------

local function AddToGroup(args, kind, value)
    local now = os.clock()
    local state, category, dmgType = ArgInt(args[5]), ArgInt(args[6]), ArgInt(args[7])
    local flag1, flag2 = ArgBool(args[9]), ArgBool(args[10])
    -- The sum is shown with the state, type and flags of its first number, so only numbers that
    -- agree on them are added up: a state like NO_DAMAGE or SHIELD would hide or change the sum
    local key = string.format("%s|%d|%d|%d|%s|%s", kind, state, category, dmgType, tostring(flag1), tostring(flag2))
    local group = Groups[key]
    if group and group.value + value > GROUP_LIMIT then
        Groups[key] = nil
        group = nil
    end
    if not group then
        local pos = sdk.to_valuetype(args[3], "via.vec3")
        group = {
            key = key,
            kind = kind,
            first = now,
            value = 0,
            count = 0,
            pos = Vector3f.new(pos.x, pos.y, pos.z),
            state = state,
            category = category,
            dmgType = dmgType,
            crit = 0,
            flag1 = flag1,
            flag2 = flag2,
        }
        Groups[key] = group
        GroupList[#GroupList + 1] = group
    end
    group.last = now
    group.value = group.value + value
    group.count = group.count + 1
    -- CRITICAL wins over MINUS_CRITICAL
    local crit = ArgInt(args[8])
    if crit == 1 or group.crit == 0 then group.crit = crit end

    if DebugEnabled then
        DebugAdd("GROUP %s +%.1f = %.1f (%d numbers) key=%s", kind, select(2, DecodeKind(value)),
            select(2, DecodeKind(group.value)), group.count, key)
    end
end

sdk.hook(sdk.find_type_definition("app.GUI020020"):get_method(REQUEST_DAMAGE_SIG),
    function(args)
        if not Config.Enabled then return end
        local ok, result = pcall(function()
            if not DefaultGUIFromArg(args[2]) then return end

            local value = sdk.to_float(args[4])
            local kind = DecodeKind(value)
            -- A group's sum must not take a queued hit that happens to have the same value
            if kind == "proc" and not FlushingGroups then
                local hit = TakeHit(Key(value))
                if hit then
                    kind = HitKind(hit)
                    value = EncodeKind(value, kind)
                    args[4] = sdk.float_to_ptr(value)
                end
            end

            -- Requested on the next update, not from inside this request
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

            if IsGrouped(kind) and not FlushingGroups then
                AddToGroup(args, kind, value)
                return sdk.PreHookResult.SKIP_ORIGINAL
            end

            if DebugEnabled then
                DebugCount(DebugTotals.passed, kind, select(2, DecodeKind(value)))
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

local function RequestNumber(gui, pos, value, state, category, dmgType, crit, flag1, flag2, what)
    local ok, err = pcall(gui.call, gui, REQUEST_DAMAGE_SIG, pos, value, state, category, dmgType, crit,
        flag1, flag2, nil)
    if not ok then LogError(what .. " request", err) end
end

local function FlushGroups(gui)
    local now, list = os.clock(), GroupList
    GroupList = {}
    FlushingGroups = true
    for _, g in ipairs(list) do
        local closed = Groups[g.key] ~= g
        if closed or not IsGrouped(g.kind) or now - g.last >= Config.GroupGap
            or now - g.first >= Config.GroupMaxTime then
            if not closed then Groups[g.key] = nil end
            if DebugEnabled then
                DebugAdd("FLUSH %s %.1f (%d numbers)%s", g.kind, select(2, DecodeKind(g.value)), g.count,
                    closed and " limit" or "")
            end
            RequestNumber(gui, g.pos, g.value, g.state, g.category, g.dmgType, g.crit, g.flag1, g.flag2,
                "grouped number")
        else
            GroupList[#GroupList + 1] = g
        end
    end
    FlushingGroups = false
end

local function UpdateNumbers(gui)
    Cleanup()
    StyleNumbers(gui)
end

sdk.hook(sdk.find_type_definition("app.GUI020020"):get_method("guiLateUpdate()"),
    function(args)
        local gui = DefaultGUIFromArg(args[2])
        if not gui then return end
        if not Config.Enabled then
            -- On the game thread instead of from the menu
            if RestorePending then
                RestorePending = false
                local ok, err = pcall(RestoreOriginals, gui)
                if not ok then LogError("restoring style", err) end
            end
            return
        end
        thread.get_hook_storage().gui = gui

        -- These go through the requestDamage hook, so grouped element parts land in a group
        local outbox = ElementOutbox
        ElementOutbox = {}
        for _, element in ipairs(outbox) do
            -- category 0 = player, no crit marker on the element part
            RequestNumber(gui, element.pos, element.value, element.state, 0, element.dmgType, 0,
                element.flag1, element.flag2, "element number")
        end

        FlushGroups(gui)
    end,
    function(retval)
        local storage = thread.get_hook_storage()
        local gui = storage.gui
        storage.gui = nil
        if gui then
            local ok, err = pcall(UpdateNumbers, gui)
            if not ok then LogError("styling", err) end
        end
        return retval
    end)

-------------------------------------------------------------------------------
-- Menu
-------------------------------------------------------------------------------

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

local function Tooltip(text)
    if imgui.is_item_hovered() then imgui.set_tooltip(text) end
end

-- No imgui.separator: like table rows it would run past the box border to the window edge
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
    Config.ElementColors = false
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
    if c and Config.GroupEnabled then
        for _, kind in ipairs(KINDS) do
            Config.Group[kind] = true
        end
    end
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

local function DrawNumberTypes()
    Heading("Number types", "hover a type for what it covers, click a color to change it")
    local changed, c = false, false
    c, Config.ElementColors = imgui.checkbox("Separate element colors", Config.ElementColors)
    Tooltip("own colors for fire, water, thunder, ice and dragon instead of Element hard/soft")
    changed = changed or c
    if not imgui.begin_table("number_types", 5, TABLE_FLAGS) then return changed end
    imgui.table_setup_column("Type")
    imgui.table_setup_column("Show")
    imgui.table_setup_column("Group")
    imgui.table_setup_column("Text")
    imgui.table_setup_column("Glow")
    imgui.table_headers_row()

    for _, kind in ipairs(KINDS) do
        local shared = kind == "element_hard" or kind == "element_soft"
        if (ELEMENT_KINDS[kind] and not Config.ElementColors) or (shared and Config.ElementColors) then
            goto continue
        end
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
        ::continue::
    end
    imgui.end_table()
    return changed
end

local function DrawDebug()
    if not imgui.tree_node("Debug") then return end
    BeginBox()
    Hint("HIT = own hit, REQ = number requested, GROUP = number added to a group, FLUSH = group requested,")
    Hint("SHOW = a number appears on screen")
    imgui.spacing()
    local _
    _, DebugEnabled = imgui.checkbox("Record events", DebugEnabled)
    Tooltip("every event is also written to the REFramework log, the last " .. DEBUG_MAX .. " are shown here")
    local totals = {
        string.format("Own hits  %.1f", DebugTotals.hits),
        "Passed on " .. DebugPartsText(DebugTotals.passed),
        "Shown     " .. DebugPartsText(DebugTotals.shown),
    }
    for _, line in ipairs(totals) do
        imgui.text(line)
        Tooltip("added up while recording, compare with the training area's total damage;\n"
            .. "own hits include skill add-on damage, which the game shows as a proc number")
    end
    if imgui.button("Clear##debug") then
        DebugAdd("CLEAR %s", table.concat(totals, " | "))
        DebugLog = {}
        DebugTotals = NewDebugTotals()
    end
    imgui.spacing()
    for _, line in ipairs(DebugLog) do
        imgui.text(line)
    end
    EndBox()
    imgui.tree_pop()
end

-------------------------------------------------------------------------------
-- Callbacks
-------------------------------------------------------------------------------

re.on_frame(function()
    if SaveDue and os.clock() >= SaveDue then FlushSave() end
end)
re.on_script_reset(FlushSave)

re.on_draw_ui(function()
    if not imgui.tree_node("Split Damage Numbers") then return end
    BeginBox()
    local changed, c = false, false

    c, Config.Enabled = imgui.checkbox("Enabled", Config.Enabled)
    changed = changed or c
    if c then
        ClearQueues()
        RestorePending = not Config.Enabled
    end

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
