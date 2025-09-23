--
-- Skill Uptime Tracker
--
-- @author https://github.com/thieleju
--
--
---@diagnostic disable: undefined-global, undefined-doc-name

-- Type definitions
local TD_MessageUtil            = sdk.find_type_definition("app.MessageUtil")
local TD_HunterSkillDef         = sdk.find_type_definition("app.HunterSkillDef")
local TD_GuiMessage             = sdk.find_type_definition("via.gui.message")
local TD_SkillEnum              = sdk.find_type_definition("app.HunterDef.Skill")
local TD_SkillParamInfo         = sdk.find_type_definition("app.cHunterSkillParamInfo")
local TD_QuestPlaying           = sdk.find_type_definition("app.cQuestPlaying")
local TD_SoundMusic             = sdk.find_type_definition("app.SoundMusicManager")
local TD_BattleMusic            = sdk.find_type_definition("app.BattleMusicManager")
local TD_MissionManager         = sdk.find_type_definition("app.MissionManager")
local TD_App                    = sdk.find_type_definition("via.Application")

-- Methods
local FN_GetSkillName           = TD_MessageUtil:get_method("getHunterSkillName(app.HunterDef.Skill)")
local FN_GetLeveledSkillName    = TD_MessageUtil:get_method(
  "getHunterSkillNameChatLog(app.HunterDef.Skill, System.Int32)")
local FN_ConvertSkillToGroup    = TD_HunterSkillDef:get_method("convertSkillToGroupSkill(app.HunterDef.Skill)")
local FN_GetMsg                 = TD_GuiMessage:get_method("get(System.Guid)")
local FN_GetMsgLang             = TD_GuiMessage:get_method("get(System.Guid, via.Language)")
local FN_BeginSkillLog          = TD_SkillParamInfo:get_method("beginSkillLog(app.HunterDef.Skill)")
local FN_EndSkillLog            = TD_SkillParamInfo:get_method("endSkillLog(app.HunterDef.Skill)")
local FN_QuestEnter             = TD_QuestPlaying:get_method("enter()")
local M_GetBattleMusic          = TD_SoundMusic and TD_SoundMusic:get_method("get_BattleMusic()")
local FN_IsBattle               = TD_BattleMusic and TD_BattleMusic:get_method("get_IsBattle()")
local FN_IsActiveQuest          = TD_MissionManager and TD_MissionManager:get_method("get_IsActiveQuest()")
local FN_IsPlayingQuest         = TD_MissionManager and TD_MissionManager:get_method("get_IsPlayingQuest()")
local FN_Now                    = TD_App:get_method("get_UpTimeSecond")

-- Fields/constants
local SkillIDMax                = TD_SkillEnum:get_field("MAX"):get_data() or nil
local COLOR_RED                 = 0xFF0000FF
local COLOR_GREEN               = 0xFF00FF00
local COLOR_BLUE                = 0xFFFFA500
local PREFIX                    = "[Skill Tracker] "

-- Skill tracking
local running_skills            = {}
local timing_starts             = {} -- skill_id -> battle start time
local skill_uptime              = {} -- skill_id -> seconds (battle-only)
local skill_name_cache          = {}
local showUptimeWindow          = false
-- UI toggles for table sections
local showTable_Skills          = true
local showTable_Items           = false
local showTable_Weapons         = false
local showTable_Flags           = false
-- UI state: tracking strategy selection (1-based index)
local trackingStrategyIndex     = 1
local TRACKING_STRATEGY_OPTIONS = { "in combat" }

-- Optional: Use REFramework's default font for this window at the configured default size
local DEFAULT_FONT              = nil
local function ensure_default_font()
  if DEFAULT_FONT ~= nil then return DEFAULT_FONT end
  local size = (imgui.get_default_font_size and imgui.get_default_font_size()) or nil
  local font = nil
  if imgui.load_font then
    -- nil path loads the default font at the requested size
    font = imgui.load_font(nil, size)
  end
  DEFAULT_FONT = font
  return DEFAULT_FONT
end

-- =============================
-- Globals (data registries and static tables)
-- =============================
-- Status flags
local StatusFlagNames      = {} -- [flag_id] -> enum name
local StatusFlagData       = {} -- [flag_id] -> { Name, Timer, MaxTimer, Activated, LastSeen }
local FLAGS_NAME_MAP       = {
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
local HumanFlagNames       = FLAGS_NAME_MAP

-- Items
local ItemBuffNames        = {
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
}
local ItemBuffData         = {} -- [name] -> { Name, Timer, MaxTimer, Activated }

-- Weapon states (Dual Blades demon/archdemon)
local WeaponStateData      = {} -- [name] -> { Name, Activated, Meter, MeterLabel }

-- Skills
local StatusData           = { SkillData = {} } -- [skill_id] -> { Activated, Timer, MaxTimer, Level, Name }

-- SkillInfo fields scanned every frame
local InfoFieldNames       = {
  "_ToishiBoostInfo", "_RebellionInfo", "_ElementConvertInfo", "_RyukiInfo",
  "_MusclemanInfo", "_BarbarianInfo", "_PowerAwakeInfo", "_RyunyuInfo",
  "_ContinuousAttackInfo", "_GuardianAreaInfo", "_ResentmentInfo", "_KnightInfo",
  "_MoraleInfo", "_BattoWazaInfo", "_HunkiInfo", "_SlidingPowerUpInfo",
  "_CounterAttackInfo", "_DisasterInfo", "_MantleStrengtheningInfo", "_BegindAttackInfo",
  "_YellInfo", "_TechnicalAttack_Info", "_DischargeInfo", "_IamCoalMinerInfo",
}

-- Non-skill uptimes (battle-only)
local item_timing_starts   = {} -- item_name -> start_time
local item_uptime          = {} -- item_name -> seconds
local flag_timing_starts   = {} -- flag_id -> start_time
local flag_uptime          = {} -- flag_id -> seconds
-- Weapon states (battle-only)
local weapon_timing_starts = {} -- state_name -> start_time
local weapon_uptime        = {} -- state_name -> seconds

-- Battle state
local battle_active        = false
local battle_start_time    = 0.0
local battle_total         = 0.0

-- ==== Helpers ====
local function logDebug(msg) log.debug(PREFIX .. tostring(msg)) end
local function logError(msg) log.error(PREFIX .. tostring(msg)) end

local function registerHook(method, pre, post)
  if not method then
    logError("registerHook called with nil method")
    return
  end
  local ok, err = pcall(function() sdk.hook(method, pre, post) end)
  if not ok then logError("Failed to hook method: " .. tostring(err)) end
end

-- Safe singleton access
local _SINGLETON_CACHE = {}
local function GetSingleton(name)
  local cached = _SINGLETON_CACHE[name]
  if cached ~= nil then return cached or nil end
  local ok, v = pcall(function() return sdk.get_managed_singleton(name) end)
  if ok and v ~= nil then
    _SINGLETON_CACHE[name] = v; return v
  end
  _SINGLETON_CACHE[name] = false; return nil
end

local function now()
  if FN_Now then return FN_Now:call(nil) end
  return os.clock()
end

local function fmt_mss_hh(total)
  total = total or 0
  if total < 0 then total = 0 end
  local minutes = math.floor(total / 60)
  local seconds = math.floor(total % 60)
  local hundredths = math.floor((total - math.floor(total)) * 100)
  return string.format("%02d'%02d\"%02d", minutes, seconds, hundredths)
end

local function fmt_time_pair(remain, maxv)
  local r = tonumber(remain) or 0
  local m = tonumber(maxv) or 0
  if (r <= 0) and (m <= 0) then return "—" end
  if m <= 0 then return string.format("%.1fs/—", r) end
  return string.format("%.1fs/%.1fs", r, m)
end

local function fmt_pct_label(label, pct)
  if pct == nil then return "—" end
  local p = math.max(0, math.min(100, math.floor(((pct or 0) * 100) + 0.5)))
  if label and label ~= "" then
    return string.format("%s %d%%", label, p)
  end
  return string.format("%d%%", p)
end

local function get_battle_elapsed()
  local total = battle_total
  if battle_active and battle_start_time > 0 then
    total = total + math.max(0, now() - battle_start_time)
  end
  return total
end

-- Debug/test: dump all STATUS_FLAG names and current known MaxTimer values
local function dump_all_flags()
  local ids = {}
  for id, _ in pairs(StatusFlagNames or {}) do table.insert(ids, id) end
  table.sort(ids)
  logDebug("=== STATUS_FLAG dump (" .. tostring(#ids) .. ") ===")
  for _, id in ipairs(ids) do
    local name = StatusFlagNames[id] or ("FLAG " .. tostring(id))
    local rec = StatusFlagData and StatusFlagData[id] or nil
    local max = rec and rec.MaxTimer or 0
    local maxStr = (max and max > 0) and string.format("%.3f", max) or "—"
    logDebug(string.format("FLAG %3d  %-32s  MaxTimer=%s", id, name, maxStr))
  end
end

-- Generic helpers to reduce repetition
-- Build row data for registries with Activated and uptime tracking
local function build_rows(registry, uptimeMap, startTimes, epsilon, name_fn)
  local rows = {}
  for key, rec in pairs(registry or {}) do
    local base = uptimeMap[key] or 0.0
    local live = 0.0
    if startTimes[key] then
      live = now() - startTimes[key]; if live < 0 then live = 0 end
    end
    local total = base + live
    local active = rec.Activated and true or (startTimes[key] ~= nil)
    if total > epsilon or active then
      local name = name_fn and name_fn(key, rec) or (rec.Name or tostring(key))
      table.insert(rows, { key = key, name = name, total = total, rec = rec, active = active })
    end
  end
  return rows
end

-- Accumulate uptime based on Activated and in-battle state
local function accumulate_uptime(registry, startTimes, uptimeMap, in_battle, tnow)
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

local function str_contains(str, target)
  if not str or not target then return false end
  return string.find(str, target, 1, true) ~= nil
end

local function get_localized_text(guid, lang)
  if not guid then return "[EMPTY_GUID]" end
  if lang and FN_GetMsgLang then return FN_GetMsgLang:call(nil, guid, lang) end
  if FN_GetMsg then return FN_GetMsg:call(nil, guid) end
  return tostring(guid)
end

local function is_valid_name(name)
  if name == nil or name == "" then return false end
  if str_contains(name, "Rejected") then return false end
  if str_contains(name, "---") or name == "－－－－－－" then return false end
  return true
end

local function resolve_skill_name(skill_id, level)
  if not skill_id or skill_id < 0 then return "[INVALID_SKILL]" end
  if SkillIDMax and skill_id >= SkillIDMax then return "[INVALID_SKILL]" end
  local function try(skill, lv)
    if lv and FN_GetLeveledSkillName then
      local guid = FN_GetLeveledSkillName:call(nil, skill, lv)
      if guid then
        local name = get_localized_text(guid)
        if is_valid_name(name) then return name end
      end
    end
    if FN_GetSkillName then
      local guid = FN_GetSkillName:call(nil, skill)
      if guid then
        local name = get_localized_text(guid)
        if is_valid_name(name) then return name end
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

local function extract_skill_id_from_args(args)
  for i = 3, 6 do
    local ok, id = pcall(function() return sdk.to_int64(args[i]) end)
    if ok and id ~= nil and id >= 0 and (not SkillIDMax or id < SkillIDMax) then return id end
  end
  return nil
end

local function IsQuestFinishing()
  local mm = GetSingleton("app.MissionManager")
  if not mm then return false end
  local isActive, isPlaying = false, false
  if FN_IsActiveQuest then
    local ok, v = pcall(function() return FN_IsActiveQuest:call(mm) end); if ok then isActive = v and true or false end
  end
  if FN_IsPlayingQuest then
    local ok, v = pcall(function() return FN_IsPlayingQuest:call(mm) end); if ok then isPlaying = v and true or false end
  end
  return isActive and (not isPlaying)
end

local function IsInBattle()
  if IsQuestFinishing() then return false end
  local soundMgr = GetSingleton("app.SoundMusicManager")
  local manager = nil
  if soundMgr and M_GetBattleMusic then
    local ok, battleMgr = pcall(function() return M_GetBattleMusic:call(soundMgr) end)
    if ok and battleMgr then manager = battleMgr end
  end
  if FN_IsBattle and manager then
    local ok2, res = pcall(function() return FN_IsBattle:call(manager) end)
    if ok2 then return res and true or false end
  end
  return false
end

-- Battle tick
local function tick_battle()
  local in_battle = IsInBattle()
  if in_battle and not battle_active then
    battle_active = true
    battle_start_time = now()
    for id, is_running in pairs(running_skills) do
      if is_running and timing_starts[id] == nil then timing_starts[id] = now() end
    end
  elseif (not in_battle) and battle_active then
    local t = now() - battle_start_time
    if t > 0 then battle_total = battle_total + t end
    battle_active = false
    battle_start_time = 0.0
    for id, start_t in pairs(timing_starts) do
      if start_t then
        local seg = now() - start_t
        if seg > 0 then skill_uptime[id] = (skill_uptime[id] or 0) + seg end
        timing_starts[id] = nil
      end
    end
  end
end

-- =============================
-- Status Flags tracker
-- =============================
local TD_StatusFlagEnum = sdk.find_type_definition("app.HunterDef.STATUS_FLAG")
local TD_HunterCharacter = sdk.find_type_definition("app.HunterCharacter")
local FN_SetStatusBuff = TD_HunterCharacter and
    TD_HunterCharacter:get_method("setStatusBuff(app.HunterDef.STATUS_FLAG, System.Single, System.Single)")

if TD_StatusFlagEnum then
  local ok, fields = pcall(function() return TD_StatusFlagEnum:get_fields() end)
  if ok and fields then
    for _, f in ipairs(fields) do
      local name = f:get_name()
      if name and not string.find(name, "__") then
        local ok2, val = pcall(function() return f:get_data(nil) end)
        if ok2 and type(val) == "number" then StatusFlagNames[val] = name end
      end
    end
  end
end

local lastFlagTick = nil

local function ensure_flag(flagId)
  local rec = StatusFlagData[flagId]
  if not rec then
    rec = {
      Name = (HumanFlagNames and HumanFlagNames[flagId]) or StatusFlagNames[flagId] or ("FLAG " .. tostring(flagId)),
      Timer = 0,
      MaxTimer = 0,
      Activated = false,
      LastSeen =
          now()
    }
    StatusFlagData[flagId] = rec
  end
  return rec
end

local function update_status_flag(flagId, timer, max)
  local rec = ensure_flag(flagId)
  timer = timer or 0
  if max and max > (rec.MaxTimer or 0) then rec.MaxTimer = max end
  if (not max) and timer > (rec.MaxTimer or 0) then rec.MaxTimer = timer end
  rec.Timer = timer
  rec.Activated = (timer or 0) > 0
  rec.LastSeen = now()
end

local function onSetStatusBuff(args)
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
  update_status_flag(flagId, timer, max)
end

local function tick_status_flags()
  local t = now()
  if not lastFlagTick then
    lastFlagTick = t; return
  end
  local dt = t - lastFlagTick; if dt < 0 then dt = 0 end
  for _, rec in pairs(StatusFlagData) do
    if rec.Activated and rec.Timer and rec.Timer > 0 then
      rec.Timer = rec.Timer - dt
      if rec.Timer <= 0 then
        rec.Timer = 0; rec.Activated = false
      end
    end
  end
  lastFlagTick = t
end
-- (hook registration moved to unified block below)

-- =============================
-- Active Skills + Items/Frenzy
-- =============================
local TD_cHunterSkill = sdk.find_type_definition("app.cHunterSkill")
local FN_GetSkillLevel2 = TD_cHunterSkill and
    TD_cHunterSkill:get_method("getSkillLevel(app.HunterDef.Skill, System.Boolean, System.Boolean)")

local TD_SkillParamInfo_cInfo = sdk.find_type_definition("app.cHunterSkillParamInfo.cInfo")
local FLD_Info_Skill = TD_SkillParamInfo_cInfo and TD_SkillParamInfo_cInfo:get_field("_Skill")
local FLD_Info_Timer = TD_SkillParamInfo_cInfo and TD_SkillParamInfo_cInfo:get_field("_Timer")
local FLD_Info_MaxTimer = TD_SkillParamInfo_cInfo and TD_SkillParamInfo_cInfo:get_field("_MaxTimer")

local FLD_Challenger = TD_SkillParamInfo and TD_SkillParamInfo:get_field("_IsActiveChallenger")
local FLD_FullCharge = TD_SkillParamInfo and TD_SkillParamInfo:get_field("_IsActiveFullCharge")
local FLD_Konshin = TD_SkillParamInfo and TD_SkillParamInfo:get_field("_IsActiveKonshin")
local FLD_KonshinUse = TD_SkillParamInfo and TD_SkillParamInfo:get_field("_KonshinStaminaUseTime")


local function get_hunter_skill()
  local pm = sdk.get_managed_singleton and sdk.get_managed_singleton("app.PlayerManager") or nil
  if not pm then return nil end
  local info = pm:getMasterPlayer(); if not info then return nil end
  local chr = info:get_Character(); if not chr then return nil end
  local st = chr:get_HunterStatus(); if not st then return nil end
  local ok, skl = pcall(function() return st:get_Skill() end)
  if ok and skl then return skl end
  return st._Skill
end

local function ensure_skill(skillObj, skillId)
  if not skillId then return nil end
  local rec = StatusData.SkillData[skillId]
  if not rec then
    rec = { Activated = false, Timer = 0, MaxTimer = 0, Level = 0, Name = nil }
    local lvl = 0
    if FN_GetSkillLevel2 then
      local ok, v = pcall(function() return FN_GetSkillLevel2:call(skillObj, skillId, false, false) end)
      if ok and v then lvl = v end
    end
    rec.Level = lvl
    rec.Name = resolve_skill_name(skillId, lvl)
    StatusData.SkillData[skillId] = rec
  end
  return rec
end

local function update_from_info(skillObj, infoObj)
  if not infoObj then return end
  local sid = FLD_Info_Skill and FLD_Info_Skill:get_data(infoObj) or nil
  if not sid then return end
  local rec = ensure_skill(skillObj, sid); if not rec then return end
  local t = FLD_Info_Timer and (FLD_Info_Timer:get_data(infoObj) or 0) or 0
  local m = FLD_Info_MaxTimer and (FLD_Info_MaxTimer:get_data(infoObj) or 0) or 0
  rec.Timer = t; rec.MaxTimer = m; rec.Activated = (t or 0) > 0
end

local function update_boolean(skillObj, skillId, active, timer, max)
  local rec = ensure_skill(skillObj, skillId); if not rec then return end
  rec.Timer = timer or 0; rec.MaxTimer = max or 0; rec.Activated = active and true or false
end

local function update_active_skills()
  local skl = get_hunter_skill(); if not skl then return nil, nil, nil end
  local infos = skl._HunterSkillParamInfo; if not infos then return skl, nil, nil end
  local status = nil; local okSt, st = pcall(function() return skl:get_Status() end); if okSt then status = st end
  for _, fname in ipairs(InfoFieldNames) do
    local fld = TD_SkillParamInfo:get_field(fname)
    if fld then
      local ok, infoObj = pcall(function() return fld:get_data(infos) end); if ok then update_from_info(skl, infoObj) end
    end
  end
  update_boolean(skl, 59, FLD_Challenger and FLD_Challenger:get_data(infos), 0, 0)
  update_boolean(skl, 60, FLD_FullCharge and FLD_FullCharge:get_data(infos), 0, 0)
  local isKon = FLD_Konshin and FLD_Konshin:get_data(infos)
  local useT = FLD_KonshinUse and (FLD_KonshinUse:get_data(infos) or 0) or 0
  if isKon then update_boolean(skl, 65, true, math.max(0, 2 - useT), 2) else update_boolean(skl, 65, false, 0, 0) end
  return skl, infos, status
end

-- Items + Frenzy
local function ensure_item(name)
  local rec = ItemBuffData[name]
  if not rec then
    rec = { Name = ItemBuffNames[name] or name, Timer = 0, MaxTimer = 0, Activated = false }; ItemBuffData[name] = rec
  end
  return rec
end

local function update_itembuff(name, timer, max)
  local rec = ensure_item(name)
  timer = timer or 0
  if max and max > (rec.MaxTimer or 0) then rec.MaxTimer = max end
  if (not max) and timer > (rec.MaxTimer or 0) then rec.MaxTimer = timer end
  rec.Timer = timer; rec.Activated = (timer or 0) > 0
end

local function update_items_and_frenzy(skl, status)
  if not skl then return end
  local st = status
  if not st then
    local okSt, s = pcall(function() return skl:get_Status() end); if okSt then st = s end
  end
  if st and st._ItemBuff then
    local item = st._ItemBuff
    update_itembuff("Kairiki", item._Kairiki_Timer, item._Kairiki_MaxTime)
    update_itembuff("KairikiG", item._Kairiki_G_Timer, item._Kairiki_G_MaxTime)
    update_itembuff("KijinAmmo", item._KijinAmmo_Timer)
    update_itembuff("KijinPowder", item._KijinPowder_Timer, item._KijinPowder_MaxTime)
    update_itembuff("Nintai", item._Nintai_Timer, item._Nintai_MaxTime)
    update_itembuff("NintaiG", item._Nintai_G_Timer, item._Nintai_G_MaxTime)
    update_itembuff("KoukaAmmo", item._KoukaAmmo_Timer)
    update_itembuff("KoukaPowder", item._KoukaPowder_Timer, item._KoukaPowder_MaxTime)
    update_itembuff("DashJuice", item._DashJuice_Timer, item._DashJuice_MaxTime)
    update_itembuff("Immunizer", item._Immunizer_Timer, item._Immunizer_MaxTime)
    update_itembuff("HotDrink", item._HotDrink_Timer, item._HotDrink_MaxTime)
    update_itembuff("CoolerDrink", item._CoolerDrink_Timer, item._CoolerDrink_MaxTime)
    if item._KijinDrink then update_itembuff("KijinDrink", item._KijinDrink._Timer, item._KijinDrink._MaxTime) end
    if item._KijinDrink_G then update_itembuff("KijinDrinkG", item._KijinDrink_G._Timer, item._KijinDrink_G._MaxTime) end
    if item._KoukaDrink then update_itembuff("KoukaDrink", item._KoukaDrink._Timer, item._KoukaDrink._MaxTime) end
    if item._KoukaDrink_G then update_itembuff("KoukaDrinkG", item._KoukaDrink_G._Timer, item._KoukaDrink_G._MaxTime) end
  end
  if st and st._BadConditions and st._BadConditions._Frenzy then
    local frenzy = st._BadConditions._Frenzy
    local sid = 194
    local rec = ensure_skill(skl, sid)
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

-- =============================
-- Weapon States: Dual Blades Demon/Archdemon
-- =============================
local function get_hunter_character()
  local pm = sdk.get_managed_singleton and sdk.get_managed_singleton("app.PlayerManager") or nil
  if not pm then return nil end
  local info = pm:getMasterPlayer(); if not info then return nil end
  local chr = info:get_Character(); return chr
end

-- WeaponStateData declared in Globals

local function ensure_weapon_state(name, label)
  local rec = WeaponStateData[name]
  if not rec then
    rec = { Name = name, Activated = false, Meter = nil, MeterLabel = label }
    WeaponStateData[name] = rec
  end
  if label and rec.MeterLabel ~= label then rec.MeterLabel = label end
  return rec
end

local function update_weapon_states()
  local chr = get_hunter_character(); if not chr then return end
  local okH, wpHdlr = pcall(function() return chr:get_WeaponHandling() end)
  if not okH or not wpHdlr then return end
  -- Only meaningful for Dual Blades (WeaponType 2). If not DB, clear states.
  local okWT, wtype = pcall(function() return chr:get_WeaponType() end)
  if not okWT or wtype ~= 2 then
    for _, rec in pairs(WeaponStateData) do rec.Activated = false end
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
  local recD = ensure_weapon_state("Demon Mode", "Stamina")
  recD.Activated = isDemon; recD.Meter = staminaPct
  local recA = ensure_weapon_state("Archdemon", "Gauge")
  recA.Activated = isArch; recA.Meter = gaugePct
end

-- =============================
-- Hooks
-- =============================
local function onBeginSkillLog(args)
  local skill_id = extract_skill_id_from_args(args); if not skill_id then return end
  local name = resolve_skill_name(skill_id, 1)
  running_skills[skill_id] = true
  if battle_active and timing_starts[skill_id] == nil then timing_starts[skill_id] = now() end
  logDebug(string.format("Skill on:  ID=%d, Name=%s", skill_id, name))
end

local function onEndSkillLog(args)
  local skill_id = extract_skill_id_from_args(args)
  if not skill_id then
    logDebug("endSkillLog: missing skill id"); return
  end
  local added = 0.0
  if timing_starts[skill_id] then
    added = now() - timing_starts[skill_id]
    if added < 0 then added = 0 end
    skill_uptime[skill_id] = (skill_uptime[skill_id] or 0) + added
    timing_starts[skill_id] = nil
  end
  running_skills[skill_id] = nil
  local name = resolve_skill_name(skill_id, 1)
  if added > 0 then
    logDebug(string.format("Skill off: ID=%d, Name=%s, +%.3fs", skill_id, name, added))
  else
    logDebug(
      string.format("Skill off: ID=%d, Name=%s", skill_id, name))
  end
end

local function onQuestEnter()
  battle_active = false; battle_start_time = 0.0; battle_total = 0.0
  skill_uptime = {}; running_skills = {}; timing_starts = {}
  item_uptime = {}; item_timing_starts = {}; flag_uptime = {}; flag_timing_starts = {}
  weapon_uptime = {}; weapon_timing_starts = {}; WeaponStateData = {}
end

-- Manual reset for session stats
local function reset_all()
  onQuestEnter()
  -- Clear transient activation/timers so UI reflects a clean slate
  for _, rec in pairs(StatusFlagData or {}) do
    rec.Activated = false; rec.Timer = 0
  end
  for _, rec in pairs(ItemBuffData or {}) do
    rec.Activated = false; rec.Timer = 0
  end
end

registerHook(FN_BeginSkillLog, onBeginSkillLog, nil)
registerHook(FN_EndSkillLog, onEndSkillLog, nil)
registerHook(FN_QuestEnter, onQuestEnter, nil)
registerHook(FN_SetStatusBuff, onSetStatusBuff, nil)

-- =============================
-- UI
-- =============================
local function drawUptimeWindow()
  local openFlag = { true }
  -- Always call end_window() after begin_window(), even if collapsed
  local window_open = imgui.begin_window("Skill Uptime Tracker", openFlag, 64)
  if window_open then
    -- Push default font if available so this window matches REFramework UI settings
    local pushed_font = false
    local font = ensure_default_font()
    if font then
      imgui.push_font(font); pushed_font = true
    end
    local elapsed = get_battle_elapsed()
    local in_battle = IsInBattle()
    imgui.text(string.format("In Battle time: %s ", fmt_mss_hh(elapsed)))
    imgui.same_line(); if in_battle then
      imgui.text_colored("(active)", COLOR_GREEN)
    else
      imgui.text_colored(
        "(inactive)", COLOR_RED)
    end
    imgui.spacing()

    local tableFlags = imgui.TableFlags.Borders
    local epsilon = 0.0005

    -- Skills table
    if showTable_Skills then
      local id_set = {}
      for id, sec in pairs(skill_uptime) do if (sec or 0) > epsilon then id_set[id] = true end end
      for id, start_t in pairs(timing_starts) do
        if start_t then
          local live = now() - start_t; if live and live > epsilon then id_set[id] = true end
        end
      end
      local ids = {}; for id, _ in pairs(id_set) do table.insert(ids, id) end; table.sort(ids)
      imgui.text_colored("> Skills (" .. #ids .. ")", COLOR_BLUE)
      if imgui.begin_table("skill_uptime_table", 5, tableFlags) then
        imgui.table_setup_column("Name")
        imgui.table_setup_column("Uptime")
        imgui.table_setup_column("Uptime (%)")
        imgui.table_setup_column("Active Time")
        imgui.table_setup_column("State")
        imgui.table_headers_row()
        for _, id in ipairs(ids) do
          local base = skill_uptime[id] or 0.0
          local live = 0.0
          if timing_starts[id] then
            live = now() - timing_starts[id]; if live < 0 then live = 0 end
          end
          local total = base + live
          if total > epsilon then
            local name = skill_name_cache[id] or resolve_skill_name(id, 1); skill_name_cache[id] = name
            local pct = (elapsed > 0) and (total / elapsed * 100.0) or 0.0
            imgui.table_next_row()
            imgui.table_set_column_index(0); imgui.text(name)
            imgui.table_set_column_index(1); imgui.text(fmt_mss_hh(total))
            imgui.table_set_column_index(2); imgui.text(string.format("%.2f%%", pct))
            local s = StatusData.SkillData[id]
            imgui.table_set_column_index(3); imgui.text(fmt_time_pair(s and s.Timer, s and s.MaxTimer))
            imgui.table_set_column_index(4); if timing_starts[id] ~= nil then
              imgui.text_colored("active", COLOR_GREEN)
            else
              imgui.text_colored("inactive", COLOR_RED)
            end
          end
        end
        imgui.end_table()
      end
    end

    imgui.spacing()
    -- Item Buffs table
    if showTable_Items then
      local itemRows = build_rows(ItemBuffData, item_uptime, item_timing_starts, epsilon,
        function(key, rec) return rec.Name or tostring(key) end)
      table.sort(itemRows, function(a, b) return a.name < b.name end)
      imgui.text_colored("> Item Buffs (" .. #itemRows .. ")", COLOR_BLUE)
      if imgui.begin_table("item_uptime_table", 5, tableFlags) then
        imgui.table_setup_column("Name")
        imgui.table_setup_column("Uptime")
        imgui.table_setup_column("Uptime (%)")
        imgui.table_setup_column("Active Time")
        imgui.table_setup_column("State")
        imgui.table_headers_row()
        for _, row in ipairs(itemRows) do
          local pct = (elapsed > 0) and (row.total / elapsed * 100.0) or 0.0
          imgui.table_next_row()
          imgui.table_set_column_index(0); imgui.text(row.name)
          imgui.table_set_column_index(1); imgui.text(fmt_mss_hh(row.total))
          imgui.table_set_column_index(2); imgui.text(string.format("%.2f%%", pct))
          imgui.table_set_column_index(3); imgui.text(fmt_time_pair(row.rec and row.rec.Timer,
            row.rec and row.rec.MaxTimer))
          imgui.table_set_column_index(4); if row.active then
            imgui.text_colored("active", COLOR_GREEN)
          else
            imgui
                .text_colored("inactive", COLOR_RED)
          end
        end
        imgui.end_table()
      end
    end

    imgui.spacing()
    -- Weapon States (Dual Blades)
    if showTable_Weapons then
      local rows = build_rows(WeaponStateData, weapon_uptime, weapon_timing_starts, epsilon,
        function(key, rec) return rec.Name or tostring(key) end)
      table.sort(rows, function(a, b) return a.name < b.name end)
      imgui.text_colored("> Weapon States (" .. #rows .. ")", COLOR_BLUE)
      if imgui.begin_table("weapon_states_table", 5, tableFlags) then
        imgui.table_setup_column("Name")
        imgui.table_setup_column("Uptime")
        imgui.table_setup_column("Uptime (%)")
        imgui.table_setup_column("Active Meter")
        imgui.table_setup_column("State")
        imgui.table_headers_row()
        for _, row in ipairs(rows) do
          local pct = (elapsed > 0) and (row.total / elapsed * 100.0) or 0.0
          local meterStr = fmt_pct_label(row.rec and row.rec.MeterLabel, row.rec and row.rec.Meter)
          imgui.table_next_row()
          imgui.table_set_column_index(0); imgui.text(row.name)
          imgui.table_set_column_index(1); imgui.text(fmt_mss_hh(row.total))
          imgui.table_set_column_index(2); imgui.text(string.format("%.2f%%", pct))
          imgui.table_set_column_index(3); imgui.text(meterStr)
          imgui.table_set_column_index(4); if row.active then
            imgui.text_colored("active", COLOR_GREEN)
          else
            imgui
                .text_colored("inactive", COLOR_RED)
          end
        end
        imgui.end_table()
      end
    end

    imgui.spacing()
    -- Status Flags table
    if showTable_Flags then
      local flagRows = build_rows(StatusFlagData, flag_uptime, flag_timing_starts, epsilon,
        function(fid, rec) return rec.Name or ("FLAG " .. tostring(fid)) end)
      table.sort(flagRows, function(a, b) return a.key < b.key end)
      imgui.text_colored("> Status Flags (" .. #flagRows .. ")", COLOR_BLUE)
      if imgui.begin_table("flag_uptime_table", 5, tableFlags) then
        imgui.table_setup_column("Name")
        imgui.table_setup_column("Uptime")
        imgui.table_setup_column("Uptime (%)")
        imgui.table_setup_column("Active Time")
        imgui.table_setup_column("State")
        imgui.table_headers_row()
        for _, row in ipairs(flagRows) do
          local pct = (elapsed > 0) and (row.total / elapsed * 100.0) or 0.0
          imgui.table_next_row()
          imgui.table_set_column_index(0); imgui.text(row.name)
          imgui.table_set_column_index(1); imgui.text(fmt_mss_hh(row.total))
          imgui.table_set_column_index(2); imgui.text(string.format("%.2f%%", pct))
          imgui.table_set_column_index(3); imgui.text(fmt_time_pair(row.rec and row.rec.Timer,
            row.rec and row.rec.MaxTimer))
          imgui.table_set_column_index(4); if row.active then
            imgui.text_colored("active", COLOR_GREEN)
          else
            imgui
                .text_colored("inactive", COLOR_RED)
          end
        end
        imgui.end_table()
      end
    end
    if pushed_font then imgui.pop_font() end
    imgui.end_window()
  end
  if not openFlag[1] then showUptimeWindow = false end
end

-- UI entry
re.on_draw_ui(function()
  if imgui.tree_node("Skill Uptime Tracker") then
    imgui.begin_rect()
    imgui.text("Displays the uptime of skills, item buffs, and status flags while in battle.")
    imgui.spacing()
    local _
    -- Tracking Strategy dropdown (reduced width)
    imgui.push_item_width(180)
    local changed
    changed, trackingStrategyIndex = imgui.combo("Tracking Strategy", trackingStrategyIndex or 1,
      TRACKING_STRATEGY_OPTIONS)
    imgui.pop_item_width()
    -- (Currently only one option; reserved for future strategies.)
    _, showTable_Skills = imgui.checkbox("Skills", showTable_Skills)
    -- experimental stuff
    local col_text = (imgui.Col and imgui.Col.Text) or 0
    imgui.push_style_color(col_text, COLOR_RED)
    local exp_open = imgui.tree_node("Experimental")
    imgui.pop_style_color(1)
    if exp_open then
      _, showTable_Items = imgui.checkbox("Item Buffs", showTable_Items)
      _, showTable_Weapons = imgui.checkbox("Weapon States (only DBs atm)", showTable_Weapons)
      _, showTable_Flags = imgui.checkbox("Status Flags", showTable_Flags)
      imgui.tree_pop()
    end
    -- imgui.same_line()
    -- if imgui.button("Dump Flags to Console") then dump_all_flags() end
    -- imgui.same_line()
    local buttonText = showUptimeWindow and "Close Skill Uptime Overview" or "Show Skill Uptime Overview"
    if imgui.button(buttonText) then showUptimeWindow = not showUptimeWindow end
    imgui.same_line()
    if imgui.button("Reset Uptime") then reset_all() end
    imgui.spacing()
    imgui.end_rect(2)
    imgui.tree_pop()
  end
end)

-- Frame loop
re.on_frame(function()
  if showUptimeWindow then drawUptimeWindow() end
  tick_battle()
  local skl, _, status = update_active_skills()
  update_items_and_frenzy(skl, status)
  update_weapon_states()
  tick_status_flags()
  local in_battle = battle_active
  local tnow = now()
  -- Accumulate uptimes via helper
  accumulate_uptime(ItemBuffData, item_timing_starts, item_uptime, in_battle, tnow)
  accumulate_uptime(StatusFlagData, flag_timing_starts, flag_uptime, in_battle, tnow)
  accumulate_uptime(WeaponStateData, weapon_timing_starts, weapon_uptime, in_battle, tnow)
end)
