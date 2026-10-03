local U=require('autobuilder.core.util')
local F=require('autobuilder.factory.factory')
local function fixture()
  local f=require('tests.managed_logistics_support').new()
  local w=f.app.state.workers['12'];w.telemetry.depot={x=2,y=1,z=0};w.telemetry.capabilities.returnCargoV1=true
  w.telemetry.cargo={items={['minecraft:stone']=5,['minecraft:dirt']=3},limits={['minecraft:stone']=64,['minecraft:dirt']=64}}
  f.returns=assert(f.production.returns,'return service missing')
  function f:returnJob(r) return assert(self.queue.state.jobs[r.jobId]) end
  function f:deposit(j)
    self.inventories.a={[1]={name='minecraft:stone',count=5},[2]={name='minecraft:dirt',count=3}}
    j.workerId=12;j.status='running'
    assert(self.queue:progress(12,{jobId=j.id,phase='completed',progress=8,homeReceipt={sequence=2,deposited=U.copy(j.returning.items)}}))
  end
  return f
end

test('return controller reserves mixed cargo capacity and credits only central collection',function()
  local f=fixture();local r=f.returns:request(12);f:step(4);local j=f:returnJob(r)
  assert(j.returnReady and j.returning);eq(f.transfers,0);eq(f.production.ledger:view('minecraft:stone',{}).expected,5)
  eq(f.app.state.capacityLedger.leases[j.id].status,'held');assert(require('autobuilder.core.workflows').workerBusy(f.app.state,12))
  f:deposit(j);eq(j.status,'collecting');eq(f.production.ledger:view('minecraft:stone',{}).expected,5)
  f.partial=2;f:step(20);eq(j.status,'completed');eq(F.count(f.inventories.base,'minecraft:stone'),29);eq(F.count(f.inventories.base,'minecraft:dirt'),10)
  eq(next(f.inventories.a),nil);eq(f.app.state.inventoryLedger.leases[j.id].status,'released');eq(f.app.state.capacityLedger.leases[j.id].status,'released')
end)

test('return contract waits without claims for missing cargo capability full buffer or occupied worker',function()
  for _,reason in ipairs({'capability','full','busy'}) do
    local f=fixture();local w=f.app.state.workers['12']
    if reason=='capability' then w.telemetry.capabilities.returnCargoV1=nil
    elseif reason=='full' then f.inventories.a[1]={name='minecraft:dirt',count=1}
    else w.telemetry.task='other';w.telemetry.status='working' end
    local r=f.returns:request(12);f:step(4);eq(f.transfers,0)
    local j=r.jobId and f.queue.state.jobs[r.jobId];assert(not j or not j.returnReady)
    eq(next(f.app.state.capacityLedger.leases),nil);eq(next(f.app.state.inventoryLedger.leases),nil)
    assert(r.error or j and j.error)
  end
end)

test('home completion requires exact monotone per item receipts and rejects changed duplicates',function()
  local f=fixture();local r=f.returns:request(12);f:step(4);local j=f:returnJob(r);j.workerId=12;j.status='running'
  local function report(phase,n,seq)
    return f.queue:progress(12,{jobId=j.id,phase=phase,progress=n,homeReceipt={sequence=seq,deposited={['minecraft:stone']=n}}})
  end
  assert(not report('completed',0,0));assert(report('work',2,1));assert(report('work',2,1))
  assert(not report('work',3,1));assert(not report('work',1,2));assert(not report('work',6,2));eq(j.progress,2)
end)

test('return admission rolls back both ledgers when its atomic checkpoint fails',function()
  local f=fixture();local r=f.returns:request(12);local save=f.app.save;local failed=false
  f.app.save=function(app)
    local j=r.jobId and f.queue.state.jobs[r.jobId]
    if not failed and j and j.returnReady and app.state.capacityLedger.leases[j.id] then failed=true;return false,'disk full' end
    return save(app)
  end
  f:step();assert(failed);local j=f:returnJob(r);eq(j.returnReady,false);eq(j.returning,nil)
  eq(next(f.app.state.capacityLedger.leases),nil);eq(next(f.app.state.inventoryLedger.leases),nil);eq(f.transfers,0)
  f:step(4);assert(j.returnReady);eq(f.app.state.capacityLedger.leases[j.id].status,'held')
end)

test('return admission rechecks ownership and cargo after native observations yield',function()
  for _,change in ipairs({'worker','cargo'}) do
    local f=fixture();local r=f.returns:request(12);local call=f.e.peripheral.call;local changed=false
    f.e.peripheral.call=function(name,method,...)
      if method=='size' and not changed then
        changed=true
        if change=='worker' then local j=f.queue:submit('RETURN_HOME',{preferredWorker=12},{});j.workerId=12;j.status='assigned'
        else f.app.state.workers['12'].telemetry.cargo.items['minecraft:stone']=6 end
      end
      return call(name,method,...)
    end
    f:step();assert(changed);eq(f:returnJob(r).returnReady,false);eq(f.transfers,0)
    eq(next(f.app.state.capacityLedger.leases),nil);eq(next(f.app.state.inventoryLedger.leases),nil)
  end
end)

test('owned home node and buffer cannot be rebound or exposed as shared storage',function()
  local f=fixture();local r=f.returns:request(12);f:step(4)
  local Nodes=require('autobuilder.storage.nodes');assert(Nodes.validateSaved(f.config,f.app.state)==nil)
  for _,change in ipairs({'node','position','buffer'}) do
    local c=U.copy(f.config)
    if change=='node' then c.logistics.nodes[1].inventory='site'
    elseif change=='position' then c.logistics.nodes[1].buffers[1].position.x=8
    else c.logistics.nodes[1].buffers[1].inventory='b' end
    assert(not pcall(Nodes.validateSaved,c,f.app.state),'accepted changed owned '..change)
  end
  local j=f:returnJob(r);j.workerId=12
  local area=require('autobuilder.core.chunks').area(j,{position={x=2,y=1,z=0,known=true},depot={x=2,y=1,z=0}})
  j.returning.node.position.x=64
  local extended=require('autobuilder.core.chunks').area(j,{position={x=2,y=1,z=0,known=true},depot={x=2,y=1,z=0}})
  assert(extended.maxX>area.maxX,'central collection node omitted from loaded mission')
end)

test('worker keeps immutable home assignments and replays its exact acknowledged deposit receipt',function()
  local f=fixture();local r=f.returns:request(12);f:step(4);local j=U.copy(f:returnJob(r));j.workerId=12
  local c=require('tests.loaded_config').load({role='worker',controllerId=7,depot=U.copy(j.home),automation={courier=true}})
  local app={navigation={},state={id=12,position={x=2,y=1,z=2,known=true,heading='north'}}};function app:save() return true end
  local sent={};local net={send=function(_,_,kind,p) sent[#sent+1]={kind=kind,p=U.copy(p)};return true end}
  local ex=require('autobuilder.workers.executor').new(app,c,{},net,function() return 100 end);local seq=0
  local function control(kind,p) seq=seq+1;return ex:handle(7,{boot=1,sequence=seq,type=kind,payload=p}) end
  assert(control('task_assign',{job=j}));local changed=U.copy(j);changed.returning.items['minecraft:stone']=6
  assert(not control('task_assign',{job=changed}));changed=U.copy(j);changed.returning.buffer.inventory='b'
  assert(not control('task_assign',{job=changed}))
  app.state.currentTask.phase='completed';app.state.currentTask.progress=8
  app.state.currentTask.homeCargo={sequence=2,deposited=U.copy(j.returning.items)}
  assert(control('task_ack',{jobId=j.id}));eq(app.state.currentTask,nil)
  assert(control('task_assign',{job=j}));eq(sent[#sent].p.homeReceipt.sequence,2);eq(sent[#sent].p.homeReceipt.deposited['minecraft:dirt'],3)
end)

test('owned home cargo prevents a new shared factory observer until collection settles',function()
  local f=fixture();local r=f.returns:request(12);f:step(4)
  local j=f:returnJob(r);local craft=f.queue:submit('CRAFT',{item='minecraft:stone_bricks',batches=1,quantity=4},{})
  local Q=require('autobuilder.core.workflows')
  assert(not Q.factoryCanRun(f.app.state,craft),'shared factory overlapped owned return collection')
  assert(not Q.canOfferSupply(f.app.state,{type='BUILD'}),'new supply overlapped return ownership')
  f:deposit(j);f:step(20);eq(j.status,'completed');assert(Q.factoryCanRun(f.app.state,craft))
end)

test('unclaimed project home request releases an empty actor only to another durable task',function()
  for _,mode in ipairs({'safe','manual','owned','cargo','unowned','save'}) do
    local f=fixture();local r=f.returns:request(12,mode=='manual' and 'manual' or 'project:sample:run:1:worker:12')
    if mode=='owned' then f:step() end
    local j=f.queue:submit('BUILD',{blocks={{x=8,y=0,z=0,name='minecraft:stone',state={}}}},{})
    j.workerId=mode=='unowned' and 13 or 12;j.status='assigned'
    local w=f.app.state.workers['12'];w.telemetry.task=j.id;w.telemetry.status='working';w.lastSeen=101
    if mode~='cargo' then w.telemetry.cargo={items={},limits={}} end
    if mode=='save' then f.app.save=function() return false,'disk full' end end
    local ok,result=pcall(f.returns.releaseToTask,f.returns,r.id,j.id)
    if mode=='safe' then assert(ok and result);eq(r.status,'completed');eq(r.reassignedTo,j.id)
    else assert(not ok or not result);assert(f.queue.state.returns[r.id].status~='completed') end
  end
end)

test('paused home collection reconciles its pending native effect without another transfer',function()
  local f=fixture();local r=f.returns:request(12);f:step();local j=f:returnJob(r);f:deposit(j)
  f.crashTransfer=true;pcall(function() f:step() end);assert(f.crashed)
  local pending;for _,flow in pairs(j.returnFlow.collect) do if flow.intent then pending=flow end end;assert(pending)
  f.crashed=false;j.paused=true;local transfers=f.transfers;f:step()
  eq(pending.intent,nil);eq(f.transfers,transfers);assert(j.status~='completed')
end)
