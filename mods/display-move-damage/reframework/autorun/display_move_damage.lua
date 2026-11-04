-- display_move_damage: shows the damage of your current and previous move in a
-- copy of the game's training-area combo panel (top: current, bottom: previous).
local TAG="[DisplayMoveDamage] "
local CONFIG_PATH="DisplayMoveDamage/config.json"
local NODE_NAME="DisplayMoveDamagePanel"
local CURRENT="PNL_G02_Group/PNL_TotalDamage"
local PREVIOUS="PNL_G02_Group/PNL_PreviousCombo"
local PATHS={current=CURRENT,previous=PREVIOUS,
    title=CURRENT.."/txt_title",damage=CURRENT.."/PNL_TotalDamage_Damege/txt_Damage",hits=CURRENT.."/txt_hitNum",
    old_title=PREVIOUS.."/txt_title",old_damage=PREVIOUS.."/PNL_PreviousCombo_Damege/txt_Damage",old_hits=PREVIOUS.."/txt_hitNum"}
local PANEL_W,PANEL_H=438,128
-- A hit that lands while the hunter already dodges/moves belongs to the last attack.
local LAST_ATTACK_SECONDS=1.5
local MAX_SHELLS=4096

local function call(object,signature,...)
    if not object then error("Missing receiver for "..signature) end
    return object:call(signature,...)
end
local function try(fn,...)
    local ok,result=pcall(fn,...)
    if ok then return result end
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
local uptime=sdk.find_type_definition("via.Application"):get_method("get_UpTimeSecond()")
local function clock() return uptime:call(nil) end

local logged={}
local function log_once(key,text)
    if logged[key] then return end
    logged[key]=true
    log.error(TAG..text)
end

-- Settings ---------------------------------------------------------------
local schema={
    enabled={default=true},
    large_monsters_only={default=true},
    show_hits={default=true},
    show_in_training={default=true},
    merge_window={default=1,min=.1,max=5},
    hide_delay={default=10,min=1,max=60,integer=true},
    x={default=3,min=0,max=100},
    y={default=65.5,min=0,max=100},
    scale={default=100,min=50,max=200},
}
local function validate(key,value)
    local spec=schema[key]
    if type(spec.default)=="boolean" then
        if type(value)=="boolean" then return value end
    elseif finite(value) then
        if spec.integer then value=math.floor(value+.5) end
        return math.max(spec.min,math.min(spec.max,value))
    end
    return spec.default
end
local function load_settings()
    local ok,config=pcall(json.load_file,CONFIG_PATH)
    local loaded=ok and type(config)=="table"
    config=loaded and config or {}
    local settings={}
    for key in pairs(schema) do settings[key]=validate(key,config[key]) end
    return settings,loaded
end
local function save_settings(settings)
    local config={}
    for key in pairs(schema) do config[key]=validate(key,settings[key]) end
    local ok,err=pcall(json.dump_file,CONFIG_PATH,config)
    if not ok or err==false then log.error(TAG.."Could not write "..CONFIG_PATH..": "..tostring(err)) end
end
local settings,loaded=load_settings()
-- Write the defaults once so the next start does not log a missing config.
if not loaded then save_settings(settings) end

-- Game helpers -----------------------------------------------------------
local SHELL_TYPE=sdk.typeof("app.AppShell")
local ENEMY_TYPE=sdk.typeof("app.EnemyCharacter")
local message_get=sdk.find_type_definition("via.gui.message"):get_method("get(System.Guid)")

local function master_hunter()
    local manager=sdk.get_managed_singleton("app.PlayerManager")
    local info=manager and call(manager,"getMasterPlayer()")
    return info and call(info,"get_Character()")
end
local function static(type_name,signature,...)
    return sdk.find_type_definition(type_name):get_method(signature):call(nil,...)
end
local function message(guid)
    if guid==nil then return end
    local text=try(message_get.call,message_get,nil,guid)
    if type(text)=="string" and text~="" and not text:find("#Rejected#",1,true) and not text:find("---",1,true) then
        return text
    end
end

-- Move names -------------------------------------------------------------
-- Names come from the game's action guide table (the localized move names
-- shown in the action guide), keyed by the action's _ActionGuideID.
local WEAPON_TYPE_COUNT=14
local GUIDE_ALIASES={[-90670656]=1763677568,[1088001664]=1497865856,[8482]=1897592832}
local SUFFIXES={"Land","NoCombo","WeakHit","Front","Back","Left","Right","Loop","End"}
local FIXED={cPorterRide="Riding",cDamageCatch="Pinned",cBattleRide="Mounting"}
local SLINGER,KINSECT,UNKNOWN="Slinger","Kinsect","Unknown"
local WEAPON_LONG_SWORD,WEAPON_GLAIVE,WEAPON_BOW,WEAPON_HEAVY_BOWGUN,WEAPON_LIGHT_BOWGUN=3,10,11,12,13
local MARK_SHOT_HASHES={[729186967]=true,[509541477]=true,[2205688478]=true,[1292422029]=true}

local Names={cache={},by_class={},items={},texts={}}
function Names.load_guides()
    local manager=sdk.get_managed_singleton("app.VariousDataManager")
    local setting=manager and manager:get_field("_Setting")
    local dataset=setting and setting:get_field("_ActionGuideSetting")
    if not dataset then return end
    local guides={}
    local function scan(list)
        if not list then return end
        local values=call(list,"getValues()")
        for i=0,call(values,"get_Count()")-1 do
            local entry=call(values,"get_Item(System.Int32)",i)
            local guide,guid=entry and entry:get_field("_Action"),entry and entry:get_field("_ActionName")
            if type(guide)=="number" and guid~=nil then guides[guide]=guid end
        end
    end
    scan(dataset:get_field("_ActionGuideName_Common"))
    for weapon=0,WEAPON_TYPE_COUNT-1 do scan(dataset:get_field(string.format("_ActionGuideName_Wp%02d",weapon))) end
    return guides
end
function Names.guide(guide)
    if not Names.guides and (not Names.retry_at or clock()>=Names.retry_at) then
        local ok,guides=pcall(Names.load_guides)
        if ok and guides then Names.guides=guides
        else
            Names.retry_at=clock()+5
            if not ok then log_once("guides",tostring(guides)) end
        end
    end
    if not Names.guides or guide==nil then return end
    if Names.texts[guide]==nil then Names.texts[guide]=message(Names.guides[guide]) or false end
    return Names.texts[guide] or nil
end
function Names.action(class,guide)
    local key=class..":"..tostring(guide)
    if Names.cache[key] then return Names.cache[key] end
    local name
    if guide~=-1 then
        name=Names.guide(guide)
        if not name and GUIDE_ALIASES[guide] then name=Names.guide(GUIDE_ALIASES[guide]) end
    end
    if name then
        Names.cache[key]=name; Names.by_class[class]=name
        return name
    end
    for prefix,fixed in pairs(FIXED) do
        if class:sub(1,#prefix)==prefix then return fixed end
    end
    -- Variants such as cFooLand/cFooLoop share the name of cFoo.
    for _,suffix in ipairs(SUFFIXES) do
        if class:sub(-#suffix)==suffix then
            local sibling=Names.by_class[class:sub(1,#class-#suffix)]
            if sibling then return sibling end
        end
    end
    return (class:gsub("^c",""))
end
function Names.item(item)
    if Names.items[item] then return Names.items[item] end
    local name=message(try(static,"app.ItemDef","Name(app.ItemDef.ID)",item))
    if name then Names.items[item]=name end
    return name or ("#"..tostring(item))
end

-- Current action ---------------------------------------------------------
local function describe(action)
    if not action then return end
    local class=action:get_type_definition():get_name()
    local guide=action:get_field("_ActionGuideID")
    return class,type(guide)=="number" and guide or -1
end
local function controller_action(hunter,getter)
    local ok,class,guide=pcall(function() return describe(call(call(hunter,getter),"get_CurrentAction()")) end)
    if ok then return class,guide end
end
local function non_attack(class)
    return class~=nil and (class:find("^cDodge") or class:find("^cDamage") or class:find("^cLandSmash")
        or class:find("^cMove$") or class:find("^cAimWalk") or class:find("^cDash")
        or class:find("^cUseItem") or class:find("^cSlinger"))~=nil
end
-- Same choice of base/sub action controller as MyHuntReport.
local function current_action(hunter)
    if not hunter then return end
    local sub,sub_guide=controller_action(hunter,"get_SubActionController()")
    if sub and (sub:find("^cSlinger") or sub:find("^cCatchSlinger")) then return nil,nil,true end
    if sub and (sub:find("^cShot") or sub:find("^cShoot")) then return sub,sub_guide end
    local class,guide=controller_action(hunter,"get_BaseActionController()")
    if class and class:find("^cPorterRide") and sub and sub~="cNothing" then return sub,sub_guide end
    if class and not non_attack(class) and sub and sub~="cNothing" and sub_guide~=-1
        and (guide==-1 or not Names.guide(guide)) and Names.guide(sub_guide) then
        return sub,sub_guide
    end
    return class,guide
end

local last_attack=nil
local function track_last_attack()
    local hunter=master_hunter()
    local class,guide=current_action(hunter)
    if class and not non_attack(class) then
        last_attack=last_attack or {}
        last_attack.class,last_attack.guide,last_attack.time=class,guide,clock()
    end
end

local function action_name(hunter)
    local class,guide,slinger=current_action(hunter)
    if slinger then return SLINGER end
    if non_attack(class) and last_attack and clock()-last_attack.time<=LAST_ATTACK_SECONDS then
        class,guide=last_attack.class,last_attack.guide
    end
    return class and Names.action(class,guide) or UNKNOWN
end

-- Projectiles ------------------------------------------------------------
-- Shells (arrows, ammo, delayed slashes, ...) keep the move that launched them.
local shells,shell_count={},0
local function set_shell(address,name)
    if shells[address]==nil and name~=nil then shell_count=shell_count+1
    elseif shells[address]~=nil and name==nil then shell_count=shell_count-1 end
    shells[address]=name
end
local function launch_name(shell,hunter)
    local weapon=try(call,hunter,"get_WeaponType()")
    if weapon==WEAPON_GLAIVE and MARK_SHOT_HASHES[try(call,shell,"get_NameHash()")] then
        return Names.action("cGunShot",-1726610048)
    end
    if weapon==WEAPON_LONG_SWORD then
        local handling=try(call,hunter,"get_WeaponHandling()")
        if handling and handling:get_field("_IsKabutowariDelayHitSetup")==true then
            return Names.action("cKabutowariLand",1909693824)
        end
        if handling and handling:get_field("_IsWeakPointBreakDelayReserve")==true then
            return Names.action("cWeakHitSlashDir",-1840683648)
        end
    end
    local name=action_name(hunter)
    if name==SLINGER then return name end
    local handling=try(call,hunter,"get_WeaponHandling()")
    if handling and (weapon==WEAPON_LIGHT_BOWGUN or weapon==WEAPON_HEAVY_BOWGUN) then
        local shell_type=handling:get_field("_ActionShellType")
        local item=finite(shell_type) and try(static,"app.WeaponGunDef","getItemIDFromShellType(System.Int32)",shell_type)
        if finite(item) and item>0 then
            local class=current_action(hunter) or ""
            local ammo=Names.item(item)
            if class:find("Variable",1,true) or class:find("StepDodge",1,true) then return ammo.." - "..name end
            if handling:get_field("_IsRapidShotBoost")==true then return ammo.." (Rapid)" end
            return ammo
        end
    elseif handling and weapon==WEAPON_BOW then
        local bottle=try(call,handling,"get_BottleType()")
        local item=handling:get_field("SelectedBottleItem")
        if finite(bottle) and bottle>0 and finite(item) then return name.." ["..Names.item(item).."]" end
    end
    return name
end

-- Move tracking ----------------------------------------------------------
local Move={visible=false,dirty=false}
function Move.clear()
    Move.current,Move.previous,Move.hide_at=nil,nil,nil
    Move.current_state,Move.previous_state=nil,nil
    Move.visible=false; Move.dirty=true
end
function Move.hit(name,damage,now)
    local current=Move.current
    if current and current.name==name and now-current.last<=settings.merge_window then
        current.damage,current.hits,current.last=current.damage+damage,current.hits+1,now
        Move.current_state=Move.visible and "ATTACK" or "FADE_IN"
    else
        Move.previous=current
        Move.current={name=name,damage=damage,hits=1,last=now}
        Move.current_state="FADE_IN"
        if current then Move.previous_state="FADE_IN" end
    end
    if not Move.visible and Move.previous then Move.previous_state="FADE_IN" end
    Move.visible=true; Move.hide_at=now+settings.hide_delay; Move.dirty=true
end
function Move.preview()
    local now=clock()
    Move.previous={name="Previous move",damage=987,hits=2,last=now}
    Move.current={name="Current move",damage=1234,hits=3,last=now}
    Move.current_state,Move.previous_state="FADE_IN","FADE_IN"
    Move.visible=true; Move.hide_at=now+settings.hide_delay; Move.dirty=true
end

local function on_hit(calc,hit)
    if not calc or not hit then return end
    local damage=calc:get_field("FinalDamage")
    if not finite(damage) or damage<=0 then return end
    local hunter=master_hunter()
    if not hunter then return end
    local owner=call(hit,"getActualAttackOwner()")
    if not owner or id(owner)~=id(call(hunter,"get_GameObject()")) then return end
    local target=call(hit,"get_DamageOwner()")
    local enemy=target and call(target,"getComponent(System.Type)",ENEMY_TYPE)
    local context=enemy and enemy:get_field("_Context")
    local em=context and context:get_field("_Em")
    if not em then return end
    if settings.large_monsters_only and call(em,"get_IsBoss()")~=true then return end
    local name
    local object=try(call,hit,"get_AttackObj()")
    if object then
        local shell=try(call,object,"getComponent(System.Type)",SHELL_TYPE)
        name=shell and shells[shell:get_address()]
        local object_name=not name and try(call,object,"get_Name()")
        if type(object_name)=="string" then
            if object_name=="Tip" or object_name:find("^SlingerShell") then name=SLINGER
            elseif object_name:sub(1,6)=="it1003" then name=KINSECT end
        end
    end
    Move.hit(name or action_name(hunter),damage,clock())
end

local function hook(type_name,signature,pre,post)
    local method=sdk.find_type_definition(type_name):get_method(signature)
    if not method then log.error(TAG.."Missing method "..type_name.."."..signature); return end
    sdk.hook(method,pre,post)
end
local function guarded(key,fn)
    return function(args)
        if not settings.enabled then return end
        local ok,err=pcall(fn,args)
        if not ok then log_once(key,key..": "..tostring(err)) end
    end
end

hook("app.cEnemyStockDamage.mcEnemyHitMarkManager","playHitMarkEffect(app.cEnemyStockDamage.cCalcDamage, app.HitInfo)",
    guarded("hit",function(args) on_hit(sdk.to_managed_object(args[3]),sdk.to_managed_object(args[4])) end))
hook("app.AppShell","doOnSetUp",guarded("shell",function(args)
    local shell=sdk.to_managed_object(args[2])
    if not shell then return end
    local hunter=master_hunter()
    local owner=try(call,shell,"get_ShellOwner()")
    if not hunter or not owner or id(owner)~=id(call(hunter,"get_GameObject()")) then return end
    if shell_count>=MAX_SHELLS then shells,shell_count={},0 end
    local parent=try(call,shell,"get_ParentShell()")
    set_shell(shell:get_address(),parent and shells[parent:get_address()] or launch_name(shell,hunter))
end))
hook("app.AppShell","doOnDestroy",guarded("shell",function(args)
    local shell=sdk.to_managed_object(args[2])
    if shell then set_shell(shell:get_address(),nil) end
end))

-- Native panel -----------------------------------------------------------
-- A duplicate of the training area's combo display (UI600100), attached to
-- the HUD root of UI020012 the same way WildsHUD shows its player damage.
local Panel={status="Waiting for first hit"}
local function in_training()
    local manager=sdk.get_managed_singleton("app.GUIManager")
    local guide=manager and call(manager,"get_ActionGuide()")
    return guide~=nil and call(guide,"get_IsTrainingArea()")==true
end
-- app.GUIManager.openGUI with 4 parameters, preferring the one declared on
-- the type itself (same lookup as WildsHUD).
local function open_gui_method()
    local td=sdk.find_type_definition("app.GUIManager")
    while td do
        local found,declared={},{}
        for _,method in ipairs(td:get_methods()) do
            if method:get_name()=="openGUI" and method:get_num_params()==4 then
                found[#found+1]=method
                if method:get_declaring_type():get_full_name()==td:get_full_name() then declared[#declared+1]=method end
            end
        end
        if #declared>0 then found=declared end
        if #found==1 then return found[1] end
        td=td:get_parent_type()
    end
    error("app.GUIManager.openGUI/4 not found")
end
-- Combo panel of UI600100; asks the game to load and open that GUI (again
-- every 2 seconds) while it is not available.
function Panel.source()
    local manager=sdk.get_managed_singleton("app.GUIManager")
    Panel.source_id=Panel.source_id or enum("app.GUIID.ID","UI600100")
    local source=call(manager,"getGUI(app.GUIID.ID)",Panel.source_id)
    local combo=source and source:get_field("_ComboDisplayPanel")
    if combo then return combo end
    local now=clock()
    if Panel.next_request and now<Panel.next_request then return end
    Panel.next_request=now+2
    local waits=manager:get_field("_WaitInstantiate")
    local waiting=waits and waits:get_size()>Panel.source_id and waits:get_element(Panel.source_id)
    local instantiating=call(manager,"isInstantiateWithOpenGUI(app.GUIID.ID)",Panel.source_id)
    if not source and not waiting and not instantiating then
        call(manager,"instantiateWithOpenGUIEvent(app.GUIID.ID)",Panel.source_id)
    end
    local open=call(manager,"isOpenGUI(app.GUIID.ID)",Panel.source_id)
    local open_request=call(manager,"hasOpenRequestGUI(app.GUIID.ID)",Panel.source_id)
    if not open and not open_request then
        Panel.open_gui=Panel.open_gui or open_gui_method()
        Panel.open_gui:call(manager,Panel.source_id,nil,nil,nil)
    end
end
function Panel.prepare(root)
    local combo=Panel.source()
    if not combo then Panel.status="Waiting for native combo panel"; return end
    local ok,result=pcall(call,combo,"duplicate(System.String)",NODE_NAME)
    local group=ok and result or child(call(combo,"get_Parent()"),NODE_NAME)
    if not group then error("Cannot duplicate combo panel: "..tostring(result)) end
    call(root,"addChild(via.gui.PlayObject)",group)
    call(group,"set_ForceInvisible(System.Boolean)",false)
    call(group,"set_ResolutionAdjust(System.Boolean)",false)
    for _,path in pairs(PATHS) do
        local n=resolve(group,path)
        if n then
            call(n,"set_Visible(System.Boolean)",true); call(n,"set_ForceInvisible(System.Boolean)",false)
        end
    end
    return group
end
-- Group scale = combo panel size on screen, times the scale setting.
function Panel.place(gui,root,group)
    local combo=Panel.source()
    local m=call(root,"get_WorldMatrix()")
    if combo then
        local a=call(combo,"get_WorldMatrix()")
        Panel.base={x=a[0].x/m[0].x,y=a[1].y/m[1].y}
    end
    if not Panel.base then return false end
    local z=settings.scale/100
    local scale=call(group,"get_Scale()")
    scale.x,scale.y=z*Panel.base.x,z*Panel.base.y
    call(group,"set_Scale(via.vec3)",scale)
    local screen=call(gui:get_field("_Root"),"get_ScreenSize()")
    local w,h=PANEL_W*m[0].x*scale.x,PANEL_H*m[1].y*scale.y
    local p=call(group,"get_Position()")
    p.x=(w/2+(screen.w-w)*settings.x/100-m[3].x)/m[0].x
    p.y=((screen.h-h)*settings.y/100-m[3].y)/m[1].y
    call(group,"set_Position(via.vec3)",p)
    return true
end
function Panel.flush(gui)
    local root=resolve(root_window(gui),"PNL_All")
    if not root then return end
    if id(root)~=Panel.root_id then Panel.root_id,Panel.layout=id(root),true end
    local show=settings.enabled and Move.visible and Move.current~=nil
        and (settings.show_in_training or not in_training())
    local group=child(root,NODE_NAME)
    if not group then
        if not show then Move.dirty=false; return end
        group=Panel.prepare(root)
        if not group then return end
        Panel.layout=true
    end
    if not show then
        call(group,"set_Visible(System.Boolean)",false)
        Panel.status="Hidden"; Move.dirty=false
        return
    end
    local function text(role,value) call(resolve(group,PATHS[role]),"set_Message(System.String)",value) end
    local function visible(role,value) call(resolve(group,PATHS[role]),"set_Visible(System.Boolean)",value) end
    local function hits(count) return string.format('%d <PLURAL %d "Hit" "Hits">',count,count) end
    local current,previous=Move.current,Move.previous
    text("title",current.name); text("damage",tostring(math.floor(current.damage))); text("hits",hits(current.hits))
    visible("hits",settings.show_hits)
    visible("previous",previous~=nil)
    if previous then
        text("old_title",previous.name); text("old_damage",tostring(math.floor(previous.damage)))
        text("old_hits",hits(previous.hits)); visible("old_hits",settings.show_hits)
    end
    if Panel.layout and Panel.place(gui,root,group) then Panel.layout=nil end
    call(group,"set_Visible(System.Boolean)",true)
    if Move.current_state then call(resolve(group,PATHS.current),"set_PlayState(System.String)",Move.current_state) end
    if Move.previous_state and previous then
        call(resolve(group,PATHS.previous),"set_PlayState(System.String)",Move.previous_state)
    end
    Move.current_state,Move.previous_state=nil,nil
    Panel.status="Showing"
    Move.dirty=Panel.layout==true
end
function Panel.hide()
    local manager=sdk.get_managed_singleton("app.GUIManager")
    local gui=manager and call(manager,"getGUI(app.GUIID.ID)",enum("app.GUIID.ID","UI020012"))
    local root=resolve(root_window(gui),"PNL_All")
    local group=root and child(root,NODE_NAME)
    if group then call(group,"set_Visible(System.Boolean)",false) end
end

-- Hooks ------------------------------------------------------------------
local stopped,pending=false,0
local function active() return not stopped and not Panel.error and Move.dirty end
local function guard(fn,...)
    local ok,err=xpcall(fn,debug.traceback,...)
    if not ok then
        Panel.error=tostring(err); Panel.status="Panel stopped"
        log.error(TAG..Panel.error)
    end
end

-- GUI changes only inside the HUD's own guiUpdate, never from on_frame.
sdk.hook(sdk.find_type_definition("app.GUIHudBase"):get_method("guiUpdate()"),function(args)
    if not active() then return end
    local owner=sdk.to_managed_object(args[2])
    if owner and owner:get_type_definition():get_full_name()=="app.GUI020015" then
        thread.get_hook_storage().display_move_damage_pending=true
        pending=pending+1
    end
end,function(retval)
    if pending==0 then return retval end
    local storage=thread.get_hook_storage()
    if not storage.display_move_damage_pending then return retval end
    storage.display_move_damage_pending=nil; pending=pending-1
    if active() then guard(function()
        local manager=sdk.get_managed_singleton("app.GUIManager")
        Panel.gui_id=Panel.gui_id or enum("app.GUIID.ID","UI020012")
        local gui=manager and call(manager,"getGUI(app.GUIID.ID)",Panel.gui_id)
        if gui then Panel.flush(gui) end
    end) end
    return retval
end)

re.on_frame(function()
    if stopped or not settings.enabled then return end
    pcall(track_last_attack)
end)

re.on_application_entry("UpdateGUI",function()
    if stopped then return end
    if Move.hide_at and clock()>=Move.hide_at then
        Move.hide_at,Move.visible,Move.dirty=nil,false,true
    end
end)

re.on_draw_ui(function()
    if stopped or not imgui.tree_node("DisplayMoveDamage") then return end
    local function control(label,key,format)
        local spec=schema[key]
        local changed,value
        if type(spec.default)=="boolean" then
            changed,value=imgui.checkbox(label,settings[key])
        else
            changed,value=imgui.slider_float(label,settings[key],spec.min,spec.max,format or (spec.integer and "%.0f" or "%.2f"))
        end
        if changed then
            settings[key]=validate(key,value); save_settings(settings)
            Panel.layout=true; Move.dirty=true
            if key=="enabled" and not value then Move.clear() end
        end
    end
    control("Enable","enabled")
    control("Large monsters only","large_monsters_only")
    control("Show hit count","show_hits")
    control("Show in training area","show_in_training")
    control("Merge window (seconds)","merge_window")
    control("Auto-hide (seconds)","hide_delay")
    imgui.text("Position")
    control("X","x")
    control("Y","y")
    control("Scale","scale","%.0f")
    if imgui.button("Preview") and settings.enabled then Move.preview() end
    imgui.same_line()
    if imgui.button("Reset to default settings") then
        for key,spec in pairs(schema) do settings[key]=spec.default end
        save_settings(settings); Panel.layout=true; Move.dirty=true
    end
    imgui.text("Status: "..Panel.status)
    if Panel.error then imgui.text("Error: "..Panel.error:match("[^\r\n]*"):sub(1,240)) end
    imgui.tree_pop()
end)

re.on_script_reset(function()
    pcall(Panel.hide); stopped=true
end)
