--
-- Skill Uptime Tracker
--
-- Props to the authors of CatLib and mhwilds_overlay, I used their code as a reference.
--
-- @author https://github.com/thieleju
--
---@diagnostic disable: undefined-global, undefined-doc-name, undefined-field

-- ============================================================================
-- Type Definitions
-- ============================================================================
local TD_MessageUtil                  = sdk.find_type_definition("app.MessageUtil")
local TD_HunterSkillDef               = sdk.find_type_definition("app.HunterSkillDef")
local TD_GuiMessage                   = sdk.find_type_definition("via.gui.message")
local TD_SkillEnum                    = sdk.find_type_definition("app.HunterDef.Skill")
local TD_SkillParamInfo               = sdk.find_type_definition("app.cHunterSkillParamInfo")
local TD_QuestPlaying                 = sdk.find_type_definition("app.cQuestPlaying")
local TD_App                          = sdk.find_type_definition("via.Application")
local TD_HunterCharacter              = sdk.find_type_definition("app.HunterCharacter")
local TD_EnemyCharacter               = sdk.find_type_definition("app.EnemyCharacter")
local TD_cHunterSkill                 = sdk.find_type_definition("app.cHunterSkill")
local TD_SkillParamInfo_cInfo         = sdk.find_type_definition("app.cHunterSkillParamInfo.cInfo")
local TD_HunterSkillUpdater           = sdk.find_type_definition("app.HunterSkillUpdater")
local TD_ItemDef                      = sdk.find_type_definition("app.ItemDef")
local TD_ActionGuideID                = sdk.find_type_definition("app.ActionGuideID")

-- ============================================================================
-- Type Constants
-- ============================================================================
local TYPE_EnemyCharacter             = sdk.typeof(TD_EnemyCharacter:get_full_name())
local TYPE_HunterCharacter            = sdk.typeof(TD_HunterCharacter:get_full_name())

-- ============================================================================
-- Method Definitions
-- ============================================================================
local FN_GetSkillName                 =
    TD_MessageUtil:get_method("getHunterSkillName(app.HunterDef.Skill)") or nil
local FN_GetLeveledSkillName          =
    TD_MessageUtil:get_method("getHunterSkillNameChatLog(app.HunterDef.Skill, System.Int32)") or nil
local FN_ConvertSkillToGroup          =
    TD_HunterSkillDef:get_method("convertSkillToGroupSkill(app.HunterDef.Skill)") or nil
local FN_GetMsg                       = TD_GuiMessage:get_method("get(System.Guid)") or nil
local FN_GetMsgLang                   = TD_GuiMessage:get_method("get(System.Guid, via.Language)") or nil
local FN_QuestEnter                   = TD_QuestPlaying:get_method("enter()") or nil
local FN_Now                          = TD_App:get_method("get_UpTimeSecond") or nil
local FN_SetStatusBuff                =
    TD_HunterCharacter:get_method("setStatusBuff(app.HunterDef.STATUS_FLAG, System.Single, System.Single)") or nil
local FN_HunterHitPost                = TD_HunterCharacter:get_method("evHit_AttackPostProcess(app.HitInfo)") or nil
local FN_SkillUpdaterLateUpdate       = TD_HunterSkillUpdater and TD_HunterSkillUpdater:get_method("lateUpdate()") or nil
local FN_GetSkillLevel2               = TD_cHunterSkill:get_method(
  "getSkillLevel(app.HunterDef.Skill, System.Boolean, System.Boolean)") or nil
local FN_GetItemNameRaw               = TD_ItemDef and TD_ItemDef:get_method("RawName(app.ItemDef.ID)") or nil

-- Resonance tracking methods
local FN_BeginResonanceNear           = TD_SkillParamInfo:get_method("beginResonanceNear") or nil
local FN_BeginResonanceFar            = TD_SkillParamInfo:get_method("beginResonanceFar") or nil
local FN_BeginResonanceNearCriticalUp = TD_SkillParamInfo:get_method("beginResonanceNearCriticalUp") or nil
local FN_BeginResonanceFarAttackUp    = TD_SkillParamInfo:get_method("beginResonanceFarAttackUp") or nil

-- ============================================================================
-- Field Definitions
-- ============================================================================
local FLD_FullCharge                  = TD_SkillParamInfo:get_field("_IsActiveFullCharge") or nil
local FLD_Konshin                     = TD_SkillParamInfo:get_field("_IsActiveKonshin") or nil
local FLD_KonshinUse                  = TD_SkillParamInfo:get_field("_KonshinStaminaUseTime") or nil
local FLD_Challenger                  = TD_SkillParamInfo:get_field("_IsActiveChallenger") or nil
local FLD_Info_Skill                  = TD_SkillParamInfo_cInfo and TD_SkillParamInfo_cInfo:get_field("_Skill") or nil
local FLD_Info_Timer                  = TD_SkillParamInfo_cInfo and TD_SkillParamInfo_cInfo:get_field("_Timer") or nil
local FLD_Info_MaxTimer               = TD_SkillParamInfo_cInfo and TD_SkillParamInfo_cInfo:get_field("_MaxTimer") or nil
local SkillIDMax                      = TD_SkillEnum:get_field("MAX"):get_data() or nil

-- ============================================================================
-- Configuration and State Management
-- ============================================================================
local config                          = {
  openWindow = false,
  strategyIndex = 1,
  show = { skills = true, items = false, flags = false, weapons = false, movedamage = true },
  columns = { primary = true, percent = true, active = true, state = true },
  debug = false,
  hideButtons = false,
}

-- Module namespace
local SkillUptime                     = {
  UI       = {
    defaultFont = nil,
    open = false,
    tables = { Skills = true, Items = false, Flags = false, Weapons = false, MoveDamage = true },
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
      -- All cInfo fields from cHunterSkillParamInfo that contain skill data
      "_ToishiBoostInfo",         -- Sharpness Management
      "_RebellionInfo",           -- Rebellion
      "_ElementConvertInfo",      -- Elemental Absorption
      "_RyukiInfo",               -- Convert Element
      "_MusclemanInfo",           -- Strongman
      "_BarbarianInfo",           -- Barbaric Feast
      "_PowerAwakeInfo",          -- Power Awakening
      "_RyunyuInfo",              -- Dragon Milk Activation
      "_ContinuousAttackInfo",    -- Continuous Attack
      "_GuardianAreaInfo",        -- Guardian Area
      "_ResentmentInfo",          -- Resentment
      "_KnightInfo",              -- Offensive Guard
      "_MoraleInfo",              -- Morale
      "_BattoWazaInfo",           -- Draw Attack
      "_HunkiInfo",               -- Poison Enhancement
      "_SlidingPowerUpInfo",      -- Sliding Power Up
      "_CounterAttackInfo",       -- Counterstrike
      "_DisasterInfo",            -- Disaster (Blessing in Disguise)
      "_MantleStrengtheningInfo", -- Mantle Strengthening
      "_BegindAttackInfo",        -- Rush Attack
      "_YellInfo",                -- Yell
      "_TechnicalAttack_Info",    -- Technical Attack
      "_DischargeInfo",           -- Discharge
      "_IamCoalMinerInfo",        -- Coal Miner
      "_CaptureMasterInfo",       -- Capture Master
      "_HagitoriMasterInfo",      -- Hagitori Master
      "_LuckInfo",                -- Luck
      "_SpringEventInfo",         -- Spring Event
      "_SummerEventInfo",         -- Summer Event
      "_AutumnEventInfo",         -- Autumn Event
      "_DarkBladeInfo",           -- Dark Blade
      "_DarkWaveInfo",            -- Dark Wave
      "_CooperationInfo",         -- Cooperation
      "_ShieldOptionInfo",        -- Shield Option
      "_ResonanceInfo",           -- Resonance
    }
  },
  Status   = { SkillData = {} },
  Items    = {
    data = {},
    timing_starts = {},
    uptime = {},
    hits_up = {},
    name_cache = {},
    ItemIDs = {
      Kairiki = 125,
      KairikiG = 168,
      Nintai = 126,
      NintaiG = 171,
      KijinPowder = 175,
      KoukaPowder = 176,
      KijinAmmo = 412,
      KoukaAmmo = 413,
      DashJuice = 163,
      Immunizer = 164,
      HotDrink = 166,
      CoolerDrink = 165,
      KijinDrink = 167,
      KijinDrinkG = 169,
      KoukaDrink = 170,
      KoukaDrinkG = 172,
    },
  },
  Weapons  = { data = {}, timing_starts = {}, uptime = {}, hits_up = {} },
  -- Per-move damage tracker (player only, boss hits)
  Moves    = {
    damage = {},
    hits = {},
    names = {},
    total = 0,
    lastWeaponType = nil,
    last_hit_time = {},     -- moveKey -> last timestamp of a hit
    active_start = {},      -- moveKey -> segment start time (if currently active)
    active_accum = {},      -- moveKey -> accumulated active seconds
    colIds = {},            -- moveKey -> collision id
    wpTypes = {},           -- moveKey -> weapon type
    action_name_cache = {}, -- ActionGuideID -> localized name
    action_names_inited = false,
    wmap = {                -- weapon type short codes
      [0] = "GS",
      [1] = "SNS",
      [2] = "DB",
      [3] = "LS",
      [4] = "Ham",
      [5] = "HH",
      [6] = "Lan",
      [7] = "GL",
      [8] = "SA",
      [9] = "CB",
      [10] = "IG",
      [11] = "Bow",
      [12] = "HBG",
      [13] = "LBG",
      [14] = "Tz",
    },
    maxHit = {}, -- moveKey -> highest single hit damage
  },
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
    MOVE_ACTIVE_GAP = 2.0,       -- seconds; gap threshold to close an activity segment for a move
    MOVE_TABLE_MAX_HEIGHT = 260, -- pixels; max height for Move Damage table before scrolling
    EPSILON = 0.0005,
  },
  -- Ensure sub-namespaces exist before assigning functions
  Util     = {},
  Config   = {},
  Core     = {},
  Hooks    = {},
}

-- ============================================================================
-- Initialization & Data Tables
-- ============================================================================
for i, s in ipairs(SkillUptime.Strategy.defs) do SkillUptime.Strategy.labels[i] = s.label end

-- Singleton cache
local _SINGLETON_CACHE = {}

-- Status flags mapping
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

-- ============================================================================
-- Utility Functions
-- ============================================================================
-- Helper function to get current time (shorthand for SkillUptime.Core.now())
local function now()
  return SkillUptime.Core.now()
end

SkillUptime.Util.logDebug = function(msg)
  if config and config.debug then log.debug(SkillUptime.Const.PREFIX .. tostring(msg)) end
end

SkillUptime.Util.logError = function(msg) log.error(SkillUptime.Const.PREFIX .. tostring(msg)) end

-- Shell label mapping (gunlance shells)
local function _build_shell_label_map()
  return {
    [0] = "Normal Lv1",
    [1] = "Normal Lv2",
    [20] = "Normal Lv3",
    [9] = "Pierce Lv1",
    [5] = "Pierce Lv2",
    [6] = "Pierce Lv3",
    [11] = "Spread Lv1",
    [13] = "Spread Lv2",
    [12] = "Spread Lv3",
    [23] = "Wyvern Fire",
    [29] = "Shelling Burst",
    [30] = "Shelling Burst",
    [38] = "Focus",
    [58] = "Focus2",
    [40] = "Mine",
    [21] = "Roar",
    [19] = "Roar2",
    [16] = "HeatCnt",
    [26] = "HeatCnt2",
    [14] = "HeatEgg",
  }
end

-- Initialize action name lookup from ActionGuideID
SkillUptime.Moves.init_action_names = function()
  if SkillUptime.Moves.action_names_inited then return end
  SkillUptime.Moves.action_names_inited = true

  local mgr = SkillUptime.Core.GetSingleton("app.VariousDataManager")
  if not mgr or not mgr._Setting or not mgr._Setting._ActionGuideSetting then return end

  local dataset = mgr._Setting._ActionGuideSetting
  if not TD_ActionGuideID then return end

  -- Iterate through all weapon types (0-13)
  for wpType = 0, 13 do
    local key = string.format("_ActionGuideName_Wp%02d", wpType)
    local data = dataset[key]
    if data then
      local okValues, values = pcall(function() return data:getValues() end)
      if okValues and values then
        local okEach, _ = pcall(function()
          for i = 0, values:get_Count() - 1 do
            local cData = values:get_Item(i)
            if cData then
              local actionFixedID = cData._Action
              if actionFixedID and cData._ActionName then
                local name = SkillUptime.Util.get_localized_text(cData._ActionName)
                if SkillUptime.Util.is_valid_name(name) then
                  SkillUptime.Moves.action_name_cache[actionFixedID] = name
                end
              end
            end
          end
        end)
        if not okEach then
          SkillUptime.Util.logDebug(string.format("Failed to iterate action names for weapon %d", wpType))
        end
      end
    end
  end
  SkillUptime.Util.logDebug(string.format("Initialized %d action names",
    SkillUptime.Util.table_length(SkillUptime.Moves.action_name_cache)))
end

SkillUptime.Moves.get_action_name = function(hitInfo)
  if not hitInfo then return nil end

  local playerMgr = SkillUptime.Core.GetSingleton("app.PlayerManager")
  if not playerMgr then return nil end

  local okMaster, masterInfo = pcall(function() return playerMgr:getMasterPlayer() end)
  if not okMaster or not masterInfo then return nil end

  local okChar, hunter = pcall(function() return masterInfo:get_Character() end)
  if not okChar or not hunter then return nil end

  local okWT, wpType = pcall(function() return hunter:get_WeaponType() end)
  if not okWT then return nil end

  -- Skip bowguns for action naming (their indices collide with shells)
  if wpType == 8 or wpType == 9 then return nil end
  -- Check for gunlance shells
  local okOwner, owner = pcall(function() return hitInfo:get_AttackHit()._Owner end)
  if okOwner and owner and owner.get_Name then
    local ownerName = owner:get_Name()
    if ownerName and (ownerName:find("WpGunShell", 1, true) or ownerName:find("WpGunConstShell", 1, true)) then
      if not SkillUptime.Moves._gunShellNames then
        SkillUptime.Moves._gunShellNames = _build_shell_label_map()
      end
      local attackIndex = hitInfo:get_AttackIndex()._Index
      return SkillUptime.Moves._gunShellNames[attackIndex]
    end
  end

  return nil
end

-- Get descriptive move name from hit info
SkillUptime.Moves.resolve_name = function(hitInfo)
  if not hitInfo then return "Unknown" end

  -- Initialize action names on first use
  SkillUptime.Moves.init_action_names()

  -- Try to get action name (shells, etc.)
  local actionName = SkillUptime.Moves.get_action_name(hitInfo)
  if actionName and actionName ~= '' then return actionName end

  -- Try to get action from hunter and check for ActionGuideID
  local ok, owner = pcall(function() return hitInfo:getActualAttackOwner() end)
  if ok and owner and owner.getComponent then
    local okHC, hunter = pcall(function() return owner:getComponent(TYPE_HunterCharacter) end)
    if okHC and hunter then
      local okBAC, controller = pcall(function() return hunter:get_BaseActionController() end)
      if okBAC and controller then
        local okAct, action = pcall(function() return controller:get_CurrentAction() end)
        if okAct and action then
          -- Try to get localized name from ActionGuideID
          local okGuide, guideID = pcall(function() return action._ActionGuideID end)
          if okGuide and guideID and guideID ~= -1 then
            local localizedName = SkillUptime.Moves.action_name_cache[guideID]
            if localizedName then
              return localizedName
            end
          end

          -- Fallback: get action class name
          local okTD, typeDef = pcall(function() return action:get_type_definition() end)
          if okTD and typeDef then
            local okName, className = pcall(function() return typeDef:get_name() end)
            if okName and className and className ~= '' then
              return className:gsub('^cAct', '')
            end
          end
        end
      end
    end
  end

  -- Fallback: attack index
  local okAtk, atkIdx = pcall(function() return hitInfo:get_AttackIndex() end)
  if okAtk and atkIdx then
    return string.format("Atk %d/%d", atkIdx._Resource or -1, atkIdx._Index or -1)
  end

  return "Unknown"
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
  SkillUptime.UI.tables.MoveDamage = (config.show and config.show.movedamage ~= false)
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
    config.show.movedamage = (loaded.show.movedamage ~= false)
  end
  if type(loaded.columns) == "table" then
    config.columns.primary = (loaded.columns.primary ~= false)
    config.columns.percent = (loaded.columns.percent ~= false)
    config.columns.active = (loaded.columns.active ~= false)
    config.columns.state = (loaded.columns.state ~= false)
  end
  if type(loaded.debug) == "boolean" then config.debug = loaded.debug end
  if type(loaded.hideButtons) == "boolean" then config.hideButtons = loaded.hideButtons end
  -- transparency removed
  -- Apply loaded config immediately to UI state
  SkillUptime.Config.apply()
end

SkillUptime.Core.registerHook = function(method, pre, post)
  if not method then
    SkillUptime.Util.logError("registerHook called with nil method")
    return
  end
  local ok, err = pcall(function() sdk.hook(method, pre, post) end)
  if not ok then SkillUptime.Util.logError("Failed to hook method: " .. tostring(err)) end
end

-- Cached singleton access
SkillUptime.Core.GetSingleton = function(name)
  if _SINGLETON_CACHE[name] ~= nil then
    return _SINGLETON_CACHE[name] or nil
  end

  local ok, singleton = pcall(function() return sdk.get_managed_singleton(name) end)
  _SINGLETON_CACHE[name] = (ok and singleton) or false
  return _SINGLETON_CACHE[name] or nil
end

SkillUptime.Core.now = function()
  return FN_Now and FN_Now:call(nil) or os.clock()
end

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
      live = SkillUptime.Core.now() - startTimes[key]; if live < 0 then live = 0 end
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

SkillUptime.Util.table_length = function(tbl)
  local count = 0
  for _ in pairs(tbl or {}) do count = count + 1 end
  return count
end

SkillUptime.Skills.resolve_name = function(skill_id, level)
  if not skill_id or skill_id < 0 then return "[INVALID_SKILL]" end

  -- Custom names for Resonance tracking (custom skill IDs) - check BEFORE SkillIDMax validation
  if skill_id == 999001 then return "Resonance Near" end
  if skill_id == 999002 then return "Resonance Far" end
  if skill_id == 999003 then return "Resonance Near+Critical" end
  if skill_id == 999004 then return "Resonance Far+Attack" end

  if SkillIDMax and skill_id >= SkillIDMax then return "[INVALID_SKILL]" end

  -- Check cache first (with level key if provided)
  local cache_key = level and (skill_id .. "_L" .. level) or skill_id
  if SkillUptime.Skills.name_cache[cache_key] then
    return SkillUptime.Skills.name_cache[cache_key]
  end

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
  if name then
    SkillUptime.Skills.name_cache[cache_key] = name
    return name
  end

  if FN_ConvertSkillToGroup then
    local group_skill = FN_ConvertSkillToGroup:call(nil, skill_id)
    if group_skill and group_skill > 0 and group_skill ~= skill_id then
      name = try(group_skill, level)
      if name then
        SkillUptime.Skills.name_cache[cache_key] = name
        return name
      end
    end
  end

  if not name and FN_GetLeveledSkillName then
    for lv = 1, 4 do
      name = try(skill_id, lv)
      if name then
        SkillUptime.Skills.name_cache[cache_key] = name
        return name
      end
    end
  end

  local fallback = string.format("Skill %d", skill_id)
  SkillUptime.Skills.name_cache[cache_key] = fallback
  return fallback
end

SkillUptime.Skills.extract_skill_id_from_args = function(args)
  -- Try a wider range to be resilient to signature shifts across game updates
  for i = 1, 12 do
    local ok, id = pcall(function() return sdk.to_int64(args[i]) end)
    if ok and id ~= nil and id >= 0 and (not SkillIDMax or id < SkillIDMax) then return id end
  end
  return nil
end

SkillUptime.Items.resolve_name = function(key)
  -- Check cache first
  if SkillUptime.Items.name_cache[key] then
    return SkillUptime.Items.name_cache[key]
  end

  -- Get ItemDef ID
  local itemId = SkillUptime.Items.ItemIDs[key]
  if not itemId or itemId < 0 then
    SkillUptime.Util.logDebug(string.format("Item %s: No ItemID found, using key", key))
    SkillUptime.Items.name_cache[key] = key
    return key
  end

  -- Try to get localized name
  if FN_GetItemNameRaw then
    local ok, guid = pcall(function() return FN_GetItemNameRaw:call(nil, itemId) end)
    if ok and guid then
      local name = SkillUptime.Util.get_localized_text(guid)
      if SkillUptime.Util.is_valid_name(name) then
        SkillUptime.Util.logDebug(string.format("Item %s (ID %d): Resolved to '%s'", key, itemId, name))
        SkillUptime.Items.name_cache[key] = name
        return name
      else
        SkillUptime.Util.logDebug(string.format("Item %s (ID %d): Invalid name '%s', using key", key, itemId,
          tostring(name)))
      end
    else
      SkillUptime.Util.logDebug(string.format("Item %s (ID %d): Failed to get GUID", key, itemId))
    end
  else
    SkillUptime.Util.logDebug("FN_GetItemNameRaw not available")
  end

  -- Fallback to key
  SkillUptime.Items.name_cache[key] = key
  return key
end

SkillUptime.Core.IsQuestFinishing = function()
  local mm = SkillUptime.Core.GetSingleton("app.MissionManager")
  if not mm then return false end

  local isActive = false
  local okActive, vActive = pcall(function() return mm:get_IsActiveQuest() end)
  if okActive then
    isActive = vActive and true or false
  end

  local isPlaying = false
  local okPlaying, vPlaying = pcall(function() return mm:get_IsPlayingQuest() end)
  if okPlaying then
    isPlaying = vPlaying and true or false
  end

  return isActive and (not isPlaying)
end

SkillUptime.Core.IsInBattle = function()
  if SkillUptime.Core.IsQuestFinishing() then return false end
  local soundMgr = SkillUptime.Core.GetSingleton("app.SoundMusicManager")
  if not soundMgr then return false end

  -- Get BattleMusicManager directly using get_BattleMusic() method
  local ok, battleMgr = pcall(function() return soundMgr:get_BattleMusic() end)
  if not ok or not battleMgr then return false end

  -- Check if battle music is playing
  local ok2, isBattle = pcall(function() return battleMgr:get_IsBattle() end)
  if ok2 and isBattle then return true end

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
        SkillUptime.Skills.timing_starts[id] = now()
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
    -- Try to get name from dynamic enum lookup first (these come from the game's enum)
    local enumName = SkillUptime.Flags.names[flagId]
    -- Fall back to hardcoded map if enum name not available
    local flagName = enumName or FLAGS_NAME_MAP[flagId]
    -- Final fallback to FLAG + ID
    if not flagName then
      flagName = "FLAG " .. tostring(flagId)
    end

    rec = {
      Name = flagName,
      Timer = 0,
      MaxTimer = 0,
      Activated = false,
      LastSeen = now()
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
  local t = SkillUptime.Core.now()
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
  local pm = SkillUptime.Core.GetSingleton("app.PlayerManager")
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

  -- Poll all skills from cInfo array in _SkillData
  if status and status._SkillData then
    local skillDataArray = status._SkillData
    local count = skillDataArray:get_Count()

    for i = 0, count - 1 do
      local info = skillDataArray[i]
      if info then
        SkillUptime.Skills.update_from_info(skl, info)
      end
    end
  end

  -- Poll named fields that are separate cInfo objects (not in _SkillData array)
  for _, fname in ipairs(SkillUptime.Skills.InfoFields) do
    local fld = TD_SkillParamInfo and TD_SkillParamInfo:get_field(fname)
    if fld then
      local ok, infoObj = pcall(function() return fld:get_data(infos) end)
      if ok and infoObj then
        SkillUptime.Skills.update_from_info(skl, infoObj)
      end
    end
  end

  -- Special handling for Frenzy - Skill ID 194
  if status and status._BadConditions then
    local frenzy = status._BadConditions._Frenzy
    if frenzy and frenzy._IsActive then
      if frenzy._State == 2 then
        -- Overcome state - skill is active
        local timer = frenzy._DurationTimer or 0
        local maxTimer = frenzy._DurationTime or 0
        SkillUptime.Skills.update_boolean(skl, 194, timer > 0, timer, maxTimer)
      else
        -- Infect (State 0) or Outbreak/Failed (State 1) - skill inactive
        SkillUptime.Skills.update_boolean(skl, 194, false, 0, 0)
      end
    else
      SkillUptime.Skills.update_boolean(skl, 194, false, 0, 0)
    end
  end

  -- Special handling for boolean skills (no timer, just on/off)
  SkillUptime.Skills.update_boolean(skl, 59, FLD_Challenger and FLD_Challenger:get_data(infos), 0, 0) -- Agitator
  SkillUptime.Skills.update_boolean(skl, 60, FLD_FullCharge and FLD_FullCharge:get_data(infos), 0, 0) -- Maximum Might

  -- Maximum Might / Konshin - Skill ID 65
  local isKon = FLD_Konshin and FLD_Konshin:get_data(infos)
  local useT = FLD_KonshinUse and (FLD_KonshinUse:get_data(infos) or 0) or 0
  if isKon then
    SkillUptime.Skills.update_boolean(skl, 65, true, math.max(0, 2 - useT), 2)
  else
    SkillUptime.Skills.update_boolean(skl, 65, false, 0, 0)
  end

  -- Adrenaline Rush - Skill ID 101 (Low HP attack boost)
  local isAdrenaline = infos and infos._IsAdrenalineRush
  if isAdrenaline ~= nil then
    SkillUptime.Skills.update_boolean(skl, 101, isAdrenaline, 0, 0)
  end
  return skl, infos, status
end

-- Poll all skills and track uptime based on state changes (from polling)
SkillUptime.Skills.poll_skill_uptime = function(in_battle, tnow)
  if not in_battle then
    -- Not in battle - end all active skill timings
    for skill_id, start_time in pairs(SkillUptime.Skills.timing_starts or {}) do
      if start_time and not SkillUptime.Skills.is_excluded_skill(skill_id) then
        local added = tnow - start_time
        if added > 0 then
          SkillUptime.Skills.uptime[skill_id] = (SkillUptime.Skills.uptime[skill_id] or 0) + added
        end
        SkillUptime.Skills.timing_starts[skill_id] = nil
      end
    end
    return
  end

  -- In battle - check all skills for state changes
  for skill_id, skillRec in pairs(SkillUptime.Status.SkillData or {}) do
    if not SkillUptime.Skills.is_excluded_skill(skill_id) then
      local was_active = SkillUptime.Skills.timing_starts[skill_id] ~= nil
      local is_active = skillRec.Activated

      if is_active and not was_active then
        -- Skill just activated
        SkillUptime.Skills.timing_starts[skill_id] = tnow
        SkillUptime.Util.logDebug(string.format("Skill on:  ID=%d, Name=%s", skill_id,
          skillRec.Name or SkillUptime.Skills.resolve_name(skill_id, 1)))
      elseif not is_active and was_active then
        -- Skill just deactivated
        local added = tnow - SkillUptime.Skills.timing_starts[skill_id]
        if added > 0 then
          SkillUptime.Skills.uptime[skill_id] = (SkillUptime.Skills.uptime[skill_id] or 0) + added
        end
        SkillUptime.Skills.timing_starts[skill_id] = nil
        if added > 0 then
          SkillUptime.Util.logDebug(string.format("Skill off: ID=%d, Name=%s, +%.3fs", skill_id,
            skillRec.Name or SkillUptime.Skills.resolve_name(skill_id, 1), added))
        else
          SkillUptime.Util.logDebug(string.format("Skill off: ID=%d, Name=%s", skill_id,
            skillRec.Name or SkillUptime.Skills.resolve_name(skill_id, 1)))
        end
      end
    end
  end
end

-- Frenzy doesn't trigger beginSkill/endSkill hooks, so it needs special polling (DEPRECATED - now using polling for all skills)
SkillUptime.Skills.tick_frenzy_time_uptime = function(in_battle, tnow)
  -- This function is now deprecated as we poll all skills
  -- Keeping for compatibility but it does nothing
end

SkillUptime.Items.ensure_item = function(name)
  local rec = SkillUptime.Items.data[name]
  if not rec then
    local displayName = SkillUptime.Items.resolve_name(name)
    rec = { Name = displayName, Timer = 0, MaxTimer = 0, Activated = false }
    SkillUptime.Items.data[name] = rec
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
  -- SkillUptime.Util.logDebug("ItemBuff : " .. tostring(status))
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

-- ============================================================================
-- Game Event Hooks
-- ============================================================================

-- Resonance tracking hooks
-- Resonance is a set bonus skill that alternates between Near (Affinity boost) and Far (Attack boost)
-- These functions are called continuously while active, so we need to track state changes only

-- Helper function to end all resonance states when switching types
local function end_all_resonance_states()
  local resonance_ids = { 999001, 999002, 999003, 999004 }
  local now = SkillUptime.Core.now()

  for _, skill_id in ipairs(resonance_ids) do
    if SkillUptime.Skills.timing_starts[skill_id] then
      local added = now - SkillUptime.Skills.timing_starts[skill_id]
      if added > 0 then
        SkillUptime.Skills.uptime[skill_id] = (SkillUptime.Skills.uptime[skill_id] or 0) + added
      end
      SkillUptime.Skills.timing_starts[skill_id] = nil
    end
    SkillUptime.Skills.running[skill_id] = nil

    local skillRec = SkillUptime.Skills.ensure_skill(nil, skill_id)
    if skillRec and skillRec.Activated then
      skillRec.Activated = false
      if skillRec.ActivationTime then
        local duration = now - skillRec.ActivationTime
        if duration > (skillRec.MaxTimer or 0) then
          skillRec.MaxTimer = duration
        end
        skillRec.ActivationTime = nil
      end
      skillRec.Timer = 0
    end
  end
end

SkillUptime.Hooks.onResonanceNear = function(args)
  local skill_id = 999001 -- Custom ID for Resonance Near
  -- Only activate if not already running
  if not SkillUptime.Skills.running[skill_id] then
    end_all_resonance_states() -- End other resonance states first
    local now = SkillUptime.Core.now()
    SkillUptime.Skills.running[skill_id] = true
    SkillUptime.Skills.timing_starts[skill_id] = now
    local skillRec = SkillUptime.Skills.ensure_skill(nil, skill_id)
    if skillRec then
      skillRec.Activated = true
      skillRec.ActivationTime = now
    end
    SkillUptime.Util.logDebug("Resonance Near activated (Affinity boost)")
  end
end

SkillUptime.Hooks.onResonanceFar = function(args)
  local skill_id = 999002 -- Custom ID for Resonance Far
  -- Only activate if not already running
  if not SkillUptime.Skills.running[skill_id] then
    end_all_resonance_states() -- End other resonance states first
    local now = SkillUptime.Core.now()
    SkillUptime.Skills.running[skill_id] = true
    SkillUptime.Skills.timing_starts[skill_id] = now
    local skillRec = SkillUptime.Skills.ensure_skill(nil, skill_id)
    if skillRec then
      skillRec.Activated = true
      skillRec.ActivationTime = now
    end
    SkillUptime.Util.logDebug("Resonance Far activated (Attack boost)")
  end
end

SkillUptime.Hooks.onResonanceNearCriticalUp = function(args)
  local skill_id = 999003 -- Custom ID for Resonance Near + Critical Up
  -- Only activate if not already running
  if not SkillUptime.Skills.running[skill_id] then
    end_all_resonance_states() -- End other resonance states first
    local now = SkillUptime.Core.now()
    SkillUptime.Skills.running[skill_id] = true
    SkillUptime.Skills.timing_starts[skill_id] = now
    local skillRec = SkillUptime.Skills.ensure_skill(nil, skill_id)
    if skillRec then
      skillRec.Activated = true
      skillRec.ActivationTime = now
    end
    SkillUptime.Util.logDebug("Resonance Near + Critical Up activated (Enhanced Affinity)")
  end
end

SkillUptime.Hooks.onResonanceFarAttackUp = function(args)
  local skill_id = 999004 -- Custom ID for Resonance Far + Attack Up
  -- Only activate if not already running
  if not SkillUptime.Skills.running[skill_id] then
    end_all_resonance_states() -- End other resonance states first
    local now = SkillUptime.Core.now()
    SkillUptime.Skills.running[skill_id] = true
    SkillUptime.Skills.timing_starts[skill_id] = now
    local skillRec = SkillUptime.Skills.ensure_skill(nil, skill_id)
    if skillRec then
      skillRec.Activated = true
      skillRec.ActivationTime = now
    end
    SkillUptime.Util.logDebug("Resonance Far + Attack Up activated (Enhanced Attack)")
  end
end

SkillUptime.Hooks.onQuestEnter = function()
  SkillUptime.Battle.active = false; SkillUptime.Battle.start = 0.0; SkillUptime.Battle.total = 0.0
  SkillUptime.Skills.uptime = {}; SkillUptime.Skills.running = {}; SkillUptime.Skills.timing_starts = {}; SkillUptime.Skills.hits_up = {}; SkillUptime.Skills.name_cache = {}
  SkillUptime.Items.uptime = {}; SkillUptime.Items.timing_starts = {}; SkillUptime.Items.data = {}; SkillUptime.Items.hits_up = {}
  SkillUptime.Flags.uptime = {}; SkillUptime.Flags.timing_starts = {}; SkillUptime.Flags.data = {}; SkillUptime.Flags.hits_up = {}
  SkillUptime.Weapons.uptime = {}; SkillUptime.Weapons.timing_starts = {}; SkillUptime.Weapons.data = {}; SkillUptime.Weapons.hits_up = {}
  SkillUptime.Moves.damage = {}; SkillUptime.Moves.hits = {}; SkillUptime.Moves.names = {}; SkillUptime.Moves.total = 0;
  SkillUptime.Moves.colIds = {}; SkillUptime.Moves.wpTypes = {}; SkillUptime.Moves.maxHit = {}
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
  SkillUptime.Moves.damage = {}; SkillUptime.Moves.hits = {}; SkillUptime.Moves.names = {}; SkillUptime.Moves.total = 0;
  SkillUptime.Moves.colIds = {}; SkillUptime.Moves.wpTypes = {}; SkillUptime.Moves.maxHit = {}
  SkillUptime.Util.logDebug("Manual reset requested")
end

-- Count boss-target hits and attribute them to currently active skills
SkillUptime.Hooks.onHunterHitPost = function(args)
  local hitInfo = sdk.to_managed_object(args[3]); if not hitInfo then return end

  -- Only count hits from the current player
  local okOwner, hitOwner = pcall(function() return hitInfo:getActualAttackOwner() end)
  if not okOwner or not hitOwner then return end

  -- Get the master player's character GameObject
  local pm = SkillUptime.Core.GetSingleton("app.PlayerManager")
  if not pm then return end
  local okPlayer, playerInfo = pcall(function() return pm:getMasterPlayer() end)
  if not okPlayer or not playerInfo then return end
  local okChar, playerChar = pcall(function() return playerInfo:get_Character() end)
  if not okChar or not playerChar then return end

  -- Get the GameObject from playerChar (it should already be a GameObject)
  local okPlayerGO, playerGO = pcall(function() return playerChar:get_GameObject() end)
  if okPlayerGO and playerGO then
    -- Compare GameObjects
    if hitOwner ~= playerGO then return end
  else
    -- Fallback: compare directly if playerChar is already a GameObject
    if hitOwner ~= playerChar then return end
  end

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
  SkillUptime.Util.logDebug(string.format("Player hit registered! Total hits: %d, Damage: %.0f", SkillUptime.Hits.total,
    final))

  -- Per-move damage collection (only when strategy with moveDamage present is selected OR always accumulate
  -- so that switching strategies later still shows historical data).
  local mv = SkillUptime.Moves
  if mv then
    local atkIndex = nil
    local okAtk, atkIdxVT = pcall(function() return hitInfo:get_AttackIndex() end)
    if okAtk and atkIdxVT then
      -- attack index object has _Resource and _Index numeric fields
      local resId = atkIdxVT._Resource or 0
      local idx = atkIdxVT._Index or 0
      if idx and idx >= 0 then
        atkIndex = (resId or 0) .. ":" .. idx
      end
    end
    if atkIndex then
      mv.damage[atkIndex] = (mv.damage[atkIndex] or 0) + final
      mv.hits[atkIndex] = (mv.hits[atkIndex] or 0) + 1
      mv.total = (mv.total or 0) + final
      if (not mv.maxHit[atkIndex]) or final > mv.maxHit[atkIndex] then mv.maxHit[atkIndex] = final end
      -- Capture collision id & weapon type for later display (if not already)
      if mv.colIds[atkIndex] == nil then
        local okAD, atkData = pcall(function() return hitInfo:get_AttackData() end)
        if okAD and atkData and atkData._RuntimeData and atkData._RuntimeData._CollisionDataID then
          mv.colIds[atkIndex] = atkData._RuntimeData._CollisionDataID._Index
        end
      end
      if mv.wpTypes[atkIndex] == nil then
        local okChr, chr = pcall(function() return SkillUptime.Weapons.get_hunter_character() end)
        if okChr and chr and chr.get_WeaponType then
          local okWT, wtype = pcall(function() return chr:get_WeaponType() end)
          if okWT then mv.wpTypes[atkIndex] = wtype end
        end
      end
      if mv.names[atkIndex] == nil then
        local okName, nm = pcall(function() return SkillUptime.Moves.resolve_name(hitInfo) end)
        mv.names[atkIndex] = (okName and nm) or ("Atk " .. atkIndex)
      end
      -- no extra per-hit debug logging
    end
  end

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

-- Hook for HunterSkillUpdater.lateUpdate to properly sync item buff values
-- This is necessary because _ItemBuff values can desync if not read at the right time in the update cycle
SkillUptime.Hooks.onSkillUpdaterLateUpdate = function(args)
  local this = sdk.to_managed_object(args[2])
  if not this then return end

  local skill = this._HunterSkill
  if not skill then return end

  local status = skill.Status
  if not status then return end

  -- Only update for master player
  local okMaster, isMaster = pcall(function() return status:get_IsMaster() end)
  if not okMaster or not isMaster then return end

  -- Update item buffs with properly synced values
  SkillUptime.Items.update_items_and_frenzy(skill, status)
end

-- ============================================================================
-- UI Rendering
-- ============================================================================
SkillUptime.UI.draw = function()
  -- Title and flags
  local __as = SkillUptime.Strategy.get_active()
  local __title = "Skill Uptime Tracker: " .. ((__as and __as.label) or "")
  local window_open = imgui.begin_window(__title, true, 64)
  if not window_open then
    SkillUptime.UI.open = false; config.openWindow = false; SkillUptime.Config.save()
    imgui.end_window()
    return
  end

  -- Font and common locals
  local pushed_font = false
  local font = SkillUptime.UI.ensure_default_font()
  if font then
    imgui.push_font(font); pushed_font = true
  end

  local strategy = SkillUptime.Strategy.get_active()
  local elapsed = SkillUptime.Core.get_battle_elapsed()
  local tableFlags = imgui.TableFlags.Borders
  local epsilon = SkillUptime.Const.EPSILON or 0.0005

  -- Battle timer header for "In combat" strategy
  if strategy.showBattleHeader then
    local timerText = "In combat: " .. SkillUptime.Util.fmt_mss_hh(elapsed)
    if SkillUptime.Battle.active then
      imgui.text(timerText)
      imgui.same_line()
      imgui.text_colored("(active)", SkillUptime.Const.COLOR_GREEN)
    else
      imgui.text(timerText)
      imgui.same_line()
      imgui.text_colored("(inactive)", SkillUptime.Const.COLOR_RED)
    end
    imgui.spacing()
  end

  -- Skills
  if SkillUptime.UI.tables.Skills then
    local id_set = {}
    local useHits = (strategy.useHitsView == true)
    if useHits then
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
    if #ids > 0 then
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
                s and s.MaxTimer)); col =
                  col + 1
            end
            if SkillUptime.UI.columns.State then
              imgui.table_set_column_index(col); if s and s.Activated then
                imgui.text_colored("active", SkillUptime.Const.COLOR_GREEN)
              else
                imgui.text_colored("inactive", SkillUptime.Const.COLOR_RED)
              end
              col = col + 1
            end
          end
        end
        imgui.end_table()
      end
    end
  end

  -- Items
  if SkillUptime.UI.tables.Items then
    -- Build rows for items that have been used (have uptime, hits, or currently active)
    local itemRows = {}
    local useHits = (strategy.useHitsView == true)

    for key, rec in pairs(SkillUptime.Items.data or {}) do
      local base = SkillUptime.Items.uptime[key] or 0.0
      local live = 0.0
      -- Calculate live time if item is currently being timed
      if SkillUptime.Items.timing_starts[key] then
        live = SkillUptime.Core.now() - SkillUptime.Items.timing_starts[key]
        if live < 0 then live = 0 end
      end
      local total = base + live
      local hits = SkillUptime.Items.hits_up[key] or 0
      local active = rec.Activated and true or false

      -- Show item if it has uptime, hits, or is currently active
      if total > epsilon or hits > 0 or active then
        table.insert(itemRows, {
          key = key,
          name = rec.Name or tostring(key),
          total = total,
          rec = rec,
          active = active
        })
      end
    end

    table.sort(itemRows, function(a, b) return a.name < b.name end)
    imgui.text_colored("> Item Buffs (" .. #itemRows .. ")", SkillUptime.Const.COLOR_BLUE)

    if #itemRows > 0 then
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
              imgui.text_colored("active",
                SkillUptime.Const.COLOR_GREEN)
            else
              imgui.text_colored("inactive", SkillUptime.Const.COLOR_RED)
            end; col =
                col + 1
          end
        end
        imgui.end_table()
      end
    end
  end

  imgui.spacing()

  -- Flags
  if SkillUptime.UI.tables.Flags then
    local flagRows = SkillUptime.Core.build_rows(SkillUptime.Flags.data, SkillUptime.Flags.uptime,
      SkillUptime.Flags.timing_starts, epsilon, function(fid, rec) return rec.Name or ("FLAG " .. tostring(fid)) end)
    table.sort(flagRows, function(a, b) return a.key < b.key end)
    imgui.text_colored("> Status Flags (" .. #flagRows .. ")", SkillUptime.Const.COLOR_BLUE)
    if #flagRows > 0 then
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
              imgui.table_set_column_index(col); if totHits > 0 then
                imgui.text(string.format("%d/%d", up, totHits))
              else
                imgui.text("—")
              end; col = col + 1
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
              imgui.text_colored("active",
                SkillUptime.Const.COLOR_GREEN)
            else
              imgui.text_colored("inactive", SkillUptime.Const.COLOR_RED)
            end; col =
                col + 1
          end
        end
        imgui.end_table()
      end
    end
  end

  -- Weapons
  if SkillUptime.UI.tables.Weapons then
    local rows = SkillUptime.Core.build_rows(SkillUptime.Weapons.data, SkillUptime.Weapons.uptime,
      SkillUptime.Weapons.timing_starts, epsilon, function(key, rec) return rec.Name or tostring(key) end)
    table.sort(rows, function(a, b) return a.name < b.name end)
    imgui.text_colored("> Weapon States (" .. #rows .. ")", SkillUptime.Const.COLOR_BLUE)
    if #rows > 0 then
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
              imgui.table_set_column_index(col); if totHits > 0 then
                imgui.text(string.format("%d/%d", up, totHits))
              else
                imgui.text("—")
              end; col = col + 1
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
              imgui.text_colored("active",
                SkillUptime.Const.COLOR_GREEN)
            else
              imgui.text_colored("inactive", SkillUptime.Const.COLOR_RED)
            end; col =
                col + 1
          end
        end
        imgui.end_table()
      end
    end
  end


  -- Move Damage
  if SkillUptime.UI.tables.MoveDamage then
    local mv = SkillUptime.Moves
    local totalDmg = (mv and mv.total) or 0
    local moveCount = 0
    if mv and mv.damage then
      for _ in pairs(mv.damage) do moveCount = moveCount + 1 end
    end
    imgui.text_colored("> Move Damage (" .. tostring(moveCount) .. ")", SkillUptime.Const.COLOR_BLUE)

    if moveCount > 0 then
      if imgui.begin_table("move_damage_table", 7, tableFlags) then
        imgui.table_setup_column("Weapon")
        imgui.table_setup_column("Move Name")
        imgui.table_setup_column("Hits")
        imgui.table_setup_column("Hit %")
        imgui.table_setup_column("Total Damage")
        imgui.table_setup_column("Highest Single Hit")
        imgui.table_setup_column("Dmg %")
        imgui.table_headers_row()

        -- Group moves by weapon + move name
        local grouped = {}
        for key, dmg in pairs(mv.damage) do
          local wtype = mv.wpTypes[key]
          local moveName = mv.names[key] or key

          -- Get weapon name
          local wname = ""
          if wtype ~= nil then
            local wmap = SkillUptime.Moves.wmap
            wname = (wmap and wmap[wtype]) or ("#" .. tostring(wtype))
          end

          -- Create group key from weapon + move name
          local groupKey = wname .. "|" .. moveName

          if not grouped[groupKey] then
            grouped[groupKey] = {
              wname = wname,
              moveName = moveName,
              dmg = 0,
              hits = 0,
              maxHit = 0
            }
          end

          -- Aggregate data
          grouped[groupKey].dmg = grouped[groupKey].dmg + dmg
          grouped[groupKey].hits = grouped[groupKey].hits + (mv.hits[key] or 0)
          local thisMaxHit = mv.maxHit[key] or 0
          if thisMaxHit > grouped[groupKey].maxHit then
            grouped[groupKey].maxHit = thisMaxHit
          end
        end

        -- Convert to array and sort by damage
        local rows = {}
        for _, group in pairs(grouped) do
          table.insert(rows, group)
        end
        table.sort(rows, function(a, b) return a.dmg > b.dmg end)

        local totalHits = SkillUptime.Hits.total or 0
        for _, r in ipairs(rows) do
          imgui.table_next_row()

          -- Weapon name column
          imgui.table_set_column_index(0)
          imgui.text(r.wname)

          -- Move name column
          imgui.table_set_column_index(1)
          imgui.text(r.moveName)

          -- Hits column
          local hitPct = (totalHits > 0) and (r.hits / totalHits * 100.0) or 0.0
          imgui.table_set_column_index(2)
          if totalHits > 0 then
            imgui.text(string.format("%d/%d", r.hits, totalHits))
          else
            imgui.text(tostring(r.hits))
          end

          -- Hit % column
          imgui.table_set_column_index(3)
          imgui.text(string.format("%.1f%%", hitPct))

          -- Total Damage column
          imgui.table_set_column_index(4)
          imgui.text(string.format("%.0f", r.dmg))

          -- Highest Single Hit column
          imgui.table_set_column_index(5)
          imgui.text(r.maxHit > 0 and string.format("%.0f", r.maxHit) or "-")

          -- Dmg % column
          imgui.table_set_column_index(6)
          imgui.text(string.format("%.1f%%", (r.dmg / totalDmg) * 100.0))
        end
        imgui.end_table()
      end

      -- Total damage footer
      if totalDmg > 0 then
        imgui.text(string.format("Total Damage: %.0f", totalDmg))
      end
    end
  end

  imgui.spacing()

  -- Footer buttons
  if not config.hideButtons then
    imgui.spacing()
    if imgui.button("Reset Uptime") then
      SkillUptime.Hooks.reset_all(); SkillUptime.Config.save()
    end
    imgui.spacing()
  end

  if pushed_font then imgui.pop_font() end
  imgui.end_window()
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
    -- (Currently only two options; reserved for future strategies.)
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
    toggled, SkillUptime.UI.tables.Flags = imgui.checkbox("Status Flags", SkillUptime.UI.tables.Flags)
    if toggled then
      config.show.flags = SkillUptime.UI.tables.Flags; SkillUptime.Config.save()
    end
    imgui.same_line(); imgui.text_colored("(experimental)", SkillUptime.Const.COLOR_RED)
    toggled, SkillUptime.UI.tables.Weapons = imgui.checkbox("Weapon States (only DBs atm)",
      SkillUptime.UI.tables.Weapons)
    if toggled then
      config.show.weapons = SkillUptime.UI.tables.Weapons; SkillUptime.Config.save()
    end
    imgui.same_line(); imgui.text_colored("(experimental)", SkillUptime.Const.COLOR_RED)
    toggled, SkillUptime.UI.tables.MoveDamage = imgui.checkbox("Move Damage", SkillUptime.UI.tables.MoveDamage)
    if toggled then
      config.show.movedamage = SkillUptime.UI.tables.MoveDamage; SkillUptime.Config.save()
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
      local hbChanged, hb = imgui.checkbox("Hide Reset Button", config.hideButtons == true)
      if hbChanged then
        config.hideButtons = hb and true or false; SkillUptime.Config.save()
      end
      -- transparency controls removed
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

-- Helper function to update all game state
-- Update Timer values for skills tracked via hooks
local function update_tracker_state()
  SkillUptime.Core.tick_battle()
  SkillUptime.Skills.update_active_skills() -- Poll all skills from game state
  SkillUptime.Weapons.update_weapon_states()
  SkillUptime.Core.tick_status_flags()
end


-- Helper function to accumulate uptime for time-based strategies
local function accumulate_time_based_uptime(in_battle, tnow)
  -- All skills are now tracked via polling (not hooks)
  SkillUptime.Skills.poll_skill_uptime(in_battle, tnow)
  SkillUptime.Core.accumulate_uptime(SkillUptime.Items.data, SkillUptime.Items.timing_starts, SkillUptime.Items.uptime,
    in_battle, tnow)
  SkillUptime.Core.accumulate_uptime(SkillUptime.Flags.data, SkillUptime.Flags.timing_starts, SkillUptime.Flags.uptime,
    in_battle, tnow)
  SkillUptime.Core.accumulate_uptime(SkillUptime.Weapons.data, SkillUptime.Weapons.timing_starts,
    SkillUptime.Weapons.uptime, in_battle, tnow)
end

-- ============================================================================
-- Main Frame Loop
-- ============================================================================
re.on_frame(function()
  -- Update all tracker state
  update_tracker_state()

  -- Accumulate uptimes for time-based strategies only
  local strategy = SkillUptime.Strategy.get_active()
  if strategy.accumulateTime then
    accumulate_time_based_uptime(SkillUptime.Battle.active, SkillUptime.Core.now())
  end

  -- Draw UI
  if SkillUptime.UI.open then
    SkillUptime.UI.draw()
  end
end)

-- ============================================================================
-- Hook Registration
-- ============================================================================
SkillUptime.Core.registerHook(FN_QuestEnter, SkillUptime.Hooks.onQuestEnter, nil)
SkillUptime.Core.registerHook(FN_SetStatusBuff, SkillUptime.Hooks.onSetStatusBuff, nil)
SkillUptime.Core.registerHook(FN_HunterHitPost, SkillUptime.Hooks.onHunterHitPost, nil)
SkillUptime.Core.registerHook(FN_SkillUpdaterLateUpdate, SkillUptime.Hooks.onSkillUpdaterLateUpdate, nil)

-- Resonance tracking hooks
SkillUptime.Core.registerHook(FN_BeginResonanceNear, SkillUptime.Hooks.onResonanceNear, nil)
SkillUptime.Core.registerHook(FN_BeginResonanceFar, SkillUptime.Hooks.onResonanceFar, nil)
SkillUptime.Core.registerHook(FN_BeginResonanceNearCriticalUp, SkillUptime.Hooks.onResonanceNearCriticalUp, nil)
SkillUptime.Core.registerHook(FN_BeginResonanceFarAttackUp, SkillUptime.Hooks.onResonanceFarAttackUp, nil)
