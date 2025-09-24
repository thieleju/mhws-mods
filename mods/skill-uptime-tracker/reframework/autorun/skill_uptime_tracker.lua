--
-- Skill Uptime Tracker
--
-- @author https://github.com/thieleju
--
---@diagnostic disable: undefined-global, undefined-doc-name, undefined-field

local TD_MessageUtil          = sdk.find_type_definition("app.MessageUtil")
local TD_HunterSkillDef       = sdk.find_type_definition("app.HunterSkillDef")
local TD_GuiMessage           = sdk.find_type_definition("via.gui.message")
local TD_SkillEnum            = sdk.find_type_definition("app.HunterDef.Skill")
local TD_SkillParamInfo       = sdk.find_type_definition("app.cHunterSkillParamInfo")
local TD_QuestPlaying         = sdk.find_type_definition("app.cQuestPlaying")
local TD_SoundMusic           = sdk.find_type_definition("app.SoundMusicManager")
local TD_BattleMusic          = sdk.find_type_definition("app.BattleMusicManager")
local TD_MissionManager       = sdk.find_type_definition("app.MissionManager")
local TD_App                  = sdk.find_type_definition("via.Application")
local TD_HunterCharacter      = sdk.find_type_definition("app.HunterCharacter")
local TD_EnemyCharacter       = sdk.find_type_definition("app.EnemyCharacter")
local TD_cHunterSkill         = sdk.find_type_definition("app.cHunterSkill")
local TD_SkillParamInfo_cInfo = sdk.find_type_definition("app.cHunterSkillParamInfo.cInfo")
local TD_StatusFlagEnum       = sdk.find_type_definition("app.HunterDef.STATUS_FLAG")
local TYPE_EnemyCharacter     = sdk.typeof(TD_EnemyCharacter:get_full_name()) or nil

local FN_GetSkillName         =
    TD_MessageUtil:get_method("getHunterSkillName(app.HunterDef.Skill)") or nil
local FN_GetLeveledSkillName  =
    TD_MessageUtil:get_method("getHunterSkillNameChatLog(app.HunterDef.Skill, System.Int32)") or nil
local FN_ConvertSkillToGroup  =
    TD_HunterSkillDef:get_method("convertSkillToGroupSkill(app.HunterDef.Skill)") or nil
local FN_GetMsg               = TD_GuiMessage:get_method("get(System.Guid)") or nil
local FN_GetMsgLang           = TD_GuiMessage:get_method("get(System.Guid, via.Language)") or nil
local FN_BeginSkillLog        =
    TD_SkillParamInfo:get_method("beginSkillLog(app.HunterDef.Skill)") or nil
local FN_EndSkillLog          =
    TD_SkillParamInfo:get_method("endSkillLog(app.HunterDef.Skill)") or nil
local FN_QuestEnter           = TD_QuestPlaying:get_method("enter()") or nil
local FN_GetBattleMusic       = TD_SoundMusic:get_method("get_BattleMusic()") or nil
local FN_IsBattle             = TD_BattleMusic:get_method("get_IsBattle()") or nil
local FN_IsActiveQuest        = TD_MissionManager:get_method("get_IsActiveQuest()") or nil
local FN_IsPlayingQuest       = TD_MissionManager:get_method("get_IsPlayingQuest()") or nil
local FN_Now                  = TD_App:get_method("get_UpTimeSecond") or nil
local FN_SetStatusBuff        =
    TD_HunterCharacter:get_method("setStatusBuff(app.HunterDef.STATUS_FLAG, System.Single, System.Single)") or nil
local FN_HunterHitPost        =
    TD_HunterCharacter:get_method("evHit_AttackPostProcess(app.HitInfo)") or nil
local FN_GetSkillLevel2       =
    TD_cHunterSkill:get_method("getSkillLevel(app.HunterDef.Skill, System.Boolean, System.Boolean)") or nil

local FLD_Info_Skill          = TD_SkillParamInfo_cInfo:get_field("_Skill") or nil
local FLD_Info_Timer          = TD_SkillParamInfo_cInfo:get_field("_Timer") or nil
local FLD_Info_MaxTimer       = TD_SkillParamInfo_cInfo:get_field("_MaxTimer") or nil
local FLD_Challenger          = TD_SkillParamInfo:get_field("_IsActiveChallenger") or nil
local FLD_FullCharge          = TD_SkillParamInfo:get_field("_IsActiveFullCharge") or nil
local FLD_Konshin             = TD_SkillParamInfo:get_field("_IsActiveKonshin") or nil
local FLD_KonshinUse          = TD_SkillParamInfo:get_field("_KonshinStaminaUseTime") or nil
local SkillIDMax              = TD_SkillEnum:get_field("MAX"):get_data() or nil

-- Config for skil_uptime_tracker.json
local config                  = {
  openWindow = false,
  strategyIndex = 1,
  show = { skills = true, items = false, weapons = false, flags = false },
  columns = { primary = true, percent = true, active = true, state = true },
  debug = false,
  hideButtons = false,
}

-- Module namespace
local SkillUptime             = {
  UI       = {
    defaultFont = nil,
    open = false,
    tables = { Skills = true, Items = false, Weapons = false, Flags = false },
    columns = { Primary = true, Percent = true, Active = true, State = true },
  },
  Strategy = {
    index = 1,
    defs = {
      { label = "In combat",       useHitsView = false, showBattleHeader = true,  accumulateTime = true },
      { label = "Hits (up/total)", useHitsView = true,  showBattleHeader = false, accumulateTime = false },
    },
    labels = {},
  },
  Battle   = { active = false, start = 0.0, total = 0.0 },
  Skills   = {
    running = {},
    timing_starts = {},
    uptime = {},
    name_cache = {},
    hits_up = {},
    InfoFields = {
      "_ToishiBoostInfo", "_RebellionInfo", "_ElementConvertInfo", "_RyukiInfo", "_MusclemanInfo", "_BarbarianInfo",
      "_PowerAwakeInfo", "_RyunyuInfo", "_ContinuousAttackInfo", "_GuardianAreaInfo", "_ResentmentInfo", "_KnightInfo",
      "_MoraleInfo", "_BattoWazaInfo", "_HunkiInfo", "_SlidingPowerUpInfo", "_CounterAttackInfo", "_DisasterInfo",
      "_MantleStrengtheningInfo", "_BegindAttackInfo", "_YellInfo", "_TechnicalAttack_Info", "_DischargeInfo",
      "_IamCoalMinerInfo", "_CaptureMasterInfo", "_HagitoriMasterInfo", "_LuckInfo", "_SpringEventInfo",
      "_SummerEventInfo"
    }
  },
  Status   = { SkillData = {} },
  Items    = {
    data = {},
    timing_starts = {},
    uptime = {},
    hits_up = {},
    Names = {
      Kairiki = "Attack Seed",
      KairikiG = "Attack Pill",
      Nintai = "Defense Seed",
      NintaiG = "Defense Pill",
      KijinPowder = "Demondrug Powder",
      KoukaPowder = "Armorskin Powder",
      KijinAmmo = "Demondrug Ammo",
      KoukaAmmo = "Armorskin Ammo",
      DashJuice = "Dash Juice",
      Immunizer = "Immunizer",
      HotDrink = "Hot Drink",
      CoolerDrink = "Cool Drink",
      KijinDrink = "Demondrug",
      KijinDrinkG = "Might Pill",
      KoukaDrink = "Armorskin",
      KoukaDrinkG = "Adamant Pill",
    },
  },
  Weapons  = { data = {}, timing_starts = {}, uptime = {}, hits_up = {} },
  Flags    = { names = {}, data = {}, timing_starts = {}, uptime = {}, hits_up = {}, lastTick = nil },
  Hits     = { total = 0 },
  Const    = {
    COLOR_RED = 0xFF0000FF,
    COLOR_GREEN = 0xFF00FF00,
    COLOR_BLUE = 0xFFFFA500,
    PREFIX = "[Skill Tracker] ",
    CONFIG_PATH = "skill_uptime_tracker.json",
    FRENZY_SKILL_ID = 194,
    SEREGIOS_TENACITY_SKILL_ID = 217,
  },
  -- Ensure sub-namespaces exist before assigning functions
  Util     = {},
  Config   = {},
  Core     = {},
  Hooks    = {},
}

for i, s in ipairs(SkillUptime.Strategy.defs) do SkillUptime.Strategy.labels[i] = s.label end

-- Singleton cache
local _SINGLETON_CACHE = {}

-- Status flags
local FLAGS_NAME_MAP   = {
  [0] = "No Damage",
  [1] = "Friendly Fire Disabled",
  [2] = "Guard",
  [3] = "Power Guard",
  [4] = "Perfect Guard",
  [5] = "Laser Guard",
  [6] = "Guard Point",
  [7] = "Super Armor",
  [8] = "Hyper Armor",
  [9] = "Pause Status Timers",
  [10] = "Ignore Status Timer Pause",
  [11] = "Stop Red Health Recovery",
  [12] = "Disable Red Health",
  [13] = "Stop Stamina Recovery",
  [14] = "No Stamina Consumption",
  [15] = "Keep Stun Request",
  [16] = "No Damage Reaction",
  [17] = "Cannot Die",
  [18] = "No Small Damage Reaction",
  [19] = "No Slip Damage Reaction",
  [20] = "Slip → Small Reaction",
  [21] = "Refresh Skill Gauge",
  [22] = "Meal Effects Active",
  [23] = "In Thorns",
  [24] = "In Hiding Bush",
  [25] = "In Smoke",
  [26] = "In Poison Area",
  [27] = "Heating Grass",
  [28] = "Ignore Area Temperature",
  [29] = "Frenzy Boost",
  [30] = "Stamina Down",
  [31] = "Attack Up (Effect)",
  [32] = "Defense Up (Effect)",
  [33] = "Disaster Skill Active",
  [34] = "Attack Charm",
  [35] = "Defense Charm",
  [36] = "Attack Up",
  [37] = "Attack Up (Drink)",
  [38] = "Attack Up (Seed)",
  [39] = "Attack Up (Powder)",
  [40] = "Defense Up",
  [41] = "Defense Up (Drink)",
  [42] = "Defense Up (Seed)",
  [43] = "Defense Up (Powder)",
  [44] = "Dragon Attack Up",
  [45] = "Elemental Attack Up",
  [46] = "Afflicted Attack Up",
  [47] = "Affinity Up",
  [48] = "Red Health Recovery Up",
  [49] = "Stamina Boost",
  [50] = "Cool Drink",
  [51] = "Hot Drink",
  [52] = "Regeneration",
  [53] = "Evasion Boost",
  [54] = "DB: Demon Dodge",
  [55] = "HH: Self-Improvement",
  [56] = "HH: Self-Improvement (W)",
  [57] = "HH: Attack Up",
  [58] = "HH: Defense Up",
  [59] = "HH: Elemental Attack Up",
  [60] = "HH: Ailment/Blight Attack Up",
  [61] = "HH: Divine Protection",
  [62] = "HH: Fire Res (S)",
  [63] = "HH: Fire Res (L)",
  [64] = "HH: Water Res (S)",
  [65] = "HH: Water Res (L)",
  [66] = "HH: Thunder Res (S)",
  [67] = "HH: Thunder Res (L)",
  [68] = "HH: Ice Res (S)",
  [69] = "HH: Ice Res (L)",
  [70] = "HH: Dragon Res (S)",
  [71] = "HH: Dragon Res (L)",
  [72] = "HH: Earplugs (S)",
  [73] = "HH: Earplugs (L)",
  [74] = "HH: Tremor Resistance",
  [75] = "HH: Paralysis Resistance",
  [76] = "HH: Stun Resistance",
  [77] = "HH: Wind Pressure Negated (S)",
  [78] = "HH: Wind Pressure Negated (L)",
  [79] = "HH: Steadiness",
  [80] = "HH: Env. Damage Negated",
  [81] = "HH: Super Armor",
  [82] = "HH: Elemental Damage Negated",
  [83] = "HH: All Ailments Negated",
  [84] = "HH: Affinity Up (S) + Recovery (S)",
  [85] = "HH: Sonic Barrier",
  [86] = "HH: Movement Speed Up",
  [87] = "HH: Stamina Regen Up",
  [88] = "HH: All Element Res Up",
  [89] = "Element Conversion (S)",
  [90] = "Element Conversion (M)",
  [91] = "Element Conversion (L)",
  [92] = "Stamina Recovery Up",
  [93] = "Meal Effects",
  [94] = "Poisoned",
  [95] = "Stunned",
  [96] = "Sleep",
  [97] = "Paralyzed",
  [98] = "Fireblight",
  [99] = "Thunderblight",
  [100] = "Waterblight",
  [101] = "Iceblight",
  [102] = "Dragonblight",
  [103] = "Stench",
  [104] = "Blastblight",
  [105] = "Bleeding",
  [106] = "Defense Down",
  [107] = "Sticky",
  [108] = "Frozen",
  [109] = "Frenzy (Infected)",
  [110] = "Frenzy (Outbreak)",
  [111] = "Frenzy (Overcome)",
  [112] = "Ailment EX",
  [113] = "Ailment EX (S)",
  [114] = "Ailment EX (R)",
  [115] = "Icon Max",
  [116] = "Max",
}

if TD_StatusFlagEnum then
  local ok, fields = pcall(function() return TD_StatusFlagEnum:get_fields() end)
  if ok and fields then
    for _, f in ipairs(fields) do
      local name = f:get_name()
      if name and not string.find(name, "__") then
        local ok2, val = pcall(function() return f:get_data(nil) end)
        if ok2 and type(val) == "number" then SkillUptime.Flags.names[val] = name end
      end
    end
  end
end

SkillUptime.Skills.is_excluded_skill = function(skill_id)
  return skill_id == SkillUptime.Const.SEREGIOS_TENACITY_SKILL_ID or skill_id == 0
end

SkillUptime.Strategy.get_active = function()
  return SkillUptime.Strategy.defs[SkillUptime.Strategy.index] or SkillUptime.Strategy.defs[1]
end

SkillUptime.UI.ensure_default_font = function()
  if SkillUptime.UI.defaultFont ~= nil then return SkillUptime.UI.defaultFont end
  local size = (imgui.get_default_font_size and imgui.get_default_font_size()) or nil
  local font = nil
  if imgui.load_font then
    -- nil path loads the default font at the requested size
    font = imgui.load_font(nil, size)
  end
  SkillUptime.UI.defaultFont = font
  return SkillUptime.UI.defaultFont
end

SkillUptime.Config.save = function()
  if json and json.dump_file then json.dump_file(SkillUptime.Const.CONFIG_PATH, config) end
end

SkillUptime.Config.apply = function()
  SkillUptime.Strategy.index = config.strategyIndex or SkillUptime.Strategy.index
  SkillUptime.UI.tables.Skills = (config.show and config.show.skills) or SkillUptime.UI.tables.Skills
  SkillUptime.UI.tables.Items = (config.show and config.show.items) or SkillUptime.UI.tables.Items
  SkillUptime.UI.tables.Weapons = (config.show and config.show.weapons) or SkillUptime.UI.tables.Weapons
  SkillUptime.UI.tables.Flags = (config.show and config.show.flags) or SkillUptime.UI.tables.Flags
  SkillUptime.UI.columns.Primary = (config.columns and config.columns.primary ~= false)
  SkillUptime.UI.columns.Percent = (config.columns and config.columns.percent ~= false)
  SkillUptime.UI.columns.Active = (config.columns and config.columns.active ~= false)
  SkillUptime.UI.columns.State = (config.columns and config.columns.state ~= false)
  SkillUptime.UI.open = (config.openWindow == true)
end

SkillUptime.Config.load = function()
  if not (json and json.load_file) then return end
  local loaded = json.load_file(SkillUptime.Const.CONFIG_PATH)
  if not loaded then return end
  if type(loaded.openWindow) == "boolean" then config.openWindow = loaded.openWindow end
  if type(loaded.strategyIndex) == "number" then config.strategyIndex = loaded.strategyIndex end
  if type(loaded.show) == "table" then
    config.show.skills = (loaded.show.skills ~= false)
    config.show.items = (loaded.show.items == true)
    config.show.weapons = (loaded.show.weapons == true)
    config.show.flags = (loaded.show.flags == true)
  end
  if type(loaded.columns) == "table" then
    config.columns.primary = (loaded.columns.primary ~= false)
    config.columns.percent = (loaded.columns.percent ~= false)
    config.columns.active = (loaded.columns.active ~= false)
    config.columns.state = (loaded.columns.state ~= false)
  end
  if type(loaded.debug) == "boolean" then config.debug = loaded.debug end
  if type(loaded.hideButtons) == "boolean" then config.hideButtons = loaded.hideButtons end
  -- Apply loaded config immediately to UI state
  SkillUptime.Config.apply()
end

SkillUptime.Util.logDebug = function(msg)
  if config and config.debug then log.debug(SkillUptime.Const.PREFIX .. tostring(msg)) end
end

SkillUptime.Util.logError = function(msg) log.error(SkillUptime.Const.PREFIX .. tostring(msg)) end

SkillUptime.Core.registerHook = function(method, pre, post)
  if not method then
    SkillUptime.Util.logError("registerHook called with nil method")
    return
  end
  local ok, err = pcall(function() sdk.hook(method, pre, post) end)
  if not ok then SkillUptime.Util.logError("Failed to hook method: " .. tostring(err)) end
end

-- Safe singleton access
SkillUptime.Core.GetSingleton = function(name)
  local cached = _SINGLETON_CACHE[name]
  if cached ~= nil then return cached or nil end
  local ok, v = pcall(function() return sdk.get_managed_singleton(name) end)
  if ok and v ~= nil then
    _SINGLETON_CACHE[name] = v; return v
  end
  _SINGLETON_CACHE[name] = false; return nil
end

SkillUptime.Core.now = function()
  if FN_Now then return FN_Now:call(nil) end
  return os.clock()
end
local now = SkillUptime.Core.now

SkillUptime.Util.fmt_mss_hh = function(total)
  total = total or 0
  if total < 0 then total = 0 end
  local minutes = math.floor(total / 60)
  local seconds = math.floor(total % 60)
  local hundredths = math.floor((total - math.floor(total)) * 100)
  return string.format("%02d'%02d\"%02d", minutes, seconds, hundredths)
end

SkillUptime.Util.fmt_time_pair = function(remain, maxv)
  local r = tonumber(remain) or 0
  local m = tonumber(maxv) or 0
  if r < 0 then r = 0 end
  if m < 0 then m = 0 end
  if (r <= 0) and (m <= 0) then return "—" end
  if m <= 0 then return string.format("%.1fs/—", r) end
  return string.format("%.1fs/%.1fs", r, m)
end

SkillUptime.Util.fmt_pct_label = function(label, pct)
  if pct == nil then return "—" end
  local p = math.max(0, math.min(100, math.floor(((pct or 0) * 100) + 0.5)))
  if label and label ~= "" then
    return string.format("%s %d%%", label, p)
  end
  return string.format("%d%%", p)
end

SkillUptime.Core.get_battle_elapsed = function()
  local total = SkillUptime.Battle.total
  if SkillUptime.Battle.active and SkillUptime.Battle.start > 0 then
    total = total + math.max(0, now() - SkillUptime.Battle.start)
  end
  return total
end

-- Build row data for registries with Activated and uptime tracking
SkillUptime.Core.build_rows = function(registry, uptimeMap, startTimes, epsilon, name_fn)
  local rows = {}
  for key, rec in pairs(registry or {}) do
    local base = uptimeMap[key] or 0.0
    local live = 0.0
    if startTimes[key] then
      live = now() - startTimes[key]; if live < 0 then live = 0 end
    end
    local total = base + live
    local active = rec.Activated and true or false
    if total > epsilon or active then
      local name = name_fn and name_fn(key, rec) or (rec.Name or tostring(key))
      table.insert(rows, { key = key, name = name, total = total, rec = rec, active = active })
    end
  end
  return rows
end

-- Accumulate uptime based on Activated and in-battle state
SkillUptime.Core.accumulate_uptime = function(registry, startTimes, uptimeMap, in_battle, tnow)
  for key, rec in pairs(registry or {}) do
    if in_battle then
      if rec.Activated and (startTimes[key] == nil) then
        startTimes[key] = tnow
      elseif (not rec.Activated) and startTimes[key] then
        local seg = tnow - startTimes[key]
        if seg > 0 then uptimeMap[key] = (uptimeMap[key] or 0) + seg end
        startTimes[key] = nil
      end
    else
      if startTimes[key] then
        local seg = tnow - startTimes[key]
        if seg > 0 then uptimeMap[key] = (uptimeMap[key] or 0) + seg end
        startTimes[key] = nil
      end
    end
  end
end

SkillUptime.Util.str_contains = function(str, target)
  if not str or not target then return false end
  return string.find(str, target, 1, true) ~= nil
end
local str_contains = SkillUptime.Util.str_contains

SkillUptime.Util.get_localized_text = function(guid, lang)
  if not guid then return "[EMPTY_GUID]" end
  if lang and FN_GetMsgLang then return FN_GetMsgLang:call(nil, guid, lang) end
  if FN_GetMsg then return FN_GetMsg:call(nil, guid) end
  return tostring(guid)
end

SkillUptime.Util.is_valid_name = function(name)
  if name == nil or name == "" then return false end
  if str_contains(name, "Rejected") then return false end
  if str_contains(name, "---") or name == "－－－－－－" then return false end
  return true
end

SkillUptime.Skills.resolve_name = function(skill_id, level)
  if not skill_id or skill_id < 0 then return "[INVALID_SKILL]" end
  if SkillIDMax and skill_id >= SkillIDMax then return "[INVALID_SKILL]" end
  local function try(skill, lv)
    if lv and FN_GetLeveledSkillName then
      local guid = FN_GetLeveledSkillName:call(nil, skill, lv)
      if guid then
        local name = SkillUptime.Util.get_localized_text(guid)
        if SkillUptime.Util.is_valid_name(name) then return name end
      end
    end
    if FN_GetSkillName then
      local guid = FN_GetSkillName:call(nil, skill)
      if guid then
        local name = SkillUptime.Util.get_localized_text(guid)
        if SkillUptime.Util.is_valid_name(name) then return name end
      end
    end
    return nil
  end
  local name = try(skill_id, level)
  if name then return name end
  if FN_ConvertSkillToGroup then
    local group_skill = FN_ConvertSkillToGroup:call(nil, skill_id)
    if group_skill and group_skill > 0 and group_skill ~= skill_id then
      name = try(group_skill, level)
      if name then return name end
    end
  end
  if not name and FN_GetLeveledSkillName then
    for lv = 1, 4 do
      name = try(skill_id, lv)
      if name then return name end
    end
  end
  return string.format("Skill %d", skill_id)
end

SkillUptime.Skills.extract_skill_id_from_args = function(args)
  for i = 3, 6 do
    local ok, id = pcall(function() return sdk.to_int64(args[i]) end)
    if ok and id ~= nil and id >= 0 and (not SkillIDMax or id < SkillIDMax) then return id end
  end
  return nil
end

SkillUptime.Core.IsQuestFinishing = function()
  local mm = SkillUptime.Core.GetSingleton("app.MissionManager")
  if not mm then return false end
  local isActive, isPlaying = false, false
  if FN_IsActiveQuest then
    local ok, v = pcall(function() return FN_IsActiveQuest:call(mm) end); if ok then
      isActive = v and true or
          false
    end
  end
  if FN_IsPlayingQuest then
    local ok, v = pcall(function() return FN_IsPlayingQuest:call(mm) end); if ok then
      isPlaying = v and true or
          false
    end
  end
  return isActive and (not isPlaying)
end

SkillUptime.Core.IsInBattle = function()
  if SkillUptime.Core.IsQuestFinishing() then return false end
  local soundMgr = SkillUptime.Core.GetSingleton("app.SoundMusicManager")
  local manager = nil
  if soundMgr and FN_GetBattleMusic then
    local ok, battleMgr = pcall(function() return FN_GetBattleMusic:call(soundMgr) end)
    if ok and battleMgr then manager = battleMgr end
  end
  if FN_IsBattle and manager then
    local ok2, res = pcall(function() return FN_IsBattle:call(manager) end)
    if ok2 then return res and true or false end
  end
  return false
end

-- Battle tick
SkillUptime.Core.tick_battle = function()
  local in_battle = SkillUptime.Core.IsInBattle()
  if in_battle and not SkillUptime.Battle.active then
    SkillUptime.Battle.active = true
    SkillUptime.Battle.start = now()
    for id, is_running in pairs(SkillUptime.Skills.running) do
      if is_running and (not SkillUptime.Skills.is_excluded_skill(id)) and SkillUptime.Skills.timing_starts[id] == nil then
        SkillUptime.Skills.timing_starts[id] =
            now()
      end
    end
    SkillUptime.Util.logDebug("Battle started")
  elseif (not in_battle) and SkillUptime.Battle.active then
    local t = now() - SkillUptime.Battle.start
    if t > 0 then SkillUptime.Battle.total = SkillUptime.Battle.total + t end
    SkillUptime.Battle.active = false
    SkillUptime.Battle.start = 0.0
    for id, start_t in pairs(SkillUptime.Skills.timing_starts) do
      if start_t and (not SkillUptime.Skills.is_excluded_skill(id)) then
        local seg = now() - start_t
        if seg > 0 then SkillUptime.Skills.uptime[id] = (SkillUptime.Skills.uptime[id] or 0) + seg end
        SkillUptime.Skills.timing_starts[id] = nil
      end
    end
    SkillUptime.Util.logDebug(string.format("Battle ended (+%.3fs), total=%.3fs", t, SkillUptime.Battle.total))
  end
end

SkillUptime.Flags.ensure_flag = function(flagId)
  local rec = SkillUptime.Flags.data[flagId]
  if not rec then
    rec = {
      Name = (FLAGS_NAME_MAP and FLAGS_NAME_MAP[flagId]) or SkillUptime.Flags.names[flagId] or
          ("FLAG " .. tostring(flagId)),
      Timer = 0,
      MaxTimer = 0,
      Activated = false,
      LastSeen =
          now()
    }
    SkillUptime.Flags.data[flagId] = rec
  end
  return rec
end

SkillUptime.Flags.update_status_flag = function(flagId, timer, max)
  local rec = SkillUptime.Flags.ensure_flag(flagId)
  timer = timer or 0
  if max and max > (rec.MaxTimer or 0) then rec.MaxTimer = max end
  if (not max) and timer > (rec.MaxTimer or 0) then rec.MaxTimer = timer end
  rec.Timer = timer
  rec.Activated = (timer or 0) > 0
  rec.LastSeen = now()
end

SkillUptime.Hooks.onSetStatusBuff = function(args)
  local flagId = nil
  local okF, vF = pcall(function() return sdk.to_int64(args[3]) end)
  if okF then flagId = vF end
  if not flagId then return end
  local timer = 0.0
  local max = 0.0
  local okT, vT = pcall(function() return sdk.to_float(args[4]) end)
  if okT then timer = vT end
  local okM, vM = pcall(function() return sdk.to_float(args[5]) end)
  if okM then max = vM end
  SkillUptime.Flags.update_status_flag(flagId, timer, max)
end

SkillUptime.Core.tick_status_flags = function()
  local t = now()
  if not SkillUptime.Flags.lastTick then
    SkillUptime.Flags.lastTick = t; return
  end
  local dt = t - SkillUptime.Flags.lastTick; if dt < 0 then dt = 0 end
  for _, rec in pairs(SkillUptime.Flags.data) do
    if rec.Activated and rec.Timer and rec.Timer > 0 then
      rec.Timer = rec.Timer - dt
      if rec.Timer <= 0 then
        rec.Timer = 0; rec.Activated = false
      end
    end
  end
  SkillUptime.Flags.lastTick = t
end

SkillUptime.Skills.get_hunter_skill = function()
  local pm = sdk.get_managed_singleton and sdk.get_managed_singleton("app.PlayerManager") or nil
  if not pm then return nil end
  local info = pm:getMasterPlayer(); if not info then return nil end
  local chr = info:get_Character(); if not chr then return nil end
  local st = chr:get_HunterStatus(); if not st then return nil end
  local ok, skl = pcall(function() return st:get_Skill() end)
  if ok and skl then return skl end
  return st._Skill
end

SkillUptime.Skills.ensure_skill = function(skillObj, skillId)
  if not skillId then return nil end
  local rec = SkillUptime.Status.SkillData[skillId]
  if not rec then
    rec = { Activated = false, Timer = 0, MaxTimer = 0, Level = 0, Name = nil }
    local lvl = 0
    if FN_GetSkillLevel2 then
      local ok, v = pcall(function() return FN_GetSkillLevel2:call(skillObj, skillId, false, false) end)
      if ok and v then lvl = v end
    end
    rec.Level = lvl
    rec.Name = SkillUptime.Skills.resolve_name(skillId, lvl)
    SkillUptime.Status.SkillData[skillId] = rec
  end
  return rec
end

SkillUptime.Skills.update_from_info = function(skillObj, infoObj)
  if not infoObj then return end
  local sid = FLD_Info_Skill and FLD_Info_Skill:get_data(infoObj) or nil
  if not sid then return end
  local rec = SkillUptime.Skills.ensure_skill(skillObj, sid); if not rec then return end
  local t = FLD_Info_Timer and (FLD_Info_Timer:get_data(infoObj) or 0) or 0
  local m = FLD_Info_MaxTimer and (FLD_Info_MaxTimer:get_data(infoObj) or 0) or 0
  rec.Timer = t; rec.MaxTimer = m; rec.Activated = (t or 0) > 0
end

SkillUptime.Skills.update_boolean = function(skillObj, skillId, active, timer, max)
  local rec = SkillUptime.Skills.ensure_skill(skillObj, skillId); if not rec then return end
  rec.Timer = timer or 0; rec.MaxTimer = max or 0; rec.Activated = active and true or false
end

SkillUptime.Skills.update_active_skills = function()
  local skl = SkillUptime.Skills.get_hunter_skill(); if not skl then return nil, nil, nil end
  local infos = skl._HunterSkillParamInfo; if not infos then return skl, nil, nil end
  local status = nil; local okSt, st = pcall(function() return skl:get_Status() end); if okSt then status = st end
  for _, fname in ipairs(SkillUptime.Skills.InfoFields) do
    local fld = TD_SkillParamInfo and TD_SkillParamInfo:get_field(fname)
    if fld then
      local ok, infoObj = pcall(function() return fld:get_data(infos) end); if ok then
        SkillUptime.Skills
            .update_from_info(skl, infoObj)
      end
    end
  end
  SkillUptime.Skills.update_boolean(skl, 59, FLD_Challenger and FLD_Challenger:get_data(infos), 0,
    0)
  SkillUptime.Skills.update_boolean(skl, 60, FLD_FullCharge and FLD_FullCharge:get_data(infos), 0,
    0)
  local isKon = FLD_Konshin and FLD_Konshin:get_data(infos)
  local useT = FLD_KonshinUse and (FLD_KonshinUse:get_data(infos) or 0) or 0
  if isKon then
    SkillUptime.Skills.update_boolean(skl, 65, true, math.max(0, 2 - useT), 2)
  else
    SkillUptime.Skills
        .update_boolean(skl, 65, false, 0, 0)
  end
  return skl, infos, status
end

-- Ensure Frenzy contributes to time-based uptime despite lacking begin/end logs
SkillUptime.Skills.tick_frenzy_time_uptime = function(in_battle, tnow)
  local sid = SkillUptime.Const and SkillUptime.Const.FRENZY_SKILL_ID or nil
  if not sid then return end
  local frenzyRec = SkillUptime.Status and SkillUptime.Status.SkillData and SkillUptime.Status.SkillData[sid] or nil
  local frenzyLogged = SkillUptime.Skills.running and SkillUptime.Skills.running[sid]
  if (not frenzyRec) or frenzyLogged or SkillUptime.Skills.is_excluded_skill(sid) then return end
  if in_battle then
    if frenzyRec.Activated and (SkillUptime.Skills.timing_starts[sid] == nil) then
      SkillUptime.Skills.timing_starts[sid] = tnow
    elseif (not frenzyRec.Activated) and SkillUptime.Skills.timing_starts[sid] then
      local seg = tnow - SkillUptime.Skills.timing_starts[sid]
      if seg > 0 then
        SkillUptime.Skills.uptime[sid] = (SkillUptime.Skills.uptime[sid] or 0) + seg
      end
      SkillUptime.Skills.timing_starts[sid] = nil
    end
  else
    if SkillUptime.Skills.timing_starts[sid] then
      local seg = tnow - SkillUptime.Skills.timing_starts[sid]
      if seg > 0 then
        SkillUptime.Skills.uptime[sid] = (SkillUptime.Skills.uptime[sid] or 0) + seg
      end
      SkillUptime.Skills.timing_starts[sid] = nil
    end
  end
end

SkillUptime.Items.ensure_item = function(name)
  local rec = SkillUptime.Items.data[name]
  if not rec then
    rec = { Name = SkillUptime.Items.Names[name] or name, Timer = 0, MaxTimer = 0, Activated = false }; SkillUptime.Items.data[name] =
        rec
  end
  return rec
end

SkillUptime.Items.update_itembuff = function(name, timer, max)
  local rec = SkillUptime.Items.ensure_item(name)
  timer = timer or 0
  if max and max > (rec.MaxTimer or 0) then rec.MaxTimer = max end
  if (not max) and timer > (rec.MaxTimer or 0) then rec.MaxTimer = timer end
  rec.Timer = timer; rec.Activated = (timer or 0) > 0
end

SkillUptime.Items.update_items_and_frenzy = function(skl, status)
  if not skl then return end
  local st = status
  if not st then
    local okSt, s = pcall(function() return skl:get_Status() end); if okSt then st = s end
  end
  if st and st._ItemBuff then
    local item = st._ItemBuff
    SkillUptime.Items.update_itembuff("Kairiki", item._Kairiki_Timer, item._Kairiki_MaxTime)
    SkillUptime.Items.update_itembuff("KairikiG", item._Kairiki_G_Timer, item._Kairiki_G_MaxTime)
    SkillUptime.Items.update_itembuff("KijinAmmo", item._KijinAmmo_Timer)
    SkillUptime.Items.update_itembuff("KijinPowder", item._KijinPowder_Timer, item._KijinPowder_MaxTime)
    SkillUptime.Items.update_itembuff("Nintai", item._Nintai_Timer, item._Nintai_MaxTime)
    SkillUptime.Items.update_itembuff("NintaiG", item._Nintai_G_Timer, item._Nintai_G_MaxTime)
    SkillUptime.Items.update_itembuff("KoukaAmmo", item._KoukaAmmo_Timer)
    SkillUptime.Items.update_itembuff("KoukaPowder", item._KoukaPowder_Timer, item._KoukaPowder_MaxTime)
    SkillUptime.Items.update_itembuff("DashJuice", item._DashJuice_Timer, item._DashJuice_MaxTime)
    SkillUptime.Items.update_itembuff("Immunizer", item._Immunizer_Timer, item._Immunizer_MaxTime)
    SkillUptime.Items.update_itembuff("HotDrink", item._HotDrink_Timer, item._HotDrink_MaxTime)
    SkillUptime.Items.update_itembuff("CoolerDrink", item._CoolerDrink_Timer, item._CoolerDrink_MaxTime)
    if item._KijinDrink then
      SkillUptime.Items.update_itembuff("KijinDrink", item._KijinDrink._Timer,
        item._KijinDrink._MaxTime)
    end
    if item._KijinDrink_G then
      SkillUptime.Items.update_itembuff("KijinDrinkG", item._KijinDrink_G._Timer,
        item._KijinDrink_G._MaxTime)
    end
    if item._KoukaDrink then
      SkillUptime.Items.update_itembuff("KoukaDrink", item._KoukaDrink._Timer,
        item._KoukaDrink._MaxTime)
    end
    if item._KoukaDrink_G then
      SkillUptime.Items.update_itembuff("KoukaDrinkG", item._KoukaDrink_G._Timer,
        item._KoukaDrink_G._MaxTime)
    end
  end
  if st and st._BadConditions and st._BadConditions._Frenzy then
    local frenzy = st._BadConditions._Frenzy
    local sid = SkillUptime.Const.FRENZY_SKILL_ID
    local rec = SkillUptime.Skills.ensure_skill(skl, sid)
    if rec then
      if frenzy._IsActive and frenzy._State == 2 then
        rec.Timer = frenzy._DurationTimer or 0
        rec.MaxTimer = frenzy._DurationTime or rec.MaxTimer or 0
        rec.Activated = (rec.Timer or 0) > 0
      else
        rec.Timer = 0; rec.MaxTimer = rec.MaxTimer or 0; rec.Activated = false
      end
    end
  end
end

SkillUptime.Weapons.get_hunter_character = function()
  local pm = sdk.get_managed_singleton and sdk.get_managed_singleton("app.PlayerManager") or nil
  if not pm then return nil end
  local info = pm:getMasterPlayer(); if not info then return nil end
  local chr = info:get_Character(); return chr
end

SkillUptime.Weapons.ensure_weapon_state = function(name, label)
  local rec = SkillUptime.Weapons.data[name]
  if not rec then
    rec = { Name = name, Activated = false, Meter = nil, MeterLabel = label }
    SkillUptime.Weapons.data[name] = rec
  end
  if label and rec.MeterLabel ~= label then rec.MeterLabel = label end
  return rec
end

SkillUptime.Weapons.update_weapon_states = function()
  local chr = SkillUptime.Weapons.get_hunter_character(); if not chr then return end
  local okH, wpHdlr = pcall(function() return chr:get_WeaponHandling() end)
  if not okH or not wpHdlr then return end
  -- Only meaningful for Dual Blades (WeaponType 2). If not DB, clear states.
  local okWT, wtype = pcall(function() return chr:get_WeaponType() end)
  if not okWT or wtype ~= 2 then
    for _, rec in pairs(SkillUptime.Weapons.data) do rec.Activated = false end
    return
  end
  local okS, stamin = pcall(function() return chr:get_HunterStamina() end)
  local staminaPct = nil
  if okS and stamin then
    local maxS = stamin:get_MaxStamina()
    if maxS and maxS > 0 then staminaPct = (stamin:get_Stamina() or 0) / maxS end
  end
  local isDemon = false
  local isArch = false
  local gaugePct = nil
  -- Direct field access as in dualblades_simple_overlay.lua
  local okD, vD = pcall(function() return wpHdlr._IsKijinOn end); if okD then isDemon = vD and true or false end
  local okA, vA = pcall(function() return wpHdlr._IsKijinEnhancement end); if okA then isArch = vA and true or false end
  local okG, gaugeObj = pcall(function() return wpHdlr:get_field("<KijinGauge>k__BackingField") end)
  if okG and gaugeObj and gaugeObj._Value ~= nil then
    local gv = gaugeObj._Value
    if type(gv) == "number" then gaugePct = gv end
  end
  local recD = SkillUptime.Weapons.ensure_weapon_state("Demon Mode", "Stamina")
  recD.Activated = isDemon; recD.Meter = staminaPct
  local recA = SkillUptime.Weapons.ensure_weapon_state("Archdemon", "Gauge")
  recA.Activated = isArch; recA.Meter = gaugePct
end

SkillUptime.Hooks.onBeginSkillLog = function(args)
  local skill_id = SkillUptime.Skills.extract_skill_id_from_args(args); if not skill_id then return end
  if SkillUptime.Skills.is_excluded_skill(skill_id) then return end
  local name = SkillUptime.Skills.resolve_name(skill_id, 1)
  SkillUptime.Skills.running[skill_id] = true
  if SkillUptime.Battle.active and SkillUptime.Skills.timing_starts[skill_id] == nil then
    SkillUptime.Skills.timing_starts[skill_id] =
        now()
  end
  SkillUptime.Util.logDebug(string.format("Skill on:  ID=%d, Name=%s", skill_id, name))
end

SkillUptime.Hooks.onEndSkillLog = function(args)
  local skill_id = SkillUptime.Skills.extract_skill_id_from_args(args)
  if not skill_id then
    SkillUptime.Util.logDebug("endSkillLog: missing skill id"); return
  end
  if SkillUptime.Skills.is_excluded_skill(skill_id) then return end
  local added = 0.0
  if SkillUptime.Skills.timing_starts[skill_id] then
    added = now() - SkillUptime.Skills.timing_starts[skill_id]
    if added < 0 then added = 0 end
    SkillUptime.Skills.uptime[skill_id] = (SkillUptime.Skills.uptime[skill_id] or 0) + added
    SkillUptime.Skills.timing_starts[skill_id] = nil
  end
  SkillUptime.Skills.running[skill_id] = nil
  local name = SkillUptime.Skills.resolve_name(skill_id, 1)
  if added > 0 then
    SkillUptime.Util.logDebug(string.format("Skill off: ID=%d, Name=%s, +%.3fs", skill_id, name, added))
  else
    SkillUptime.Util.logDebug(
      string.format("Skill off: ID=%d, Name=%s", skill_id, name))
  end
end

SkillUptime.Hooks.onQuestEnter = function()
  SkillUptime.Battle.active = false; SkillUptime.Battle.start = 0.0; SkillUptime.Battle.total = 0.0
  SkillUptime.Skills.uptime = {}; SkillUptime.Skills.running = {}; SkillUptime.Skills.timing_starts = {}; SkillUptime.Skills.hits_up = {}; SkillUptime.Skills.name_cache = {}
  SkillUptime.Items.uptime = {}; SkillUptime.Items.timing_starts = {}; SkillUptime.Items.data = {}; SkillUptime.Items.hits_up = {}
  SkillUptime.Flags.uptime = {}; SkillUptime.Flags.timing_starts = {}; SkillUptime.Flags.data = {}; SkillUptime.Flags.hits_up = {}
  SkillUptime.Weapons.uptime = {}; SkillUptime.Weapons.timing_starts = {}; SkillUptime.Weapons.data = {}; SkillUptime.Weapons.hits_up = {}
  SkillUptime.Hits.total = 0
  SkillUptime.Util.logDebug("Quest enter: cleared trackers and counters")
end

-- Manual reset for session stats
SkillUptime.Hooks.reset_all = function()
  SkillUptime.Hooks.onQuestEnter()
  -- Clear transient activation/timers so UI reflects a clean slate
  for _, rec in pairs(SkillUptime.Flags.data or {}) do
    rec.Activated = false; rec.Timer = 0
  end
  for _, rec in pairs(SkillUptime.Items.data or {}) do
    rec.Activated = false; rec.Timer = 0
  end
  for _, rec in pairs(SkillUptime.Status and SkillUptime.Status.SkillData or {}) do
    rec.Activated = false; rec.Timer = 0
  end
  SkillUptime.Hits.total = 0; SkillUptime.Skills.hits_up = {}; SkillUptime.Items.hits_up = {}; SkillUptime.Weapons.hits_up = {}; SkillUptime.Flags.hits_up = {}
  SkillUptime.Util.logDebug("Manual reset requested")
end

-- Count boss-target hits and attribute them to currently active skills
SkillUptime.Hooks.onHunterHitPost = function(args)
  local hitInfo = sdk.to_managed_object(args[3]); if not hitInfo then return end
  local damageData = hitInfo:get_DamageData(); if not damageData then return end
  if damageData:get_type_definition():get_name() ~= "cDamageParamEm" then return end
  local final = 0
  local fld = damageData:get_type_definition():get_field("FinalDamage")
  if fld then final = fld:get_data(damageData) or 0 end
  if (final or 0) <= 0 then return end
  local dmgOwner = hitInfo:get_DamageOwner(); if not dmgOwner or not TYPE_EnemyCharacter then return end
  local ok, enemy = pcall(function() return dmgOwner:getComponent(TYPE_EnemyCharacter) end)
  if not ok or not enemy or not enemy._Context or not enemy._Context._Em then return end
  local ctx = enemy._Context._Em
  local isBoss = false
  local okB, vB = pcall(function() return ctx:get_IsBoss() end); if okB then isBoss = vB and true or false end
  if not isBoss then return end
  -- Count this hit
  SkillUptime.Hits.total = (SkillUptime.Hits.total or 0) + 1
  SkillUptime.Util.logDebug(string.format("Monster hit credited: total=%d", SkillUptime.Hits.total))
  -- Attribute to active skills
  local counted = {}
  for sid, rec in pairs(SkillUptime.Status and SkillUptime.Status.SkillData or {}) do
    if rec and rec.Activated and (not SkillUptime.Skills.is_excluded_skill(sid)) then
      SkillUptime.Skills.hits_up[sid] = (SkillUptime.Skills.hits_up[sid] or 0) + 1; counted[sid] = true
    end
  end
  for sid, on in pairs(SkillUptime.Skills.running or {}) do
    if on and (not SkillUptime.Skills.is_excluded_skill(sid)) and not counted[sid] then
      SkillUptime.Skills.hits_up[sid] = (SkillUptime.Skills.hits_up[sid] or 0) + 1; counted[sid] = true
    end
  end
  -- Attribute to active item buffs
  for name, rec in pairs(SkillUptime.Items.data or {}) do
    if rec and rec.Activated then
      SkillUptime.Items.hits_up[name] = (SkillUptime.Items.hits_up[name] or 0) + 1
    end
  end
  -- Attribute to active weapon states
  for name, rec in pairs(SkillUptime.Weapons.data or {}) do
    if rec and rec.Activated then
      SkillUptime.Weapons.hits_up[name] = (SkillUptime.Weapons.hits_up[name] or 0) + 1
    end
  end
  -- Attribute to active status flags
  for fid, rec in pairs(SkillUptime.Flags.data or {}) do
    if rec and rec.Activated then
      SkillUptime.Flags.hits_up[fid] = (SkillUptime.Flags.hits_up[fid] or 0) + 1
    end
  end
end

SkillUptime.UI.draw = function()
  local openFlag = { true }
  -- Always call end_window() after begin_window(), even if collapsed
  local __as = SkillUptime.Strategy.get_active()
  local __title = "Skill Uptime Tracker: " .. ((__as and __as.label) or "")
  local window_open = imgui.begin_window(__title, openFlag, 64)
  if window_open then
    -- Push default font if available so this window matches REFramework UI settings
    local pushed_font = false
    local font = SkillUptime.UI.ensure_default_font()
    if font then
      imgui.push_font(font); pushed_font = true
    end
    local strategy = SkillUptime.Strategy.get_active()
    local elapsed = SkillUptime.Core.get_battle_elapsed()
    local in_battle = SkillUptime.Core.IsInBattle()
    if strategy.showBattleHeader then
      imgui.text(string.format("In combat timer: %s ", SkillUptime.Util.fmt_mss_hh(elapsed)))
      imgui.same_line(); if in_battle then
        imgui.text_colored("(active)", SkillUptime.Const.COLOR_GREEN)
      else
        imgui.text_colored("(inactive)", SkillUptime.Const.COLOR_RED)
      end
      imgui.spacing()
    end

    local tableFlags = imgui.TableFlags.Borders
    local epsilon = 0.0005

    -- Skills table
    if SkillUptime.UI.tables.Skills then
      local id_set = {}
      local useHits = (strategy.useHitsView == true)
      if useHits then
        -- Include skills with any hit credit or currently active
        for id, cnt in pairs(SkillUptime.Skills.hits_up or {}) do if (cnt or 0) > 0 and (not SkillUptime.Skills.is_excluded_skill(id)) then id_set[id] = true end end
        for id, rec in pairs(SkillUptime.Status.SkillData or {}) do if rec and rec.Activated and (not SkillUptime.Skills.is_excluded_skill(id)) then id_set[id] = true end end
        for id, on in pairs(SkillUptime.Skills.running or {}) do if on and (not SkillUptime.Skills.is_excluded_skill(id)) then id_set[id] = true end end
      else
        for id, sec in pairs(SkillUptime.Skills.uptime) do if (sec or 0) > epsilon and (not SkillUptime.Skills.is_excluded_skill(id)) then id_set[id] = true end end
        for id, start_t in pairs(SkillUptime.Skills.timing_starts) do
          if start_t and (not SkillUptime.Skills.is_excluded_skill(id)) then
            local live = SkillUptime.Core.now() - start_t; if live and live > epsilon then id_set[id] = true end
          end
        end
      end
      local ids = {}; for id, _ in pairs(id_set) do table.insert(ids, id) end; table.sort(ids)
      imgui.text_colored("> Skills (" .. #ids .. ")", SkillUptime.Const.COLOR_BLUE)
      local colCount = 1
      if SkillUptime.UI.columns.Primary then colCount = colCount + 1 end
      if SkillUptime.UI.columns.Percent then colCount = colCount + 1 end
      if SkillUptime.UI.columns.Active then colCount = colCount + 1 end
      if SkillUptime.UI.columns.State then colCount = colCount + 1 end
      if imgui.begin_table("skill_uptime_table", colCount, tableFlags) then
        imgui.table_setup_column("Name")
        if useHits then
          if SkillUptime.UI.columns.Primary then imgui.table_setup_column("Hits (up/total)") end
          if SkillUptime.UI.columns.Percent then imgui.table_setup_column("Hit Uptime (%)") end
        else
          if SkillUptime.UI.columns.Primary then imgui.table_setup_column("Uptime") end
          if SkillUptime.UI.columns.Percent then imgui.table_setup_column("Uptime (%)") end
        end
        if SkillUptime.UI.columns.Active then imgui.table_setup_column("Active Time") end
        if SkillUptime.UI.columns.State then imgui.table_setup_column("State") end
        imgui.table_headers_row()
        for _, id in ipairs(ids) do
          local base = (not SkillUptime.Skills.is_excluded_skill(id)) and (SkillUptime.Skills.uptime[id] or 0.0) or 0.0
          local live = 0.0
          if SkillUptime.Skills.timing_starts[id] and (not SkillUptime.Skills.is_excluded_skill(id)) then
            live = SkillUptime.Core.now() - SkillUptime.Skills.timing_starts[id]; if live < 0 then live = 0 end
          end
          local total = base + live
          local display = true
          if (not useHits) and (total <= epsilon) then display = false end
          if display then
            local name = SkillUptime.Skills.name_cache[id] or SkillUptime.Skills.resolve_name(id, 1); SkillUptime.Skills.name_cache[id] =
                name
            imgui.table_next_row()
            local col = 0
            imgui.table_set_column_index(col); imgui.text(name); col = col + 1
            if useHits then
              local up = SkillUptime.Skills.hits_up[id] or 0
              local totHits = SkillUptime.Hits.total or 0
              local hitPct = (totHits > 0) and (up / totHits * 100.0) or 0.0
              if SkillUptime.UI.columns.Primary then
                imgui.table_set_column_index(col);
                if totHits > 0 then imgui.text(string.format("%d/%d", up, totHits)) else imgui.text("—") end
                col = col + 1
              end
              if SkillUptime.UI.columns.Percent then
                imgui.table_set_column_index(col); imgui.text(string.format("%.1f%%", hitPct)); col = col + 1
              end
            else
              local pct = (elapsed > 0) and (total / elapsed * 100.0) or 0.0
              if SkillUptime.UI.columns.Primary then
                imgui.table_set_column_index(col); imgui.text(SkillUptime.Util.fmt_mss_hh(total)); col = col + 1
              end
              if SkillUptime.UI.columns.Percent then
                imgui.table_set_column_index(col); imgui.text(string.format("%.1f%%", pct)); col = col + 1
              end
            end
            local s = SkillUptime.Status.SkillData[id]
            if SkillUptime.UI.columns.Active then
              imgui.table_set_column_index(col); imgui.text(SkillUptime.Util.fmt_time_pair(s and s.Timer,
                s and s.MaxTimer)); col = col +
                  1
            end
            if SkillUptime.UI.columns.State then
              imgui.table_set_column_index(col);
              local is_active = (s and s.Activated) and true or false
              if is_active then
                imgui.text_colored("active", SkillUptime.Const.COLOR_GREEN)
              else
                imgui.text_colored(
                  "inactive", SkillUptime.Const.COLOR_RED)
              end
              col = col + 1
            end
          end
        end
        imgui.end_table()
      end
    end
    -- Item Buffs table
    if SkillUptime.UI.tables.Items then
      local itemRows = SkillUptime.Core.build_rows(SkillUptime.Items.data, SkillUptime.Items.uptime,
        SkillUptime.Items.timing_starts,
        epsilon,
        function(key, rec) return rec.Name or tostring(key) end)
      table.sort(itemRows, function(a, b) return a.name < b.name end)
      imgui.text_colored("> Item Buffs (" .. #itemRows .. ")", SkillUptime.Const.COLOR_BLUE)
      local strategy = SkillUptime.Strategy.get_active()
      local useHits = (strategy.useHitsView == true)
      local colCount = 1
      if SkillUptime.UI.columns.Primary then colCount = colCount + 1 end
      if SkillUptime.UI.columns.Percent then colCount = colCount + 1 end
      if SkillUptime.UI.columns.Active then colCount = colCount + 1 end
      if SkillUptime.UI.columns.State then colCount = colCount + 1 end
      if imgui.begin_table("item_uptime_table", colCount, tableFlags) then
        imgui.table_setup_column("Name")
        if useHits then
          if SkillUptime.UI.columns.Primary then imgui.table_setup_column("Hits (up/total)") end
          if SkillUptime.UI.columns.Percent then imgui.table_setup_column("Hit Uptime (%)") end
        else
          if SkillUptime.UI.columns.Primary then imgui.table_setup_column("Uptime") end
          if SkillUptime.UI.columns.Percent then imgui.table_setup_column("Uptime (%)") end
        end
        if SkillUptime.UI.columns.Active then imgui.table_setup_column("Active Time") end
        if SkillUptime.UI.columns.State then imgui.table_setup_column("State") end
        imgui.table_headers_row()
        for _, row in ipairs(itemRows) do
          imgui.table_next_row()
          local col = 0
          imgui.table_set_column_index(col); imgui.text(row.name); col = col + 1
          if useHits then
            local up = SkillUptime.Items.hits_up[row.key] or 0
            local totHits = SkillUptime.Hits.total or 0
            local hitPct = (totHits > 0) and (up / totHits * 100.0) or 0.0
            if SkillUptime.UI.columns.Primary then
              imgui.table_set_column_index(col);
              if totHits > 0 then imgui.text(string.format("%d/%d", up, totHits)) else imgui.text("—") end
              col = col + 1
            end
            if SkillUptime.UI.columns.Percent then
              imgui.table_set_column_index(col); imgui.text(string.format("%.1f%%", hitPct)); col = col + 1
            end
          else
            local pct = (elapsed > 0) and (row.total / elapsed * 100.0) or 0.0
            if SkillUptime.UI.columns.Primary then
              imgui.table_set_column_index(col); imgui.text(SkillUptime.Util.fmt_mss_hh(row.total)); col = col + 1
            end
            if SkillUptime.UI.columns.Percent then
              imgui.table_set_column_index(col); imgui.text(string.format("%.1f%%", pct)); col = col + 1
            end
          end
          if SkillUptime.UI.columns.Active then
            imgui.table_set_column_index(col); imgui.text(SkillUptime.Util.fmt_time_pair(row.rec and row.rec.Timer,
              row.rec and row.rec.MaxTimer)); col = col + 1
          end
          if SkillUptime.UI.columns.State then
            imgui.table_set_column_index(col); if row.active then
              imgui.text_colored("active", SkillUptime.Const.COLOR_GREEN)
            else
              imgui.text_colored("inactive", SkillUptime.Const.COLOR_RED)
            end
            col = col + 1
          end
        end
        imgui.end_table()
      end
    end

    imgui.spacing()
    -- Weapon States (Dual Blades)
    if SkillUptime.UI.tables.Weapons then
      local rows = SkillUptime.Core.build_rows(SkillUptime.Weapons.data, SkillUptime.Weapons.uptime,
        SkillUptime.Weapons.timing_starts,
        epsilon,
        function(key, rec) return rec.Name or tostring(key) end)
      table.sort(rows, function(a, b) return a.name < b.name end)
      imgui.text_colored("> Weapon States (" .. #rows .. ")", SkillUptime.Const.COLOR_BLUE)
      local strategy = SkillUptime.Strategy.get_active()
      local useHits = (strategy.useHitsView == true)
      local colCount2 = 1
      if SkillUptime.UI.columns.Primary then colCount2 = colCount2 + 1 end
      if SkillUptime.UI.columns.Percent then colCount2 = colCount2 + 1 end
      if SkillUptime.UI.columns.Active then colCount2 = colCount2 + 1 end
      if SkillUptime.UI.columns.State then colCount2 = colCount2 + 1 end
      if imgui.begin_table("weapon_states_table", colCount2, tableFlags) then
        imgui.table_setup_column("Name")
        if useHits then
          if SkillUptime.UI.columns.Primary then imgui.table_setup_column("Hits (up/total)") end
          if SkillUptime.UI.columns.Percent then imgui.table_setup_column("Hit Uptime (%)") end
        else
          if SkillUptime.UI.columns.Primary then imgui.table_setup_column("Uptime") end
          if SkillUptime.UI.columns.Percent then imgui.table_setup_column("Uptime (%)") end
        end
        if SkillUptime.UI.columns.Active then imgui.table_setup_column(useHits and "Active Time" or "Active Meter") end
        if SkillUptime.UI.columns.State then imgui.table_setup_column("State") end
        imgui.table_headers_row()
        for _, row in ipairs(rows) do
          imgui.table_next_row()
          local col = 0
          imgui.table_set_column_index(col); imgui.text(row.name); col = col + 1
          if useHits then
            local up = SkillUptime.Weapons.hits_up[row.key] or 0
            local totHits = SkillUptime.Hits.total or 0
            local hitPct = (totHits > 0) and (up / totHits * 100.0) or 0.0
            if SkillUptime.UI.columns.Primary then
              imgui.table_set_column_index(col);
              if totHits > 0 then imgui.text(string.format("%d/%d", up, totHits)) else imgui.text("—") end
              col = col + 1
            end
            if SkillUptime.UI.columns.Percent then
              imgui.table_set_column_index(col); imgui.text(string.format("%.1f%%", hitPct)); col = col + 1
            end
            if SkillUptime.UI.columns.Active then
              imgui.table_set_column_index(col); imgui.text("—"); col = col + 1
            end
          else
            local pct = (elapsed > 0) and (row.total / elapsed * 100.0) or 0.0
            local meterStr = SkillUptime.Util.fmt_pct_label(row.rec and row.rec.MeterLabel, row.rec and row.rec.Meter)
            if SkillUptime.UI.columns.Primary then
              imgui.table_set_column_index(col); imgui.text(SkillUptime.Util.fmt_mss_hh(row.total)); col = col + 1
            end
            if SkillUptime.UI.columns.Percent then
              imgui.table_set_column_index(col); imgui.text(string.format("%.1f%%", pct)); col = col + 1
            end
            if SkillUptime.UI.columns.Active then
              imgui.table_set_column_index(col); imgui.text(meterStr); col = col + 1
            end
          end
          if SkillUptime.UI.columns.State then
            imgui.table_set_column_index(col); if row.active then
              imgui.text_colored("active", SkillUptime.Const.COLOR_GREEN)
            else
              imgui.text_colored("inactive", SkillUptime.Const.COLOR_RED)
            end
            col = col + 1
          end
        end
        imgui.end_table()
      end
    end

    imgui.spacing()
    -- Status Flags table
    if SkillUptime.UI.tables.Flags then
      local flagRows = SkillUptime.Core.build_rows(SkillUptime.Flags.data, SkillUptime.Flags.uptime,
        SkillUptime.Flags.timing_starts,
        epsilon,
        function(fid, rec) return rec.Name or ("FLAG " .. tostring(fid)) end)
      table.sort(flagRows, function(a, b) return a.key < b.key end)
      imgui.text_colored("> Status Flags (" .. #flagRows .. ")", SkillUptime.Const.COLOR_BLUE)
      local strategy = SkillUptime.Strategy.get_active()
      local useHits = (strategy.useHitsView == true)
      local colCount3 = 1
      if SkillUptime.UI.columns.Primary then colCount3 = colCount3 + 1 end
      if SkillUptime.UI.columns.Percent then colCount3 = colCount3 + 1 end
      if SkillUptime.UI.columns.Active then colCount3 = colCount3 + 1 end
      if SkillUptime.UI.columns.State then colCount3 = colCount3 + 1 end
      if imgui.begin_table("flag_uptime_table", colCount3, tableFlags) then
        imgui.table_setup_column("Name")
        if useHits then
          if SkillUptime.UI.columns.Primary then imgui.table_setup_column("Hits (up/total)") end
          if SkillUptime.UI.columns.Percent then imgui.table_setup_column("Hit Uptime (%)") end
        else
          if SkillUptime.UI.columns.Primary then imgui.table_setup_column("Uptime") end
          if SkillUptime.UI.columns.Percent then imgui.table_setup_column("Uptime (%)") end
        end
        if SkillUptime.UI.columns.Active then imgui.table_setup_column("Active Time") end
        if SkillUptime.UI.columns.State then imgui.table_setup_column("State") end
        imgui.table_headers_row()
        for _, row in ipairs(flagRows) do
          imgui.table_next_row()
          local col = 0
          imgui.table_set_column_index(col); imgui.text(row.name); col = col + 1
          if useHits then
            local up = SkillUptime.Flags.hits_up[row.key] or 0
            local totHits = SkillUptime.Hits.total or 0
            local hitPct = (totHits > 0) and (up / totHits * 100.0) or 0.0
            if SkillUptime.UI.columns.Primary then
              imgui.table_set_column_index(col);
              if totHits > 0 then imgui.text(string.format("%d/%d", up, totHits)) else imgui.text("—") end
              col = col + 1
            end
            if SkillUptime.UI.columns.Percent then
              imgui.table_set_column_index(col); imgui.text(string.format("%.1f%%", hitPct)); col = col + 1
            end
          else
            local pct = (elapsed > 0) and (row.total / elapsed * 100.0) or 0.0
            if SkillUptime.UI.columns.Primary then
              imgui.table_set_column_index(col); imgui.text(SkillUptime.Util.fmt_mss_hh(row.total)); col = col + 1
            end
            if SkillUptime.UI.columns.Percent then
              imgui.table_set_column_index(col); imgui.text(string.format("%.1f%%", pct)); col = col + 1
            end
          end
          if SkillUptime.UI.columns.Active then
            imgui.table_set_column_index(col); imgui.text(SkillUptime.Util.fmt_time_pair(row.rec and row.rec.Timer,
              row.rec and row.rec.MaxTimer)); col = col + 1
          end
          if SkillUptime.UI.columns.State then
            imgui.table_set_column_index(col); if row.active then
              imgui.text_colored("active", SkillUptime.Const.COLOR_GREEN)
            else
              imgui.text_colored("inactive", SkillUptime.Const.COLOR_RED)
            end
            col = col + 1
          end
        end
        imgui.end_table()
      end
    end
    -- Final footer controls at the bottom of the last table
    if not config.hideButtons then
      imgui.spacing()
      if imgui.button("Reset Uptime") then
        SkillUptime.Hooks.reset_all(); SkillUptime.Config.save()
      end
      imgui.same_line()
      if imgui.button("Close Window") then
        SkillUptime.UI.open = false; config.openWindow = false; SkillUptime.Config.save()
      end
      imgui.spacing()
    end
    if pushed_font then imgui.pop_font() end
    imgui.end_window()
  end
  if not openFlag[1] then
    SkillUptime.UI.open = false; config.openWindow = false; SkillUptime.Config.save()
  end
end

-- UI entry
re.on_draw_ui(function()
  if imgui.tree_node("Skill Uptime Tracker") then
    imgui.begin_rect()
    -- inner padding for options box
    local __inner_pad = 6
    if imgui.dummy then imgui.dummy(0, __inner_pad) end
    if imgui.indent then imgui.indent(__inner_pad) end
    imgui.text("Displays the uptime of skills, item buffs, and status flags while in battle.")
    imgui.spacing()
    local _
    -- Tracking Strategy dropdown (reduced width)
    imgui.push_item_width(180)
    local changed
    changed, SkillUptime.Strategy.index = imgui.combo("Tracking Strategy", SkillUptime.Strategy.index or 1,
      SkillUptime.Strategy.labels)
    imgui.pop_item_width()
    if changed then
      config.strategyIndex = SkillUptime.Strategy.index; SkillUptime.Config.save()
    end
    -- (Currently only one option; reserved for future strategies.)
    local toggled
    toggled, SkillUptime.UI.tables.Skills = imgui.checkbox("Skills", SkillUptime.UI.tables.Skills)
    if toggled then
      config.show.skills = SkillUptime.UI.tables.Skills; SkillUptime.Config.save()
    end
    -- Direct toggles with (experimental) tag
    toggled, SkillUptime.UI.tables.Items = imgui.checkbox("Item Buffs", SkillUptime.UI.tables.Items)
    if toggled then
      config.show.items = SkillUptime.UI.tables.Items; SkillUptime.Config.save()
    end
    imgui.same_line(); imgui.text_colored("(experimental)", SkillUptime.Const.COLOR_RED)
    toggled, SkillUptime.UI.tables.Weapons = imgui.checkbox("Weapon States (only DBs atm)", SkillUptime.UI.tables
      .Weapons)
    if toggled then
      config.show.weapons = SkillUptime.UI.tables.Weapons; SkillUptime.Config.save()
    end
    imgui.same_line(); imgui.text_colored("(experimental)", SkillUptime.Const.COLOR_RED)
    toggled, SkillUptime.UI.tables.Flags = imgui.checkbox("Status Flags", SkillUptime.UI.tables.Flags)
    if toggled then
      config.show.flags = SkillUptime.UI.tables.Flags; SkillUptime.Config.save()
    end
    imgui.same_line(); imgui.text_colored("(experimental)", SkillUptime.Const.COLOR_RED)
    -- Display Settings
    if imgui.tree_node("Display Settings") then
      local c
      c, SkillUptime.UI.columns.Primary = imgui.checkbox("Show Uptime/Hits column", SkillUptime.UI.columns.Primary)
      if c then
        config.columns.primary = SkillUptime.UI.columns.Primary; SkillUptime.Config.save()
      end
      c, SkillUptime.UI.columns.Percent = imgui.checkbox("Show Uptime %", SkillUptime.UI.columns.Percent)
      if c then
        config.columns.percent = SkillUptime.UI.columns.Percent; SkillUptime.Config.save()
      end
      c, SkillUptime.UI.columns.Active = imgui.checkbox("Show Active Time", SkillUptime.UI.columns.Active)
      if c then
        config.columns.active = SkillUptime.UI.columns.Active; SkillUptime.Config.save()
      end
      c, SkillUptime.UI.columns.State = imgui.checkbox("Show State", SkillUptime.UI.columns.State)
      if c then
        config.columns.state = SkillUptime.UI.columns.State; SkillUptime.Config.save()
      end
      local hbChanged, hb = imgui.checkbox("Hide Window Buttons (Reset/Close)", config.hideButtons == true)
      if hbChanged then
        config.hideButtons = hb and true or false; SkillUptime.Config.save()
      end
      imgui.tree_pop()
    end
    -- Developer Options
    if imgui.tree_node("Developer Options") then
      local dchg, dbg = imgui.checkbox("Debug Mode (console logs)", config.debug == true)
      if dchg then
        config.debug = dbg and true or false
        SkillUptime.Config.save()
      end
      imgui.tree_pop()
    end
    local buttonText = SkillUptime.UI.open and "Close Skill Uptime Overview" or "Show Skill Uptime Overview"
    if imgui.button(buttonText) then
      SkillUptime.UI.open = not SkillUptime.UI.open; config.openWindow = SkillUptime.UI.open; SkillUptime.Config.save()
    end
    imgui.same_line()
    if imgui.button("Reset Uptime") then
      SkillUptime.Hooks.reset_all(); SkillUptime.Config.save()
    end
    imgui.spacing()
    if imgui.unindent then imgui.unindent(__inner_pad) end
    if imgui.dummy then imgui.dummy(0, __inner_pad) end
    imgui.end_rect(2)
    imgui.tree_pop()
  end
end)

-- Frame loop
-- Load persisted settings once
SkillUptime.Config.load()

re.on_config_save(function()
  SkillUptime.Config.save()
  SkillUptime.Config.load()
end)

re.on_frame(function()
  if SkillUptime.UI.open then SkillUptime.UI.draw() end
  SkillUptime.Core.tick_battle()
  local skl, _, status = SkillUptime.Skills.update_active_skills()
  SkillUptime.Items.update_items_and_frenzy(skl, status)
  SkillUptime.Weapons.update_weapon_states()
  SkillUptime.Core.tick_status_flags()
  local strategy = SkillUptime.Strategy.get_active()
  local in_battle = SkillUptime.Battle.active
  local tnow = SkillUptime.Core.now()
  -- Accumulate uptimes via helper (only for combat strategy)
  if strategy.accumulateTime then
    -- Frenzy special-case accumulation
    SkillUptime.Skills.tick_frenzy_time_uptime(in_battle, tnow)
    SkillUptime.Core.accumulate_uptime(SkillUptime.Items.data, SkillUptime.Items.timing_starts, SkillUptime.Items.uptime,
      in_battle, tnow)
    SkillUptime.Core.accumulate_uptime(SkillUptime.Flags.data, SkillUptime.Flags.timing_starts, SkillUptime.Flags.uptime,
      in_battle, tnow)
    SkillUptime.Core.accumulate_uptime(SkillUptime.Weapons.data, SkillUptime.Weapons.timing_starts,
      SkillUptime.Weapons.uptime, in_battle,
      tnow)
  end
end)

-- Register hooks
SkillUptime.Core.registerHook(FN_BeginSkillLog, SkillUptime.Hooks.onBeginSkillLog, nil)
SkillUptime.Core.registerHook(FN_EndSkillLog, SkillUptime.Hooks.onEndSkillLog, nil)
SkillUptime.Core.registerHook(FN_QuestEnter, SkillUptime.Hooks.onQuestEnter, nil)
SkillUptime.Core.registerHook(FN_SetStatusBuff, SkillUptime.Hooks.onSetStatusBuff, nil)
SkillUptime.Core.registerHook(FN_HunterHitPost, SkillUptime.Hooks.onHunterHitPost, nil)
