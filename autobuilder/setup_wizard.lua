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
local function idle(e,config,preparation)
  local store=Checkpoint.new(e.fs,e.textutils,config.dataDir..'/'..config.role..'.state')
  local state,source=store:load()
  assert(source=='primary' or source=='missing','Checkpoint recovery required before setup: '..source)
  if state then
    assert(state.schema==1 and state.id==e.os.getComputerID() and state.role==config.role
      and U.integer(state.boot) and type(state.phase)=='string','Invalid or foreign checkpoint')
    assert(not state.fuelRecovery and not state.fuelResume,'Finish fuel recovery before setup')
    assert(not state.assignmentRecovery and not state.currentTask and not state.motionReservation
      and not next(state.pendingSupplyAcks or {}),'Finish current jobs and acknowledgements before setup')
    assert(not (state.firstBuild and state.firstBuild.autoStart),'Finish the requested first test before changing setup; pausing keeps its saved settings in use')
    if config.role=='worker' then
      assert(type(state.position)=='table' and type(state.position.known)=='boolean','Invalid saved position')
      assert(not state.position.pending and not state.position.uncertain,'Recover uncertain movement with /autobuilder/pose.lua before setup')
    end
    local a=state.automation or {}
    assert(not a.supply,'Finish the outstanding supply batch before setup')
    for _,jobs in ipairs({state.jobs or {},a.jobs or {},preparation and {} or a.requests or {}}) do
      for _,job in pairs(jobs) do
        assert(job.type~='RESCUE' or job.rescueSettled,'Finish fuel recovery before setup')
        assert(job.status=='completed','Finish queued or paused work before setup')
      end
    end
    for _,project in pairs(a.projects or {}) do
      assert(not ({building=true,verifying=true,repairing=true,clearing=true,preparing=not preparation})[project.phase],
        'Finish the active project before setup')
    end
  end
  return store,state
end
local function persist(e,config,overrides,pose,original,preparation)
  Config.load(overrides) -- Validate the entire merged configuration before writing.
  local raw='-- Saved by setup. Previous settings: '..config.dataDir..'/settings-before-setup.lua\nreturn '..e.textutils.serialize(overrides)..'\n'
  assert(load(raw,'@settings.lua','t',{}),'Settings serialization failed')
  assert(IO.read(e.fs,settingsPath)==original,'Settings changed during setup; retry')
  local store,state=idle(e,config,preparation)
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
  e.print('Step 2/3: choose the 8 x 8 test site')
  e.print('Press Enter for AUTO: the builder clears a small site behind its saved supply position.')
  e.print('AUTO removes common terrain only. Chests, machines, ores and liquids stop it.')
  e.print('Keep other turtles and players out of that area. Ground below the build stays in place.')
  e.print('For a MANUAL site instead, enter three coordinates:')
  e.print('Choose its northwest corner: lowest x and z. It extends 7 east (+x), 7 south (+z).')
  e.print('Press F3 (or Fn+F3), point at the GROUND block at that corner, and read Targeted Block.')
  e.print('Use that x and z; add 1 to its y. Example: ground 20 63 -9 -> enter 20 64 -9.')
  e.print('This is the bottom layer of the build, not your player XYZ. Keep it and two blocks above clear.')
  e.print('Keep the depot/chests outside that square and leave a clear route from the turtle.')
  local choice=ask(e,'Build corner: auto OR x y z',function(value)
    if value:lower()=='auto' then return 'auto' end
    return coordinate(value)
  end,'auto')
  local automatic=choice=='auto'
  local origin=automatic and U.copy(config.build.origin) or choice
  overrides.storageInventories=stock; overrides.supply=U.copy(overrides.supply or {})
  overrides.supply.inventory=stage; overrides.supply.side='front'
  overrides.build=U.copy(overrides.build or {}); overrides.build.enabled=true; overrides.build.origin=origin; overrides.build.autoSite=automatic
  overrides.build.rotation=0; overrides.build.mirrorX=false; overrides.build.mirrorZ=false
  overrides.clearSite=false; overrides.automation=U.copy(overrides.automation or {}); overrides.automation.enabled=true
  e.print('Step 3/3: review and save')
  e.print('Supply: '..stage..'; stock: '..table.concat(stock,', '))
  e.print(automatic and 'Build site: AUTO, behind the builder; clears before building.' or 'Build corner: '..describe(origin))
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
  e.print('Keep machines and cables away from above the turtle. AUTO can clear common terrain there.')
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
  e.print('Put 16 coal/charcoal or 2 coal blocks there. Keep slot 16 (bottom-right) reserved; keep build blocks in STOCK.')
  e.print('Saving will consume only coal/charcoal or coal blocks in slot 15 if fuel is below 1000. It will not move the turtle.')
  return position
end
local function miningResources(line)
  local Materials=require('autobuilder.resources.materials')
  if line:lower()=='all' then return {} end
  local aliases={stone='cobblestone',deepslate='cobbled_deepslate',clay='clay_ball',iron='raw_iron',copper='raw_copper',gold='raw_gold',lapis='lapis_lazuli'}
  local resources,seen={},{}
  for word in line:lower():gmatch('[^,%s]+') do
    local item=word:find(':',1,true) and word or 'minecraft:'..(aliases[word] or word)
    if not Materials.get(item) or seen[item] then return nil,'Choose distinct supported resources: stone, coal, sand, clay, diorite, deepslate, or full item IDs.' end
    resources[#resources+1]=item; seen[item]=true
  end
  if #resources>0 then return resources end
  return nil,'Enter one or more resources, or all for an unrestricted miner.'
end
local function explorationController(e,overrides,config)
  local E=require('autobuilder.resources.exploration')
  local function input(label,validate,default)
    return ask(e,label..' (cancel to stop)',function(v) if v=='cancel' then return false end; return validate(v) end,default)
  end
  local function integer(v) local n=tonumber(v); if U.integer(n) then return n end end
  e.print('Automatic exploration: one operating boundary, no deposit coordinates.')
  local base=input('Base position x y z',coordinate); if not base then return false end
  local radius=input('Horizontal radius',function(v) local n=integer(v); if n and n>=1 and n<=256 then return n end end,'64'); if not radius then return false end
  local minDimension=input('Dimension minimum Y',integer,tostring(config.exploration.dimensionMinY)); if minDimension==false then return false end
  local maxDimension=input('Dimension maximum Y',integer,tostring(config.exploration.dimensionMaxY)); if maxDimension==false then return false end
  local minY=input('Search minimum Y',integer,tostring(math.max(minDimension,base.y-16))); if minY==false then return false end
  local maxY=input('Search maximum Y',integer,tostring(math.min(maxDimension,base.y+16))); if maxY==false then return false end
  e.print('Protect all base storage, cables, farms and machines. Additional restrictedAreas remain in effect.')
  local low=input('Protected base minimum x y z',coordinate); if not low then return false end
  local high=input('Protected base maximum x y z',coordinate); if not high then return false end
  local chosen={enabled=true,base=base,bounds={min={x=base.x-radius,y=minY,z=base.z-radius},max={x=base.x+radius,y=maxY,z=base.z+radius}},baseProtection={min=low,max=high},dimensionMinY=minDimension,dimensionMaxY=maxDimension}
  local ok,why=E.validate(chosen); assert(ok,why)
  e.print('Search bounds: '..describe(chosen.bounds.min)..' through '..describe(chosen.bounds.max))
  e.print('Protected base: '..describe(low)..' through '..describe(high))
  e.print('Software does not load chunks. Keep every search cell and depot loaded and within modem coverage.')
  if not yes(e,'Is this operating boundary loaded, reachable and protected as shown? yes/no') then return false end
  chosen.revision=(config.exploration.revision or 0)+1
  overrides.exploration=chosen; return true
end
local function miner(e,overrides,config,resource)
  assert(e.turtle,'Miner setup requires a turtle')
  assert(config.controllerId~=e.os.getComputerID(),'A worker cannot be its own controller')
  local P=require('autobuilder.core.pathfinding')
  local function input(label,validate,default)
    return ask(e,label..' (cancel to stop)',function(line)
      if line:lower()=='cancel' then return false end
      return validate(line)
    end,default)
  end
  e.print('Miner '..e.os.getComputerID()..' - park directly ABOVE its dedicated deposit chest/barrel.')
  e.print('Connect that chest by wired modem and cable to controller '..config.controllerId..'. Add its peripheral name to controller STOCK during controller setup.')
  e.print(resource=='explore' and 'Explorers receive their search areas from the controller. Keep SUPPLY separate from deposit chests.' or 'Keep SUPPLY separate. Every miner needs a different mine site with the requested resources actually present; setup does not create deposits.')
  e.print('Keep a pickaxe and wireless modem equipped. Reserve slot 16 for the scanner; without a scanner the miner uses a limited strip survey.')
  while true do
    local ok,found,block=pcall(e.turtle.inspectDown)
    if ok and found and block and containers[block.name] then break end
    if not retry(e,'No deposit chest/barrel directly below. Place the turtle on top of its dedicated wired STOCK chest.') then return nil end
  end
  local position,err=require('autobuilder.core.gps').new(e.gps,config.gps):locate()
  if position then e.print('GPS turtle position: '..describe(position))
  else
    e.print('GPS unavailable: '..tostring(err))
    e.print('Press F3 (or Fn+F3), point at the TURTLE, and read Targeted Block x y z. Use the turtle block, not player XYZ or the chest. Do not add 1 to y.')
    position=input('Turtle block position: x y z',coordinate); if not position then return nil end
  end
  e.print('Read F3 Facing while looking in the same direction as the turtle front. north=-z, east=+x, south=+z, west=-x.')
  local aliases={n='north',e='east',s='south',w='west',north='north',east='east',south='south',west='west'}
  position.heading=input('Turtle faces north/east/south/west',function(v) return aliases[v:lower()] end)
  if not position.heading then return nil end
  if resource=='explore' then
    e.print('Declare a CLEAR exit beyond the protected base. Route order: vertical, then X, then Z. No digging is allowed along this exit.')
    local delta={north={0,-1},east={1,0},south={0,1},west={-1,0}}; local d=delta[position.heading]
    local target=input('Clear exit endpoint x y z',coordinate,describe({x=position.x+d[1],y=position.y,z=position.z+d[2]})); if not target then return nil end
    assert(U.distance(position,target)<=math.min(config.maxTravelDistance,1024),'Exit exceeds travel limit')
    local route={}; local p={x=position.x,y=position.y,z=position.z}
    for _,axis in ipairs({'y','x','z'}) do while p[axis]~=target[axis] do p[axis]=p[axis]+(target[axis]>p[axis] and 1 or -1); route[#route+1]=U.copy(p) end end
    e.print('Depot '..describe(position)..'; clear exit '..describe(target)..'; '..#route..' moves.')
    if not yes(e,'Is this route clear and the deposit chest connected to controller STOCK? yes/no') then return nil end
    overrides.depot=U.copy(position); overrides.initialPosition=U.copy(position)
    overrides.mining=U.copy(overrides.mining or {}); overrides.mining.enabled=true; overrides.mining.mode='explore'; overrides.mining.resources={}; overrides.mining.exitRoute=route
    e.print('Provide startup fuel before assigning missions. Setup does not move or consume fuel.')
    return position
  end
  local resources
  if resource then resources=assert(miningResources(resource))
  else resources=input('Resources (space/comma separated; all means unrestricted)',miningResources) end
  if not resources then return nil end
  e.print('Resource targets: '..(#resources==0 and 'all supported mining resources' or table.concat(resources,', ')))
  e.print('Stone yields cobblestone; deepslate yields cobbled deepslate; clay yields clay balls. Coal needs coal ore; sand needs sand. Place this miner at the source, not beside the build.')
  local delta={north={0,-1},east={1,0},south={0,1},west={-1,0}}; local d=delta[position.heading]
  local defaultEntry={x=position.x+d[1],y=position.y,z=position.z+d[2]}
  local function protected(point)
    for _,box in ipairs(config.restrictedAreas) do if P.inside(point,box) then return true end end
    return false
  end
  local function routeSafe(entry)
    local point={x=position.x,y=position.y,z=position.z}
    for _,axis in ipairs({'y','x','z'}) do
      while point[axis]~=entry[axis] do
        point[axis]=point[axis]+(entry[axis]>point[axis] and 1 or -1)
        if protected(point) then return false end
      end
    end
    return true
  end
  e.print('Default mine: 8 x 8 blocks, 3 blocks high, immediately in front of this turtle. Bounds include every coordinate shown.')
  e.print('Entry is a corner at turtle height. For a custom entry, clear the depot-to-entry route: vertical first, then x, then z. The miner will not dig outside its mine.')
  local entry=input('Mine entry: x y z',function(line)
    local value,why=coordinate(line); if not value then return nil,why end
    if U.distance(position,value)==0 or U.distance(position,value)>config.maxTravelDistance then return nil,'Entry must differ from depot and stay within the configured travel limit.' end
    if protected(value) or not routeSafe(value) then return nil,'Entry or its route intersects a restricted area. Choose another entry.' end
    return value
  end,describe(defaultEntry)); if not entry then return nil end
  local defaultCorner={x=entry.x+(position.heading=='west' and -7 or 7),y=entry.y+2,z=entry.z+(position.heading=='north' and -7 or 7)}
  local chest={x=position.x,y=position.y-1,z=position.z}
  local bounds=input('Opposite mine corner (upper layer): x y z',function(line)
    local corner,why=coordinate(line); if not corner then return nil,why end
    if corner.y<entry.y then return nil,'Opposite corner y must be at or above the entry.' end
    local box={min={},max={}}
    for _,axis in ipairs({'x','y','z'}) do
      box.min[axis]=math.min(entry[axis],corner[axis]); box.max[axis]=math.max(entry[axis],corner[axis])
      if box.max[axis]-box.min[axis]>256 then return nil,'Each mine dimension must span at most 256 blocks.' end
    end
    if P.inside(position,box) or P.inside(chest,box) then return nil,'Mine bounds must exclude the depot turtle and its deposit chest.' end
    for _,area in ipairs(config.restrictedAreas) do
      local overlap=true
      for _,axis in ipairs({'x','y','z'}) do if box.max[axis]<area.min[axis] or box.min[axis]>area.max[axis] then overlap=false end end
      if overlap then return nil,'Mine bounds intersect a restricted area. Choose a different corner.' end
    end
    return box
  end,describe(defaultCorner)); if not bounds then return nil end
  e.print('Review depot: '..describe(position)..' facing '..position.heading..'; deposit chest below at '..describe(chest))
  e.print('Review mine entry: '..describe(entry)..'; bounds '..describe(bounds.min)..' through '..describe(bounds.max))
  e.print('Keep other miners, builds, machines and cables outside these bounds. Overlapping active mines cannot run together.')
  if not yes(e,'Are these coordinates correct, resources present, and the deposit chest connected to controller STOCK? yes/no') then return nil end
  local found,block=e.turtle.inspectDown()
  assert(found and block and containers[block.name],'Deposit chest changed. Leave the turtle parked, then rerun setup.')
  overrides.depot=U.copy(position); overrides.initialPosition=U.copy(position)
  overrides.mining=U.copy(overrides.mining or {}); overrides.mining.enabled=true; overrides.mining.resources=resources
  overrides.mining.mode='fixed'; overrides.mining.entry=entry; overrides.mining.bounds=bounds
  overrides.automation=U.copy(overrides.automation or {}); overrides.automation.enabled=true; overrides.automation.building=false
  e.print('Slot 15 = bottom row, third box: put 16 coal/charcoal or 2 coal blocks there. Keep slot 16 reserved.')
  e.print('Saving loads slot 15 fuel toward 1000 after settings are saved. Setup does not move or dig. Replenish fuel between trips; the deposit chest is below, not a fuel supply.')
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
    e.print('Settings saved, but more fuel is needed before working.')
    e.print('Put 16 coal/charcoal or 2 coal blocks in slot 15 (bottom row, third box), then run setup again to load it.')
  end
end
function M.run(args,e,opts)
  assert(#args==0 or (#args==1 and (args[1]=='fuel' or args[1]=='builder' or args[1]=='controller' or args[1]=='miner' or args[1]=='factory' or args[1]=='crafter' or args[1]=='exploration'))
    or (#args==2 and args[1]=='miner'),'Usage: setup [builder|controller|miner [resource]|factory|crafter|fuel]')
  if args[1]=='miner' and args[2] and args[2]~='explore' then assert(miningResources(args[2])) end
  assert(not e.fs.exists('/.autobuilder-install/transaction'),'Run /installer.lua --recover before setup')
  local original=IO.read(e.fs,settingsPath)
  local fn,err=load(original,'@settings.lua','t',{}); assert(fn,err)
  local overrides=fn(); assert(type(overrides)=='table','Settings must return a plain table')
  local config=Config.load(overrides)
  if args[1] then assert((args[1]=='controller' or args[1]=='factory' or args[1]=='exploration')==(config.role=='controller'),'Setup role does not match this installation') end
  local factory=args[1]=='factory' or args[1]=='crafter'
  local preparation=args[1]=='factory'
  idle(e,config,preparation)
  e.print('Guided setup: answer each prompt and press Enter. Saving requires yes; Enter means no.')
  e.print('Checking wireless modem...')
  local network=require('autobuilder.core.network').new(e,config,e.os.getComputerID(),1)
  while true do
    local opened,why=network:open(); if opened then break end
    if not retry(e,tostring(why)..'. Attach a wireless modem to this computer/turtle.') then return cancel(e) end
  end
  local pose
  if args[1]=='fuel' then
    assert(config.depot,'Set up this worker depot before enabling automatic fuel')
    local profile=require('autobuilder.setup_share').fetch(e,config)
    assert(profile.fuel and profile.fuel.enabled,'Configure and enable fuel on the controller first')
    overrides.fuel=U.copy(profile.fuel)
    e.print('Automatic fuel: '..profile.fuel.item..', low '..profile.fuel.low..', target '..profile.fuel.target)
    e.print('Depot remains '..describe(config.depot)..'. Saving does not move or refuel this turtle.')
  elseif factory then
    if not require('autobuilder.factory_setup').configure(e,overrides,config,ask) then return cancel(e) end
  elseif args[1]=='exploration' then
    if not explorationController(e,overrides,config) then return cancel(e) end
  elseif config.role=='controller' then
    if not controller(e,overrides,config) then return cancel(e) end
  else
    if args[1]=='miner' then pose=miner(e,overrides,config,args[2]) else pose=worker(e,overrides,config) end
    if not pose then return cancel(e) end
  end
  local exploring=args[1]=='miner' and args[2]=='explore'
  if not yes(e,pose and not exploring and 'Save settings and load slot 15 coal/charcoal or coal blocks if needed? yes/no' or 'Save these settings? yes/no') then return cancel(e) end
  persist(e,config,overrides,pose,original,preparation)
  if pose and not exploring then loadFuel(e) end
  if opts and opts.returnToApp then e.print('Setup saved. Returning to Autobuilder...')
  else e.print('Setup saved. Run reboot to reconnect.') end
  if config.role=='controller' then e.print(factory and 'Factory saved. Use 8 on the controller to see the material team.' or 'Then run setup on one builder. Use setup miner on gathering turtles.') end
  return true
end
return M
