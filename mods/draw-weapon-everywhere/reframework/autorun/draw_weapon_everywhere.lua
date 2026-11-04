-- draw_weapon_everywhere: lets you draw your weapon, attack and use items in
-- rest areas (Grand Hub, villages, base camps). While a hunter is in a rest
-- area its life area mini component (mcHunterLifeArea.updateMain) sets the
-- per-frame continue flags that block combat and items; while the mod is
-- active that update is skipped for the local hunter, so the flags are never set.
-- Toggle in game with a configurable controller / keyboard shortcut (default
-- L3 + R3).
local TAG="[DrawWeaponEverywhere] "
local CONFIG_PATH="DrawWeaponEverywhere/config.json"

local function enum(type_name,name,fallback)
    local ok,value=pcall(function()
        return sdk.find_type_definition(type_name):get_field(name):get_data(nil)
    end)
    if ok and value~=nil then return value end
    return fallback
end
local HUB_STAGE=enum("app.FieldDef.STAGE","ST502",14)
local L3=enum("ace.ACE_PAD_KEY.BITS","L3",1024)
local R3=enum("ace.ACE_PAD_KEY.BITS","R3",8192)

-- Controller buttons that can be bound (ace.ACE_PAD_KEY.BITS), in display order.
local PAD_BUTTONS={
    {"L_UP","D-Pad Up"},{"L_DOWN","D-Pad Down"},{"L_LEFT","D-Pad Left"},{"L_RIGHT","D-Pad Right"},
    {"R_UP","Triangle/Y"},{"R_DOWN","Cross/A"},{"R_LEFT","Square/X"},{"R_RIGHT","Circle/B"},
    {"L1","L1/LB"},{"L2","L2/LT"},{"L3","L3"},{"R1","R1/RB"},{"R2","R2/RT"},{"R3","R3"},
    {"C_LEFT","Share/View"},{"C_RIGHT","Options/Menu"},{"C_CENTER","Touchpad"},
}
local PAD_MASK=0
for _,button in ipairs(PAD_BUTTONS) do
    button.bit=enum("ace.ACE_PAD_KEY.BITS",button[1],0)
    PAD_MASK=PAD_MASK|button.bit
end

-- Windows virtual-key codes that can be bound (no mouse buttons, no left/right
-- duplicates of Shift/Ctrl/Alt).
local KEY_NAMES={[0x08]="Backspace",[0x09]="Tab",[0x0D]="Enter",[0x10]="Shift",[0x11]="Ctrl",[0x12]="Alt",
    [0x13]="Pause",[0x14]="Caps Lock",[0x1B]="Esc",[0x20]="Space",[0x21]="Page Up",[0x22]="Page Down",
    [0x23]="End",[0x24]="Home",[0x25]="Left",[0x26]="Up",[0x27]="Right",[0x28]="Down",[0x2D]="Insert",
    [0x2E]="Delete",[0xBA]=";",[0xBB]="=",[0xBC]=",",[0xBD]="-",[0xBE]=".",[0xBF]="/",[0xC0]="`",
    [0xDB]="[",[0xDC]="\\",[0xDD]="]",[0xDE]="'"}
for code=0x30,0x39 do KEY_NAMES[code]=string.char(code) end
for code=0x41,0x5A do KEY_NAMES[code]=string.char(code) end
for code=0x60,0x69 do KEY_NAMES[code]="Num "..(code-0x60) end
for code=0x70,0x87 do KEY_NAMES[code]="F"..(code-0x6F) end
local KEY_CODES={}
for code in pairs(KEY_NAMES) do KEY_CODES[#KEY_CODES+1]=code end
table.sort(KEY_CODES)

-- Settings -----------------------------------------------------------------
local DEFAULTS={
    enabled=true,
    enabled_on_start=false,
    hub_only=false,
    chat_message=true,
    pad_combo=L3|R3,
    key_combo={},
}
local function load_settings()
    local data=json.load_file(CONFIG_PATH)
    local result={}
    for key,default in pairs(DEFAULTS) do
        local value=type(data)=="table" and data[key]
        result[key]=type(value)==type(default) and value or default
    end
    local keys={}
    for _,code in ipairs(result.key_combo) do
        code=math.tointeger(code)
        if code and KEY_NAMES[code] then keys[#keys+1]=code end
    end
    result.key_combo=keys
    result.pad_combo=math.tointeger(result.pad_combo) or 0
    return result,type(data)=="table"
end
local settings,loaded=load_settings()
local function save_settings() json.dump_file(CONFIG_PATH,settings) end
if not loaded then save_settings() end

local active=settings.enabled_on_start
local logged={}
local function log_once(key,text)
    if logged[key] then return end
    logged[key]=true
    log.error(TAG..text)
end

-- Game helpers -------------------------------------------------------------
local function master_hunter()
    local manager=sdk.get_managed_singleton("app.PlayerManager")
    local info=manager and manager:call("getMasterPlayer()")
    return info and info:call("get_Character()")
end
local function chat(text)
    if not settings.chat_message then return end
    local manager=sdk.get_managed_singleton("app.ChatManager")
    if manager then pcall(manager.call,manager,"addSystemLog(System.String)",text) end
end
local current_stage_method=sdk.find_type_definition("app.OtomoUtil"):get_method("getCurrentStageID()")

-- Local hunter's life area component and stage, refreshed every frame.
local area_address=nil
local in_hub=false
local function refresh()
    local ok,address=pcall(function() return master_hunter():call("get_LifeArea()"):get_address() end)
    area_address=ok and address or nil
    local stage_ok,stage=pcall(current_stage_method.call,current_stage_method,nil)
    in_hub=stage_ok and stage==HUB_STAGE
end
local function forcing() return settings.enabled and active and (in_hub or not settings.hub_only) end

-- Hook ---------------------------------------------------------------------
-- Skipped, the update reports "nothing to do" (true), like an idle component.
local ok,err=pcall(function()
    sdk.hook(sdk.find_type_definition("app.mcHunterLifeArea"):get_method("updateMain()"),function(args)
        local skip=forcing() and area_address~=nil and sdk.to_int64(args[2])==area_address
        thread.get_hook_storage()["skip"]=skip or nil
        if skip then return sdk.PreHookResult.SKIP_ORIGINAL end
    end,function(retval)
        if thread.get_hook_storage()["skip"] then return sdk.to_ptr(1) end
        return retval
    end)
end)
if not ok then log_once("hook","hook failed: "..tostring(err)) end

local function set_active(value)
    active=value
    chat(value and "Draw Weapon Everywhere: ON" or "Draw Weapon Everywhere: OFF")
end

-- Shortcuts -----------------------------------------------------------------
local function pad_keys()
    local manager=sdk.get_managed_singleton("ace.PadManager")
    local pad=manager and manager:call("get_MainPad()")
    local keys=pad and pad:call("get_KeyOn()")
    return type(keys)=="number" and keys&PAD_MASK or 0
end
local function key_down(code) return reframework:is_key_down(code) end

local function pad_name(bits)
    local names={}
    for _,button in ipairs(PAD_BUTTONS) do
        if button.bit~=0 and bits&button.bit==button.bit then names[#names+1]=button[2] end
    end
    return #names>0 and table.concat(names," + ") or "None"
end
local function key_name(codes)
    local names={}
    for _,code in ipairs(codes) do names[#names+1]=KEY_NAMES[code] end
    return #names>0 and table.concat(names," + ") or "None"
end

-- Toggle on the press of a whole combination (rising edge per device).
local pad_held,keys_held=false,false
local function poll_shortcuts()
    local combo=settings.pad_combo
    local held=combo~=0 and pad_keys()&combo==combo
    if held and not pad_held then set_active(not active) end
    pad_held=held
    held=#settings.key_combo>0
    for _,code in ipairs(settings.key_combo) do
        if not key_down(code) then held=false; break end
    end
    if held and not keys_held then set_active(not active) end
    keys_held=held
end

-- Binding: collect everything pressed until all of it is released again.
local binding=nil  -- {device="pad"|"keys", bits=..., codes={}, seen=bool}
local function capture()
    if binding.device=="pad" then
        local keys=pad_keys()
        if keys~=0 then
            binding.bits=binding.bits|keys
        elseif binding.bits~=0 then
            settings.pad_combo=binding.bits
            save_settings()
            binding=nil
        end
        return
    end
    local any=false
    for _,code in ipairs(KEY_CODES) do
        if key_down(code) then
            any=true
            binding.codes[code]=true
        end
    end
    if not any and next(binding.codes) then
        local codes={}
        for code in pairs(binding.codes) do codes[#codes+1]=code end
        table.sort(codes)
        settings.key_combo=codes
        save_settings()
        binding=nil
    end
end

re.on_frame(function()
    if not settings.enabled then return end
    refresh()
    if binding then
        local ok_capture,capture_err=pcall(capture)
        if not ok_capture then binding=nil; log_once("capture","capture: "..tostring(capture_err)) end
    else
        local ok_poll,poll_err=pcall(poll_shortcuts)
        if not ok_poll then log_once("poll","shortcut: "..tostring(poll_err)) end
    end
end)

-- REFramework menu ---------------------------------------------------------
local BOX_PADDING=10
re.on_draw_ui(function()
    if not imgui.tree_node("Draw Weapon Everywhere") then return end
    imgui.begin_rect()
    imgui.spacing()
    imgui.indent(BOX_PADDING)
    local function option(label,key)
        local option_changed,option_value=imgui.checkbox(label,settings[key])
        if option_changed then settings[key]=option_value; save_settings() end
        return option_changed
    end
    if option("Enabled","enabled") and not settings.enabled then
        if active then set_active(false) end
        binding=nil
    end
    if settings.enabled then
        imgui.text("Status: "..(active and "ON" or "OFF").." (toggle with the shortcut)")
        option("Active on game start","enabled_on_start")
        option("Grand Hub only","hub_only")
        option("Chat message on toggle","chat_message")
        local function shortcut(label,device,text,clear)
            imgui.text(label..": "..text)
            imgui.same_line()
            if imgui.button("Set##"..device) then binding={device=device,bits=0,codes={}} end
            imgui.same_line()
            if imgui.button("Clear##"..device) then clear(); save_settings() end
        end
        shortcut("Controller","pad",pad_name(settings.pad_combo),function() settings.pad_combo=0 end)
        shortcut("Keyboard","keys",key_name(settings.key_combo),function() settings.key_combo={} end)
        if binding then
            imgui.text_colored("Press the "..(binding.device=="pad" and "controller buttons" or "keys")
                ..", then release them",0xFF40C0FF)
            imgui.same_line()
            if imgui.button("Cancel") then binding=nil end
        end
        if imgui.button("Reset shortcuts") then
            settings.pad_combo,settings.key_combo=DEFAULTS.pad_combo,{}
            save_settings()
        end
    end
    if not ok then imgui.text_colored("Hook failed: "..tostring(err),0xFF4040FF) end
    imgui.unindent(BOX_PADDING)
    imgui.spacing()
    imgui.end_rect(BOX_PADDING/2)
    imgui.tree_pop()
end)
