local U=require('autobuilder.core.util')
local Config=require('autobuilder.config')
local Checkpoint=require('autobuilder.core.checkpoint')
local IO=require('autobuilder.install.io')
local M={}
local settingsPath='/autobuilder/settings.lua'
local containers={['minecraft:chest']=true,['minecraft:trapped_chest']=true,['minecraft:barrel']=true}
local function ask(e,label,validate,default)
  while true do
    e.write(label..(default and ' ['..default..']' or '')..': ')
    local line=e.read(); assert(type(line)=='string','Input cancelled')
    line=line:match('^%s*(.-)%s*$'); if line=='' and default then line=default end
    local value,err=validate(line)
    if value~=nil then return value end
    e.print(err or 'Please enter one of the listed choices.')
  end
end
local function yes(e,label)
  return ask(e,label,function(v)
    v=v:lower(); if v=='y' or v=='yes' then return true elseif v=='n' or v=='no' then return false end
  end,'no')
end
local function coordinate(line)
  local x,y,z=line:match('^(%-?%d+)%s+(%-?%d+)%s+(%-?%d+)$')
  local p={x=tonumber(x),y=tonumber(y),z=tonumber(z)}
  if U.position(p) then return p end
  return nil,'Enter three whole numbers separated by spaces: x y z'
end
local function describe(p) return p.x..' '..p.y..' '..p.z end
function M.inventories(e)
  local found={}
  for _,name in ipairs(e.peripheral.getNames()) do
    local ok,methods=pcall(e.peripheral.getMethods,name); local has={}
    if ok and type(methods)=='table' then for _,method in ipairs(methods) do has[method]=true end end
    if has.list and has.size and has.pushItems then
      local good,items=pcall(e.peripheral.call,name,'list')
      if good and type(items)=='table' then
        local counts={}; for _,item in pairs(items) do counts[item.name]=(counts[item.name] or 0)+item.count end
        found[#found+1]={name=name,items=counts,container=containers[e.peripheral.getType(name)]==true}
      end
    end
  end
  table.sort(found,function(a,b) return a.name<b.name end); return found
end
local function idle(e,config)
  local store=Checkpoint.new(e.fs,e.textutils,config.dataDir..'/'..config.role..'.state')
  local state,source=store:load()
  assert(source=='primary' or source=='missing','Checkpoint recovery required before setup: '..source)
  if state then
    assert(state.schema==1 and state.id==e.os.getComputerID() and state.role==config.role
      and U.integer(state.boot) and type(state.phase)=='string','Invalid or foreign checkpoint')
    assert(not state.assignmentRecovery and not state.currentTask and not state.motionReservation
      and not next(state.pendingSupplyAcks or {}),'Finish current jobs and acknowledgements before setup')
    if config.role=='worker' then
      assert(type(state.position)=='table' and type(state.position.known)=='boolean','Invalid saved position')
      assert(not state.position.pending and not state.position.uncertain,'Recover uncertain movement with /autobuilder/pose.lua before setup')
    end
    local a=state.automation or {}
    assert(not a.supply,'Finish the outstanding supply batch before setup')
    for _,jobs in ipairs({state.jobs or {},a.jobs or {},a.requests or {}}) do
      for _,job in pairs(jobs) do assert(job.status=='completed','Finish queued or paused work before setup') end
    end
    for _,project in pairs(a.projects or {}) do
      assert(not ({building=true,verifying=true,repairing=true,clearing=true,preparing=true})[project.phase],
        'Finish the active project before setup')
    end
  end
  return store,state
end
local function persist(e,config,overrides,pose,original)
  Config.load(overrides) -- Validate the entire merged configuration before writing.
  local raw='-- Saved by setup. Previous settings: '..config.dataDir..'/settings-before-setup.lua\nreturn '..e.textutils.serialize(overrides)..'\n'
  assert(load(raw,'@settings.lua','t',{}),'Settings serialization failed')
  assert(IO.read(e.fs,settingsPath)==original,'Settings changed during setup; retry')
  local store,state=idle(e,config)
  local backup=config.dataDir..'/settings-before-setup.lua'
  if not e.fs.exists(backup) then IO.write(e.fs,backup,original) end
  if pose then
    -- No physical action occurs. Persist the operator's current pose before
    -- enabling building, including on turtles which already have a checkpoint.
    state=state or {schema=1,id=e.os.getComputerID(),role='worker',boot=0,phase='telemetry',workers={}}
    state.position=U.copy(pose); state.position.known=true; state.position.source='manual'; state.status='idle'
    local saved,why=store:save(state); assert(saved,why)
  end
  local tx=require('autobuilder.install.transaction').new(e.fs,e.textutils)
  tx:begin()
  local ok,err=pcall(function() tx:stage('autobuilder/settings.lua',raw); tx:commit() end)
  if not ok then
    local recovered,why=pcall(function() tx:recover() end)
    error(tostring(err)..(recovered and ' (previous settings restored)' or '; run /installer.lua --recover: '..tostring(why)))
  end
end
local function controller(e,overrides,config)
  e.print('Controller '..e.os.getComputerID()..': guided building setup')
  e.print('Connect a stock chest and a separate empty supply chest by wired modems. Enable both modems.')
  local list=M.inventories(e)
  assert(#list>=2,'Need at least two visible inventories: stock and an empty supply chest. Connect them, then rerun setup.')
  for i,entry in ipairs(list) do
    local samples={}; for name,count in pairs(entry.items) do samples[#samples+1]=name..' x'..count end
    table.sort(samples)
    e.print(i..') '..entry.name..'  '..(#samples==0 and '(empty)' or table.concat(samples,', ')))
  end
  local excluded={}
  for _,name in ipairs(config.furnaces) do excluded[name]=true end
  excluded[config.craftingStation.input]=true; excluded[config.craftingStation.output]=true
  e.print('Choose the dedicated supply chest your builder will face at its depot.')
  local stage=ask(e,'Supply chest number',function(v)
    local n=tonumber(v); local entry=n and list[n]
    if entry and entry.container and not excluded[entry.name] and not next(entry.items) then return entry.name end
    return nil,'Choose an empty chest/barrel, excluding configured crafting and furnace inventories.'
  end)
  excluded[stage]=true
  local stock=ask(e,'Stock chest numbers (space-separated)',function(v)
    local names,seen={},{}
    for word in v:gmatch('%S+') do
      local entry=list[tonumber(word) or 0]
      if not entry or excluded[entry.name] or seen[entry.name] then return nil,'Choose distinct stock chests, excluding supply and configured crafting/furnace inventories.' end
      names[#names+1]=entry.name; seen[entry.name]=true
    end
    if #names>0 then return names end
  end)
  e.print('Choose the lowest x/y/z corner of the empty 8 x 8 cathedral test site.')
  e.print('The test extends 7 blocks east (+x) and south (+z), with two clear blocks above it.')
  local origin=ask(e,'Build corner: x y z',coordinate)
  overrides.storageInventories=stock; overrides.supply=U.copy(overrides.supply or {})
  overrides.supply.inventory=stage; overrides.supply.side='front'
  overrides.build=U.copy(overrides.build or {}); overrides.build.enabled=true; overrides.build.origin=origin
  overrides.build.rotation=0; overrides.build.mirrorX=false; overrides.build.mirrorZ=false
  overrides.clearSite=false; overrides.automation=U.copy(overrides.automation or {}); overrides.automation.enabled=true
  e.print('Supply: '..stage..'; stock: '..table.concat(stock,', ')); e.print('Build corner: '..describe(origin))
end
local function worker(e,overrides,config)
  assert(e.turtle,'Builder setup requires a turtle')
  assert(config.controllerId~=e.os.getComputerID(),'A worker cannot be its own controller')
  e.print('Builder '..e.os.getComputerID()..': reading settings from controller '..config.controllerId)
  local profile=require('autobuilder.setup_share').fetch(e,config)
  assert(profile.side=='front','This wizard uses a supply chest in front of the depot. Configure the controller with setup first.')
  e.print('Park this turtle at its depot, facing supply chest '..profile.inventory..'.')
  e.print('Keep the space above its travel route clear. Equip a pickaxe and wireless modem.')
  local position,err=require('autobuilder.core.gps').new(e.gps,config.gps):locate()
  if position then e.print('GPS position: '..describe(position))
  else e.print(err); position=ask(e,'Turtle block position: x y z',coordinate) end
  local aliases={n='north',e='east',s='south',w='west',north='north',east='east',south='south',west='west'}
  position.heading=ask(e,'Turtle faces north/east/south/west',function(v) return aliases[v:lower()] end)
  assert(yes(e,'Is it parked here, facing that supply chest? yes/no'),'Park the turtle, then rerun setup')
  local found,block=e.turtle.inspect()
  assert(found and block and containers[block.name],'No chest/barrel in front of the turtle. Place its supply chest, then rerun setup.')
  overrides.depot=U.copy(position); overrides.initialPosition=U.copy(position)
  overrides.supply=U.copy(overrides.supply or {}); overrides.supply.inventory=profile.inventory; overrides.supply.side=profile.side
  overrides.automation=U.copy(overrides.automation or {}); overrides.automation.enabled=true; overrides.automation.building=true
  e.print('Builder depot: '..describe(position)..' facing '..position.heading)
  e.print('Fuel: '..tostring(e.turtle.getFuelLevel())..'. Put coal/charcoal in slot 15; keep slot 16 reserved.')
  return position
end
function M.run(args,e)
  assert(#args==0 or (#args==1 and (args[1]=='builder' or args[1]=='controller')),'Usage: setup [builder|controller]')
  assert(not e.fs.exists('/.autobuilder-install/transaction'),'Run /installer.lua --recover before setup')
  local original=IO.read(e.fs,settingsPath)
  local fn,err=load(original,'@settings.lua','t',{}); assert(fn,err)
  local overrides=fn(); assert(type(overrides)=='table','Settings must return a plain table')
  local config=Config.load(overrides)
  if args[1] then assert((args[1]=='controller')==(config.role=='controller'),'Setup role does not match this installation') end
  idle(e,config)
  local network=require('autobuilder.core.network').new(e,config,e.os.getComputerID(),1)
  local opened,why=network:open(); assert(opened,why)
  local pose
  if config.role=='controller' then controller(e,overrides,config) else pose=worker(e,overrides,config) end
  if not yes(e,'Save these settings? yes/no') then e.print('Cancelled. Settings and checkpoint unchanged.'); return false end
  persist(e,config,overrides,pose,original)
  e.print('Setup saved. Run reboot to reconnect.')
  if config.role=='controller' then e.print('Then run setup on one builder. The other workers can remain idle.') end
  return true
end
return M
