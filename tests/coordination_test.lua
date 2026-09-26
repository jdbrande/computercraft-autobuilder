local U=require('autobuilder.core.util')
local S=require('tests.support')
local Jobs=require('autobuilder.core.jobs')
local Workflows=require('autobuilder.core.workflows')
local function mc(item) return 'minecraft:'..item end
local function worker(id)
  return {id=id,online=true,telemetry={status='idle',capabilities={mining=true,building=true,crafting=true,courier=true,logging=true,farming=true},
    miningArea={min={x=id*10,y=0,z=0},max={x=id*10+8,y=8,z=8}}}}
end
local function queues()
  local state={}; local save=function() return true end
  return state,Jobs.new(state,save,function() return 100 end,7),Workflows.new(state,save,function() return 100 end,7),{['12']=worker(12),['13']=worker(13)}
end
local block={x=0,y=64,z=0,name=mc('stone'),state={}}

test('both task queues exclude durable owners from the other queue before heartbeat updates',function()
  for _,miningFirst in ipairs({true,false}) do
    local state,mine,generic,workers=queues(); workers['13']=nil
    local a=mine:submit(mc('raw_iron'),4,0); local b=generic:submit('VERIFY',{blocks={block}},{})
    if miningFirst then eq(mine:assign(workers).id,a.id); eq(generic:assign(workers),nil)
    else eq(generic:assign(workers).id,b.id); eq(mine:assign(workers),nil) end
    assert(not (a.workerId and b.workerId),'same stale-idle worker acquired two durable tasks')
  end
end)

test('generic pending assignments resend fairly without starving another assigned worker',function()
  local _,_,generic,workers=queues()
  local a=generic:submit('TRANSPORT',{item=mc('stone'),quantity=1},{})
  local b=generic:submit('TRANSPORT',{item=mc('dirt'),quantity=1},{})
  eq(generic:assign(workers).id,a.id); eq(generic:assign(workers).id,b.id)
  local first=generic:assign(workers); local second=generic:assign(workers)
  assert(first.id~=second.id,'one pending assignment starved another')
end)

test('both ownership recovery paths reject a worker already held by the other queue',function()
  for _,miningFirst in ipairs({true,false}) do
    local _,mine,generic,workers=queues(); workers['13']=nil
    local a=mine:submit(mc('raw_iron'),4,0); local b=generic:submit('VERIFY',{blocks={block}},{})
    if miningFirst then
      mine:assign(workers); workers['12'].telemetry.task=b.id
      assert(not generic:recoverOwner(12,{jobId=b.id},workers)); eq(b.workerId,nil)
    else
      generic:assign(workers); workers['12'].telemetry.task=a.id
      assert(not mine:recoverOwner(12,{jobId=a.id,assignedQuantity=4},workers)); eq(a.workerId,nil)
    end
  end
end)

local function environment(id,h)
  local e={fs=S.fs(),textutils=S.codec(),now=100,packets={}}
  e.os={getComputerID=function() return id end,epoch=function() return e.now*1000 end}
  e.rednet={isOpen=function() return true end,open=function() end,send=function(to,message,protocol)
    e.packets[#e.packets+1]={to=to,message=U.copy(message),protocol=protocol}; return true
  end}
  e.peripheral={getNames=function() return {'right','store','stage','furnace'} end,
    getType=function(name) return name=='right' and 'modem' or 'inventory' end,
    call=function(name,method,...)
      if name=='right' then return true end
      local inv=assert(h.inventories[name],name)
      if method=='list' then return U.copy(inv) end
      assert(method=='pushItems'); local target,slot,limit,toSlot=...; local dst=h.inventories[target]
      local item=inv[slot]; if not item then return 0 end
      toSlot=toSlot or 1
      if dst[toSlot] and dst[toSlot].name~=item.name then return 0 end
      local n=math.min(limit,item.count,64-(dst[toSlot] and dst[toSlot].count or 0))
      dst[toSlot]={name=item.name,count=(dst[toSlot] and dst[toSlot].count or 0)+n}
      item.count=item.count-n; if item.count==0 then inv[slot]=nil end
      h.transfers=h.transfers+1
      if h.crash then h.crash=false; error('lost peripheral response after transfer') end
      return n
    end}
  e.turtle=S.turtle(); e.gps={locate=function() return 0,64,0 end}
  return e
end
local function runtime()
  local h={inventories={store={[1]={name=mc('stone'),count=4},[2]={name=mc('cobblestone'),count=8},[3]={name=mc('coal'),count=4}},stage={},furnace={}},transfers=0}
  local ce=environment(7,h); local we=environment(12,h)
  local C=require('autobuilder.config'); local R=require('autobuilder.core.runtime')
  local cc=C.load({role='controller',storageInventories={'store'},furnaces={'furnace'},turtleFuelReserveItems={},
    supply={inventory='stage'},heartbeatInterval=1,registrationInterval=3,workerTimeout=8})
  local wc=C.load({role='worker',controllerId=7,initialPosition={x=0,y=64,z=0,heading='north'},depot={x=0,y=64,z=0},
    mining={enabled=true,entry={x=1,y=64,z=0},bounds={min={x=1,y=64,z=0},max={x=8,y=70,z=8}}},
    automation={building=true,crafting=true,courier=true,logging=true,farming=true},
    heartbeatInterval=1,registrationInterval=3,workerTimeout=8})
  local f={h=h,ce=ce,we=we,c=R.new(cc,ce),w=R.new(wc,we)}
  function f:pump(from,to)
    local packets=from.packets; from.packets={}
    for _,p in ipairs(packets) do assert(to:receive(p.message.sender,p.message,p.protocol)) end
  end
  f.w:tick(); f:pump(we,f.c); f:pump(ce,f.w)
  function f:smelt()
    return self.c.automation.queue:submit('SMELT',{item=mc('stone'),quantity=8,batches=8,furnaceLane='furnace'},{})
  end
  return f
end

test('real runtime tick sends one assignment to a stale-idle dual-capability worker',function()
  local f=runtime(); local ok,id=f.c:command('mine minecraft:raw_iron 4'); assert(ok,id)
  local build=f.c.automation.queue:submit('VERIFY',{blocks={block}},{})
  assert(f.c:tick()); local assignments=0
  for _,p in ipairs(f.ce.packets) do if p.message.type=='mine_assign' or p.message.type=='task_assign' then assignments=assignments+1 end end
  eq(assignments,1); eq(f.c.state.jobs[id].workerId,12); eq(build.workerId,nil)
  f:pump(f.ce,f.w); eq(f.w.state.currentTask.id,id)
end)

test('queued factory operations hold manual mining and renewable courier assignments',function()
  local f=runtime(); local factory=f:smelt(); local ok,id=f.c:command('mine minecraft:raw_iron 4'); assert(ok,id)
  local queue=f.c.automation.queue
  for _,kind in ipairs({'TRANSPORT','HARVEST','FARM'}) do queue:submit(kind,{item=mc('dirt'),quantity=1},{}) end
  f.c:tick(); eq(f.c.state.jobs[id].workerId,nil)
  for _,j in pairs(queue.state.jobs) do if j~=factory then eq(j.workerId,nil) end end
  factory.status='completed'; f.ce.now=f.ce.now+2; f.c:tick()
  eq(f.c.state.jobs[id].workerId,12)
end)

test('factory waits for a prior courier and resumes after its physical completion',function()
  local f=runtime(); local queue=f.c.automation.queue
  local courier=queue:submit('TRANSPORT',{item=mc('dirt'),quantity=1},{})
  eq(queue:assign(f.c.state.workers).id,courier.id); f:smelt()
  f.c:workStep(); eq(f.h.transfers,0)
  assert(queue:progress(12,{jobId=courier.id,phase='completed',progress=1}))
  f.c:workStep(); eq(f.h.transfers,1)
end)

test('factory waits for outstanding staged supply and permits release before starting',function()
  local f=runtime(); local supply=require('autobuilder.storage.supply').new(f.c.state.automation,f.c.config,f.ce,function() return f.c:save() end)
  eq(supply:offer('batch:1',12,mc('stone'),1),1)
  f:smelt(); local before=f.h.transfers
  f.c:workStep(); eq(f.h.transfers,before)
  f.h.inventories.stage={}; assert(supply:release('batch:1'))
  f.c:workStep(); eq(f.h.transfers,before+1)
end)

test('pending production intent prevents fresh supply transfers while construction can stay active',function()
  local f=runtime(); local smelt=f:smelt(); f.h.crash=true; f.c:workStep()
  assert(smelt.production.intent)
  local build=f.c.automation.queue:submit('BUILD',{blocks={block}},{})
  build.workerId=12; build.status='blocked'; build.missingItem=mc('stone'); build.missingCount=1; build.supplyId=build.id..':supply:1'
  local before=f.h.transfers; f.c:tick(); eq(f.h.transfers,before); eq(f.c.state.automation.supply,nil)
  eq(build.workerId,12)
end)

test('factory waits for active manual mining but does not block acquisition-only requests',function()
  local f=runtime(); local ok,id=f.c:command('mine minecraft:raw_iron 4'); assert(ok,id)
  f.c.mining:tick(); eq(f.c.state.jobs[id].workerId,12)
  f:smelt(); f.c:workStep(); eq(f.h.transfers,0)
  local g=runtime(); local ok2,request=g.c:command('request minecraft:iron_bars 16'); assert(ok2,request)
  g.c:tick(); g.ce.now=g.ce.now+2; g.c:tick()
  local acquired=false; for _,j in pairs(g.c.state.jobs) do if j.item==mc('raw_iron') and j.workerId==12 then acquired=true end end
  assert(acquired,'raw acquisition was blocked by a request with no queued factory operation')
end)

test('Crafty assignments wait for active storage workers while verification remains schedulable',function()
  local _,_,queue,workers=queues()
  local courier=queue:submit('TRANSPORT',{item=mc('dirt'),quantity=1},{})
  eq(queue:assign(workers).id,courier.id); courier.status='running'
  local craft=queue:submit('CRAFT',{item=mc('stone_bricks'),quantity=4,batches=1},{})
  local verify=queue:submit('VERIFY',{blocks={block}},{})
  eq(queue:assign(workers).id,verify.id); eq(craft.workerId,nil); eq(verify.workerId,13)
  courier.status='completed'; eq(queue:assign(workers).id,craft.id)
end)

test('existing supply grant resends without touching storage while factory waits',function()
  local f=runtime(); local queue=f.c.automation.queue
  local build=queue:submit('BUILD',{blocks={block}},{})
  build.workerId=12; build.status='blocked'; build.missingItem=mc('stone'); build.missingCount=1; build.supplyId=build.id..':supply:1'
  local supply=require('autobuilder.storage.supply').new(queue.state,f.c.config,f.ce,function() return f.c:save() end)
  eq(supply:offer(build.supplyId,12,mc('stone'),1),1); f:smelt()
  local before=f.h.transfers; f.ce.packets={}; f.c:tick(); eq(f.h.transfers,before)
  local grant=false; for _,p in ipairs(f.ce.packets) do if p.message.type=='task_supply' then eq(p.message.payload.supplyId,build.supplyId); grant=true end end
  assert(grant,'lost prior grant cannot drain outstanding staging')
end)

test('resume command cannot bypass factory storage ownership barrier',function()
  local f=runtime(); local queue=f.c.automation.queue
  local courier=queue:submit('TRANSPORT',{item=mc('dirt'),quantity=1},{})
  queue:assign(f.c.state.workers); courier.status='running'
  local smelt=f:smelt(); smelt.status='blocked'; smelt.error='prior failure'
  assert(f.c:command('resume '..smelt.id)); eq(f.h.transfers,0)
  f.c:workStep(); eq(f.h.transfers,0)
end)

test('empty failed supply claim is released so material production can acquire its inputs',function()
  local f=runtime(); local queue=f.c.automation.queue
  local build=queue:submit('BUILD',{blocks={block}},{})
  build.workerId=12; build.status='blocked'; build.missingItem=mc('stone_bricks'); build.missingCount=4; build.supplyId=build.id..':supply:1'
  f.c:tick(); eq(queue.state.supply,nil)
  local requested=false; for _,r in pairs(queue.state.requests) do if r.requirements[mc('stone_bricks')]==4 then requested=true end end
  assert(requested); eq(f.h.transfers,0)
end)

test('partially staged supply recovers before production queues a factory reservation',function()
  local f=runtime(); local queue=f.c.automation.queue
  local build=queue:submit('BUILD',{blocks={block}},{})
  build.workerId=12; build.status='blocked'; build.missingItem=mc('stone'); build.missingCount=1; build.supplyId=build.id..':supply:1'
  local supply=require('autobuilder.storage.supply').new(queue.state,f.c.config,f.ce,function() return f.c:save() end)
  f.h.crash=true; eq(supply:offer(build.supplyId,12,mc('stone'),1),nil); assert(queue.state.supply.intent)
  assert(f.c:command('request minecraft:stone 8')); f.c:tick()
  for _,j in pairs(queue.state.jobs) do assert(j.type~='SMELT','factory queued before prior supply recovery') end
  assert(queue.state.supply.offered); eq(queue.state.supply.amount,1)
  f.h.inventories.stage={}; assert(supply:release(build.supplyId)); f.ce.now=f.ce.now+2; f.c:tick()
  local queued=false; for _,j in pairs(queue.state.jobs) do if j.type=='SMELT' then queued=true end end
  assert(queued,'production did not proceed after prior supply release')
end)

test('preexisting farm can drain required seed supply before queued factory takes storage',function()
  local f=runtime(); local queue=f.c.automation.queue
  f.h.inventories.store[4]={name=mc('wheat_seeds'),count=1}
  local farm=queue:submit('FARM',{item=mc('wheat'),quantity=1},{})
  eq(queue:assign(f.c.state.workers).id,farm.id)
  farm.status='blocked'; farm.missingItem=mc('wheat_seeds'); farm.missingCount=1; farm.supplyId=farm.id..':supply:1'
  f:smelt(); f.c:tick()
  eq(f.h.inventories.stage[1] and f.h.inventories.stage[1].name,mc('wheat_seeds'))
  eq(f.h.transfers,1); f.c:workStep(); eq(f.h.transfers,1)
end)

test('queued factory prevents fresh construction supply before its first physical effect',function()
  local f=runtime(); local queue=f.c.automation.queue
  local build=queue:submit('BUILD',{blocks={block}},{})
  build.workerId=12; build.status='blocked'; build.missingItem=mc('stone'); build.missingCount=1; build.supplyId=build.id..':supply:1'
  f:smelt(); f.c:tick(); eq(f.h.transfers,0); eq(queue.state.supply,nil)
end)
