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
local function cancel(e)
  e.print('Cancelled. Settings, checkpoint and fuel unchanged.'); return false
end
local function retry(e,message)
  e.print(message)
  return ask(e,'Fix this, then press Enter to retry, or type cancel',function(v)
    v=v:lower(); if v=='retry' then return true elseif v=='cancel' then return false end
    return nil,'Press Enter to check again, or type cancel to leave setup.'
  end,'retry')
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
    assert(not (state.firstBuild and state.firstBuild.autoStart),'Finish the requested first test before changing setup; pausing keeps its saved settings in use')
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
  e.print('Controller '..e.os.getComputerID()..' - Step 1/3: connect two chests')
  e.print('STOCK holds building blocks. SUPPLY must be a separate, empty chest/barrel.')
  e.print('Place a wired modem on each chest and on this computer; join them with networking cable.')
  e.print('Right-click each chest modem so it lights up and shows a peripheral name.')
  e.print('Keep the wireless modem attached too; it talks to your builders.')
  local excluded={}
  for _,name in ipairs(config.furnaces) do excluded[name]=true end
  excluded[config.craftingStation.input]=true; excluded[config.craftingStation.output]=true
  local list,stages
  while true do
    local ok,result=pcall(M.inventories,e)
    list=ok and result or {}; stages={}; local available=0
    for i,entry in ipairs(list) do
      if not excluded[entry.name] then
        available=available+1
        if entry.container and not next(entry.items) then stages[#stages+1]=tostring(i) end
      end
    end
    if available>=2 and #stages>0 then break end
    if not retry(e,'Need two connected inventories, including an empty supply chest/barrel. Check cables, modem lights and chest contents.') then return false end
  end
  for i,entry in ipairs(list) do
    local samples={}; for name,count in pairs(entry.items) do samples[#samples+1]=name..' x'..count end
    table.sort(samples)
    e.print(i..') '..entry.name..'  '..(#samples==0 and '(empty)' or table.concat(samples,', '))..(excluded[entry.name] and ' [reserved; cannot choose]' or ''))
  end
  e.print('Your builder will park directly beside SUPPLY, with its front facing the chest.')
  e.print('Match the name shown by that chest modem. [A number] means Enter accepts it.')
  local stage=ask(e,'Supply chest number',function(v)
    local n=tonumber(v); local entry=n and list[n]
    if entry and entry.container and not excluded[entry.name] and not next(entry.items) then return entry.name end
    return nil,'Choose an empty chest/barrel, excluding configured crafting and furnace inventories.'
  end,#stages==1 and stages[1] or nil)
  excluded[stage]=true
  local stocks={}
  for i,entry in ipairs(list) do if not excluded[entry.name] then stocks[#stocks+1]=tostring(i) end end
  e.print('Choose STOCK: the chest containing your building materials.')
  local stock=ask(e,'Stock chest numbers (space-separated)',function(v)
    local names,seen={},{}
    for word in v:gmatch('%S+') do
      local entry=list[tonumber(word) or 0]
      if not entry or excluded[entry.name] or seen[entry.name] then return nil,'Choose distinct stock chests, excluding supply and configured crafting/furnace inventories.' end
      names[#names+1]=entry.name; seen[entry.name]=true
    end
    if #names>0 then return names end
  end,#stocks==1 and stocks[1] or nil)
  e.print('Step 2/3: choose the empty 8 x 8 test site')
  e.print('Choose its northwest corner: lowest x and z. It extends 7 east (+x), 7 south (+z).')
  e.print('Press F3 (or Fn+F3), point at the GROUND block at that corner, and read Targeted Block.')
  e.print('Use that x and z; add 1 to its y. Example: ground 20 63 -9 -> enter 20 64 -9.')
  e.print('This is the bottom layer of the build, not your player XYZ. Keep it and two blocks above clear.')
  e.print('Keep the depot/chests outside that square and leave a clear route from the turtle.')
  local origin=ask(e,'Build corner: x y z',coordinate)
  overrides.storageInventories=stock; overrides.supply=U.copy(overrides.supply or {})
  overrides.supply.inventory=stage; overrides.supply.side='front'
  overrides.build=U.copy(overrides.build or {}); overrides.build.enabled=true; overrides.build.origin=origin
  overrides.build.rotation=0; overrides.build.mirrorX=false; overrides.build.mirrorZ=false
  overrides.clearSite=false; overrides.automation=U.copy(overrides.automation or {}); overrides.automation.enabled=true
  e.print('Step 3/3: review and save')
  e.print('Supply: '..stage..'; stock: '..table.concat(stock,', ')); e.print('Build corner: '..describe(origin))
  return true
end
local function worker(e,overrides,config)
  assert(e.turtle,'Builder setup requires a turtle')
  assert(config.controllerId~=e.os.getComputerID(),'A worker cannot be its own controller')
  e.print('Builder '..e.os.getComputerID()..' - Step 1/4: connect to controller '..config.controllerId)
  local profile
  while true do
    local ok,result=pcall(require('autobuilder.setup_share').fetch,e,config)
    if ok and result.side=='front' then profile=result; break end
    if not retry(e,'On controller '..config.controllerId..', finish setup, then leave Autobuilder running. It must already list this worker. This wizard needs a supply chest in front of the builder.') then return nil end
  end
  e.print('Step 2/4: park beside supply chest '..profile.inventory)
  e.print('Use ONE builder for the test. Its depot means the block where it parks beside SUPPLY.')
  e.print('Place it directly beside that chest at the same height, with its front facing the chest.')
  e.print('Match the chest modem name above. Keep a pickaxe and wireless modem equipped.')
  e.print('Leave the block above the turtle and its route to the test site clear.')
  while true do
    local ok,found,block=pcall(e.turtle.inspect)
    if ok and found and block and containers[block.name] then break end
    if not retry(e,'No chest/barrel detected directly in front. Check the turtle orientation and supply chest placement.') then return nil end
  end
  e.print('Step 3/4: record where this turtle is parked')
  local position,err=require('autobuilder.core.gps').new(e.gps,config.gps):locate()
  if position then e.print('GPS position: '..describe(position))
  else
    e.print('GPS unavailable: '..tostring(err))
    e.print('Close this screen, press F3 (or Fn+F3), and point at the TURTLE block.')
    e.print('Read Targeted Block: x y z. Reopen the turtle and type those three whole numbers.')
    e.print('Use the turtle block, not player XYZ or the chest. Do not add 1 to y here.')
    position=ask(e,'Turtle block position: x y z',coordinate)
  end
  e.print('Facing means the direction FROM the turtle TOWARD the supply chest.')
  e.print('Stand behind the turtle, look straight toward the chest, and read F3 Facing.')
  e.print('north = -z; east = +x; south = +z; west = -x. Type a word or n/e/s/w.')
  local aliases={n='north',e='east',s='south',w='west',north='north',east='east',south='south',west='west'}
  position.heading=ask(e,'Turtle faces north/east/south/west',function(v) return aliases[v:lower()] end)
  if not yes(e,'Is it parked here, facing that supply chest? yes/no') then return nil end
  local found,block=e.turtle.inspect()
  assert(found and block and containers[block.name],'Supply chest changed. Leave the turtle parked, then rerun setup.')
  overrides.depot=U.copy(position); overrides.initialPosition=U.copy(position)
  overrides.supply=U.copy(overrides.supply or {}); overrides.supply.inventory=profile.inventory; overrides.supply.side=profile.side
  overrides.automation=U.copy(overrides.automation or {}); overrides.automation.enabled=true; overrides.automation.building=true
  e.print('Step 4/4: fuel and save')
  e.print('Builder depot: '..describe(position)..' facing '..position.heading)
  e.print('Fuel: '..tostring(e.turtle.getFuelLevel())..'. Target for this test: 1000.')
  e.print('Slots count left to right, top to bottom in the turtle inventory. Slot 15 = bottom row, third box.')
  e.print('Put 16 coal or charcoal there. Keep slot 16 (bottom-right) reserved; keep build blocks in STOCK.')
  e.print('Saving will consume only coal/charcoal in slot 15 if fuel is below 1000. It will not move the turtle.')
  return position
end
local function loadFuel(e)
  local t=e.turtle
  local fuel=t.getFuelLevel()
  if fuel=='unlimited' or fuel>=1000 then return end
  local selected=t.getSelectedSlot and t.getSelectedSlot()
  local ok,ready=pcall(function() return require('autobuilder.storage.inventory').new(t):refuel(1000,false) end)
  if selected then t.select(selected) end
  if ok and ready then e.print('Fuel loaded: '..tostring(t.getFuelLevel())..'.')
  else
    e.print('Settings saved, but more fuel is needed before building.')
    e.print('Put 16 coal/charcoal in slot 15 (bottom row, third box), then run setup again to load it.')
  end
end
function M.run(args,e,opts)
  assert(#args==0 or (#args==1 and (args[1]=='builder' or args[1]=='controller')),'Usage: setup [builder|controller]')
  assert(not e.fs.exists('/.autobuilder-install/transaction'),'Run /installer.lua --recover before setup')
  local original=IO.read(e.fs,settingsPath)
  local fn,err=load(original,'@settings.lua','t',{}); assert(fn,err)
  local overrides=fn(); assert(type(overrides)=='table','Settings must return a plain table')
  local config=Config.load(overrides)
  if args[1] then assert((args[1]=='controller')==(config.role=='controller'),'Setup role does not match this installation') end
  idle(e,config)
  e.print('Guided setup: answer each prompt and press Enter. Saving requires yes; Enter means no.')
  e.print('Checking wireless modem...')
  local network=require('autobuilder.core.network').new(e,config,e.os.getComputerID(),1)
  while true do
    local opened,why=network:open(); if opened then break end
    if not retry(e,tostring(why)..'. Attach a wireless modem to this computer/turtle.') then return cancel(e) end
  end
  local pose
  if config.role=='controller' then
    if not controller(e,overrides,config) then return cancel(e) end
  else
    pose=worker(e,overrides,config); if not pose then return cancel(e) end
  end
  if not yes(e,pose and 'Save settings and load slot 15 coal/charcoal if needed? yes/no' or 'Save these settings? yes/no') then return cancel(e) end
  persist(e,config,overrides,pose,original)
  if pose then loadFuel(e) end
  if opts and opts.returnToApp then e.print('Setup saved. Returning to Autobuilder...')
  else e.print('Setup saved. Run reboot to reconnect.') end
  if config.role=='controller' then e.print('Then run setup on one builder. The other workers can remain idle.') end
  return true
end
return M
