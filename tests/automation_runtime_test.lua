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
  local C=require('autobuilder.config')
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
