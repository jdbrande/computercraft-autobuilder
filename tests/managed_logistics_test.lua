local U=require('autobuilder.core.util')
local F=require('autobuilder.factory.factory')
local function fixture() return require('tests.managed_logistics_support').new() end
local item='minecraft:stone'

test('managed hauls stage only requested mixed stock and reserve final capacity before assignment',function()
  local f=fixture();local r=f.service:request(item,8,'base','site','one');f:step(20)
  local j=assert(f:jobs()[1]);eq(j.quantity,8);eq(j.logisticsReady,true)
  eq(F.count(f.inventories.base,item),16);eq(F.count(f.inventories.base,'minecraft:dirt'),7)
  eq(F.count(f.inventories.a,item),8);eq(F.count(f.inventories.site,item),0)
  local l=f.app.state.capacityLedger.leases[j.id];eq(l.status,'held');assert(l.nodes.a.exclusive and l.nodes.c.exclusive);assert(l.nodes.site)
  local v=f.production.ledger:view(item,f.app.mining.storage.counts);eq(v.transit,8)
  f:deliver(j);eq(j.status,'collecting');assert(require('autobuilder.core.workflows').workerBusy(f.app.state,j.workerId))
  f:step(20);eq(r.status,'completed');eq(F.count(f.inventories.site,item),8)
  eq(f.app.state.inventoryLedger.leases[j.id].status,'released');eq(l.status,'held') -- old returned reference is not authoritative
  eq(f.app.state.capacityLedger.leases[j.id].status,'released')
end)

test('two private haulers reserve disjoint buffers without double spending finite source stock',function()
  local f=fixture();f.service:request(item,24,'base','site','parallel');f:step(30)
  local jobs=f:jobs();eq(#jobs,2)
  assert(jobs[1].preferredWorker~=jobs[2].preferredWorker)
  assert(jobs[1].logistics.pickup.inventory~=jobs[2].logistics.pickup.inventory)
  assert(jobs[1].logistics.drop.inventory~=jobs[2].logistics.drop.inventory)
  eq(F.count(f.inventories.base,item),8)
  for _,j in ipairs(jobs) do f:deliver(j) end;f:step(30)
  jobs=f:jobs();eq(#jobs,3);f:deliver(jobs[3]);f:step(20)
  eq(F.count(f.inventories.base,item),0);eq(F.count(f.inventories.site,item),24)
end)

test('stage and collection power loss reconcile partial physical transfers exactly after restart',function()
  for _,when in ipairs({'stage','collect'}) do
    local f=fixture();f.partial=2;f.service:request(item,8,'base','site',when)
    if when=='collect' then f:step(30);f:deliver(f:jobs()[1]) end
    f.crashTransfer=true;for _=1,10 do pcall(f.step,f);if f.crashed then break end end;assert(f.crashed)
    f:boot(true);f:step(40)
    local j=f:jobs()[1];if when=='stage' then f:deliver(j);f:step(30) end
    eq(j.status,'completed');eq(F.count(f.inventories.site,item),8);eq(F.count(f.inventories.base,item),16)
    eq(f.production.ledger:view(item,f.app.mining.storage.counts).transit,0)
  end
end)

test('full disconnected destination and offline courier keep physical ownership until exact collection',function()
  local f=fixture();f.service:request(item,8,'base','site','offline');f:step(20)
  local j=f:jobs()[1];local owner=j.preferredWorker
  f.app.state.workers[tostring(owner)].online=false;f:step(10);eq(#f:jobs(),1)
  eq(f.app.state.capacityLedger.leases[j.id].status,'held')
  f:deliver(j);f.offline='site';f:step(10);eq(j.status,'blocked')
  eq(f.app.state.inventoryLedger.leases[j.id].status,'held');eq(F.count(f.inventories[j.logistics.drop.inventory],item),8)
  f.offline=nil;f:step(20);eq(j.status,'completed');eq(F.count(f.inventories.site,item),8)
end)

test('managed completion requires monotone bounded physical receipts and does not credit destination stock',function()
  local f=fixture();f.service:request(item,8,'base','site','receipts');f:step(20)
  local j=f:jobs()[1];j.workerId=j.preferredWorker;j.status='running'
  local function report(phase,picked,delivered,sequence)
    return f.queue:progress(j.workerId,{jobId=j.id,phase=phase,progress=delivered,
      transportReceipt={sequence=sequence,pickedUp=picked,delivered=delivered}})
  end
  assert(not report('completed',0,0,1),'empty completion accepted')
  assert(not report('work',9,0,1),'overdraw accepted')
  assert(not report('work',1,2,1),'delivery before pickup accepted')
  assert(report('work',4,0,1));assert(report('work',4,0,1))
  assert(not report('work',5,0,1),'changed duplicate receipt accepted')
  assert(not report('work',3,0,2),'regressed pickup accepted')
  assert(report('work',8,4,2));eq(f.production.ledger:view(item,f.app.mining.storage.counts).transit,8)
  assert(report('completed',8,8,3));eq(j.status,'collecting');eq(F.count(f.inventories.site,item),0)
end)

test('managed assignment protocol rejects malformed node contracts and only updated couriers are eligible',function()
  local f=fixture();f.service:request(item,8,'base','site','protocol');f:step(20)
  local j=f:jobs()[1];j.workerId=j.preferredWorker
  local P=require('autobuilder.core.task_messages');assert(P.validate('task_assign',{job=j}))
  local bad=U.copy(j);bad.logistics.drop.position.x=100
  assert(not P.validate('task_assign',{job=bad}),'destination does not match private drop')
  bad=U.copy(j);bad.logistics.source.inventory=bad.logistics.pickup.inventory
  assert(not P.validate('task_assign',{job=bad}),'private pickup aliases stock')
  assert(not P.validate('task_progress',{jobId=j.id,phase='work',progress=0,transportReceipt={sequence=-1,pickedUp=0,delivered=0}}))
  j.workerId=nil
  f.app.state.workers[tostring(j.preferredWorker)].telemetry.capabilities.logisticsV1=nil
  eq(f.queue:assign(f.app.state.workers),nil)
  f.app.state.workers[tostring(j.preferredWorker)].telemetry.capabilities.logisticsV1=true
  eq(f.queue:assign(f.app.state.workers).id,j.id)
end)

test('worker rejects changed managed assignments and retains exact completion receipt after acknowledgement',function()
  local f=fixture();f.service:request(item,8,'base','site','duplicates');f:step(20)
  local j=U.copy(f:jobs()[1]);j.workerId=j.preferredWorker
  local c=require('tests.loaded_config').load({role='worker',controllerId=7,automation={courier=true}})
  eq(c.capabilities.logisticsV1,true)
  local app={navigation={},state={id=j.workerId,position={x=j.source.x,y=j.source.y,z=j.source.z,known=true}}}
  function app:save() return true end
  local sent={};local network={send=function(_,_,kind,p) sent[#sent+1]={kind=kind,p=U.copy(p)};return true end}
  local ex=require('autobuilder.workers.executor').new(app,c,{},network,function() return 100 end)
  local seq=0
  local function control(kind,p) seq=seq+1;return ex:handle(7,{boot=1,sequence=seq,type=kind,payload=p}) end
  local function assign(job) return control('task_assign',{job=job}) end
  assert(assign(j));local changed=U.copy(j);changed.quantity=7
  assert(not assign(changed),'changed active quantity accepted')
  changed=U.copy(j);changed.logistics.source.inventory='other';assert(not assign(changed),'changed active endpoint accepted')
  local t=app.state.currentTask;t.phase='completed';t.progress=8;t.pickedUp=8;t.delivered=8;t.transportSequence=3
  ex:tick();eq(sent[#sent].p.transportReceipt.pickedUp,8)
  assert(control('task_ack',{jobId=j.id}));eq(app.state.currentTask,nil)
  assert(assign(j));eq(sent[#sent].p.transportReceipt.delivered,8)
end)

test('managed transport coverage includes registered stock containers beyond the courier stands',function()
  local f=fixture();f.service:request(item,8,'base','site','coverage');f:step(20)
  local j=U.copy(f:jobs()[1]);j.logistics.destination.position.x=200
  local C=require('autobuilder.core.chunks')
  local area=assert(C.area(j,{position={x=2,y=1,z=2,known=true}}))
  assert(C.contains(area,j.logistics.destination.position),'remote stock absent from loading contract')
end)

test('unclaimed hauls let older factory owners drain and held cargo blocks shared factory effects',function()
  local f=fixture();local factory=f.queue:submit('SMELT',{item='minecraft:stone',quantity=1},{})
  factory.workerId=99;factory.status='blocked'
  f.service:request(item,8,'base','site','barrier');f:step(4);eq(#f:jobs(),0);eq(f.transfers,0)
  factory.status='completed';f:step(20);local j=f:jobs()[1];assert(j.logisticsReady)
  local waiting=f.queue:submit('CRAFT',{item='minecraft:stone_bricks',quantity=4,batches=1},{})
  assert(not require('autobuilder.core.workflows').factoryCanRun(f.app.state,waiting))
  f:deliver(j);f:step(20);assert(require('autobuilder.core.workflows').factoryCanRun(f.app.state,waiting))
end)

test('capacity sized hauls never spend another destination reservation and recover atomic grant failure',function()
  local f=fixture();f.size=1;f.inventories.site[1]={name=item,count=62}
  f.service:request(item,8,'base','site','small');f:step(20)
  local j=f:jobs()[1];eq(j.quantity,2);assert(j.logisticsReady)
  f:deliver(j);f:step(20);eq(F.count(f.inventories.site,item),64);eq(F.count(f.inventories.base,item),22)
  local total=0;for _,lease in pairs(f.app.state.capacityLedger.leases) do if lease.status=='held' then total=total+1 end end;eq(total,0)
  f=fixture();f.service:request(item,8,'base','site','atomic');f:step() -- logical queue entry only
  local original=f.app.save;local once=true
  function f.app:save()
    if once and next(self.state.capacityLedger.leases) then once=false;return false,'disk full during grant' end
    return original(self)
  end
  f:step();eq(next(f.app.state.capacityLedger.leases),nil);eq(next(f.app.state.inventoryLedger.leases),nil);eq(f.transfers,0)
  f:step(20);assert(f:jobs()[1].logisticsReady);eq(F.count(f.inventories.base,item),16)
end)

test('held haul buffers block new shared consumers and fuel staging until the physical receipt settles',function()
  local f=fixture();f.service:request(item,8,'base','site','isolation');f:step(20)
  local Q=require('autobuilder.core.workflows')
  assert(Q.factoryPending(f.app.state),'legacy dispatch did not see held logistics stock')
  local legacy=f.queue:submit('TRANSPORT',{item=item,quantity=1,source={x=0,y=1,z=0},destination={x=30,y=1,z=0}},{})
  f.app.state.workers['14']={id=14,online=true,telemetry={status='idle',capabilities={courier=true}}}
  local offered=f.queue:assign(f.app.state.workers);assert(not offered or offered.id~=legacy.id)
end)

test('fuel fill cannot consume source stock while a managed haul owns staged inventory',function()
  local f=fixture();f.service:request(item,8,'base','site','fuel-isolation');f:step(20)
  f.config.fuel.enabled=true;f.inventories.fuel={}
  f.queue:submit('FUEL_STATION',{item=item,quantity=1,station={inventory='fuel'},stockInputs={[item]=1},stockOutputs={[item]=1}},{})
  f.production:syncClaims()
  local fuel=require('autobuilder.core.fuel_service').new(f.app,f.config,f.e,f.queue,f.production,function() return f.now end)
  local before=f.transfers;fuel:step();eq(f.transfers,before)
end)

test('automatic node targets subtract inbound ownership across restart and stop when stock is satisfied',function()
  local f=fixture();f.config.logistics.nodes[2].targets={[item]=16};f:step(25)
  local jobs=f:jobs();eq(#jobs,2)
  local requests=0;for _ in pairs(f.queue.state.hauls) do requests=requests+1 end;eq(requests,1)
  f:boot(true);f:step(15);eq(#f:jobs(),2)
  for _,j in ipairs(f:jobs()) do f:deliver(j) end;f:step(30)
  eq(F.count(f.inventories.site,item),16);eq(F.count(f.inventories.base,item),8);eq(#f:jobs(),2)
  eq(next(f.queue.state.requests),nil)
end)

test('automatic routing chooses nearest surplus and protects each source target',function()
  local f=fixture();f.config.logistics.nodes[1].targets={[item]=24};f.config.logistics.nodes[2].targets={[item]=8}
  f.config.storageInventories[3]='near';f.inventories.near={[1]={name=item,count=10}};f.inventories.nearBuffer={}
  f.config.logistics.nodes[3]={id='near',inventory='near',position={x=10,y=0,z=0},buffers={{inventory='nearBuffer',position={x=12,y=1,z=0}}},targets={[item]=2}}
  f:step(25);local j=assert(f:jobs()[1]);eq(j.logistics.source.id,'near');eq(j.quantity,8)
  eq(F.count(f.inventories.base,item),24);eq(F.count(f.inventories.near,item),2)
end)

test('automatic shortages enter production once and wait for its durable completion before hauling',function()
  local f=fixture();f.inventories.base[2]=nil;f.config.logistics.nodes[2].targets={[item]=8};f:step(5)
  local r;local count=0;for _,request in pairs(f.queue.state.requests) do r=request;count=count+1 end
  eq(count,1);eq(r.requirements[item],8);eq(#f:jobs(),0)
  f:boot(true);f:step(10);count=0;for _ in pairs(f.queue.state.requests) do count=count+1 end;eq(count,1)
  f.inventories.base[2]={name=item,count=8};f:step(10);eq(#f:jobs(),0)
  f.queue.state.requests[r.id].status='completed';f:step(20);eq(#f:jobs(),1)
  f:deliver(f:jobs()[1]);f:step(20);eq(F.count(f.inventories.site,item),8)
end)

test('courier registration order chooses its nearest private pickup instead of another parked worker stand',function()
  local f=fixture();f.app.state.workers['12'].online=false
  f.config.logistics.nodes[1].buffers[2].position={x=2,y=1,z=4}
  f.config.logistics.nodes[2].buffers[2].position={x=22,y=1,z=4}
  f.app.state.workers['13'].telemetry.position={x=2,y=1,z=4,known=true}
  f.service:request(item,16,'base','site','nearest');f:step(12)
  local first=f:jobs()[1];eq(first.preferredWorker,13);eq(first.logistics.pickup.inventory,'b')
  eq(first.logistics.drop.inventory,'d') -- keep matching independent station lanes
  f.app.state.workers['12'].online=true;f.app.state.workers['12'].telemetry.position={x=2,y=1,z=0,known=true}
  f:step(12);local second=f:jobs()[2];eq(second.logistics.pickup.inventory,'a');eq(second.logistics.drop.inventory,'c')
end)
