-- WildsHUDFork: only the monster HP value text of WildsHUD, with selectable alignment.
local CONFIG_PATH="WildsHUDFork/config.json"
local LEGACY_CONFIG_PATH="WildsHUD/config.json"
local NODE_NAME="WildsHUDForkMonsterHP_value"
-- via.gui ControlPoint/PageAlignment/LetterAlignment values (bottom row).
local ALIGNMENT={Left=8,Center=9,Right=10}
local POLL_SECONDS=.1

local function call(object,signature,...)
    if not object then error("Missing receiver for "..signature) end
    return object:call(signature,...)
end
local function id(n) return n and tostring(n:get_address()) end
local function finite(v) return type(v)=="number" and v==v and math.abs(v)<math.huge end
local function enum(type_name,name)
    return sdk.find_type_definition(type_name):get_field(name):get_data(nil)
end
local function child(root,name) return call(root,"getObject(System.String)",name) end
local function resolve(root,path)
    for name in path:gmatch("[^/]+") do root=root and child(root,name); if not root then return end end
    return root
end
local function root_window(gui)
    return gui and (gui:get_field("_RootWindow") or gui:get_field("<_RootWindow>k__BackingField"))
end
local function set_size(n,w,h,property)
    local s=call(n,"get_"..property.."()"); s.w,s.h=w,h
    call(n,"set_"..property.."(via.Size)",s)
end
local function set_position(n,x,y)
    local p=call(n,"get_Position()"); p.x,p.y,p.z=x,y,0
    call(n,"set_Position(via.vec3)",p)
end
local function set_color(n,property,rgba)
    local c=call(n,"get_"..property.."()")
    sdk.set_native_field(c,sdk.find_type_definition("via.Color"),"rgba",rgba)
    call(n,"set_"..property.."(via.Color)",c)
end

-- Settings ---------------------------------------------------------------
local schema={
    monster_hp_enabled={default=true},
    monster_hp_value_mode={default="Percent",options={"Percent","Number"}},
    monster_hp_x={default=39.5,min=0,max=100},
    monster_hp_y={default=95,min=0,max=100},
    monster_hp_bar_scale={default=100,min=80,max=200},
    monster_hp_bar_length={default=525,min=200,max=1000},
    monster_hp_value_x={default=80.8,min=0,max=100,json_key="monster_hp_value_position_x"},
    monster_hp_value_y={default=69.5,min=0,max=100,json_key="monster_hp_value_position_y"},
    monster_hp_value_font_size={default=16,min=16,max=32},
    monster_hp_value_align={default="Left",options={"Left","Center","Right"}},
}
local function validate(key,value)
    local spec=schema[key]
    if spec.options then
        for _,option in ipairs(spec.options) do if value==option then return value end end
    elseif type(spec.default)=="boolean" then
        if type(value)=="boolean" then return value end
    elseif finite(value) then
        return math.max(spec.min,math.min(spec.max,value))
    end
    return spec.default
end
local function load_settings()
    local ok,config=pcall(json.load_file,CONFIG_PATH)
    -- First run: take over the settings of the original WildsHUD.
    if not ok or type(config)~="table" then ok,config=pcall(json.load_file,LEGACY_CONFIG_PATH) end
    config=ok and type(config)=="table" and config or {}
    local settings={}
    for key,spec in pairs(schema) do settings[key]=validate(key,config[spec.json_key or key]) end
    return settings
end
local function save_settings(settings)
    local config={}
    for key,spec in pairs(schema) do config[spec.json_key or key]=validate(key,settings[key]) end
    local ok,err=pcall(json.dump_file,CONFIG_PATH,config)
    if not ok or err==false then log.error("[WildsHUDFork] Could not write "..CONFIG_PATH..": "..tostring(err)) end
end
local settings=load_settings()

-- Native text node -------------------------------------------------------
-- Clones the game's own text element (_MaxFallText from UI020003) into the
-- HUD root of UI020012 so the value is drawn with the native font.
local function create_text(root)
    local existing=child(root,NODE_NAME)
    if existing then return existing end
    local source=call(sdk.get_managed_singleton("app.GUIManager"),"getGUI(app.GUIID.ID)",enum("app.GUIID.ID","UI020003"))
    local original=source and source:get_field("_MaxFallText")
    if not original then return end
    local kind=original:get_type_definition():get_full_name()
    local template=assert(sdk.create_instance(kind),"Cannot allocate "..kind)
    local n
    local ok,err=xpcall(function()
        assert(call(root,"addChild(via.gui.PlayObject)",template),"Cannot attach blank graphic")
        local blank_block=assert(tonumber(template:read_qword(0x28)),"Blank native block unavailable")
        local source_block=assert(tonumber(original:read_qword(0x28)),"Source native block unavailable")
        assert(blank_block==0,"Unsupported blank native block")
        call(original,"copyProperties(via.gui.PlayObject)",template)
        call(template,"set_Visible(System.Boolean)",false)
        local success,result=pcall(call,template,"duplicate(System.String)",NODE_NAME)
        n=success and result or child(root,NODE_NAME)
        assert(n,"Cannot create named graphic: "..tostring(result))
        if id(call(n,"get_Parent()"))~=id(root) then
            assert(call(root,"addChild(via.gui.PlayObject)",n),"Cannot attach "..NODE_NAME)
        end
        assert(tonumber(n:read_qword(0x28))==source_block,"Unexpected copied native block")
        n:write_qword(0x28,blank_block)
        assert(tonumber(n:read_qword(0x28))==blank_block,"Native block restore failed")
        call(n,"set_Priority(System.UInt16)",210)
        call(n,"set_ForceInvisible(System.Boolean)",false)
        call(n,"set_Visible(System.Boolean)",false)
        call(n,"set_AutoRegionFit(via.gui.RegionFitType)",0)
        call(n,"set_Bold(System.Boolean)",false)
        call(n,"set_ShadowStrength(System.Single)",2)
        call(n,"set_LetterSpace(System.Single)",0)
        set_color(n,"Color",0xFFFFFFFF)
        set_color(n,"GlowColor",0xFF000000)
        set_color(n,"ShadowColor",0xFF000000)
        set_size(n,525,80,"RegionSize")
    end,debug.traceback)
    pcall(call,template,"remove()")
    if not ok then
        if n then pcall(call,n,"remove()") end
        error(err)
    end
    return n
end

-- HP value ---------------------------------------------------------------
local HP={status="Waiting for monster"}
function HP.owner()
    local manager=sdk.get_managed_singleton("app.GUIManager")
    if not manager then return end
    HP.gui_id=HP.gui_id or enum("app.GUIID.ID","UI020012")
    local gui=call(manager,"getGUI(app.GUIID.ID)",HP.gui_id)
    return gui,resolve(root_window(gui),"PNL_All")
end
function HP.target()
    local manager=sdk.get_managed_singleton("app.CameraManager")
    local camera=manager and manager:get_field("_MasterPlCamera")
    local browser=camera and call(camera,"get_LockTarget()")
    if not browser or call(browser,"get_IsCharacterValid()")~=true
        or call(browser,"get_IsDie()")==true or call(browser,"get_IsCapture()")==true then return end
    local em=call(browser,"get_EmContext()")
    if not em or call(em,"get_IsBoss()")~=true then return end
    local info=call(camera,"get_LockTargetInfo()")
    if not info or call(info,"get_CharacterValid()")~=true then return end
    local enemy=call(info,"get_Character()")
    local health=enemy and call(enemy,"get_HealthMgr()")
    if not health then return end
    local hp,maximum=call(health,"get_Health()"),call(health,"get_MaxHealth()")
    if not finite(hp) or not finite(maximum) or hp<=0 or maximum<=0 then return end
    return hp,maximum
end
function HP.message(hp,maximum)
    if settings.monster_hp_value_mode=="Number" then return tostring(math.floor(hp+.5)) end
    return string.format("%.2f %%",math.max(0,math.min(1,hp/maximum))*100)
end
function HP.hide()
    if not HP.node_id then return end
    local gui,root=HP.owner()
    if root and id(gui)==HP.owner_id and id(root)==HP.root_id then
        local n=child(root,NODE_NAME)
        if n then call(n,"set_Visible(System.Boolean)",false) end
    end
    HP.last=nil
end
-- Returns true while a target is shown.
function HP.update(gui,root)
    if HP.error or not gui or not root then return false end
    if HP.node_id and (id(gui)~=HP.owner_id or id(root)~=HP.root_id) then
        HP.node_id,HP.last,HP.layout=nil,nil,nil
    end
    local hp,maximum
    if settings.monster_hp_enabled then hp,maximum=HP.target() end
    if not HP.node_id then
        if not hp then return false end
        local n=create_text(root)
        if not n then HP.status="Waiting for native HP resources"; return false end
        HP.node_id,HP.owner_id,HP.root_id,HP.retry=id(n),id(gui),id(root),true
    end
    local n=assert(child(root,NODE_NAME),"Missing owned graphic: "..NODE_NAME)
    local screen=call(gui:get_field("_Root"),"get_ScreenSize()")
    local t=settings
    local s={show=hp~=nil,message=hp and HP.message(hp,maximum) or "",
        x=t.monster_hp_x,y=t.monster_hp_y,scale=t.monster_hp_bar_scale,length=t.monster_hp_bar_length,
        value_x=t.monster_hp_value_x,value_y=t.monster_hp_value_y,font=t.monster_hp_value_font_size,align=t.monster_hp_value_align,
        screen_w=screen.w,screen_h=screen.h}
    local previous=HP.last or {}
    local changed=HP.last==nil
    for k,v in pairs(s) do if previous[k]~=v then changed=true; break end end
    if changed then
        HP.last=s
        local z=s.scale/100
        if not HP.layout or previous.x~=s.x or previous.y~=s.y or previous.scale~=s.scale
            or previous.length~=s.length or previous.screen_w~=s.screen_w or previous.screen_h~=s.screen_h then
            -- Anchor = where the original HP bar would sit; screen -> root-local space.
            local m=call(root,"get_WorldMatrix()")
            local ax,ay,bx,by=m[0].x,m[0].y,m[1].x,m[1].y
            local tx,ty=m[3].x,m[3].y; local det=ax*by-ay*bx
            local gx=26*z*ax+(s.screen_w-(s.length*z+52*z)*ax)*s.x/100
            local gy=14*z*by+(s.screen_h-28*z*by)*s.y/100
            HP.layout={x=((gx-tx)*by-(gy-ty)*bx)/det,y=((gy-ty)*ax-(gx-tx)*ay)/det}
        end
        call(n,"set_Visible(System.Boolean)",s.show)
        if previous.font~=s.font then set_size(n,s.font,s.font,"FontSize") end
        if previous.align~=s.align then
            -- The position is the anchor; the text sits left of, around or right of it.
            local a=ALIGNMENT[s.align]
            call(n,"set_ControlPoint(via.gui.ControlPoint)",a)
            call(n,"set_LetterAlignment(via.gui.LetterAlignment)",a)
            call(n,"set_PageAlignment(via.gui.PageAlignment)",a)
        end
        if previous.message~=s.message then call(n,"set_Message(System.String)",s.message) end
        if s.show then
            set_position(n,HP.layout.x+z*((s.length+200)*s.value_x/100-100),HP.layout.y+z*(2*s.value_y-100))
        end
    elseif HP.retry then
        -- A freshly created text node can drop its first message; set it once more.
        call(n,"set_Message(System.String)",s.message); HP.retry=nil
    end
    HP.status=hp and "Showing HP" or "HP hidden"
    return hp~=nil
end

-- Hooks ------------------------------------------------------------------
local stopped,tracking,next_probe,pending=false,false,nil,0
local uptime=sdk.find_type_definition("via.Application"):get_method("get_UpTimeSecond()")
local function clock() return uptime:call(nil) end
local function guard(fn,...)
    local ok,err=xpcall(fn,debug.traceback,...)
    if not ok then
        HP.error=tostring(err); HP.status="Native HP stopped"
        log.error("[WildsHUDFork] "..HP.error)
    end
    return ok and err
end
local function active() return not stopped and not HP.error and settings.monster_hp_enabled and tracking end

-- Update right after the HUD's own guiUpdate so the text isn't overwritten.
sdk.hook(sdk.find_type_definition("app.GUIHudBase"):get_method("guiUpdate()"),function(args)
    if not active() then return end
    local owner=sdk.to_managed_object(args[2])
    if owner and owner:get_type_definition():get_full_name()=="app.GUI020015" then
        thread.get_hook_storage().wilds_hud_pending=true
        pending=pending+1
    end
end,function(retval)
    if pending==0 then return retval end
    local storage=thread.get_hook_storage()
    if not storage.wilds_hud_pending then return retval end
    storage.wilds_hud_pending=nil; pending=pending-1
    if active() then guard(function()
        if not HP.update(HP.owner()) then tracking=false; next_probe=clock()+POLL_SECONDS end
    end) end
    return retval
end)

re.on_application_entry("UpdateGUI",function()
    if stopped or HP.error then return end
    if not settings.monster_hp_enabled then
        if tracking or HP.last then guard(HP.hide) end
        tracking,next_probe=false,nil
        return
    end
    if tracking then return end
    guard(function()
        local now=clock()
        if not next_probe or now>=next_probe then
            next_probe=now+POLL_SECONDS
            if HP.target() then tracking=true end
        end
    end)
end)

re.on_draw_ui(function()
    if stopped or not imgui.tree_node("WildsHUDFork") then return end
    local function control(label,key,format)
        local spec=schema[key]
        local changed,value
        if spec.options then
            local selected=1
            for i,option in ipairs(spec.options) do if settings[key]==option then selected=i end end
            local index
            changed,index=imgui.combo(label,selected,spec.options)
            value=spec.options[index]
        elseif type(spec.default)=="boolean" then
            changed,value=imgui.checkbox(label,settings[key])
        else
            changed,value=imgui.slider_float(label,settings[key],spec.min,spec.max,format or "%.2f")
        end
        if changed then settings[key]=validate(key,value); save_settings(settings) end
    end
    control("Enable","monster_hp_enabled")
    control("Value","monster_hp_value_mode")
    control("Font size","monster_hp_value_font_size","%.1f")
    control("Alignment","monster_hp_value_align")
    imgui.text("Anchor")
    control("X##anchor","monster_hp_x")
    control("Y##anchor","monster_hp_y")
    control("Scale","monster_hp_bar_scale","%.1f")
    control("Length","monster_hp_bar_length","%.1f")
    imgui.text("Offset")
    control("X##value","monster_hp_value_x")
    control("Y##value","monster_hp_value_y")
    if imgui.button("Reset to default settings") then
        for key,spec in pairs(schema) do settings[key]=spec.default end
        save_settings(settings)
    end
    imgui.text("Status: "..HP.status)
    if HP.error then imgui.text("HP error: "..HP.error:match("[^\r\n]*"):sub(1,240)) end
    imgui.tree_pop()
end)

re.on_script_reset(function()
    guard(HP.hide); stopped=true
end)
