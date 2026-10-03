local S=require('tests.support')
local U=require('autobuilder.core.util')
local Runtime=require('autobuilder.core.runtime')
local function mc(name) return 'minecraft:'..name end
local function environment(id)
  local e={fs=S.fs(),textutils=S.codec(),now=100,packets={},screen={},sent={}}
  e.os={getComputerID=function() return id end,epoch=function() return e.now*1000 end}
  e.rednet={isOpen=function() return true end,open=function() end,send=function(to,m,protocol)
    e.packets[#e.packets+1]={to=to,message=U.copy(m),protocol=protocol}
    e.sent[#e.sent+1]=U.copy(m); return true
  end}
  e.term={getSize=function() return 51,19 end,clear=function() e.screen={} end,setCursorPos=function(_,y) e.row=y end,write=function(s) e.screen[e.row]=s end}
  e.gps={locate=function() return 0,64,0 end}
  return e
end
local function fixture(furnaceCount)
  furnaceCount=furnaceCount or 1
  local h={inventories={store={},furnace={},input={},output={}},slots={},selected=1,crafts=0,transfers=0,burn=0}
  h.furnaces={'furnace'}; h.burns={}
  for i=2,furnaceCount do local name='furnace'..i; h.furnaces[i]=name; h.inventories[name]={} end
  h.inventories.store[1]={name=mc('cobblestone'),count=8}; h.inventories.store[2]={name=mc('coal'),count=2+furnaceCount}
  local function change(inv,slot,item,delta)
    local old=inv[slot]; local count=(old and old.count or 0)+delta
    assert(count>=0 and (not old or old.name==item),'physical inventory underflow/mismatch')
    inv[slot]=count>0 and {name=item,count=count} or nil
  end
  local function move(from,slot,to,target,limit)
    local stack=from[slot]; if not stack then return 0 end
    if not target then
      for i=1,27 do if not to[i] or to[i].name==stack.name and to[i].count<64 then target=i; break end end
    end
    if not target or to[target] and to[target].name~=stack.name then return 0 end
    local n=math.min(limit or 64,stack.count,64-(to[target] and to[target].count or 0))
    change(from,slot,stack.name,-n); change(to,target,stack.name,n); return n
  end
  local peripheral={getNames=function() return {'right','store','furnace','input','output'} end,
    getType=function(name) return name=='right' and 'modem' or 'inventory' end,
    call=function(name,method,...)
      if name=='right' then assert(method=='isWireless'); return true end
      if h.offline==name then error('inventory detached') end
      local inv=assert(h.inventories[name],'unknown inventory '..tostring(name))
      if method=='list' then return U.copy(inv) end
      if method=='size' then return 27 end
      if method=='getItemLimit' then return 64 end
      if method=='getItemDetail' then local slot=...; local item=U.copy(inv[slot]); if item then item.maxCount=64 end; return item end
      assert(method=='pushItems','unexpected inventory method '..method)
      local target,slot,n,toSlot=...; local moved=move(inv,slot,assert(h.inventories[target]),toSlot,n)
      h.transfers=h.transfers+1
      if h.afterTransfer then h.afterTransfer(name,target,moved) end
      return moved
    end}
  local turtle=S.turtle()
  turtle.getItemCount=function(slot) return h.slots[slot] and h.slots[slot].count or 0 end
  turtle.getItemDetail=function(slot) return U.copy(h.slots[slot]) end
  turtle.select=function(slot) h.selected=slot; return true end
  turtle.suckUp=function(n)
    for slot in pairs(h.inventories.input) do return move(h.inventories.input,slot,h.slots,h.selected,n)>0 end
    return false
  end
  turtle.dropDown=function(n) return move(h.slots,h.selected,h.inventories.output,nil,n)>0 end
  turtle.craft=function(limit)
    eq(limit,1); eq(h.selected,13)
    for slot=1,16 do
      local ingredient=slot==1 or slot==2 or slot==5 or slot==6
      if ingredient then assert(h.slots[slot] and h.slots[slot].name==mc('stone') and h.slots[slot].count==1,'incorrect real stone-brick recipe')
      else assert(not h.slots[slot],'non-grid turtle slot is occupied') end
    end
    for _,slot in ipairs({1,2,5,6}) do change(h.slots,slot,mc('stone'),-1) end
    change(h.slots,13,mc('stone_bricks'),4); h.crafts=h.crafts+1
    if h.afterCraft then h.afterCraft() end
    return true
  end
  function h:smelt()
    if self.pauseSmelting then return end
    for _,name in ipairs(self.furnaces) do
      local inv=self.inventories[name]; local burn=self.burns[name] or 0
      if inv[1] and (inv[2] or burn>0) then
        eq(inv[1].name,mc('cobblestone'))
        if burn==0 then eq(inv[2].name,mc('coal')); change(inv,2,mc('coal'),-1); burn=8 end
        change(inv,1,mc('cobblestone'),-1); change(inv,3,mc('stone'),1); self.burns[name]=burn-1
      end
    end
  end
  function h:count(item) local n=0; for _,stack in pairs(self.inventories.store) do if stack.name==item then n=n+stack.count end end; return n end
  local ce,we=environment(7),environment(12); ce.peripheral=peripheral; we.peripheral=peripheral; we.turtle=turtle
  local C=require('tests.loaded_config')
  local settings={storageInventories={'store'},furnaces=U.copy(h.furnaces),turtleFuelReserveItems={[mc('coal')]=2},
    craftingStation={input='input',output='output',inputSide='up',outputSide='down'},
    heartbeatInterval=1,registrationInterval=3,workerTimeout=8}
  local controllerSettings=U.copy(settings); controllerSettings.role='controller'
  local workerSettings=U.copy(settings); workerSettings.role='worker'; workerSettings.controllerId=7
  workerSettings.initialPosition={x=0,y=64,z=0,heading='north'}; workerSettings.automation={crafting=true}
  local f={h=h,ce=ce,we=we,cc=C.load(controllerSettings),wc=C.load(workerSettings)}
  f.c=Runtime.new(f.cc,ce); f.w=Runtime.new(f.wc,we)
  function f:pump(from,to,dropAck)
    local packets=from.packets; from.packets={}
    for _,p in ipairs(packets) do
      if not (dropAck and p.message.type=='task_ack') then
        local ok,why=to:receive(p.message.sender,p.message,p.protocol)
        if not ok then self.rejections=self.rejections or {}; self.rejections[#self.rejections+1]=p.message.type..': '..tostring(why) end
      else self.droppedAcks=(self.droppedAcks or 0)+1 end
    end
  end
  function f:step(dropAck)
    ce.now=ce.now+1; we.now=ce.now
    assert(self.c:tick()); self:pump(ce,self.w,dropAck)
    assert(self.c:workStep()); h:smelt()
    assert(self.w:tick()); assert(self.w:workStep()); self:pump(we,self.c); self:pump(ce,self.w,dropAck)
  end
  function f:request()
    assert(self.w:tick()); self:pump(we,self.c); self:pump(ce,self.w)
    local ok,id=self.c:command('request minecraft:stone_bricks 8'); assert(ok,id); self.id=id; return id
  end
  function f:finish(limit)
    for _=1,limit or 160 do self:step(); if self.c.state.automation.requests[self.id].status=='completed' and not self.w.state.currentTask then return end end
    local r=self.c.state.automation.requests[self.id]; local task=self.w.state.currentTask
    error('production did not complete: '..tostring(r.status)..' '..tostring(r.error)..'; worker '..tostring(task and task.phase)..' '..tostring(task and task.error))
  end
  return f
end

test('real production runtime makes requested stone bricks through furnace and network Crafty task',function()
  local f=fixture(); f:request(); f:finish()
  eq(f.h:count(mc('stone_bricks')),8); eq(f.h:count(mc('cobblestone')),0); eq(f.h:count(mc('coal')),2)
  eq(f.h.crafts,2); eq(next(f.h.slots),nil)
  local assigned=false
  for _,m in ipairs(f.ce.sent) do if m.type=='task_assign' then eq(m.payload.job.type,'CRAFT'); assigned=true end end
  assert(assigned,'production never assigned the Crafty worker through networking')
  for _,j in pairs(f.c.state.automation.jobs) do eq(j.status,'completed') end
end)

test('blocked crafting resumes after reconnect and reboot without hardware work in the control handler',function()
  local f=fixture(); f.h.offline='input'; f:request()
  for _=1,100 do
    f:step()
    if f.w.state.currentTask and f.w.state.currentTask.phase=='blocked' then break end
  end
  local task=assert(f.w.state.currentTask); eq(task.phase,'blocked')
  assert(task.error:find('inventory detached')); eq(f.h.crafts,0)
  f.h.offline=nil; f.w=Runtime.new(f.wc,f.we)
  local transfers=f.h.transfers
  assert(f.c:command('resume '..task.id)); f:pump(f.ce,f.w)
  eq(f.h.transfers,transfers)
  f:finish(); eq(f.h.crafts,2); eq(f.h:count(mc('stone_bricks')),8)
end)

test('production runtime reboots after furnace and craft physical effects without duplicate output',function()
  local f=fixture(); f:request(); local controllerCrash,workerCrash=false,false
  f.h.afterTransfer=function(_,target)
    if target=='furnace' and not controllerCrash then
      controllerCrash=true; f.ce.fs.fault.open='/autobuilder/data/controller.state.tmp'
    end
  end
  local ok=pcall(function() for _=1,10 do f:step() end end)
  assert(controllerCrash and not ok,'fixture never interrupted controller after real transfer')
  f.ce.fs.fault.open=nil; f.c=Runtime.new(f.cc,f.ce); f.ce.packets={}
  f.h.afterCraft=function()
    if not workerCrash then workerCrash=true; f.we.fs.fault.open='/autobuilder/data/worker.state.tmp' end
  end
  ok=pcall(function() for _=1,100 do f:step() end end)
  assert(workerCrash and not ok,'fixture never interrupted worker after real craft')
  f.we.fs.fault.open=nil; f.w=Runtime.new(f.wc,f.we); f.we.packets={}
  f:finish(); eq(f.h.crafts,2); eq(f.h:count(mc('stone_bricks')),8); eq(f.h:count(mc('coal')),2)
end)

test('production completion survives lost task acknowledgement and both runtime restarts',function()
  local f=fixture(); f:request()
  for _=1,100 do f:step(true) end
  eq(f.c.state.automation.requests[f.id].status,'completed'); eq(f.w.state.currentTask.phase,'completed')
  assert(f.droppedAcks and f.droppedAcks>0); eq(f.h.crafts,2)
  f.c=Runtime.new(f.cc,f.ce); f.w=Runtime.new(f.wc,f.we)
  for _=1,12 do f:step() end
  eq(f.w.state.currentTask,nil); eq(f.h.crafts,2); eq(f.h:count(mc('stone_bricks')),8)
end)

test('production rejects invalid quantities even when a matching request already exists',function()
  local f=fixture(); f:request()
  for _,quantity in ipairs({'0','-1','1.5','nan','1000001'}) do
    assert(not f.c:command('request minecraft:stone_bricks '..quantity),'accepted invalid quantity '..quantity)
  end
  eq(f.c.state.automation.requestSequence,1); eq(f.h.transfers,0)
end)

test('paused controller smelting task does not perform inventory transfers',function()
  local f=fixture(); f:request(); f.c:tick()
  local job; for _,j in pairs(f.c.state.automation.jobs) do if j.type=='SMELT' then job=j end end
  assert(job); assert(f.c:command('pause '..job.id)); f.c:workStep()
  eq(f.h.transfers,0)
end)


test('furnace bank loads two lanes before completion and joins both before crafting',function()
  local f=fixture(2); f.h.pauseSmelting=true; f:request()
  for _=1,6 do f:step() end
  local jobs=f.c.state.automation.jobs; local laneCount=0
  for _,j in pairs(jobs) do
    eq(j.type,'SMELT'); assert(j.furnaceLane); eq(j.batches,4); assert(j.status~='completed'); laneCount=laneCount+1
  end
  eq(laneCount,2); eq(f.h.inventories.furnace[1].count,4); eq(f.h.inventories.furnace2[1].count,4)
  eq(f.h.crafts,0)
  f.h.pauseSmelting=false; f:finish()
  eq(f.h:count(mc('stone_bricks')),8); eq(f.h.crafts,2); eq(f.h:count(mc('coal')),2)
end)

test('furnace bank reconciles a crashed lane before another lane mutates shared storage',function()
  local f=fixture(2); f.h.pauseSmelting=true; f:request(); local crashed=false
  f.h.afterTransfer=function(_,target)
    if target=='furnace' and not crashed then crashed=true; f.ce.fs.fault.open='/autobuilder/data/controller.state.tmp' end
  end
  assert(not pcall(function() for _=1,10 do f:step() end end)); assert(crashed)
  local calls=f.h.transfers
  f.ce.fs.fault.open=nil; f.c=Runtime.new(f.cc,f.ce); f.ce.packets={}
  assert(f.c:workStep()); eq(f.h.transfers,calls,'recovery must only reconcile pending observation')
  eq(next(f.h.inventories.furnace2),nil)
  f.h.pauseSmelting=false; f:finish()
  eq(f.h:count(mc('stone_bricks')),8); eq(f.h.crafts,2); eq(f.h:count(mc('coal')),2)
end)

test('furnace planning rounds fuel by lane while preserving turtle reserve',function()
  local p=require('autobuilder.blueprint.planner').expand({[mc('stone')]=8},
    {[mc('cobblestone')]=8,[mc('coal')]=3},
    {furnaces={'furnace','furnace2'},turtleFuelReserveItems={[mc('coal')]=2}})
  eq(p.fuel.items,2); eq(p.missing[mc('coal')],1); eq(#p.operations[1].lanes,2)
  eq(p.operations[1].lanes[1].batches,4); eq(p.operations[1].lanes[2].batches,4)
  assert(not pcall(require('autobuilder.blueprint.planner').expand,{[mc('stone')]=8},{},{furnaces={'furnace','furnace'}}))
end)


test('furnace bank blocks all other lane effects while a pending journal is unreadable',function()
  local f=fixture(2); f.h.pauseSmelting=true; f:request(); local crashed=false
  f.h.afterTransfer=function(_,target)
    if target=='furnace' and not crashed then crashed=true; error('peripheral call interrupted after mutation') end
  end
  f:step(); assert(crashed)
  local calls=f.h.transfers; f.h.offline='store'
  assert(f.c:workStep()); eq(f.h.transfers,calls); eq(next(f.h.inventories.furnace2),nil)
  f.h.offline=nil; assert(f.c:workStep()); eq(f.h.transfers,calls)
  f.h.pauseSmelting=false; f:finish(); eq(f.h:count(mc('stone_bricks')),8)
end)

test('furnace bank rejects duplicate durable lane owners before physical effects',function()
  local f=fixture(2)
  local queue=f.c.automation.queue
  local a=queue:submit('SMELT',{item=mc('stone'),batches=4,quantity=4,furnaceLane='furnace'},{},'owner-a')
  local b=queue:submit('SMELT',{item=mc('stone'),batches=4,quantity=4,furnaceLane='furnace'},{},'owner-b')
  assert(f.c:workStep()); eq(f.h.transfers,0); eq(a.status,'blocked'); eq(b.status,'blocked')
  assert(a.error:find('duplicate ownership'))
end)

test('furnace bank adopts a legacy unsplit active job without producing duplicate lanes',function()
  local f=fixture(2); f:request(); f.c:tick()
  local request=f.c.state.automation.requests[f.id]; local plan=request.plan
  for id in pairs(f.c.state.automation.jobs) do f.c.state.automation.jobs[id]=nil end
  f.c.state.inventoryLedger=nil -- historical checkpoints predate reservation grants
  local old=f.c.automation.queue:submit('SMELT',{item=mc('stone'),batches=8,quantity=8},{},request.id..':op:1')
  request.jobId=old.id; request.jobIds=nil; plan.operations[1].lanes=nil
  f.c:save(); f.c=Runtime.new(f.cc,f.ce); f.ce.packets={}
  f:finish()
  local lanes=0; for _,job in pairs(f.c.state.automation.jobs) do if job.type=='SMELT' then lanes=lanes+1; eq(job.id,old.id) end end
  eq(lanes,1); eq(f.h:count(mc('stone_bricks')),8); eq(f.h.crafts,2)
end)

test('legacy planned fuel budget is not enlarged when restoring without lane metadata',function()
  local f=fixture(2); f:request(); f.c:tick()
  local request=f.c.state.automation.requests[f.id]
  for id in pairs(f.c.state.automation.jobs) do f.c.state.automation.jobs[id]=nil end
  f.c.state.inventoryLedger=nil -- historical checkpoints predate reservation grants
  request.jobId=nil; request.jobIds=nil; request.plan.operations[1].lanes=nil
  request.plan.fuel.items=1; f.h.inventories.store[2].count=3
  f.c:save(); f.c=Runtime.new(f.cc,f.ce); f.ce.packets={}
  f:finish(); eq(f.h:count(mc('coal')),2); eq(f.h:count(mc('stone_bricks')),8)
end)

test('resource command exposes request dependency graph without issuing physical actions',function()
  local f=fixture(); f:request(); f.c.automation.production:tick()
  local transfers=f.h.transfers
  local ok,summary=f.c.automation:command('resource minecraft:stone_bricks')
  assert(ok,'resource command missing'); assert(summary:find('required=8',1,true),summary)
  assert(summary:find('planned=8',1,true),summary); eq(f.h.transfers,transfers)
  assert(not pcall(f.c.automation.command,f.c.automation,'resource'))
end)

test('factory inventory receipts survive reboot and release only measured output',function()
  local f=fixture(); f:request(); local partial=false
  for _=1,150 do
    f:step()
    local ledger=assert(f.c.state.inventoryLedger,'controller inventory ledger missing')
    for id,l in pairs(ledger.leases) do
      if (l.withdrawn[mc('stone')] or 0)>0 and (l.delivered[mc('stone_bricks')] or 0)<8 then
        eq(l.status,'held'); partial=true
        f.c=Runtime.new(f.cc,f.ce); f.w=Runtime.new(f.wc,f.we)
        eq(f.c.state.inventoryLedger.leases[id].withdrawn[mc('stone')],l.withdrawn[mc('stone')])
        break
      end
    end
    if partial then break end
  end
  assert(partial,'no partial physical ingredient receipt reached controller')
  f:finish(); local seen=0
  for _,l in pairs(f.c.state.inventoryLedger.leases) do eq(l.status,'released'); seen=seen+1 end
  eq(seen,2); eq(f.h:count(mc('stone_bricks')),8); eq(f.h.crafts,2)
end)

test('stock receipt protocol rejects malformed counters before accepting progress',function()
  local P=require('autobuilder.core.task_messages')
  for _,receipt in ipairs({{sequence=0,withdrawn={},delivered={}},
    {sequence=1,withdrawn={[mc('stone')]=-1},delivered={}},
    {sequence=1,withdrawn='bad',delivered={}},
    {sequence=1,withdrawn={},delivered={[mc('stone')]=math.huge}}}) do
    assert(not P.validate('task_progress',{jobId='task:7:1',phase='work',stockReceipt=receipt}))
  end
end)


test('native runtime protocol refuels an empty turtle through a claimed station and releases its owner',function()
  local f=fixture(); local h=f.h; local turtle=f.we.turtle
  h.inventories.fuel={}; turtle.fuel=0
  turtle.inspectUp=function() return true,{name=mc('chest')} end
  turtle.suckUp=function(n)
    for slot,stack in pairs(h.inventories.fuel) do
      local moved=math.min(n,stack.count)
      h.slots[h.selected]={name=stack.name,count=moved}; stack.count=stack.count-moved
      if stack.count==0 then h.inventories.fuel[slot]=nil end
      return moved>0
    end
    return false
  end
  turtle.refuel=function(n)
    local item=h.slots[h.selected]; if not item or item.name~=mc('coal') then return false end
    local used=math.min(n,item.count); turtle.fuel=turtle.fuel+used*80
    item.count=item.count-used; if item.count==0 then h.slots[h.selected]=nil end
    return true
  end
  local C=require('tests.loaded_config')
  f.cc.fuel={enabled=true,low=80,target=160,stations={{id='home',workerId=12,inventory='fuel',position={x=0,y=64,z=0},targetItems=2}}}
  f.wc.fuel={enabled=true,low=80,target=160}; f.wc.depot={x=0,y=64,z=0}
  f.cc=C.load(f.cc); f.wc=C.load(f.wc)
  f.c=Runtime.new(f.cc,f.ce); f.w=Runtime.new(f.wc,f.we)
  for _=1,25 do f:step() end
  eq(turtle.fuel,160); eq(f.w.state.currentTask,nil)
  local refuels=0
  for _,job in pairs(f.c.state.automation.jobs) do
    if job.type=='REFUEL' then refuels=refuels+1; eq(job.status,'completed') end
    if job.type=='FUEL_STATION' and job.status=='completed' then eq(f.c.state.inventoryLedger.leases[job.id].status,'released') end
  end
  eq(refuels,1); assert(not require('autobuilder.core.workflows').workerBusy(f.c.state,12))
  assert(not f.rejections,table.concat(f.rejections or {},'; '))
end)

local function stationRefuelRegression(target,stock)
  local f=fixture(); local h=f.h; local turtle=f.we.turtle
  h.inventories.fuel={}; h.inventories.store[2].count=64; turtle.fuel=0
  turtle.inspectUp=function() return true,{name=mc('chest')} end
  turtle.suckUp=function(n)
    for slot,stack in pairs(h.inventories.fuel) do
      local moved=math.min(n,stack.count)
      h.slots[h.selected]={name=stack.name,count=moved}; stack.count=stack.count-moved
      if stack.count==0 then h.inventories.fuel[slot]=nil end
      return moved>0
    end
    return false
  end
  turtle.refuel=function(n)
    local item=h.slots[h.selected]; if not item or item.name~=mc('coal') then return false end
    local used=math.min(n,item.count); turtle.fuel=turtle.fuel+used*80
    item.count=item.count-used; if item.count==0 then h.slots[h.selected]=nil end
    return true
  end
  local C=require('tests.loaded_config')
  f.cc.fuel={enabled=true,low=80,target=target,stations={{id='home',workerId=12,inventory='fuel',position={x=0,y=64,z=0},targetItems=stock}}}
  f.wc.fuel={enabled=true,low=80,target=target}; f.wc.depot={x=0,y=64,z=0}
  f.cc=C.load(f.cc); f.wc=C.load(f.wc)
  f.c=Runtime.new(f.cc,f.ce); f.w=Runtime.new(f.wc,f.we)
  for i=1,180 do
    f:step()
    if i==18 then f.c=Runtime.new(f.cc,f.ce); f.w=Runtime.new(f.wc,f.we) end
  end
  eq(turtle.fuel,math.ceil(target/80)*80); eq(f.w.state.currentTask,nil)
  local refuels=0
  for _,job in pairs(f.c.state.automation.jobs) do
    if job.type=='REFUEL' then refuels=refuels+1; eq(job.status,'completed') end
    if job.type=='FUEL_STATION' and job.status=='completed' then eq(f.c.state.inventoryLedger.leases[job.id].status,'released') end
  end
  assert(refuels>=1); assert(not require('autobuilder.core.workflows').workerBusy(f.c.state,12))
  assert(not f.rejections,table.concat(f.rejections or {},'; '))
  eq(next(h.slots),nil)
  -- Run the real crafting engine after refueling, using distinct input and fuel chests.
  turtle.suckUp=function(n)
    for slot,item in pairs(h.inventories.input) do
      h.slots[h.selected]={name=item.name,count=1}; h.inventories.input[slot]=nil; return true
    end
    return false
  end
  h.inventories.store[3]={name=mc('stone'),count=4}
  local task={item=mc('stone_bricks'),quantity=4}
  local engine=require('autobuilder.factory.crafting').new(task,f.we,f.wc,function() return true end)
  local status,why
  for _=1,40 do status,why=engine:step(); if status=='complete' or status=='blocked' then break end end
  eq(status,'complete'); eq(h.crafts,1)
end

test('default station refuel leaves a Crafty turtle empty for its next craft',function()
  stationRefuelRegression(1000,16)
end)
test('small fuel station releases and replenishes finite batches across reboot until target',function()
  stationRefuelRegression(1000,2)
end)

test('unlimited native fuel limits register workers with automatic fuel disabled',function()
  local f=fixture()
  f.we.turtle.getFuelLevel=function() return 'unlimited' end
  f.we.turtle.getFuelLimit=function() return 'unlimited' end
  assert(f.w:tick()); f:pump(f.we,f.c)
  assert(f.c.state.workers['12'],'unlimited worker registration rejected')
  assert(not f.rejections,table.concat(f.rejections or {},'; '))
end)

test('fleet runtime rescues a stranded worker and resumes its original task across lost receipts and reboot',function()
  local f=fixture(); local h=f.h; local courier=f.we.turtle
  local ve=environment(13); ve.peripheral=f.we.peripheral
  local recipient={slots={[1]={name=mc('coal'),count=4}},fuel=0,burns=0}
  local vt=S.turtle(); vt.fuel=0; ve.turtle=vt
  vt.inspect=function() return false end; vt.inspectUp=vt.inspect; vt.inspectDown=vt.inspect
  vt.getItemDetail=function(i) return U.copy(recipient.slots[i]) end
  vt.getItemCount=function(i) return recipient.slots[i] and recipient.slots[i].count or 0 end
  vt.getItemSpace=function(i) return 64-vt.getItemCount(i) end
  vt.select=function(i) recipient.selected=i; return true end
  vt.refuel=function(n)
    local i=recipient.slots[recipient.selected]; assert(i and i.name==mc('coal'))
    local used=math.min(n,i.count); i.count=i.count-used; if i.count==0 then recipient.slots[recipient.selected]=nil end
    vt.fuel=vt.fuel+80*used; recipient.burns=recipient.burns+1; return true
  end
  h.inventories.fuel={}; courier.fuel=500
  courier.getItemSpace=function(i) return 64-courier.getItemCount(i) end
  courier.inspect=function() return false end
  courier.inspectUp=function()
    local p=f.w.state.position
    if p.x==0 and p.y==64 and p.z==0 then return true,{name=mc('chest')} end
    return false
  end
  courier.inspectDown=function()
    local p=f.w.state.position
    if p.x==5 and p.y==65 and p.z==0 then return true,{name='computercraft:turtle_advanced'} end
    return false
  end
  courier.suckUp=function(n)
    for slot,i in pairs(h.inventories.fuel) do
      local moved=math.min(n,i.count); h.slots[h.selected]={name=i.name,count=(h.slots[h.selected] and h.slots[h.selected].count or 0)+moved}
      i.count=i.count-moved; if i.count==0 then h.inventories.fuel[slot]=nil end; return true
    end
    return false
  end
  courier.dropDown=function(n)
    local p=f.w.state.position; eq(p.x,5); eq(p.y,65)
    local i=h.slots[h.selected]; local moved=math.min(n,i.count)
    recipient.slots[1].count=recipient.slots[1].count+moved
    i.count=i.count-moved; if i.count==0 then h.slots[h.selected]=nil end
    return true
  end
  local call=f.we.peripheral.call; local getType=f.we.peripheral.getType
  f.we.peripheral.getType=function(name) return name=='bottom' and 'turtle' or getType(name) end
  f.we.peripheral.call=function(name,method,...) if name=='bottom' and method=='getID' then return 13 end; return call(name,method,...) end
  local C=require('tests.loaded_config')
  f.cc.fuel={enabled=true,low=80,target=160,stations={{id='courier',workerId=12,inventory='fuel',position={x=0,y=64,z=0},targetItems=2}}}
  f.wc.fuel={enabled=true,low=80,target=160}; f.wc.depot={x=0,y=64,z=0}; f.wc.automation.courier=true
  local vc=C.load({role='worker',controllerId=7,initialPosition={x=5,y=64,z=0,heading='north'},depot={x=5,y=64,z=3},
    fuel={enabled=true,low=80,target=160},mining={fuelTarget=160},heartbeatInterval=1,registrationInterval=3,workerTimeout=8})
  f.cc=C.load(f.cc); f.wc=C.load(f.wc)
  f.c=Runtime.new(f.cc,f.ce); f.w=Runtime.new(f.wc,f.we); local v=Runtime.new(vc,ve)
  local original=f.c.automation.queue:submit('RETURN_HOME',{preferredWorker=13},{})
  local rebooted,dropped=false,false
  local function pump()
    for _=1,8 do
      local any=false; local apps={[7]=f.c,[12]=f.w,[13]=v}
      for _,env in ipairs({f.ce,f.we,ve}) do
        local packets=env.packets; env.packets={}
        for _,p in ipairs(packets) do
          any=true
          if not dropped and p.message.type=='task_fuel_status' and p.message.payload.phase=='consumed' then dropped=true
          else local ok,why=apps[p.to]:receive(p.message.sender,p.message,p.protocol)
            assert(ok or why=='task message needs current worker registration' or tostring(why):find('position reserved by worker',1,true),why) end
        end
      end
      if not any then break end
    end
  end
  for _=1,150 do
    f.ce.now=f.ce.now+1; f.we.now=f.ce.now; ve.now=f.ce.now
    for _,app in ipairs({f.c,f.w,v}) do assert(app:tick()); pump(); assert(app:workStep()); pump() end
    if not rebooted and recipient.burns>0 and v.fuelRecovery:active() then
      local originalId=v.state.currentTask.id; eq(originalId,original.id)
      f.c=Runtime.new(f.cc,f.ce); v=Runtime.new(vc,ve); rebooted=true
    end
  end
  assert(rebooted and dropped); eq(recipient.burns,1); eq(recipient.slots[1].count,4)
  eq(f.c.state.automation.jobs[original.id].status,'completed'); eq(v.state.currentTask,nil)
  eq(v.state.position.x,5); eq(v.state.position.z,3); assert(vt.fuel>0); assert(courier.fuel<500 and courier.fuel>100)
  local rescues=0
  for _,j in pairs(f.c.state.automation.jobs) do if j.type=='RESCUE' then rescues=rescues+1; eq(j.status,'completed'); eq(j.rescueSettled,true) end end
  eq(rescues,1); assert(not v.fuelRecovery:active()); eq(f.w.state.position.x,0); eq(f.w.state.currentTask,nil)
end)

test('private Crafty worker only consumes and produces in its configured buffer across reboot',function()
  local f=fixture(); local h=f.h; h.inventories.buffer={[1]={name=mc('stone'),count=4}}
  f.wc.craftingStation.buffer='buffer'; f.wc.turtleFuelReserveItems[mc('stone')]=4; f.wc=require('tests.loaded_config').load(f.wc)
  f.w=Runtime.new(f.wc,f.we)
  local job={id='task:7:999',type='CRAFT',item=mc('stone_bricks'),quantity=4,batches=1,workerId=12,preferredWorker=12,
    privateStation={id='west',workerId=12,buffer='buffer',input='input',output='output'}}
  local wrong=U.copy(job); wrong.privateStation.buffer='store'
  local before=h.transfers
  local ok,why=f.w.automation:handle(7,{type='task_assign',boot=1,sequence=1,payload={job=wrong}})
  assert(not ok and why:find('station'),'mismatched private station accepted'); eq(h.transfers,before)
  assert(f.w.automation:handle(7,{type='task_assign',boot=1,sequence=2,payload={job=job}}))
  local stock=U.copy(h.inventories.store)
  for i=1,45 do
    assert(f.w:workStep())
    if i==7 then f.w=Runtime.new(f.wc,f.we) end
    if f.w.state.currentTask.phase=='completed' then break end
  end
  eq(f.w.state.currentTask.phase,'completed'); eq(h.crafts,1)
  assert(require('autobuilder.factory.factory').equal(h.inventories.store,stock),'private crafter changed shared stock')
  eq(require('autobuilder.factory.factory').count(h.inventories.buffer,mc('stone_bricks')),4)
end)

test('private worker output receipt cannot credit or release shared stock before collection',function()
  local f=fixture(); local q=f.c.automation.queue; local p=f.c.automation.production
  local j=q:submit('CRAFT',{item=mc('stone_bricks'),quantity=4,privateStation={id='west',workerId=12,buffer='buffer',input='input',output='output'},
    stockInputs={[mc('stone')]=4},stockOutputs={[mc('stone_bricks')]=4}},{})
  assert(p.ledger:reserve(j.id,j.stockInputs,j.stockOutputs,{[mc('stone')]=4}))
  assert(p:acceptReceipt(j,{withdrawn={[mc('stone')]=4},delivered={[mc('stone_bricks')]=4},sequence=1}))
  eq(next(p.ledger.state.leases[j.id].delivered),nil)
  eq(next(p.ledger.state.leases[j.id].withdrawn),nil)
end)

local function parallelFixture()
  local f=fixture(); local second=fixture(); f.other=second
  local h=f.h; h.inventories.store={[1]={name=mc('stone'),count=40}}
  for _,name in ipairs({'buffer','buffer2','input2','output2'}) do h.inventories[name]={} end
  second.h.inventories=setmetatable({}, {__index=function(_,name)
    return h.inventories[({input='input2',output='output2'})[name] or name]
  end})
  second.we.os.getComputerID=function() return 13 end; second.we.fs=S.fs()
  f.cc.turtleFuelReserveItems={}; f.cc.craftingBatchSize=2
  f.cc.craftingStation.input=''; f.cc.craftingStation.output=''
  f.cc.craftingStations={{id='west',workerId=12,buffer='buffer',input='input',output='output'},
    {id='east',workerId=13,buffer='buffer2',input='input2',output='output2'}}
  f.wc.craftingStation.buffer='buffer'; f.wc.turtleFuelReserveItems={}
  second.wc.craftingStation={buffer='buffer2',input='input2',output='output2',inputSide='up',outputSide='down'}
  second.wc.turtleFuelReserveItems={}
  local C=require('tests.loaded_config'); f.cc=C.load(f.cc); f.wc=C.load(f.wc); second.wc=C.load(second.wc)
  f.c=Runtime.new(f.cc,f.ce); f.w=Runtime.new(f.wc,f.we); second.w=Runtime.new(second.wc,second.we)
  f.maxConcurrent=0; f.droppedAcks=0
  function f:pumpAll(env)
    local packets=env.packets; env.packets={}
    for _,p in ipairs(packets) do
      local target=p.to==7 and self.c or p.to==12 and self.w or p.to==13 and self.other.w
      assert(target,'unexpected destination')
      if self.dropAcks and p.message.type=='task_ack' then self.droppedAcks=self.droppedAcks+1
      else
        local ok,why=target:receive(p.message.sender,p.message,p.protocol)
        if not ok then self.rejections=self.rejections or {}; self.rejections[#self.rejections+1]=p.message.type..': '..tostring(why) end
      end
    end
  end
  function f:step()
    self.ce.now=self.ce.now+1; self.we.now=self.ce.now; self.other.we.now=self.ce.now
    assert(self.c:tick()); self:pumpAll(self.ce); assert(self.c:workStep()); self.h:smelt()
    local concurrent=0
    for _,worker in ipairs({self,self.other}) do
      assert(worker.w:tick()); assert(worker.w:workStep()); self:pumpAll(worker.we)
      local t=worker.w.state.currentTask
      if t and t.type=='CRAFT' and t.phase~='completed' and t.phase~='blocked' then concurrent=concurrent+1 end
    end
    self.maxConcurrent=math.max(self.maxConcurrent,concurrent); self:pumpAll(self.ce)
  end
  function f:request(n)
    for _,worker in ipairs({self,self.other}) do assert(worker.w:tick()); self:pumpAll(worker.we) end; self:pumpAll(self.ce)
    local ok,id=self.c:command('request minecraft:stone_bricks '..(n or 32)); assert(ok,id); self.id=id
  end
  function f:finish(limit)
    for _=1,limit or 400 do
      self:step()
      if self.c.state.automation.requests[self.id].status=='completed' and not self.w.state.currentTask and not self.other.w.state.currentTask then return end
    end
    local r=self.c.state.automation.requests[self.id]
    local errors={tostring(r.error)}
    for _,j in pairs(self.c.state.automation.jobs) do errors[#errors+1]=j.id..' '..j.status..' '..tostring(j.error or j.stockError) end
    error('parallel factory did not finish: '..table.concat(errors,'; '))
  end
  return f
end

test('two private Crafty workers share one exact finite operation and release all claims',function()
  local f=parallelFixture(); f:request(31); f:finish()
  eq(f.h:count(mc('stone_bricks')),32); eq(f.h:count(mc('stone')),8)
  eq(f.h.crafts+f.other.h.crafts,8); eq(f.maxConcurrent,2)
  assert(f.h.crafts>0 and f.other.h.crafts>0)
  for _,lease in pairs(f.c.state.inventoryLedger.leases) do eq(lease.status,'released') end
  for _,lease in pairs(f.c.state.capacityLedger.leases) do eq(lease.status,'released') end
  for _,name in ipairs({'buffer','buffer2','input','input2','output','output2'}) do eq(next(f.h.inventories[name]),nil) end
end)

test('parallel factory keeps independent work moving while one private station is disconnected',function()
  local f=parallelFixture(); f.other.h.offline='input2'; f:request(32)
  for _=1,160 do f:step() end
  assert(f.h.crafts>0); eq(f.other.h.crafts,0)
  local blocked=f.other.w.state.currentTask; assert(blocked and blocked.phase=='blocked')
  local before=f.h:count(mc('stone_bricks')); assert(before>0 and before<32)
  f.other.h.offline=nil; assert(f.c:command('resume '..blocked.id)); f:pumpAll(f.ce); f:finish()
  eq(f.h:count(mc('stone_bricks')),32); eq(f.h.crafts+f.other.h.crafts,8)
end)

test('parallel production holds output capacity before touching ingredients',function()
  local f=parallelFixture()
  for i=2,27 do f.h.inventories.store[i]={name=mc('dirt'),count=64} end
  f:request(16); for _=1,30 do f:step() end
  eq(f.h:count(mc('stone')),40); eq(f.h.crafts+f.other.h.crafts,0)
  eq(next(f.h.inventories.buffer),nil); eq(next(f.h.inventories.buffer2),nil)
  for i=10,27 do f.h.inventories.store[i]=nil end
  f:finish(); eq(f.h:count(mc('stone_bricks')),16)
end)

test('parallel factory reconciles interrupted staging craft and collection across runtime reboots',function()
  local f=parallelFixture(); f:request(24)
  local staged=false
  f.h.afterTransfer=function(_,target)
    if target=='buffer' and not staged then staged=true; f.ce.fs.fault.open='/autobuilder/data/controller.state.tmp' end
  end
  assert(not pcall(function() for _=1,80 do f:step() end end)); assert(staged)
  f.ce.fs.fault.open=nil; f.ce.packets={}; f.c=Runtime.new(f.cc,f.ce)
  local crafted=false
  f.h.afterCraft=function()
    if not crafted then crafted=true; f.we.fs.fault.open='/autobuilder/data/worker.state.tmp' end
  end
  assert(not pcall(function() for _=1,100 do f:step() end end)); assert(crafted)
  f.we.fs.fault.open=nil; f.we.packets={}; f.w=Runtime.new(f.wc,f.we)
  local collected=false
  f.h.afterTransfer=function(source,target)
    if source=='buffer' and target=='store' and not collected then collected=true; f.ce.fs.fault.open='/autobuilder/data/controller.state.tmp' end
  end
  assert(not pcall(function() for _=1,120 do f:step() end end)); assert(collected)
  f.ce.fs.fault.open=nil; f.ce.packets={}; f.c=Runtime.new(f.cc,f.ce)
  f.dropAcks=true; for _=1,30 do f:step() end; assert(f.droppedAcks>0)
  f.dropAcks=false; f.w=Runtime.new(f.wc,f.we); f.other.w=Runtime.new(f.other.wc,f.other.we)
  f:finish(); eq(f.h:count(mc('stone_bricks')),24); eq(f.h:count(mc('stone')),16)
  eq(f.h.crafts+f.other.h.crafts,6)
end)

test('pending private staging lets an older shared furnace owner finish its physical work',function()
  local f=parallelFixture()
  f.h.inventories.store[2]={name=mc('cobblestone'),count=1}; f.h.inventories.store[3]={name=mc('coal'),count=1}
  local j=f.c.automation.queue:submit('SMELT',{item=mc('stone'),quantity=1,batches=1,furnaceLane='furnace'},{})
  j.status='running'; f.c:save()
  f:request(16); f:finish(); eq(j.status,'completed'); eq(f.h:count(mc('stone_bricks')),16)
end)

test('parallel factory reconciles one-item physical transfers without overclaiming output',function()
  local f=parallelFixture()
  for _,env in ipairs({f.ce,f.other.we}) do
    local call=env.peripheral.call
    env.peripheral.call=function(name,method,...)
      if method=='pushItems' then local target,slot,n,toSlot=...; return call(name,method,target,slot,math.min(n,1),toSlot) end
      return call(name,method,...)
    end
  end
  f:request(16); f:finish(800); eq(f.h:count(mc('stone_bricks')),16); eq(f.h:count(mc('stone')),24)
  eq(f.h.crafts+f.other.h.crafts,4); eq(f.maxConcurrent,2)
end)

test('two private batches cannot spend the same short ingredient stock',function()
  local f=parallelFixture(); f.h.inventories.store[1].count=8
  local jobs={}
  for _,station in ipairs(f.cc.craftingStations) do
    jobs[#jobs+1]=f.c.automation.queue:submit('CRAFT',{item=mc('stone_bricks'),quantity=8,batches=2,
      preferredWorker=station.workerId,privateStation=U.copy(station),privateReady=false,
      stockInputs={[mc('stone')]=8},stockOutputs={[mc('stone_bricks')]=8}},{})
  end
  for _=1,160 do f:step() end
  eq(f.h.crafts+f.other.h.crafts,2); eq(f.h:count(mc('stone_bricks')),8); eq(f.h:count(mc('stone')),0)
  local completed=0; for _,j in ipairs(jobs) do if j.status=='completed' then completed=completed+1 end end
  eq(completed,1)
  f.h.inventories.store[20]={name=mc('stone'),count=8}
  for _=1,160 do f:step() end
  for _,j in ipairs(jobs) do eq(j.status,'completed') end
  eq(f.h.crafts+f.other.h.crafts,4); eq(f.h:count(mc('stone_bricks')),16)
end)

test('factory status reports measured collection rates and station ownership without moving items',function()
  local f=parallelFixture(); f:request(16); f:finish()
  for _,j in pairs(f.c.state.automation.jobs) do if j.privateStation.id=='west' then j.factoryStartedAt=nil; j.factoryCompletedAt=nil end end
  local before=f.h.transfers; local ok,text=f.c:command('factory')
  assert(ok,text); eq(f.c.state.view,'factory')
  assert(text:find('stations=2',1,true)); assert(text:find('delivered=16',1,true)); assert(text:find('/s',1,true))
  assert(text:find('west',1,true) and text:find('east',1,true)); eq(f.h.transfers,before)
  assert(f.c.state.factoryLines[2]:find('collected=8',1,true),'legacy completed jobs disappeared from station totals')
end)


test('reboot refuses to reclassify an owned private station as shared inventory',function()
  local f=parallelFixture(); local original=U.copy(f.cc); f.cc.craftingStations={original.craftingStations[1]}
  f.c=Runtime.new(f.cc,f.ce); f:request(16)
  local staged
  for _=1,30 do
    assert(f.c:tick()); assert(f.c:workStep())
    for _,j in pairs(f.c.state.automation.jobs) do if j.privateReady then staged=j end end
    if staged then break end
  end
  assert(staged,'first private batch never staged'); eq(f.h.inventories.buffer[1].count,8)
  local before=f.h.transfers
  for _,field in ipairs({'storage','furnace','supply','legacy','station'}) do
    local changed=U.copy(original); changed.craftingStations={U.copy(original.craftingStations[2])}
    if field=='storage' then changed.storageInventories={'store','buffer'}
    elseif field=='furnace' then changed.furnaces={'buffer'}
    elseif field=='supply' then changed.supply.inventory='buffer'
    elseif field=='legacy' then changed.craftingStation.input='buffer'
    else changed.craftingStations[1].buffer='buffer' end
    local ok,why=pcall(Runtime.new,require('tests.loaded_config').load(changed),f.ce)
    assert(not ok and tostring(why):find('owned private',1,true),'accepted conflicting '..field..': '..tostring(why))
    eq(f.h.transfers,before); eq(f.h.inventories.buffer[1].count,8)
  end
  f.cc=original; f.c=Runtime.new(f.cc,f.ce); f:finish()
  eq(f.h:count(mc('stone_bricks')),16); eq(f.h.crafts+f.other.h.crafts,4)
end)

test('private batch checkpoint cannot fall back to duplicate legacy work after a crash',function()
  local f=parallelFixture(); f:request(16)
  local submit=f.c.automation.queue.submit; local crashed=false
  f.c.automation.queue.submit=function(q,...)
    local job=submit(q,...)
    if job.privateStation then crashed=true; error('power loss after private batch checkpoint') end
    return job
  end
  assert(not pcall(function() for _=1,20 do f:step() end end)); assert(crashed)
  local stations=U.copy(f.cc.craftingStations); f.cc.craftingStations={}; f.ce.packets={}
  f.c=Runtime.new(f.cc,f.ce)
  eq(f.c.state.automation.requests[f.id].privateCraft,true)
  -- Older checkpoints may predate the marker fix: saved ownership still routes work.
  f.c.state.automation.requests[f.id].privateCraft=nil; f.c:save(); f.c=Runtime.new(f.cc,f.ce)
  for _=1,100 do f:step() end
  local batches=0
  for _,j in pairs(f.c.state.automation.jobs) do
    assert(j.privateStation,'duplicate legacy operation appeared after private batch checkpoint')
    batches=batches+j.batches
  end
  eq(batches,2); eq(f.h:count(mc('stone_bricks')),8)
  f.cc.craftingStations=stations; f.c=Runtime.new(f.cc,f.ce); f:finish()
  eq(f.h:count(mc('stone_bricks')),16); eq(f.h.crafts+f.other.h.crafts,4)
end)
