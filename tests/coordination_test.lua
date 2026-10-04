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
  e.turtle=S.turtle(); e.turtle.dig=function() error('unexpected digging in coordination fixture') end; e.gps={locate=function() return 0,64,0 end}
  return e
end
local function runtime()
  local h={inventories={store={[1]={name=mc('stone'),count=4},[2]={name=mc('cobblestone'),count=8},[3]={name=mc('coal'),count=4}},stage={},furnace={}},transfers=0}
  local ce=environment(7,h); local we=environment(12,h)
  local C=require('tests.loaded_config'); local R=require('autobuilder.core.runtime')
  local cc=C.load({role='controller',storageInventories={'store'},furnaces={'furnace'},turtleFuelReserveItems={},
    inventoryAreas={store={min={x=-10,y=64,z=0},max={x=-10,y=64,z=0}},stage={min={x=0,y=63,z=0},max={x=0,y=63,z=0}},furnace={min={x=-12,y=64,z=0},max={x=-12,y=64,z=0}}},
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

test('misconfigured registered supply waits without producing replacement stock',function()
  local f=runtime(); local queue=f.c.automation.queue
  f.c.config.supplyStations={{workerId=12,inventory='privateSupply',side='front',position={x=40,y=64,z=0,heading='north'}}}
  local build=queue:submit('BUILD',{blocks={block}},{})
  build.workerId=12; build.status='blocked'; build.missingItem=mc('stone'); build.missingCount=1; build.supplyId=build.id..':supply:1'
  f.c:tick()
  assert(build.supplyError:find('matching worker depot',1,true));eq(f.h.transfers,0);eq(queue.state.supply,nil)
  eq(next(queue.state.requests),nil)
end)

test('disconnected supply endpoint does not create repeated production requests',function()
  local f=runtime();local queue=f.c.automation.queue
  f.h.inventories.stage=nil
  local j=queue:submit('BUILD',{blocks={block}},{})
  j.workerId=12;j.status='blocked';j.missingItem=mc('stone');j.missingCount=1;j.supplyId=j.id..':supply:1'
  for _=1,4 do f.ce.now=f.ce.now+2;f.c:tick() end
  eq(next(queue.state.requests),nil);eq(f.h.transfers,0)
  f.h.inventories.stage={};f.ce.now=f.ce.now+2;f.c:tick()
  eq(f.h.inventories.stage[1].count,1);eq(f.h.transfers,1)
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

test('health gates both new assignment queues restores repaired workers and retains existing owners',function()
  for _,mining in ipairs({false,true}) do
    local state,mine,generic,workers=queues();workers['13']=nil
    local h=require('autobuilder.workers.health').observe({}, {status='modified',reason='changed file'})
    workers['12'].telemetry.health=h
    local j=mining and mine:submit(mc('raw_iron'),4,0) or generic:submit('VERIFY',{blocks={block}},{})
    local queue=mining and mine or generic;eq(queue:assign(workers),nil);eq(j.workerId,nil)
    h.software={status='verified',version='0.29.0'};h.movement=true;h.digging=true
    eq(queue:assign(workers).id,j.id);eq(j.workerId,12)
    h.software={status='modified',reason='changed file'};h.movement=false
    eq(queue:assign(workers).id,j.id);eq(j.workerId,12)
  end
end)

test('health admission is rechecked after yielding coverage without leaking new ownership',function()
  for _,mining in ipairs({false,true}) do
    local state,_,_,workers=queues();workers['13']=nil
    local h=require('autobuilder.workers.health').observe({}, {status='unmanaged'});h.movement=true;h.digging=true
    workers['12'].telemetry.health=h
    local chunks={reserve=function() h.software={status='modified',reason='changed while observing coverage'};return {status='disabled'} end}
    local q=mining and Jobs.new(state,function() return true end,function() return 1 end,7,nil,chunks) or Workflows.new(state,function() return true end,function() return 1 end,7,chunks)
    local j=mining and q:submit(mc('raw_iron'),4,0) or q:submit('VERIFY',{blocks={block}})
    eq(q:assign(workers),nil);eq(j.workerId,nil)
  end
end)
test('builder supply follows project priority while an offered batch keeps its owner',function()
 local f=runtime();local a=f.c.state.automation;local q=f.c.automation.queue
 a.projects.low={name='low',priority=20};a.projects.high={name='high',priority=80}
 local low=q:submit('BUILD',{project='low',blocks={block}},{})
 local high=q:submit('BUILD',{project='high',blocks={{x=20,y=0,z=0,name=mc('stone'),state={}}}},{})
 for _,pair in ipairs({{low,12},{high,13}}) do local j=pair[1];j.workerId=pair[2];j.status='blocked';j.missingItem=mc('stone');j.missingCount=4;j.supplyId=j.id..':supply:1' end
 f.c:tick();eq(a.supply.owner,13);eq(a.supply.amount,4);eq(f.h.inventories.stage[1].count,4)
 local moved=f.h.transfers;a.projects.low.priority=100;f.ce.now=f.ce.now+2;f.c:tick()
 eq(a.supply.owner,13);eq(f.h.transfers,moved);eq(low.status,'blocked');assert(low.supplyError)
end)

test('traffic diagnostics retain first wait across retries restart and offline owners then clear on progress',function()
 local U=require('autobuilder.core.util');local W=require('autobuilder.core.workflows')
 local now,saves=10,0;local state={jobs={},workers={}}
 local c=require('tests.loaded_config').load({});local function save() saves=saves+1;return true end
 local q=W.new(state,save,function() return now end,7,nil,c)
 local j=q:submit('VERIFY',{blocks={{x=1,y=0,z=0,name='minecraft:stone',state={}}}});j.workerId=12;j.status='running'
 local from={x=0,y=1,z=0};local target={x=1,y=1,z=0}
 local workers={['13']={id=13,online=false,telemetry={position={known=true,x=1,y=1,z=0}}}}
 local events={};q.onTrafficChange=function(kind,job) events[#events+1]={kind=kind,wait=U.copy(job.trafficWait)} end
 eq(q:reserve(12,j.id,from,target,workers),false)
 eq(j.trafficWait.since,10);eq(j.trafficWait.blocker,13);eq(j.trafficWait.target.x,1);assert(j.trafficWait.remedy:find('13',1,true))
 local saved=saves;now=20;eq(q:reserve(12,j.id,from,target,workers),false);eq(saves,saved);eq(#events,1)
 state=U.copy(state);q=W.new(state,save,function() return now end,7,nil,c);j=q.state.jobs[j.id];q.onTrafficChange=function(kind) events[#events+1]={kind=kind} end
 now=41;eq(q:reserve(12,j.id,from,target,workers),false);eq(j.trafficWait.since,10);eq(j.trafficWait.prolonged,true);eq(#events,2)
 eq(workers['13'].online,false);eq(j.workerId,12)
 now=45;eq(q:reserve(12,j.id,from,target,workers),false);eq(#events,2)
 assert(q:reserve(12,j.id,from,{x=0,y=1,z=1},workers));eq(j.trafficWait,nil);eq(#events,3);eq(events[3].kind,'traffic_clear')
end)

test('failed traffic diagnostic checkpoints roll back and never emit success events',function()
 local qstate={jobs={},workers={}};local fail=false;local events=0
 local q=require('autobuilder.core.workflows').new(qstate,function() if fail then error('disk failed') end;return true end,function() return 10 end,7,nil,require('tests.loaded_config').load({}))
 local j=q:submit('VERIFY',{blocks={{x=1,y=0,z=0,name='minecraft:stone',state={}}}});j.workerId=12;j.status='running'
 q.onTrafficChange=function() events=events+1 end;fail=true
 local ok,why=pcall(q.reserve,q,12,j.id,{x=0,y=1,z=0},{x=1,y=1,z=0},{['13']={id=13,telemetry={position={known=true,x=1,y=1,z=0}}}})
 eq(ok,false);assert(tostring(why):find('disk failed',1,true));eq(j.trafficWait,nil);eq(events,0)
end)

test('blocked route diagnostics survive generic pending reports and restart until work resumes',function()
 local state,_,q,workers=queues();workers['13']=nil
 workers['12'].telemetry.position={known=true,x=10,y=2,z=0}
 local j=q:submit('VERIFY',{blocks={block}},{}) ;eq(q:assign(workers).workerId,12)
 local reason='movement reservation pending: no bounded traffic detour'
 assert(q:progress(12,{jobId=j.id,phase='blocked',progress=0,error=reason}))
 assert(q:progress(12,{jobId=j.id,phase='blocked',progress=0,error='movement reservation pending'}))
 eq(j.lastRouteFailure,reason)
 state=U.copy(state);state.id=7;state.workers=workers;q=Workflows.new(state,function() return true end,function() return 100 end,7);j=q.state.jobs[j.id]
 eq(j.lastRouteFailure,reason)
 local text=table.concat(require('autobuilder.ui.dashboard').lines(state,{},100,{},12),'\n')
 assert(text:find('Last route failure: '..reason,1,true));assert(text:find('passing bay',1,true));assert(text:find('Position 10,2,0',1,true))
 assert(q:progress(12,{jobId=j.id,phase='work',progress=0}));eq(j.lastRouteFailure,nil)
end)
