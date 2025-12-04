--
-- Better Hunter Highlights
--
-- @repo https://github.com/thieleju/mhws-mods/tree/main/mods/better-hunter-highlights
--
---@diagnostic disable: undefined-global, undefined-doc-name

-- types
local guidType                                = sdk.find_type_definition("System.Guid")
local cQuestRewardType                        = sdk.find_type_definition("app.cQuestReward")
local cQuestFlowParamType                     = sdk.find_type_definition("app.cQuestFlowParam")
local questDefType                            = sdk.find_type_definition("app.QuestDef")
local messageUtilType                         = sdk.find_type_definition("app.MessageUtil")
local subMenuType                             = sdk.find_type_definition("app.cGUISubMenuInfo")
local guiManagerType                          = sdk.find_type_definition("app.GUIManager")
local playerManagerType                       = sdk.find_type_definition("app.PlayerManager")
local questPlayingType                        = sdk.find_type_definition("app.cQuestPlaying")
local guiInputCtrlFluentScrollListType        = sdk.find_type_definition(
  "ace.cGUIInputCtrl_FluentScrollList`2<app.GUIID.ID,app.GUIFunc.TYPE>")
local panelType                               = sdk.typeof("via.gui.Panel")
local textType                                = sdk.typeof("via.gui.Text")

-- methods to hook
local setSharedQuestAwardInfo                 = cQuestFlowParamType:get_method("setSharedQuestAwardInfo")
local enterQuestReward                        = cQuestRewardType:get_method("enter()")
local guiManagerRequestSubMenu                = guiManagerType:get_method("requestSubMenu")
local guiInputCtrlFluentScrollListIndexChange = guiInputCtrlFluentScrollListType:get_method("getSelectedIndex")
local evNetLeaveMember                        = playerManagerType:get_method(
  "evNetLeaveMember(System.Int64, System.Int64)")
local cQuestPlayingEnter                      = questPlayingType:get_method("enter()")
local cQuestPlayingExit                       = questPlayingType:get_method("exit()")
-- local updateListItem = gui070003PartsList:get_method("updateListItem")

-- utility methods
local newGuid                                 = guidType:get_method("NewGuid")
local addSubMenuItem                          = subMenuType:get_method(
  "addItem(System.String, System.Guid, System.Guid, System.Boolean, System.Boolean, System.Action)")
local getAwardNameHelper                      = questDefType:get_method("Name(app.QuestDef.AwardID)")
local getAwardExplainHelper                   = questDefType:get_method("Explain(app.QuestDef.AwardID)")
local getAwardUnitHelper                      = questDefType:get_method("Unit(app.QuestDef.AwardID)")
local getTextHelper                           = messageUtilType:get_method("getText(System.Guid, System.Int32)")

-- variables
local selectedHunterId                        = ""
local memberAwardStats                        = {}
local awardList                               = {}
local showAwardWindow                         = false
local playerIsOnQuest                         = false
local config                                  = { enabled = true, debug = false, cache = {}, displayAwardIds = {} }

-- pink, red, yellow, green, gray
local COLORS                                  = { 0x50e580f5, 0x500000ff, 0x5049cff5, 0x50a4ffa4, 0xCC666666 }
local CONFIG_PATH                             = "better_hunter_highlights.json"
local DAMAGE_AWARD_ID                         = 4
local SUBMENU_CHAR_LIMIT                      = 35
local MIN_TABLE_COLUMN_WIDTH                  = 130
local AWARD_UNIT                              = { COUNT = 0, TIME = 1, NONE = 2 }
local SESSION_TYPE                            = { LOBBY = 1, QUEST = 2, LINK = 3 }
local AWARD_NUM_MAX                           = 29

-- Log debug message
local function logDebug(message)
  if config.debug then
    log.debug("[Better Hunter Highlights] " .. message)
  end
end

-- Log error message
local function logError(message)
  logDebug("ERROR: " .. message)
end

-- Save config to json file in data directory of reframework
local function saveConfig()
  json.dump_file(CONFIG_PATH, config)
  logDebug("Config saved to " .. CONFIG_PATH)
end

--- Save default config
local function saveDefaultConfig()
  config = { enabled = true, debug = false, cache = {}, displayAwardIds = {} }
  for _, award in ipairs(awardList) do
    config.displayAwardIds[tostring(award.awardId)] = true
  end
  saveConfig()
end

-- Load existing config or create default
local function loadConfig()
  local loaded = json.load_file(CONFIG_PATH)
  if loaded then
    -- check if loaded config has required fields
    if type(loaded.enabled) ~= "boolean" then
      loaded.enabled = true
    end
    if type(loaded.debug) ~= "boolean" then
      loaded.debug = false
    end
    if type(loaded.cache) ~= "table" then
      loaded.cache = {}
    end
    if type(loaded.displayAwardIds) ~= "table" then
      loaded.displayAwardIds = {}
      for _, award in ipairs(awardList) do
        loaded.displayAwardIds[tostring(award.awardId)] = true
      end
    end
    -- migrate hideDamageNumbers to displayAwardIds
    if loaded.hideDamageNumbers ~= nil then
      loaded.displayAwardIds[tostring(DAMAGE_AWARD_ID)] = not loaded.hideDamageNumbers
      loaded.hideDamageNumbers = nil
    end

    config = loaded
  else
    saveDefaultConfig()
  end
end

--- Safely call a function and return result or nil
--- @param fn function The function to call
--- @return any|nil The result if successful
local function safeCall(fn)
  local ok, result = pcall(fn)
  if not ok then
    logError("SafeCall: " .. tostring(result))
  end
  return ok and result or nil
end

--- Rounds a number to two decimal places
--- @param value number The value to round
--- @return number The rounded value
local function roundToTwoDecimalPlaces(value)
  return math.floor(value * 100 + 0.5) / 100
end

--- Gets the localized name for an award ID
--- @param awardId number The award ID to get the name for
--- @return string The localized name of the award
local function getAwardName(awardId)
  return safeCall(function()
    local guid = getAwardNameHelper:call(nil, awardId)
    return getTextHelper:call(nil, guid, 0)
  end)
end

--- Gets the localized explanation for an award ID
---@param awardId number The award ID to get the explanation for
---@return string The localized explanation of the award
local function getAwardExplain(awardId)
  return safeCall(function()
    local guid = getAwardExplainHelper:call(nil, awardId)
    local exp = getTextHelper:call(nil, guid, 0)
    return exp:gsub("\r\n", " "):gsub("\n", " ")
  end)
end

--- Gets the unit for an award ID
--- @param awardId number The award ID to get the unit for
--- @return number The unit of the award
local function getAwardUnit(awardId)
  return safeCall(function()
    return getAwardUnitHelper:call(nil, awardId)
  end)
end

--- Updates awardList with localized names and explanations
local function updateAwardList()
  for i = 0, AWARD_NUM_MAX do
    -- get localized name and explaination for each award
    awardList[i + 1] = {
      awardId = i,
      name = getAwardName(i) or "",
      explain = getAwardExplain(i) or "",
      unit = getAwardUnit(i) or AWARD_UNIT.NONE
    }
  end
end

-- Get user info for the current quest
local function getQuestUserInfo()
  local nm = sdk.get_managed_singleton("app.NetworkManager")
  if not nm then
    logError("NetworkManager singleton not found.")
    return nil, "no_network_manager"
  end

  local uim = nm:get_UserInfoManager()
  if not uim then
    logError("UserInfoManager not found in NetworkManager.")
    return nil, "no_user_info_manager"
  end

  local memberNum = uim:getMemberNum(SESSION_TYPE.QUEST)
  if memberNum <= 0 then
    logError("No members found in UserInfoList.")
    return nil, "no_members"
  end

  local uil = uim:getUserInfoList(SESSION_TYPE.QUEST)
  if not uil or not uil._ListInfo then
    logError("UserInfoList or its _ListInfo is nil.")
    return nil, "no_user_info_array"
  end

  return uil._ListInfo, memberNum
end

--- Handler for setSharedQuestAwardInfo hook
--- @param args table Hook arguments
--- @return sdk.PreHookResult|nil
local function onSetSharedQuestAwardInfo(args)
  if not config.enabled then
    return sdk.PreHookResult.CALL_ORIGINAL
  end

  -- userIndex of the player who sent the sync packet
  local userIndex = safeCall(function()
    local idx = sdk.to_int64(args[3])
    if idx < 0 or idx >= 4 then error("Invalid userIndex: " .. tostring(idx)) end
    return idx
  end)
  if not userIndex then
    logError("Invalid userIndex in syncQuestAwardInfo.")
    return sdk.PreHookResult.CALL_ORIGINAL
  end

  -- the cQuestAwardSync packet itself
  local cQuestAwardSync = safeCall(function() return sdk.to_managed_object(args[4]) end)
  if not cQuestAwardSync then
    logError("Invalid cQuestAwardSync in syncQuestAwardInfo.")
    return sdk.PreHookResult.CALL_ORIGINAL
  end

  -- get stats from cQuestAwardSync
  local statsArray = {}

  -- award01 is special case, its type is System.UInt32[]
  table.insert(statsArray, {
    awardId = 0,
    count = 0,
    award01Array = {
      cQuestAwardSync["award01"]:get_Item(0) or 0,
      cQuestAwardSync["award01"]:get_Item(1) or 0,
      cQuestAwardSync["award01"]:get_Item(2) or 0,
      cQuestAwardSync["award01"]:get_Item(3) or 0
    }
  })

  -- loop through awardList and fill statsArray
  for i = 2, #awardList do
    table.insert(statsArray, {
      awardId = i - 1,
      count = cQuestAwardSync[string.format("award%02d", i)] or 0,
    })
  end

  -- Get player identity info for matching at quest end
  local userInfoArray, memberNum = getQuestUserInfo()
  local username = nil
  local shortHunterId = nil
  local isSelf = false

  if userInfoArray and userIndex < memberNum then
    local user = userInfoArray[userIndex]
    if user then
      username = safeCall(function() return user:get_PlName() end)
      shortHunterId = safeCall(function() return user:get_ShortHunterId() end)
      isSelf = safeCall(function() return user:get_IsSelf() end) or false
    end
  end

  memberAwardStats[userIndex + 1] = {
    memberIndex = userIndex,
    username = username,
    shortHunterId = shortHunterId,
    isSelf = isSelf,
    awards = statsArray
  }

  if config.debug then
    local parts = {}
    for _, award in ipairs(statsArray) do
      table.insert(parts, string.format("(%d|%.0f)", award.awardId or 0, award.count or 0))
    end
    logDebug(string.format("Player %d: Awards: %s", userIndex, table.concat(parts, ", ")))
  end
end

--- Handler when entering quest reward state
--- @param args table Hook arguments
local function onEnterQuestReward(args)
  if not config.enabled then
    return sdk.PreHookResult.CALL_ORIGINAL
  end

  logDebug("Quest reward enter() called")

  local userInfoArray, memberNum = getQuestUserInfo()
  if not userInfoArray then
    logError("Failed to get user info array in enterQuestReward.")
    return sdk.PreHookResult.CALL_ORIGINAL
  end

  -- skip updating memberAwardStats if singleplayer
  if memberNum <= 1 then
    logDebug("Singleplayer detected, skipping memberAwardStats update.")
    return sdk.PreHookResult.CALL_ORIGINAL
  end

  logDebug(string.format("Processing %d quest members for award stats", memberNum))

  -- Build a lookup map of current members by shortHunterId
  local currentMembersMap = {}
  for i = 0, memberNum - 1 do
    local user = userInfoArray[i]
    if user then
      local shortHunterId = safeCall(function() return user:get_ShortHunterId() end)
      local username = safeCall(function() return user:get_PlName() end)
      if shortHunterId and username then
        currentMembersMap[shortHunterId] = {
          arrayIndex = i,
          username = username,
          shortHunterId = shortHunterId,
          isSelf = safeCall(function() return user:get_IsSelf() end) or false
        }
        logDebug(string.format("Current member at quest-end index %d: %s (ID: %s)", i, username, shortHunterId))
      end
    end
  end

  -- Filter memberAwardStats to only include members who are still in the quest
  -- Keep only the most recent entry (highest memberIndex) for each unique shortHunterId
  local validMemberStats = {}
  local seenHunterIds = {} -- Track which hunter IDs we've already added

  -- Process entries in reverse order (highest memberIndex first) to get most recent stats
  for i = #memberAwardStats, 1, -1 do
    local entry = memberAwardStats[i]
    if entry and entry.shortHunterId and currentMembersMap[entry.shortHunterId] then
      -- Check if we haven't already added an entry for this hunter ID
      if not seenHunterIds[entry.shortHunterId] then
        -- This member is still present at quest end
        local currentMember = currentMembersMap[entry.shortHunterId]
        entry.username = currentMember.username
        entry.shortHunterId = currentMember.shortHunterId
        entry.isSelf = currentMember.isSelf
        -- Update the array index to match the quest-end position
        entry.finalArrayIndex = currentMember.arrayIndex
        table.insert(validMemberStats, 1, entry) -- Insert at beginning to maintain order
        seenHunterIds[entry.shortHunterId] = true
        logDebug(string.format("Keeping stats for %s (original memberIndex=%d, final arrayIndex=%d)",
          entry.username, entry.memberIndex, entry.finalArrayIndex))
      else
        logDebug(string.format("Skipping duplicate entry for %s (memberIndex=%d, already have more recent stats)",
          entry.username or "Unknown", entry.memberIndex))
      end
    else
      local name = entry.username or (entry.memberIndex and string.format("Player %d", entry.memberIndex)) or "Unknown"
      logDebug(string.format("Removing stats for %s (disconnected or not present)", name))
    end
  end

  -- Replace memberAwardStats with the filtered list
  memberAwardStats = validMemberStats

  -- Calculate total damage for percentage calculation
  local totalDamage = 0
  for _, data in ipairs(memberAwardStats) do
    if data and data.awards and data.awards[DAMAGE_AWARD_ID + 1] then
      totalDamage = totalDamage + (data.awards[DAMAGE_AWARD_ID + 1].count or 0)
    end
  end

  -- calculate award01 data for each member
  local award01DataSum = { 0, 0, 0, 0 }

  -- Update damage stats for each remaining member
  for arrayIndex = 1, #memberAwardStats do
    local entry = memberAwardStats[arrayIndex]
    if entry then
      local damageEntry = entry.awards[DAMAGE_AWARD_ID + 1] or { count = 0 }
      local damageValue = damageEntry.count or 0
      local damagePercentage = totalDamage > 0 and (damageValue / totalDamage) * 100 or 0

      entry.damageTotal = roundToTwoDecimalPlaces(totalDamage)
      entry.damagePercentage = roundToTwoDecimalPlaces(damagePercentage)
      entry.damage = roundToTwoDecimalPlaces(damageValue)

      local arr = (entry.awards[1] and entry.awards[1].award01Array) or { 0, 0, 0, 0 }
      for j = 1, 4 do
        award01DataSum[j] = award01DataSum[j] + (arr[j] or 0)
      end

      memberAwardStats[arrayIndex] = entry
    end
  end

  -- apply the total award01 data to each member
  for i, entry in ipairs(memberAwardStats) do
    entry.awards[1] = entry.awards[1] or { awardId = 0, award01Array = { 0, 0, 0, 0 } }
    entry.awards[1].count = award01DataSum[i] or 0
  end

  -- log final award01DataSum array
  logDebug(string.format("Final award01DataSum: [%d, %d, %d, %d]", award01DataSum[1], award01DataSum[2],
    award01DataSum[3], award01DataSum[4]))

  -- Cache the latest memberAwardStats
  config.cache = memberAwardStats
  saveConfig()
  logDebug("Cached memberAwardStats in config")
end

--- Handler for when sub menus open
--- @param args table Hook arguments
local function onRequestSubMenu(args)
  if not config.enabled then
    return sdk.PreHookResult.CALL_ORIGINAL
  end

  local owner = safeCall(function() return sdk.to_managed_object(args[3]) end)
  if not owner then
    logError("Invalid owner in requestSubMenu.")
    return sdk.PreHookResult.CALL_ORIGINAL
  end

  local subMenu = safeCall(function() return sdk.to_managed_object(args[4]) end)
  if not subMenu then
    logDebug("requestSubMenu subMenu is nil")
    return sdk.PreHookResult.CALL_ORIGINAL
  end

  logDebug("RequestSubMenu called for " .. tostring(owner:get_type_definition():get_full_name()))

  -- skip all submenus except the one for parts list
  if owner:get_type_definition():get_full_name() ~= "app.GUI070003PartsList" then
    return sdk.PreHookResult.CALL_ORIGINAL
  end

  local item0 = subMenu:getItem(0)
  local item1 = subMenu:getItem(1)
  local item2 = subMenu:getItem(2)

  item0:clear()
  item1:clear()
  item2:clear()

  local emptyAction = sdk.create_instance(sdk.typeof("System.Action"))
  item0:set_ExecuteAction(emptyAction)
  item1:set_ExecuteAction(emptyAction)
  item2:set_ExecuteAction(emptyAction)

  -- find memberAwardStats element with hunterId matching selectedHunterId
  local memberAward = nil
  for i = 1, #memberAwardStats do
    local data = memberAwardStats[i]
    if data and data.shortHunterId == selectedHunterId then
      memberAward = data
      break
    end
  end

  if not memberAward then
    logDebug("No member award found for selected hunter ID: " .. tostring(selectedHunterId))
    -- add a message indicating no awards found
    addSubMenuItem:call(subMenu, "No highlights available", newGuid:call(nil), newGuid:call(nil), true, false,
      emptyAction)
    return sdk.PreHookResult.CALL_ORIGINAL
  end

  -- get how many awards are enabled in config.displayAwardIds
  local enabledAwardCount = 0
  for _, award in ipairs(memberAward.awards) do
    if config.displayAwardIds[tostring(award.awardId)] then
      enabledAwardCount = enabledAwardCount + 1
    end
  end

  local guid = newGuid:call(nil)
  local submenuItemCount = 0

  -- loop through awardList and add awards to sub menu
  for i = 1, #awardList do
    local award = awardList[i]
    local memberAwardData = memberAward.awards[i]

    -- after TU2 sometimes the award names are missing
    if not award.name or award.name == "" then
      -- print award object
      logDebug(" award ID object: " .. json.encode(award))
      logError(string.format("Award %d has no name, requesting name again", award.awardId))

      awardList[i].name = getAwardName(award.awardId) or ""
      awardList[i].explain = getAwardExplain(award.awardId) or ""
      awardList[i].unit = getAwardUnit(award.awardId) or AWARD_UNIT.NONE

      logDebug(string.format("Award %d updated to: %s (%s), %s, Unit: %d",
        award.awardId, awardList[i].name, awardList[i].explain, awardList[i].unit))
    end

    -- check if award is enabled in config.displayAwardIds
    if not config.displayAwardIds[tostring(award.awardId)] then
      logDebug(string.format("Skipping award %s (%d) as it is not enabled in config", award.name, award.awardId))
      goto continue
    end

    -- skip if count is 0
    if not memberAwardData or not memberAwardData.count or memberAwardData.count <= 0 then
      goto continue
    end

    local itemText = ""

    -- check if damage award
    if award.awardId == DAMAGE_AWARD_ID then
      -- format item text for damage award
      itemText = string.format("Damage: %.0f (%.2f%%)", memberAward.damage, memberAward.damagePercentage)
    else
      -- every other award
      local explainText = award.explain or ""
      -- limit explain text to SUBMENU_CHAR_LIMIT characters
      if #explainText > SUBMENU_CHAR_LIMIT then
        explainText = string.format("%s...", explainText:sub(1, SUBMENU_CHAR_LIMIT))
      end
      -- check if time unit
      if award.unit == AWARD_UNIT.TIME then
        -- change it to format 00'00"00
        local totalSeconds = memberAward.awards[i].count or 0
        local minutes = math.floor(totalSeconds / 60)
        local seconds = math.floor(totalSeconds % 60)
        local hundredths = math.floor((totalSeconds - math.floor(totalSeconds)) * 100)

        itemText = string.format("%s: %02d'%02d\"%02d", explainText, minutes, seconds, hundredths)
      else
        -- default to count unit
        itemText = string.format("%s: %.0f", explainText, memberAward.awards[i].count or 0)
      end
    end

    -- add item to sub menu with the award name and explain text
    addSubMenuItem:call(subMenu, itemText, guid, guid, true, false, emptyAction)
    submenuItemCount = submenuItemCount + 1
    logDebug(string.format("Added sub menu item: %s (ID: %d)", itemText, award.awardId))

    ::continue::
  end

  -- if no items were added, add a message indicating no valid awards
  if enabledAwardCount == 0 or submenuItemCount == 0 then
    addSubMenuItem:call(subMenu, "No highlights available", guid, guid, true, false, emptyAction)
  end

  return sdk.PreHookResult.CALL_ORIGINAL
end


--- Handler for fluent scroll list index change
--- @param args table Hook arguments
--- @return sdk.PreHookResult|nil
local function onIndexChange(args)
  if not config.enabled then
    return sdk.PreHookResult.CALL_ORIGINAL
  end

  local guiInputCtrlFluentScrollList = sdk.to_managed_object(args[2])
  if not guiInputCtrlFluentScrollList then
    logError("Invalid guiInputCtrlFluentScrollList in onIndexChange.")
    return sdk.PreHookResult.CALL_ORIGINAL
  end

  -- get SelectedItem field
  local selectedItem = guiInputCtrlFluentScrollList:call("getSelectedItem")
  if not selectedItem then
    return sdk.PreHookResult.CALL_ORIGINAL
  end

  -- get the child elements of the selected item at the specified index
  ---@param obj any The parent object to get children from
  ---@param index number The index of the child to retrieve
  ---@param childType any The type of the child to retrieve
  ---@return any The child object at the specified index, or nil if not found
  local function getChild(obj, index, childType)
    if not obj then return nil end
    local children = obj:call("getChildren", childType)
    if not children then return nil end
    return children[index]
  end

  -- this is a hardcoded path to the text element in the hunter highlights menu
  -- don't know how else to get to the hunter ID text
  -- selectedItem -> panel[2] -> panel[0] -> panel[1] -> textChild[0]
  local panel     = getChild(selectedItem, 2, panelType)
  panel           = getChild(panel, 0, panelType)
  panel           = getChild(panel, 1, panelType)
  local textChild = getChild(panel, 0, textType)

  if not textChild then
    return sdk.PreHookResult.CALL_ORIGINAL
  end
  local hunterId = textChild:call("get_Message")
  logDebug("Selected Hunter ID: " .. tostring(hunterId))
  selectedHunterId = hunterId
end

--- Handler for when a quest member leaves, remove their stats
---@param args any
local function onQuestMemberLeave(args)
  if not config.enabled then
    return sdk.PreHookResult.CALL_ORIGINAL
  end

  -- skip if not on quest
  if not playerIsOnQuest then
    logDebug("evNetLeaveMember called while not on quest, skipping")
    return sdk.PreHookResult.CALL_ORIGINAL
  end

  local sessionType = sdk.to_int64(args[3])
  local memberIndex = sdk.to_int64(args[4])

  -- only continue if sessionType is QUEST
  if sessionType ~= SESSION_TYPE.QUEST then
    return sdk.PreHookResult.CALL_ORIGINAL
  end

  -- check if memberIndex is nil
  if memberIndex == nil then
    logError("evNetLeaveMember called with nil memberIndex")
    return sdk.PreHookResult.CALL_ORIGINAL
  end

  logDebug(string.format(
    "PlayerManager: evNetLeaveMember called with SESSION_TYPE %d, memberIndex %d",
    sessionType, memberIndex))

  logDebug(string.format("Member %d left, but keeping their stats for potential rejoin", memberIndex))

  -- Cache the current memberAwardStats
  config.cache = memberAwardStats
  saveConfig()
end

--- Handler for entering quest playing state
local function onQuestPlayingEnter()
  logDebug("cQuestPlaying enter() called")
  playerIsOnQuest = true
end

-- Handler for exiting quest playing state
local function onQuestPlayingExit()
  logDebug("cQuestPlaying exit() called")
  playerIsOnQuest = false
end

-- Helper function to register hooks
local function registerHook(method, pre, post)
  if not method then return end
  sdk.hook(method, pre, post)

  logDebug("Hook registered for method: " .. tostring(method:get_name()))
end

--- Draw the award table in a separate window
--- This function is called when the user clicks the button to show the awards window
local function drawAwardWindow()
  local openFlag = { true }

  if imgui.begin_window("Better Hunter Highlights - Awards", openFlag, 64) then
    -- check how many awards are enabled to display
    local enabledCount = 0
    for _, award in ipairs(awardList) do
      if config.displayAwardIds[tostring(award.awardId)] then
        enabledCount = enabledCount + 1
      end
    end

    if enabledCount == 0 then
      imgui.text("No highlights enabled to display")
      imgui.end_window()
      return
    end

    local colCount = 3 + #memberAwardStats
    local tableFlags = imgui.TableFlags.Borders | imgui.TableFlags.SizingFixedFit | imgui.TableFlags.RowBg |
        imgui.TableFlags.ScrollY | imgui.TableFlags.Resizable

    if imgui.begin_table("awards_table", colCount, tableFlags) then
      -- Header setup
      imgui.table_setup_column("ID")
      imgui.table_setup_column("Title")
      imgui.table_setup_column("Description")

      imgui.table_next_row()
      for i = 1, #memberAwardStats do
        imgui.table_setup_column(memberAwardStats[i].username or ("Player " .. tostring(i)), nil, MIN_TABLE_COLUMN_WIDTH)
      end

      imgui.table_headers_row()

      -- loop through awardList
      for awardIndex = 1, #awardList do
        -- make sure awards names are updated
        if not awardList[awardIndex].name or awardList[awardIndex].name == "" then
          logError(string.format("Award %d has no name, requesting name again", awardList[awardIndex].awardId))
          awardList[awardIndex].name = getAwardName(awardList[awardIndex].awardId) or ""
          awardList[awardIndex].explain = getAwardExplain(awardList[awardIndex].awardId) or ""
          awardList[awardIndex].unit = getAwardUnit(awardList[awardIndex].awardId) or AWARD_UNIT.NONE
          logDebug(string.format("Award %d updated to: %s (%s), %s, Unit: %d",
            awardList[awardIndex].awardId, awardList[awardIndex].name, awardList[awardIndex].explain,
            awardList[awardIndex].unit))
        end

        local award = awardList[awardIndex]
        if config.displayAwardIds[tostring(award.awardId)] then
          imgui.table_next_row()

          imgui.table_set_column_index(0)
          imgui.text(tostring(awardIndex))

          imgui.table_set_column_index(1)
          imgui.text(award.name or ("Award " .. tostring(awardIndex)))

          imgui.table_set_column_index(2)
          imgui.text(award.explain or "")

          -- columns per player
          for playerIndex = 1, #memberAwardStats do
            local player = memberAwardStats[playerIndex]
            local awardData = player.awards and player.awards[awardIndex]
            local awardListData = awardList[awardIndex]
            imgui.table_set_column_index(2 + playerIndex)

            local count = awardData and awardData.count or 0
            local valueStr = tostring(count)

            if awardData and awardData.awardId == DAMAGE_AWARD_ID then
              if config.displayAwardIds[tostring(DAMAGE_AWARD_ID)] == false then
                valueStr = "<hidden>"
              else
                local percent = player.damagePercentage or 0
                valueStr = string.format("%.0f (%.2f%%)", count, percent)
              end
            end

            if awardData and awardListData.unit == AWARD_UNIT.TIME then
              local totalSeconds = awardData.count
              local minutes = math.floor(totalSeconds / 60)
              local seconds = math.floor(totalSeconds % 60)
              local hundredths = math.floor((totalSeconds - math.floor(totalSeconds)) * 100)
              valueStr = string.format("%02d'%02d\"%02d", minutes, seconds, hundredths)
            end

            -- highlight non-zero values
            if valueStr ~= "0" and valueStr ~= "" and valueStr ~= "00'00\"00" and valueStr ~= "<hidden>" then
              local colorIndex = (playerIndex - 1) % #COLORS + 1
              imgui.table_set_bg_color(3, COLORS[colorIndex], imgui.table_get_column_index())
            end

            imgui.text(valueStr)
          end
        end
      end
      imgui.end_table()
    end
    imgui.end_window()
  end

  if not openFlag[1] then
    showAwardWindow = false
  end
end


-- Draw REFramework UI
re.on_draw_ui(function()
  if imgui.tree_node("Better Hunter Highlights") then
    imgui.begin_rect()
    imgui.spacing()

    -- checkbox returns true if clicked
    if imgui.checkbox("Enable Mod", config.enabled) then
      config.enabled = not config.enabled
      logDebug("Config set enabled to " .. tostring(config.enabled))
    end

    -- skip if mod disabled
    if not config.enabled then
      imgui.spacing()
      imgui.end_rect(2)
      imgui.tree_pop()
      return
    end

    -- checkbox to hide damage numbers (set displayAwardIds[4] to false)
    local isHidden = not config.displayAwardIds[tostring(DAMAGE_AWARD_ID)]
    local changed, newHidden = imgui.checkbox("Hide Damage Numbers (Highlight 'Established Hunter')", isHidden)
    if changed then
      config.displayAwardIds[tostring(DAMAGE_AWARD_ID)] = not newHidden
      logDebug("Config set displayAwardIds[" .. DAMAGE_AWARD_ID .. "] to " ..
        tostring(config.displayAwardIds[tostring(DAMAGE_AWARD_ID)]))
    end

    -- use cached stats if live stats are empty and only show button if there's data
    memberAwardStats = (#memberAwardStats == 0 and config.cache) or memberAwardStats
    if #memberAwardStats > 0 then
      local buttonText = showAwardWindow and "Close Hunter Highlights Overview" or "Show Hunter Highlights Overview"
      if imgui.button(buttonText) then
        showAwardWindow = not showAwardWindow
      end
    end

    -- customize which highlights to show
    if imgui.tree_node("Customize which highlights to show") then
      -- buttons to toggle selection
      local enableAll = imgui.button("Select all")
      imgui.same_line()
      local disableAll = imgui.button("Deselect all")
      if enableAll then
        for _, award in ipairs(awardList) do
          config.displayAwardIds[tostring(award.awardId)] = true
          logDebug(string.format("Config set displayAwardIds[%s] to true", tostring(award.awardId)))
        end
      end
      if disableAll then
        for _, award in ipairs(awardList) do
          config.displayAwardIds[tostring(award.awardId)] = false
          logDebug(string.format("Config set displayAwardIds[%s] to false", tostring(award.awardId)))
        end
      end
      -- loop through awardList and create checkboxes for each award
      for _, award in ipairs(awardList) do
        local awardIdStr = tostring(award.awardId)
        local changed, newValue = imgui.checkbox(string.format("%s (%s)", award.name, award.explain),
          config.displayAwardIds[awardIdStr])
        if changed then
          config.displayAwardIds[awardIdStr] = newValue
          logDebug(string.format("Config set displayAwardIds[%s] to %s", awardIdStr, tostring(newValue)))
        end
      end
      imgui.tree_pop()
    end

    -- developer options
    if imgui.tree_node("Developer Options") then
      -- debug mode
      if imgui.checkbox("Debug Mode", config.debug) then
        config.debug = not config.debug
        logDebug("Config set debug mode to " .. tostring(config.debug))
      end

      -- clear cached stats
      local clearClicked = imgui.button("Clear cached highlights data")
      imgui.same_line()
      local resetClicked = imgui.button("Reset settings to default")

      if clearClicked then
        memberAwardStats = {}
        config.cache = {}
        saveConfig()
        logDebug("Cleared cached highlights data")
      end

      if resetClicked then
        --- Save default config
        saveDefaultConfig()
        logDebug("Config reset to default settings")
      end

      imgui.tree_pop()
    end

    imgui.spacing()
    imgui.end_rect(2)
    imgui.spacing()
    imgui.tree_pop()
  end

  -- Draw the award table if the window is open
  if showAwardWindow then
    drawAwardWindow()
  end
end)

-- Load configuration and add config save listener

loadConfig()

re.on_config_save(function()
  saveConfig()
  loadConfig()
end)

-- Game Function Hooks

-- Called multiple times per quest, updates memberAwardStats object every time
registerHook(setSharedQuestAwardInfo, onSetSharedQuestAwardInfo, nil)

-- Called when entering quest reward state, updates memberAwardStats object with final stats
registerHook(enterQuestReward, onEnterQuestReward, nil)

-- Called when opening a sub-menu, adds custom items
registerHook(guiManagerRequestSubMenu, onRequestSubMenu, nil)

-- Called when a fluent scroll list index changes, used to update the selected index in the hunter highlights menu
registerHook(guiInputCtrlFluentScrollListIndexChange, onIndexChange, nil)

-- Called when a quest member leaves, removes their stats from memberAwardStats
registerHook(evNetLeaveMember, onQuestMemberLeave, nil)

-- Called when entering quest playing state, sets playerIsOnQuest to true
registerHook(cQuestPlayingEnter, onQuestPlayingEnter, nil)

-- Called when exiting quest playing state, sets playerIsOnQuest to false
registerHook(cQuestPlayingExit, onQuestPlayingExit, nil)

-- Update the award list with localized names and explanations
updateAwardList()

logDebug("Better Hunter Highlights initialized successfully!")
