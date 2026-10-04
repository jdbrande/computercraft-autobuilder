local U=require('autobuilder.core.util')
local IS=require('tests.install_support')
local function fixture()
  local w=require('tests.build_world').new()
  for x=2,3 do w.blocks[x..',-1,0']={name='minecraft:stone',state={}} end
  local f={world=w,inventories={stock={[1]={name='minecraft:stone',count=32}},stage={},destination={}},stats={staged=0,pulled=0,dropped=0,supplyGrants=0,supplyDone=0,reservations=0},filter=nil}
  local locations={source={x=0,y=2,z=0,heading='east'},destination={x=6,y=2,z=0}}
  w.blocks['0,1,0']={name='minecraft:chest',state={}}; w.blocks['6,1,0']={name='minecraft:chest',state={}}
  local function lowerInventory()
    if w.pose.x==0 and w.pose.y==2 and w.pose.z==0 then return f.inventories.stage end
    if w.pose.x==6 and w.pose.y==2 and w.pose.z==0 then return f.inventories.destination end
  end
  w.turtle.getItemSpace=function(s) return (f.stackLimit or 64)-w.turtle.getItemCount(s) end
  w.turtle.suckDown=function(limit)
    local inv=lowerInventory(); if not inv then return false,'no chest' end
    local slot,item=next(inv); if not item then return false,'empty chest' end
    local held=w.items[w.selected]
    if held and held.name~=item.name then return false,'wrong stack' end
    local moved=math.min(limit,f.pullLimit or limit,item.count,(f.stackLimit or 64)-(held and held.count or 0)); if moved<=0 then return false end
    w.items[w.selected]=held or {name=item.name,count=0}; w.items[w.selected].count=w.items[w.selected].count+moved
    item.count=item.count-moved; if item.count==0 then inv[slot]=nil end
    f.stats.pulled=f.stats.pulled+moved
    if f.crashSuck then f.crashSuck=false; f.crashed=true; error('power lost after physical supply pull') end
    return true
  end
  w.turtle.dropDown=function(limit)
    local inv=lowerInventory(); local item=w.items[w.selected]; if not inv or not item then return false end
    if inv[1] and inv[1].name~=item.name then return false,'full chest' end
    local moved=math.min(limit,item.count,128-(inv[1] and inv[1].count or 0)); if moved<=0 then return false,'full chest' end
    inv[1]=inv[1] or {name=item.name,count=0}; inv[1].count=inv[1].count+moved; item.count=item.count-moved
    if item.count==0 then w.items[w.selected]=nil end; f.stats.dropped=f.stats.dropped+moved
    return true
  end
  local function env(id)
    local codec=require('tests.support').codec(); codec.unserializeJSON=codec.unserialize; codec.serializeJSON=codec.serialize
    local e={fs=IS.fs(),textutils=codec,now=100,packets={}}
    e.os={getComputerID=function() return id end,epoch=function() return e.now*1000 end}
    e.rednet={isOpen=function() return true end,open=function() end,send=function(to,m,p) e.packets[#e.packets+1]={to=to,m=U.copy(m),protocol=p}; return true end}
    e.peripheral={getNames=function() return {'right'} end,getType=function(name) return name=='right' and 'modem' or 'inventory' end,
      call=function(name,method,...)
        if method=='isWireless' then return true end
        local inv=assert(f.inventories[name],'unknown wired inventory '..tostring(name))
        if method=='list' then return U.copy(inv) end
        assert(method=='pushItems','unexpected wired call '..method)
        local destination,slot,limit=...; local dest=assert(f.inventories[destination]); local item=inv[slot]
        if not item or dest[1] and dest[1].name~=item.name then return 0 end
        local moved=math.min(item.count,limit,64-(dest[1] and dest[1].count or 0))
        if moved<=0 then return 0 end
        dest[1]=dest[1] or {name=item.name,count=0}; dest[1].count=dest[1].count+moved; item.count=item.count-moved
        if item.count==0 then inv[slot]=nil end; f.stats.staged=f.stats.staged+moved
        if f.crashStage then f.crashStage=false; f.stageCrashed=true; error('controller power lost after physical staging') end
        return moved
      end}
    return e
  end
  local ce,we=env(7),env(12); we.turtle=w.turtle; f.ce,f.we=ce,we
  local C=require('tests.loaded_config')
  local common={storageInventories={'stock'},turtleFuelReserveItems={},locations=locations,depot=locations.source,supply={inventory='stage',side='down',batch=1},minimumFuelReserve=0}
  common.inventoryAreas={stock={min={x=-4,y=1,z=0},max={x=-4,y=1,z=0}},stage={min={x=0,y=1,z=0},max={x=0,y=1,z=0}}}
  local cc=U.copy(common); cc.build={enabled=true,origin={x=2,y=0,z=0}}; cc=C.load(cc)
  local wc=U.copy(common); wc.role='worker'; wc.controllerId=7; wc.automation={building=true,courier=true}; wc.initialPosition=U.copy(w.pose); wc=C.load(wc)
  local Runtime=require('autobuilder.core.runtime')
  f.controller=Runtime.new(cc,ce); f.worker=Runtime.new(wc,we)
  local blueprint={schema=1,size={x=2,y=1,z=1},palette={{name='minecraft:stone',state={}}},runs={{id=1,count=2}},metadata={},requirements={['minecraft:stone']=2}}
  ce.fs.files['/supply.json']=ce.textutils.serialize(blueprint)
  function f:pump(from,to)
    local packets=from.packets; from.packets={}
    for _,p in ipairs(packets) do
      if p.m.type=='task_supply' then self.stats.supplyGrants=self.stats.supplyGrants+1 end
      if p.m.type=='task_supply_done' then self.stats.supplyDone=self.stats.supplyDone+1 end
      if p.m.type=='task_reserve' then self.stats.reservations=self.stats.reservations+1 end
      if not self.filter or self.filter(p)~=false then
        to:receive(p.m.sender,p.m,p.protocol)
        if self.duplicateGrants and p.m.type=='task_supply' then to:receive(p.m.sender,U.copy(p.m),p.protocol) end
      end
    end
  end
  function f:step()
    ce.now=ce.now+1; we.now=ce.now
    self.worker:tick(); self:pump(we,self.controller)
    self.controller:tick(); self:pump(ce,self.worker)
    self.controller:workStep(); self.worker:workStep(); self:pump(we,self.controller); self:pump(ce,self.worker)
  end
  function f:reboot(controller,worker)
    if controller then ce.packets={}; self.controller=Runtime.new(cc,ce) end
    if worker then we.packets={}; self.worker=Runtime.new(wc,we) end
  end
  function f:startBuild()
    assert(self.controller:command('build import /supply.json supplied'))
    assert(self.controller:command('build analyze supplied')); eq(w.places,0)
    assert(self.controller:command('build prepare supplied'))
    for _=1,3 do self:step() end
    eq(self.controller.state.automation.projects.supplied.phase,'ready')
    assert(self.controller:command('build start supplied'))
    -- Complete the normal survey/preparation before injecting supply faults.
    for _=1,1500 do
      if self.controller.state.automation.projects.supplied.phase=='building' then return end
      self:step()
    end
    error('supply fixture did not finish site preparation')
  end
  function f:complete(limit)
    for _=1,limit or 500 do
      self:step()
      local p=self.controller.state.automation.projects.supplied
      if p and p.phase=='built' and not self.worker.state.currentTask then return true end
    end
    local t=self.worker.state.currentTask
    return false, t and (tostring(t.phase)..': '..tostring(t.error)) or 'no worker task'
  end
  return f
end
test('return-home job resumes movement reservations without constructing an absent executor',function()
  local f=fixture(); f.world.pose.x=3
  f.worker.navigation.pose.x=3
  local job=f.controller.automation.queue:submit('RETURN_HOME',{}, {})
  for _=1,100 do
    f:step()
    if job.status=='completed' and not f.worker.state.currentTask then break end
  end
  eq(job.status,'completed'); eq(f.world.pose.x,0); eq(f.world.pose.y,2)
end)

test('runtime build stages supplies from wired stock and resumes real placement',function()
  local f=fixture(); f:startBuild(); local ok,err=f:complete(); assert(ok,err)
  eq(f.world.places,2); eq(f.stats.pulled,2); eq(f.stats.staged,2); eq(f.inventories.stock[1].count,30)
  eq(f.world.blocks['2,0,0'].name,'minecraft:stone'); eq(f.world.blocks['3,0,0'].name,'minecraft:stone')
  assert(f.stats.reservations>0 and f.stats.supplyGrants>0); eq(next(f.inventories.stage),nil)
  for _=1,10 do f:step() end
  eq(f.controller.state.automation.supply,nil)
end)
test('runtime supply survives controller staging and worker pull interruptions with duplicate grants',function()
  local f=fixture(); f.crashStage=true; f.crashSuck=true; f.duplicateGrants=true; f:startBuild()
  local controllerRebooted,workerRebooted=false,false
  for _=1,600 do
    f:step()
    if f.stageCrashed and not controllerRebooted then f:reboot(true,false); controllerRebooted=true end
    if f.crashed and not workerRebooted then f:reboot(false,true); workerRebooted=true end
    if f.controller.state.automation.projects.supplied.phase=='built' and not f.worker.state.currentTask then break end
  end
  assert(controllerRebooted and workerRebooted); eq(f.controller.state.automation.projects.supplied.phase,'built')
  eq(f.world.places,2); eq(f.stats.staged,2); eq(f.stats.pulled,2); eq(f.inventories.stock[1].count,30)
end)
test('runtime retries a lost supply completion without stranding the next batch',function()
  local f=fixture(); local dropped=false
  f.filter=function(p) if p.m.type=='task_supply_done' and not dropped then dropped=true; return false end end
  f:startBuild(); local ok,err=f:complete(600); assert(ok,err); assert(dropped)
  eq(f.world.places,2); eq(f.stats.staged,2); eq(f.stats.pulled,2)
  for _=1,10 do f:step() end
  eq(f.controller.state.automation.supply,nil)
end)
test('runtime transport command delivers through actual reservation and navigation round trips',function()
  local f=fixture(); f.inventories.stage[1]={name='minecraft:stone',count=12}
  local ok,id=f.controller:command('transport minecraft:stone 9 source destination'); assert(ok,id)
  for _=1,400 do
    f:step()
    if f.controller.state.automation.jobs[id].status=='completed' and not f.worker.state.currentTask then break end
  end
  eq(f.controller.state.automation.jobs[id].status,'completed'); eq(f.controller.state.automation.jobs[id].progress,9)
  eq(f.inventories.destination[1].count,9); eq(f.inventories.stage[1].count,3); eq(f.stats.pulled,9); eq(f.stats.dropped,9)
  assert(f.stats.reservations>0); eq(f.world.places,0)
end)
test('runtime releases final drained supply ownership when completion acknowledgement outlives a lost supply done',function()
  local f=fixture(); f:startBuild()
  for _=1,400 do f:step(); if f.stats.pulled==2 then break end end
  eq(f.stats.pulled,2); assert(f.worker.state.currentTask and f.worker.state.currentTask.lastSupply)
  -- Hardware work can finish between telemetry heartbeats. Pump only movement messages.
  for _=1,150 do
    f.worker:workStep(); f:pump(f.we,f.controller); f:pump(f.ce,f.worker)
    if f.worker.state.currentTask.phase=='completed' then break end
  end
  eq(f.worker.state.currentTask.phase,'completed'); assert(f.controller.state.automation.supply)
  local dropped=false
  f.filter=function(p) if p.m.type=='task_supply_done' and not dropped then dropped=true; return false end end
  f.ce.now=f.ce.now+10; f.we.now=f.ce.now
  f.worker:tick(); f:pump(f.we,f.controller); f:pump(f.ce,f.worker)
  assert(dropped); eq(f.worker.state.currentTask,nil)
  for _=1,10 do f:step() end
  eq(f.controller.state.automation.supply,nil)
  eq(f.stats.staged,2); eq(f.stats.pulled,2)
end)
test('runtime courier resumes assigned ownership after both runtimes reboot mid route',function()
  local f=fixture(); f.inventories.stage[1]={name='minecraft:stone',count=14}
  local ok,id=f.controller:command('transport minecraft:stone 11 source destination'); assert(ok,id)
  local rebooted=false
  for _=1,400 do
    f:step()
    local t=f.worker.state.currentTask
    if t and t.cargo and t.cargo.stage=='destination' and not rebooted then f:reboot(true,true); rebooted=true end
    if f.controller.state.automation.jobs[id].status=='completed' and not f.worker.state.currentTask then break end
  end
  assert(rebooted); eq(f.controller.state.automation.jobs[id].status,'completed')
  eq(f.inventories.destination[1].count,11); eq(f.inventories.stage[1].count,3); eq(f.stats.pulled,11); eq(f.stats.dropped,11)
end)
test('runtime retains supply completion until the next shortage can obtain a fresh batch',function()
  local f=fixture(); f:startBuild()
  for _=1,400 do f:step(); if f.stats.pulled==1 then break end end
  eq(f.stats.pulled,1); assert(f.worker.state.currentTask.lastSupply)
  -- Early top-up can create the next batch before placing or another heartbeat.
  for _=1,160 do
    f.worker:workStep(); f:pump(f.we,f.controller); f:pump(f.ce,f.worker)
    local t=f.worker.state.currentTask
    if t and t.supplyRequest then break end
  end
  eq(f.world.places,0);local nextBatch=assert(f.worker.state.currentTask.supplyRequest)
  local oldBatch=next(f.worker.state.pendingSupplyAcks);assert(oldBatch and oldBatch~=nextBatch.id)
  local ok,err=f:complete(400); assert(ok,err)
  eq(f.world.places,2); eq(f.stats.staged,2); eq(f.stats.pulled,2)
end)
test('runtime recovers supply completion persisted before the executor records its receipt',function()
  local f=fixture()
  local data=f.ce.textutils.unserialize(f.ce.fs.files['/supply.json']); data.size.x=1; data.runs[1].count=1; data.requirements['minecraft:stone']=1
  f.ce.fs.files['/supply.json']=f.ce.textutils.serialize(data); f:startBuild()
  local save=f.worker.save; local cut=false
  function f.worker:save()
    if cut then error('simulated power outage') end
    local t=self.state.currentTask
    local afterLastPull=t and t.lastSupply and t.supplyReceiptId and t.missingItem and not t.supplyRequest and next(self.state.pendingSupplyAcks or {})==nil and f.stats.pulled==1
    local result=save(self)
    if afterLastPull then cut=true; error('power lost between supply completion and receipt promotion') end
    return result
  end
  for _=1,400 do pcall(function() f:step() end); if cut then break end end
  assert(cut); f:reboot(false,true)
  local ok,err=f:complete(500); assert(ok,err)
  eq(f.world.places,1); eq(f.stats.staged,1); eq(f.stats.pulled,1)
  for _=1,10 do f:step() end
  eq(f.controller.state.automation.supply,nil); eq(next(f.worker.state.pendingSupplyAcks),nil)
end)
test('runtime network rejects supply controls without their required batch identity',function()
  local V=require('autobuilder.core.network')
  for _,kind in ipairs({'task_supply','task_supply_done','task_supply_ack'}) do
    local message={version=1,sender=7,boot=1,sequence=1,id='7:1:1',type=kind,payload={jobId='task:7:1',item='minecraft:stone',count=1}}
    local ok=V.validate(7,message)
    assert(not ok,'missing supplyId accepted for '..kind)
  end
end)
test('runtime never restages or manufactures a released batch when its following progress packet is delayed',function()
  local f=fixture(); f:startBuild()
  for _=1,400 do f:step(); if f.stats.pulled==1 then break end end
  eq(f.stats.pulled,1); assert(next(f.worker.state.pendingSupplyAcks))
  local delayed
  f.filter=function(p)
    if p.m.type=='task_progress' and not delayed then delayed=p; return false end
  end
  f.ce.now=f.ce.now+5; f.we.now=f.ce.now
  f.worker:tick(); f:pump(f.we,f.controller); assert(delayed)
  -- Controller's timer may run after the receipt but before updated task telemetry.
  local requests=f.controller.state.automation.requestSequence
  f.controller:tick(); f:pump(f.ce,f.worker)
  eq(f.stats.staged,1)
  eq(f.controller.state.automation.requestSequence,requests)
  f.filter=nil; f.controller:receive(delayed.m.sender,delayed.m,delayed.protocol)
  local ok,err=f:complete(); assert(ok,err); eq(f.stats.staged,2); eq(f.stats.pulled,2)
end)
test('runtime retries an unacknowledged supply receipt after controller and worker reboot',function()
  local f=fixture(); local dropped=false
  f.filter=function(p) if p.m.type=='task_supply_ack' and not dropped then dropped=true; return false end end
  f:startBuild(); local rebooted=false
  for _=1,600 do
    f:step()
    if dropped and not rebooted then
      assert(next(f.worker.state.pendingSupplyAcks)); f:reboot(true,true); rebooted=true
    end
    if f.controller.state.automation.projects.supplied.phase=='built' and not f.worker.state.currentTask then break end
  end
  assert(rebooted); eq(f.controller.state.automation.projects.supplied.phase,'built')
  for _=1,10 do f:step() end
  eq(next(f.worker.state.pendingSupplyAcks),nil); eq(f.controller.state.automation.supply,nil)
  eq(f.stats.staged,2); eq(f.stats.pulled,2); eq(f.world.places,2)
end)
test('released supply batch tombstones survive a crash after the release checkpoint',function()
  local f=fixture(); local state={}; local saved; local interrupt=false
  local function save()
    saved=U.copy(state)
    if interrupt then error('power lost after release checkpoint') end
    return true
  end
  local Supply=require('autobuilder.storage.supply')
  local s=Supply.new(state,f.controller.config,f.ce,save)
  eq(s:offer('task:7:1:supply:1',12,'minecraft:stone',1),1)
  f.inventories.stage={}; interrupt=true
  assert(not s:release('task:7:1:supply:1'))
  state=saved; assert(state.completedSupplyBatches['task:7:1:supply:1']); eq(state.supply,nil)
  s=Supply.new(state,f.controller.config,f.ce,function() return true end)
  eq(s:offer('task:7:1:supply:1',12,'minecraft:stone',1),nil); eq(f.stats.staged,1)
  eq(s:offer('task:7:1:supply:2',12,'minecraft:stone',1),1); eq(f.stats.staged,2)
end)

local function finiteBuilder(f,fuel)
  local w=f.world; w.fuel=fuel; w.refuels=0
  w.turtle.getFuelLevel=function() return w.fuel end
  w.turtle.getFuelLimit=function() return 20000 end
  w.turtle.refuel=function(n)
    eq(w.selected,15); local item=assert(w.items[15]); eq(item.name,'minecraft:coal_block')
    w.refuels=w.refuels+n; w.fuel=w.fuel+n*800; item.count=item.count-n
    if item.count==0 then w.items[15]=nil end; return true
  end
  for _,name in ipairs({'forward','back','up','down'}) do
    local move=w.turtle[name]
    if move then w.turtle[name]=function() local ok,err=move(); if ok then w.fuel=w.fuel-1 end; return ok,err end end
  end
end
test('far construction refuels for its full return envelope and verifies without repeating a short depot trip',function()
  local f=fixture(); finiteBuilder(f,1000)
  f.world.items[1]={name='minecraft:stone',count=1}; f.world.items[15]={name='minecraft:coal_block',count=64}
  local block={x=384,y=0,z=224,name='minecraft:stone',state={}}
  local build=f.controller.automation.queue:submit('BUILD',{blocks={block},clearanceY=2},{})
  for _=1,1500 do f:step(); if build.status=='completed' and not f.worker.state.currentTask then break end end
  local task=f.worker.state.currentTask
  assert(build.status=='completed',task and tostring(task.error) or build.status)
  eq(f.world.refuels,1); eq(f.world.places,1)
  assert(f.world.fuel>=U.distance(f.world.pose,f.worker.config.depot),'return fuel must remain after distant placement')
  local verify=f.controller.automation.queue:submit('VERIFY',{blocks={block},clearanceY=2},{})
  for _=1,60 do f:step(); if verify.status=='completed' and not f.worker.state.currentTask then break end end
  eq(verify.status,'completed'); eq(verify.progress,1)
  local home=f.controller.automation.queue:submit('RETURN_HOME',{}, {})
  for _=1,1500 do f:step(); if home.status=='completed' and not f.worker.state.currentTask then break end end
  eq(home.status,'completed'); eq(f.world.pose.x,0); eq(f.world.pose.z,0); eq(f.world.refuels,1)
end)
test('explicit construction travel limits block the task before consuming fuel or moving',function()
  local f=fixture(); finiteBuilder(f,1000); f.worker.config.maxTravelDistance=256
  f.world.items[1]={name='minecraft:stone',count=1}; f.world.items[15]={name='minecraft:coal_block',count=64}
  f.controller.automation.queue:submit('BUILD',{blocks={{x=384,y=0,z=224,name='minecraft:stone',state={}}},clearanceY=2},{})
  for _=1,10 do f:step(); if f.worker.state.currentTask and f.worker.state.currentTask.phase=='blocked' then break end end
  local task=assert(f.worker.state.currentTask)
  assert(task.error and task.error:find('maxTravelDistance',1,true),tostring(task.error))
  eq(f.world.fuel,1000); eq(f.world.refuels,0); eq(f.world.pose.x,0); eq(f.world.pose.z,0)
end)
test('construction replenishes reserved fuel through front supply and recovers a crash after the fuel pull',function()
  local f=fixture(); finiteBuilder(f,994) -- Three coal reach the exact computed round-trip budget.
  f.world.turtle.refuel=function(n)
    local item=assert(f.world.items[15]); eq(item.name,'minecraft:coal'); eq(f.world.selected,15)
    f.world.refuels=f.world.refuels+n; f.world.fuel=f.world.fuel+n*80; item.count=item.count-n
    if item.count==0 then f.world.items[15]=nil end; return true
  end
  f.world.items[1]={name='minecraft:stone',count=1}; f.inventories.stock={[1]={name='minecraft:coal',count=16}}
  f.worker.config.supply.side='front'; f.controller.config.supply.side='front'
  f.world.blocks['1,2,0']={name='minecraft:chest',state={}}; f.world.turtle.suck=f.world.turtle.suckDown
  f.crashSuck=true
  local build=f.controller.automation.queue:submit('BUILD',{blocks={{x=384,y=0,z=224,name='minecraft:stone',state={}}},clearanceY=4},{})
  local rebooted=false
  for _=1,1800 do
    f:step()
    if f.crashed and not rebooted then f:reboot(false,true); rebooted=true end
    if build.status=='completed' and not f.worker.state.currentTask then break end
  end
  assert(rebooted,'fuel must use the journaled supply pull')
  local task=f.worker.state.currentTask
  assert(build.status=='completed',task and tostring(task.error) or build.status)
  eq(f.world.places,1); eq(f.stats.staged,3); eq(f.stats.pulled,3); eq(f.world.refuels,3)
  eq(f.inventories.stock[1].count,13); eq(f.world.items[15],nil); eq(next(f.world.items),nil)
  assert(f.world.fuel>=U.distance(f.world.pose,f.worker.config.depot))
end)
test('construction never replaces a foreign reserved fuel slot with supplied coal',function()
  local f=fixture(); finiteBuilder(f,1000)
  f.world.items[15]={name='minecraft:diamond',count=1}; f.inventories.stock={[1]={name='minecraft:coal',count=16}}
  f.controller.automation.queue:submit('BUILD',{blocks={{x=384,y=0,z=224,name='minecraft:stone',state={}}},clearanceY=2},{})
  for _=1,12 do f:step() end
  local task=assert(f.worker.state.currentTask)
  assert(task.error and task.error:find('slot 15',1,true),tostring(task.error))
  eq(task.supplyRequest,nil); eq(f.stats.staged,0); eq(f.world.items[15].name,'minecraft:diamond')
end)
test('underside verification budgets its fallback descent and escapes safely for construction or return',function()
  for _,following in ipairs({'RETURN_HOME','BUILD'}) do
    local f=fixture(); finiteBuilder(f,246)
    f.world.items[15]={name='minecraft:coal_block',count=1}; f.world.items[1]={name='minecraft:stone',count=1}
    local slab={x=20,y=0,z=0,name='minecraft:stone_slab',state={type='top',waterlogged='false'}}
    f.world.blocks['20,0,0']=U.copy(slab)
    local verify=f.controller.automation.queue:submit('VERIFY',{blocks={slab},clearanceY=50},{})
    for _=1,800 do f:step(); if verify.status=='completed' and not f.worker.state.currentTask then break end end
    eq(verify.status,'completed'); eq(verify.progress,1)
    assert(f.world.fuel>=119,'the underside stand requires 119 moves to return through clearance height')
    local payload={clearanceY=50}
    if following=='BUILD' then payload.blocks={{x=21,y=0,z=0,name='minecraft:stone',state={}}} end
    local job=f.controller.automation.queue:submit(following,payload,{})
    for _=1,800 do f:step(); if job.status=='completed' and not f.worker.state.currentTask then break end end
    local task=f.worker.state.currentTask
    assert(job.status=='completed',following..': '..(task and tostring(task.error) or job.status))
    eq(f.world.digs,0); eq(f.world.refuels,1)
    if following=='RETURN_HOME' then eq(f.world.pose.x,0); eq(f.world.pose.y,2) else eq(f.world.places,1) end
  end
end)

test('GPS recovery resumes an interrupted courier move without replacing its cargo ownership',function()
  local f=fixture();f.inventories.stage[1]={name='minecraft:stone',count=9}
  f.we.gps={locate=function() return f.world.pose.x,f.world.pose.y,f.world.pose.z end}
  f:reboot(false,true)
  local original=f.world.turtle.up;local interrupted=false
  f.world.turtle.up=function()
    local ok,why=original()
    if ok and f.stats.pulled==9 and not interrupted then interrupted=true;error('power lost after actual upward move') end
    return ok,why
  end
  local ok,id=f.controller:command('transport minecraft:stone 9 source destination');assert(ok,id)
  for _=1,200 do f:step();if interrupted then break end end
  assert(interrupted);assert(f.worker.state.position.pending);eq(f.stats.pulled,9)
  f:reboot(true,true);assert(f.worker:updateGPS())
  for _=1,300 do f:step();if f.controller.state.automation.jobs[id].status=='completed' then break end end
  eq(f.controller.state.automation.jobs[id].status,'completed');eq(f.stats.pulled,9);eq(f.stats.dropped,9)
  eq(f.inventories.destination[1].count,9)
end)

test('pose recovery keeps paused and unrelated courier blocks intact',function()
  for _,mode in ipairs({'paused','unrelated','disabled'}) do
    local f=fixture();f.inventories.stage[1]={name='minecraft:stone',count=9}
    local ok,id=f.controller:command('transport minecraft:stone 9 source destination');assert(ok,id)
    for _=1,20 do f:step();if f.worker.state.currentTask then break end end
    local pulled=f.stats.pulled
    local t=f.worker.state.currentTask;t.phase='blocked';t.error='destination container missing';t.poseBlocked=mode~='unrelated' or nil
    t.paused=mode=='paused';if mode=='disabled' then f.worker.config.automation.enabled=false end
    f.we.gps={locate=function() return f.world.pose.x,f.world.pose.y,f.world.pose.z end};f.worker:save();f:reboot(false,true)
    if mode=='disabled' then f.worker.config.automation.enabled=false end
    assert(f.worker:updateGPS());eq(f.worker.state.currentTask.phase,'blocked');eq(f.stats.pulled,pulled)
  end
end)

test('GPS heading probe recovers a courier turn across both controller and worker reboots',function()
  local f=fixture();f.inventories.stage[1]={name='minecraft:stone',count=9}
  f.we.gps={locate=function() return f.world.pose.x,f.world.pose.y,f.world.pose.z end};f:reboot(false,true)
  local original=f.world.turtle.turnRight;local interrupted=false
  f.world.turtle.turnRight=function()
    local ok,why=original()
    if ok and not interrupted then interrupted=true;error('power lost after actual turn') end
    return ok,why
  end
  -- The test world only supplied forward before; backtracking must be physical too.
  f.world.turtle.back=function()
    local p=f.world.pose;local d=({north={0,-1},east={1,0},south={0,1},west={-1,0}})[p.heading]
    p.x=p.x-d[1];p.z=p.z-d[2];return true
  end
  local ok,id=f.controller:command('transport minecraft:stone 9 source destination');assert(ok,id)
  for _=1,200 do f:step();if interrupted then break end end
  assert(interrupted);local origin=U.copy(f.world.pose);f:reboot(true,true);assert(f.worker:updateGPS());eq(f.worker.state.position.heading,nil)
  local rebooted=false;local lost={}
  f.filter=function(p)
    if (p.m.type=='task_pose_grant' or p.m.type=='task_pose_ack') and not lost[p.m.type] then lost[p.m.type]=true;return false end
  end
  for _=1,350 do
    f:step()
    local r=f.worker.state.poseRecovery
    if r and r.stage=='probe' and not rebooted then
      assert(U.distance(f.world.pose,origin)==1);f:reboot(true,true);rebooted=true
    end
    if f.controller.state.automation.jobs[id].status=='completed' then break end
  end
  assert(rebooted,'physical heading probe was not exercised');assert(lost.task_pose_grant and lost.task_pose_ack)
  eq(f.controller.state.automation.jobs[id].status,'completed');eq(f.stats.pulled,9);eq(f.stats.dropped,9)
  eq(f.worker.state.poseRecovery,nil);eq(f.controller.state.automation.jobs[id].poseRecovery.status,'settled')
end)

test('controller fallback restores issued pose claims and acknowledged settlement before conflicting motion',function()
  for _,cut in ipairs({'grant','ack','delayed'}) do
    local f=fixture();f.inventories.stage[1]={name='minecraft:stone',count=9}
    f.we.gps={locate=function() return f.world.pose.x,f.world.pose.y,f.world.pose.z end};f:reboot(false,true)
    local original=f.world.turtle.turnRight;local interrupted=false
    f.world.turtle.turnRight=function()
      local ok,why=original();if ok and not interrupted then interrupted=true;error('power loss after turn') end;return ok,why
    end
    f.world.turtle.back=function()
      local p=f.world.pose;local d=({north={0,-1},east={1,0},south={0,1},west={-1,0}})[p.heading]
      p.x=p.x-d[1];p.z=p.z-d[2];return true
    end
    local ok,id=f.controller:command('transport minecraft:stone 9 source destination');assert(ok,id)
    for _=1,200 do f:step();if interrupted then break end end
    assert(interrupted);f:reboot(false,true);assert(f.worker:updateGPS())
    local rebooted=false;local delayed
    if cut=='delayed' then f.filter=function(packet)
      if packet.m.type=='task_pose_grant' and not delayed then delayed=U.copy(packet);return false end
    end end
    for _=1,350 do
      f:step();local r=f.worker.state.poseRecovery
      local ready=cut=='grant' and r and r.granted and r.stage=='ready'
        or cut=='ack' and f.worker.state.poseReceipt or cut=='delayed' and delayed and r and not r.granted
      if ready and not rebooted then
        local origin=U.copy((r or f.worker.state.poseReceipt).origin)
        f.ce.fs.files['/autobuilder/data/controller.state']='corrupt';f:reboot(true,false);rebooted=true
        assert(f.controller.state.assignmentRecovery)
        local q=f.controller.automation.queue
        q.state.jobs.other={id='other',workerId=13,status='running',type='RETURN_HOME',loadedArea=U.copy(q.state.jobs[id].loadedArea)}
        f.controller.state.chunkLedger.leases.other={status='held',workerId=13,area=U.copy(q.state.jobs[id].loadedArea)}
        assert(not q:reserve(13,'other',origin,{x=origin.x+1,y=origin.y,z=origin.z},{}),'fallback allowed motion before claim recovery')
        q.state.jobs.other=nil;f.controller.state.chunkLedger.leases.other=nil
        if cut=='delayed' then
          f.ce.now=f.ce.now+10;f.we.now=f.ce.now;f.worker:tick();f:pump(f.we,f.controller);f.controller:tick()
          assert(f.controller.state.assignmentRecovery,'backup barrier cleared before controller-generation echo')
          f:pump(f.ce,f.worker);eq(f.worker.state.controllerBoot,f.controller.state.boot)
          assert(not f.worker:receive(delayed.m.sender,delayed.m,delayed.protocol),'late old grant crossed generation fence')
          assert(not f.worker.state.poseRecovery.granted);f.filter=nil
        end
      end
      if f.controller.state.automation.jobs[id].status=='completed' then break end
    end
    assert(rebooted,'fallback checkpoint window not exercised: '..cut)
    eq(f.controller.state.automation.jobs[id].status,'completed');eq(f.stats.dropped,9);eq(f.stats.pulled,9)
    eq(f.worker.state.poseRecovery,nil);eq(f.controller.state.automation.jobs[id].poseRecovery.status,'settled')
  end
end)

test('preparation supplies only the inspected missing support instead of mining for uninspected matching ground',function()
  local f=fixture();f.inventories.stock={};f.worker.config.supply.batch=64;f.controller.config.supply.batch=64
  f.world.blocks['3,0,0']={name='minecraft:stone',state={}}
  local j=f.controller.automation.queue:submit('PREPARE_REGION',{clearanceY=3,bounds={min={x=2,y=-1,z=0},max={x=3,y=3,z=0}},
    siteWork={identity=string.rep('a',64),region=1,stage='fill'},blocks={
      {x=2,y=0,z=0,name='minecraft:cobblestone',state={},support=true},{x=3,y=0,z=0,name='minecraft:cobblestone',state={},support=true}}},{})
  local requested=false
  for _=1,500 do
    f:step();local t=f.worker.state.currentTask
    if t and t.supplyRequest then
      eq(t.supplyRequest.count,1)
      if not requested then requested=true;f.inventories.stock[1]={name='minecraft:cobblestone',count=1} end
    end
    if j.status=='completed' and not t then break end
  end
  assert(requested);eq(j.status,'completed');eq(f.world.places,1);eq(f.world.blocks['3,0,0'].name,'minecraft:stone')
  eq(next(f.controller.state.jobs),nil);eq(next(f.controller.state.automation.requests),nil)
end)


test('registered supply rejects wrong worker endpoint and changed duplicate grants before pulling',function()
  local f=fixture();f:startBuild()
  f.filter=function(p) return p.m.type~='task_supply' end
  for _=1,300 do f:step();if f.worker.state.currentTask and f.worker.state.currentTask.supplyRequest then break end end
  local task=f.worker.state.currentTask;local request=assert(task.supplyRequest)
  local station={workerId=12,inventory='stage',side='down',position={x=0,y=2,z=0}}
  local sequence=100000
  local function grant(s)
    sequence=sequence+1
    return f.worker:receive(7,{version=1,sender=7,boot=f.controller.state.boot,sequence=sequence,id='7:'..f.controller.state.boot..':'..sequence,
      type='task_supply',payload={jobId=task.id,supplyId=request.id,item=request.item,count=1,station=s}},f.controller.config.protocol)
  end
  for _,change in ipairs({function(s) s.workerId=13 end,function(s) s.inventory='other' end,
    function(s) s.position.x=1 end,function(s) s.side='up' end}) do
    local bad=U.copy(station);change(bad);assert(not grant(bad));assert(not request.granted)
  end
  assert(grant(station));assert(request.granted);eq(f.stats.pulled,0)
  assert(not grant(nil));eq(request.station.inventory,'stage')
  f:reboot(true,true)
  eq(f.worker.state.currentTask.supplyRequest.station.inventory,'stage')
  -- The original accepted grant can finish even when its duplicate was lost.
  f.filter=nil;local ok,err=f:complete(600);assert(ok,f.ce.textutils.serialize({worker=f.worker.state.currentTask,supply=f.controller.state.automation.supply,stats=f.stats,jobs=f.controller.state.automation.jobs}));eq(f.stats.pulled,2);eq(f.world.places,2)
end)

test('supply protocol rejects malformed station identity and station metadata on receipts',function()
  local V=require('autobuilder.core.task_messages')
  local p={jobId='task:7:1',supplyId='task:7:1:supply:1',item='minecraft:stone',count=1,
    station={workerId=12,inventory='stage',side='front',position={x=0,y=2,z=0,heading='north'}}}
  assert(V.validate('task_supply',p));assert(not V.validate('task_supply_done',p));assert(not V.validate('task_supply_ack',p))
  p.station.position.heading=nil;assert(not V.validate('task_supply',p))
end)

test('queued distant work triggers above low station refuel before assignment across controller reboot',function()
  local f=fixture();finiteBuilder(f,100);local w=f.world
  f.inventories.fuel={};f.inventories.stock={[1]={name='minecraft:coal',count=4}}
  w.blocks['0,3,0']={name='minecraft:chest',state={}};w.blocks['50,0,0']={name='minecraft:stone',state={}}
  w.turtle.suckUp=function(n)
    eq(w.pose.x,0);eq(w.pose.y,2);eq(w.pose.z,0)
    local item=f.inventories.fuel[1];if not item then return false end
    local moved=math.min(n,item.count);w.items[w.selected]={name=item.name,count=moved};item.count=item.count-moved
    if item.count==0 then f.inventories.fuel[1]=nil end;return moved>0
  end
  w.turtle.refuel=function(n)
    local item=assert(w.items[15]);eq(w.selected,15);eq(item.name,'minecraft:coal')
    n=math.min(n,item.count);w.refuels=w.refuels+n;w.fuel=w.fuel+80*n;item.count=item.count-n
    if item.count==0 then w.items[15]=nil end;return true
  end
  for _,e in ipairs({f.ce,f.we}) do local call=e.peripheral.call;e.peripheral.call=function(name,method,...)
    if method=='size' then return 27 elseif method=='getItemLimit' then return 64
    elseif method=='getItemDetail' then local slot=...;local item=U.copy((f.inventories[name] or {})[slot]);if item then item.maxCount=64 end;return item end
    return call(name,method,...)
  end end
  for _,config in ipairs({f.controller.config,f.worker.config}) do
    config.minimumFuelReserve=20;config.fuel.enabled=true;config.fuel.low=80;config.fuel.target=120
  end
  f.controller.config.fuel.stations={{id='home',workerId=12,inventory='fuel',position={x=0,y=2,z=0},targetItems=1}}
  f:reboot(true,true)
  local job=f.controller.automation.queue:submit('VERIFY',{blocks={{x=50,y=0,z=0,name='minecraft:stone',state={}}},clearanceY=4},{})
  local id=job.id;local rebooted,assigned=false,false
  for _=1,600 do
    f:step();job=f.controller.state.automation.jobs[id]
    local row=f.controller.state.fuel.stations.home
    if row and row.refuel and not rebooted then eq(job.workerId,nil);f:reboot(true,false);rebooted=true end
    if job.workerId and not assigned then assert(w.refuels>0,'ordinary task left before station refuel');assigned=true end
    if job.status=='completed' and not f.worker.state.currentTask then break end
  end
  assert(rebooted);assert(assigned);eq(job.status,'completed');eq(job.report.counts.correct,1);eq(w.refuels,1)
  assert(w.fuel>=20+U.distance(w.pose,f.worker.config.depot),'verification lost its return reserve')
  local total=0;for _,inv in ipairs({f.inventories.stock,f.inventories.fuel}) do for _,item in pairs(inv) do if item.name=='minecraft:coal' then total=total+item.count end end end
  eq(total+w.refuels,4);eq(next(w.items),nil)
  local home=f.controller.automation.queue:submit('RETURN_HOME',{}, {})
  for _=1,500 do f:step();if home.status=='completed' and not f.worker.state.currentTask then break end end
  eq(home.status,'completed');eq(U.distance(w.pose,f.worker.config.depot),0);eq(w.refuels,1)
end)


test('builder replenishes low positive cargo through existing supply ownership before placing the last held item',function()
  local f=fixture();f.world.items[1]={name='minecraft:stone',count=1}
  f.inventories.stock[1]={name='minecraft:stone',count=1}
  local j=f.controller.automation.queue:submit('BUILD',{blocks={{x=2,y=0,z=0,name='minecraft:stone',state={}}, {x=3,y=0,z=0,name='minecraft:stone',state={}}},clearanceY=2},{})
  local early,restarted=false,false
  for _=1,500 do
    f:step();local t=f.worker.state.currentTask
    if t and t.supplyRequest and not early then
      eq(f.world.places,0);eq(f.world.items[1].count,1);eq(t.supplyRequest.count,1);early=true
      f:reboot(true,true);restarted=true
    end
    if j.status=='completed' or f.controller.state.automation.jobs[j.id].status=='completed' then break end
  end
  assert(early and restarted);eq(f.controller.state.automation.jobs[j.id].status,'completed')
  eq(f.world.places,2);eq(f.stats.staged,1);eq(f.stats.pulled,1);eq(next(f.inventories.stock),nil)
  for _=1,10 do f:step() end;eq(f.controller.state.automation.supply,nil)
end)

test('early builder shortage creates one durable production request while positive cargo remains',function()
  local f=fixture();f.world.items[1]={name='minecraft:cobblestone',count=1};f.inventories.stock={}
  local j=f.controller.automation.queue:submit('BUILD',{blocks={{x=2,y=0,z=0,name='minecraft:cobblestone',state={}}, {x=3,y=0,z=0,name='minecraft:cobblestone',state={}}},clearanceY=2},{})
  local created=false
  for _=1,50 do
    f:step()
    if next(f.controller.state.automation.requests) then created=true;break end
  end
  assert(created,'replacement demand was not submitted');eq(f.world.items[1].count,1);eq(f.world.places,0)
  local requests=f.controller.state.automation.requests;local id,r=next(requests)
  eq(r.requirements['minecraft:cobblestone'],1);eq(next(requests,id),nil)
  f:reboot(true,true)
  for _=1,30 do f:step() end
  requests=f.controller.state.automation.requests;eq(next(requests),id);eq(next(requests,id),nil)
  eq(f.world.items[1].count,1);eq(f.world.places,0);eq(f.controller.state.automation.jobs[j.id].workerId,12)
end)


test('early supply fits full cargo and smaller stacks across partial receipt reboot',function()
  for _,limit in ipairs({64,16}) do
    local f=fixture();f.stackLimit=limit;f.pullLimit=7;f.world.blocks['6,1,0']=nil
    f.worker.config.supply.batch=64;f.controller.config.supply.batch=64
    f.world.items[1]={name='minecraft:stone',count=1}
    for slot=2,14 do f.world.items[slot]={name='minecraft:dirt',count=64} end
    f.inventories.stock[1]={name='minecraft:stone',count=64}
    local blocks={};for x=2,66 do blocks[#blocks+1]={x=x,y=0,z=0,name='minecraft:stone',state={}};f.world.blocks[x..',-1,0']={name='minecraft:stone',state={}} end
    local j=f.controller.automation.queue:submit('BUILD',{blocks=blocks,clearanceY=2},{})
    local early,restarted=false,false;f.crashSuck=true
    for _=1,6000 do
      f:step();local t=f.worker.state.currentTask
      if t and t.supplyRequest and not early then eq(t.supplyRequest.count,limit-1);early=true end
      if f.crashed and not restarted then
        assert(f.stats.pulled>0 and f.stats.pulled<limit-1);f:reboot(true,true)
        f.worker.config.supply.batch=64;f.controller.config.supply.batch=64;restarted=true
      end
      if f.controller.state.automation.jobs[j.id].status=='completed' then break end
    end
    assert(early and restarted);assert(f.controller.state.automation.jobs[j.id].status=='completed', 'limit='..limit..' places='..f.world.places..' pulled='..f.stats.pulled..' error='..tostring(f.worker.state.currentTask and f.worker.state.currentTask.error))
    eq(f.world.places,65);eq(f.stats.pulled,64);eq(next(f.inventories.stage),nil)
    for _=1,10 do f:step() end;eq(f.controller.state.automation.supply,nil)
  end
end)

test('empty builder requests one bed and reconciles its sole supply item across reboot',function()
 local f=fixture();f.world.items={};f.inventories.stock={[1]={name='minecraft:red_bed',count=1}}
 local foot={x=2,y=0,z=0,name='minecraft:red_bed',state={part='foot',facing='east',occupied='false'}}
 local head={x=3,y=0,z=0,name=foot.name,state={part='head',facing='east',occupied='false'}}
 local place=f.world.turtle.placeDown
 f.world.turtle.placeDown=function(...)
  local ok,why=place(...)
  if ok then f.world.blocks['2,0,0']={name=foot.name,state=U.copy(foot.state)};f.world.blocks['3,0,0']={name=head.name,state=U.copy(head.state)} end
  return ok,why
 end
 f.crashSuck=true
 local j=f.controller.automation.queue:submit('BUILD',{blocks={foot,head},clearanceY=2},{})
 local requested,rebooted=false,false
 for _=1,700 do
  f:step();local t=f.worker.state.currentTask
  if t and t.supplyRequest then eq(t.supplyRequest.count,1);requested=true end
  if f.crashed and not rebooted then f:reboot(true,true);rebooted=true end
  if f.controller.state.automation.jobs[j.id].status=='completed' and not f.worker.state.currentTask then break end
 end
 assert(requested and rebooted);assert(f.controller.state.automation.jobs[j.id].status=='completed',tostring(f.worker.state.currentTask and f.worker.state.currentTask.error))
 eq(f.stats.staged,1);eq(f.stats.pulled,1);eq(f.world.places,1);eq(f.controller.state.automation.supply,nil)
end)

test('runtime offers completed finite supply before admitting the next factory batch',function()
 for _,stationBroken in ipairs({false,true}) do
  local f=fixture();f:startBuild();f.inventories.stock={}
  local j
  for _=1,100 do
   f:step()
   for _,job in pairs(f.controller.state.automation.jobs) do if job.supplyId and job.missingItem then j=job end end
   if j and next(f.controller.state.automation.requests) then break end
  end
  assert(j and j.supplyId);local p=f.controller.automation.production
  local pending=p:supplyRequest(j);assert(pending)
  f.inventories.stock={[1]={name='minecraft:stone',count=1},[2]={name='minecraft:oak_log',count=1}}
  f.controller.state.workers['9']={id=9,online=true,lastSeen=f.ce.now,telemetry={status='idle',capabilities={crafting=true}}}
  local later=p:request({['minecraft:oak_planks']=4})
  if stationBroken then f.inventories.stage={[1]={name='minecraft:dirt',count=1}} end
  for _=1,10 do f:step();if j.supplyHandoffAttempted then break end end
  assert(j.supplyHandoffAttempted,'normal supply loop must durably consume the handoff opportunity')
  eq(j.supplyHandoffAttempted.request,pending)
  if stationBroken then
   for _=1,10 do f:step();if later.jobId then break end end
   assert(later.jobId,'an actionable station fault must leave later manufacturing possible')
  else eq(f.stats.staged,1);assert(f.stats.supplyGrants>0) end
 end
end)
