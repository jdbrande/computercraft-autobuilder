local U=require('autobuilder.core.util')
local function fixture()
 local f=require('tests.managed_logistics_support').new();f:boot();f.events={}
 local w=f.app.state.workers['12'];w.telemetry.status='blocked';w.telemetry.task='mine:7:1';w.telemetry.capabilities.inventoryRecoveryV1=true
 f.app.state.jobs['mine:7:1']={id='mine:7:1',workerId=12,status='blocked',type='MINE'}
 local courier=f.app.state.workers['13'];courier.telemetry.capabilities.inventoryRecoveryV1=true;courier.telemetry.depot={x=4,y=1,z=0}
 local network={send=function(_,to,kind,p) f.events[#f.events+1]={to=to,kind=kind,p=U.copy(p)};return true end}
 f.recovery=require('autobuilder.core.inventory_recovery_service').new(f.app,f.config,f.e,f.queue,f.production,network,function() return f.now end)
 function f:status(r,phase,sequence,inventory,transfer,moved)
  return {jobId=r.id,position=U.copy(r.position),originalTask=r.originalTask,phase=phase,sequence=sequence,moved=moved or 0,inventory=U.copy(inventory),transfer=U.copy(transfer)}
 end
 return f
end
test('inventory recovery creates capacity-owned courier jobs and preserves original ownership offline',function()
 local f=fixture();local r=f.recovery:request(12);f.recovery:tick();eq(f.events[#f.events].kind,'task_inventory_freeze')
 local inventory={[1]={name='minecraft:stone',count=5},[16]={name='minecraft:diamond_pickaxe',count=1,nbt='tagged'}}
 assert(f.recovery:handle(12,f:status(r,'frozen',0,inventory)));f.recovery:tick()
 local j=assert(f.queue.state.jobs[r.jobId]);eq(j.type,'RECOVER_CARGO');eq(j.quantity,5);eq(j.preferredWorker,13)
 eq(f.app.state.capacityLedger.leases[r.id].status,'held');assert(require('autobuilder.core.workflows').workerBusy(f.app.state,12))
 f.app.state.workers['12'].online=false;f.recovery:tick();eq(f.queue.state.jobs[r.jobId].id,j.id)
 eq(f.app.state.jobs['mine:7:1'].workerId,12);eq(f.recovery:request(12).id,r.id)
 local wrong=f:status(r,'sent',1,{},nil,5);assert(not f.recovery:handle(99,wrong));assert(not f.recovery:handle(12,wrong))
end)
test('inventory recovery rejects unsettled donor changes and waits for destination space',function()
 local f=fixture();local r=f.recovery:request(12);local inv={[1]={name='minecraft:stone',count=5}}
 assert(f.recovery:handle(12,f:status(r,'frozen',0,inv)))
 inv[1].count=4;assert(not f.recovery:handle(12,f:status(r,'frozen',0,inv)))
 f.inventories.b[1]={name='minecraft:dirt',count=1};f.recovery:tick();eq(r.jobId,nil);assert(r.error)
 f.inventories.b={};f.recovery:tick();assert(r.jobId)
end)
test('inventory recovery reconciles partial custody and keeps donor quarantined after completion',function()
 local f=fixture();local r=f.recovery:request(12);local inv={[1]={name='minecraft:stone',count=5}}
 assert(f.recovery:handle(12,f:status(r,'frozen',0,inv)));f.recovery:tick();local j=f.queue.state.jobs[r.jobId]
 eq(j.requiredCapability,'inventoryRecoveryV1');j.workerId=13;j.status='running'
 local function progress(stage,capacity,picked,delivered,phase)
  return f.queue:progress(13,{jobId=j.id,phase=phase or 'work',progress=delivered,recoveryReceipt={sequence=j.recoverySequence,stage=stage,capacity=capacity,pickedUp=picked,delivered=delivered}})
 end
 assert(progress('receiving',5,0,0));f.recovery:tick();local grant=U.copy(r.grant);assert(grant)
 inv[1].count=3;assert(f.recovery:handle(12,f:status(r,'sent',1,inv,grant,2)));f.recovery:tick()
 eq(f.events[#f.events].kind,'task_inventory_received');eq(f.events[#f.events].p.moved,2)
 assert(not progress('home',5,6,0));assert(progress('home',5,2,0));f.recovery:tick();eq(f.events[#f.events].kind,'task_inventory_ack')
 assert(f.recovery:handle(12,f:status(r,'frozen',1,inv,grant,2)))
 assert(progress('home',5,2,2,'completed'));eq(j.status,'collecting');f.recovery:tick();assert(r.error);eq(j.status,'collecting')
 f.inventories.b[1]={name='minecraft:stone',count=2};f.recovery:tick();eq(j.status,'completed');eq(r.jobId,nil)
 assert(require('autobuilder.core.workflows').workerBusy(f.app.state,13),'settled gap must retain the courier')
 f.recovery:tick();j=f.queue.state.jobs[r.jobId];eq(j.quantity,3);eq(j.recoverySequence,2);j.workerId=13
 assert(progress('receiving',3,0,0));f.recovery:tick();grant=U.copy(r.grant)
 inv={};assert(f.recovery:handle(12,f:status(r,'sent',2,inv,grant,3)));assert(progress('home',3,3,0));f.recovery:tick()
 assert(f.recovery:handle(12,f:status(r,'frozen',2,inv,grant,3)));f.inventories.b[1].count=5
 assert(progress('home',3,3,3,'completed'));f.recovery:tick();f.recovery:tick();for _=1,5 do f.recovery:step() end;eq(r.status,'completed')
 f.app.state.jobs['mine:7:1'].status='completed';assert(require('autobuilder.core.workflows').workerBusy(f.app.state,12))
 eq(f.app.state.capacityLedger.leases[r.id].status,'released')
end)
test('recovery collects only plain stock and preserves tagged same-name cargo across transfer reboot',function()
 local f=fixture();local r=f.recovery:request(12)
 local items={[1]={name='minecraft:stone',count=5},[2]={name='minecraft:stone',count=1,nbt='named'}}
 assert(f.recovery:handle(12,f:status(r,'frozen',0,items)));f.recovery:tick()
 local job=f.queue.state.jobs[r.jobId];job.status='completed';r.jobId=nil;r.inventory={};r.sequence=1
 r.deposited=U.copy(items);r.donor={phase='frozen',sequence=1};f.inventories.b=U.copy(items)
 f.recovery:tick();eq(r.status,'collecting')
 f.crashTransfer=true;assert(not pcall(f.recovery.step,f.recovery));assert(r.collection['minecraft:stone'].intent)
 f.crashed=false;f:boot(true)
 local network={send=function() return true end}
 f.recovery=require('autobuilder.core.inventory_recovery_service').new(f.app,f.config,f.e,f.queue,f.production,network,function() return f.now end)
 for _=1,10 do f.recovery:step() end
 r=f.queue.state.inventoryRecoveries[r.id];eq(r.status,'completed');eq(f.transfers,1)
 eq(f.inventories.base[2].count,29);eq(f.inventories.b[1],nil);eq(f.inventories.b[2].nbt,'named');eq(f.inventories.b[2].count,1)
end)
test('recovery reservation rollback retains live state references and can retry without orphan claims',function()
 local f=fixture();local r=f.recovery:request(12);assert(f.recovery:handle(12,f:status(r,'frozen',0,{[1]={name='minecraft:stone',count=5}})))
 local save=f.app.save;f.app.save=function(self) if r.buffer then return false,'disk full' end;return save(self) end
 f.recovery:tick();eq(r.buffer,nil);eq(r.jobId,nil);eq(f.app.state.capacityLedger.leases[r.id],nil)
 f.app.save=save;f.recovery:tick();assert(r.jobId);assert(f.queue.state.inventoryRecoveries[r.id]==r)
end)

test('settled recovery courier can refuel for its next trip without releasing its exclusive ownership',function()
 local f=fixture();local r=f.recovery:request(12);local inv={[1]={name='minecraft:stone',count=5},[2]={name='minecraft:dirt',count=1}}
 assert(f.recovery:handle(12,f:status(r,'frozen',0,inv)));f.recovery:tick()
 local j=f.queue.state.jobs[r.jobId];local w=f.app.state.workers['13'];local t=w.telemetry
 t.position=U.copy(t.depot);t.position.known=true;t.fuel=108;t.capabilities.fuelV1=true;t.capabilities.telemetry=true
 f.config.fuel.enabled=true;f.config.fuel.low=100;f.config.fuel.target=300
 f.config.fuel.stations={{id='home',workerId=13,inventory='fuel',position=U.copy(t.depot),side='front',targetItems=16}}
 f.inventories.fuel={[1]={name='minecraft:coal',count=16}}
 f.queue=require('autobuilder.core.workflows').new(f.app.state,function() return f.app:save() end,function() return f.now end,7,nil,f.config)
 eq(f.queue:assign(f.app.state.workers),nil);assert(j.admissionError or j.coverageError)
 local fuel=require('autobuilder.core.fuel_service').new(f.app,f.config,f.e,f.queue,f.production,function() return f.now end)
 fuel:tick();local refuel=f.queue.state.jobs[f.app.state.fuel.stations.home.refuel];assert(refuel,'no recovery refuel task')
 eq(refuel.type,'REFUEL');eq(refuel.fuelTarget,300);eq(f.queue:assign(f.app.state.workers).id,refuel.id)
 assert(require('autobuilder.core.workflows').workerBusy(f.app.state,13));eq(r.courier,13);eq(r.jobId,j.id)
 r.grant={sequence=1};eq(require('autobuilder.core.workflows').recoveryFuelJob(f.app.state,13),nil)
 assert(require('autobuilder.core.workflows').workerBusy(f.app.state,13,refuel.id));r.grant=nil
 refuel.status='completed';t.fuel=300;f.app:save();fuel:tick()
 eq(f.queue:assign(f.app.state.workers).id,j.id)
end)
test('blocked recovery collection yields to unrelated controller services and reports child failure',function()
 local f=fixture();local r=f.recovery:request(12);local items={[1]={name='minecraft:stone',count=5}}
 assert(f.recovery:handle(12,f:status(r,'frozen',0,items)));f.recovery:tick()
 local j=f.queue.state.jobs[r.jobId];j.error='Movement obstructed: minecraft:bedrock'
 local description=f.recovery:describe();assert(description:find(j.id,1,true));assert(description:find('minecraft:bedrock',1,true))
 j.status='completed';r.jobId=nil;r.inventory={};r.sequence=1;r.deposited=U.copy(items);r.donor={phase='frozen',sequence=1};f.inventories.b=U.copy(items)
 f.recovery:tick();eq(r.status,'collecting')
 f.inventories.base={[1]={name='minecraft:dirt',count=64},[2]={name='minecraft:dirt',count=64},[3]={name='minecraft:dirt',count=64}}
 for _=1,5 do eq(f.recovery:step(),false) end;assert(r.error);eq(f.transfers,0)
 f.inventories.base={};for _=1,5 do f.recovery:step() end;eq(r.status,'completed');eq(f.inventories.base[1].count,5)
end)
