local S=require('tests.support'); local U=require('autobuilder.core.util'); local World=require('tests.world')
local function environment(id)
  local e={fs=S.fs(),textutils=S.codec(),now=100,packets={},screen={}}
  e.os={getComputerID=function() return id end,epoch=function() return e.now*1000 end}
  e.rednet={isOpen=function() return true end,open=function() end,send=function(to,m,p) e.packets[#e.packets+1]={to=to,message=U.copy(m),protocol=p}; return true end}
  e.term={getSize=function() return 51,19 end,clear=function() e.screen={} end,setCursorPos=function(_,y) e.row=y end,write=function(s) e.screen[e.row]=s end}
  return e
end
local function fixture()
  local w=World.new(); local ce,we=environment(7),environment(12)
  ce.peripheral={getNames=function() return {'right','chest_0'} end,getType=function(name) return name=='right' and 'modem' or 'inventory' end,
    call=function(name,method)
      if name=='right' then return true end
      assert(method=='list'); local r={}; for item,count in pairs(w.stock) do r[#r+1]={name=item,count=count} end; return r
    end}
  we.turtle=w.turtle; w.items[16]={name='advancedperipherals:geo_scanner',count=1}
  local equipped=false
  w.turtle.equipLeft=function()
    equipped=not equipped; w.items[16]={name=equipped and 'minecraft:diamond_pickaxe' or 'advancedperipherals:geo_scanner',count=1}; return true
  end
  we.peripheral={getNames=function() return equipped and {'right','left'} or {'right'} end,
    getType=function(name) if name=='right' then return 'modem' elseif equipped then return 'geoScanner' end end,
    call=function(name,method,arg) if name=='right' then return true end; return w.peripheral.call(name,method,arg) end}
  we.gps={locate=function() return w.pose.x,w.pose.y,w.pose.z end}
  local C=require('tests.loaded_config')
  local cc=C.load({role='controller',storageInventories={'chest_0'}})
  local wc=C.load({role='worker',controllerId=7,initialPosition=U.copy(w.pose),depot={x=0,y=0,z=0},minimumFuelReserve=5,
    mining={enabled=true,entry={x=1,y=0,z=0},bounds={min={x=1,y=-1,z=-2},max={x=8,y=1,z=2}},fuelTarget=100}})
  local R=require('autobuilder.core.runtime')
  return w,ce,we,R.new(cc,ce),R.new(wc,we),cc,wc
end
local function pump(from,to)
  local packets=from.packets; from.packets={}
  for _,p in ipairs(packets) do to:receive(p.message.sender,p.message,p.protocol) end
end

test('mine command drives real runtime to gather missing stock and acknowledge once',function()
  local w,ce,we,c,worker=fixture(); w.stock['minecraft:raw_iron']=2
  for x=2,6 do w.blocks[x..',0,0']='minecraft:iron_ore' end
  assert(worker:tick()); pump(we,c); pump(ce,worker)
  local ok,id=c:command('mine minecraft:raw_iron 5'); assert(ok,id)
  for i=1,250 do
    ce.now=100+i; we.now=ce.now; w.time=ce.now
    c:tick(); pump(ce,worker); worker:tick(); worker:workStep(); pump(we,c); pump(ce,worker)
    if c.state.jobs[id].status=='completed' and not worker.state.currentTask then break end
  end
  eq(c.state.jobs[id].status,'completed'); eq(c.state.jobs[id].quantity,3)
  eq(w.stock['minecraft:raw_iron'],5); eq(worker.state.currentTask,nil)
  eq(w.pose.x,0); eq(w.items[16].name,'advancedperipherals:geo_scanner')
  assert(worker:receive(7,{version=1,id='7:999999:1',sender=7,boot=999999,sequence=1,type='mine_assign',payload={jobId=id,item='minecraft:raw_iron',quantity=3}},'autobuilder.v1'))
  eq(worker.state.currentTask,nil)
end)
test('GPS fix started before mining motion is discarded when it returns',function()
  local _,_,we,_,worker=fixture()
  we.gps.locate=function() worker.motionVersion=worker.motionVersion+1; worker.state.position.x=4; return 0,0,0 end
  assert(worker:updateGPS()); eq(worker.state.position.x,4)
end)
test('controller mine command rejects missing storage and malformed input',function()
  local _,ce,_,_,_,cc=fixture(); cc.storageInventories={}
  local c=require('autobuilder.core.runtime').new(cc,ce)
  assert(not c:command('mine minecraft:raw_iron 5'))
  assert(not c:command('mine minecraft:bedrock -3'))
end)

test('idle action steps do not invalidate GPS and GPS lock prevents hardware steps',function()
  local _,_,_,_,worker=fixture()
  local revision=worker.motionVersion; worker:workStep(); eq(worker.motionVersion,revision)
  worker.state.currentTask={id='mine:test',item='minecraft:raw_iron',quantity=1,phase='setup'}
  worker.gpsRequested=true; worker:workStep(); eq(worker.motionVersion,revision)
end)
test('quit during a hardware step waits for a safe boundary',function()
  local _,_,_,_,worker=fixture()
  worker.busy=true; assert(worker:event('char','q')); eq(worker.quitRequested,true)
  worker.busy=false; eq(worker:event('timer',1),false)
end)

test('controller and worker reboot mid-job resume one assignment and one stock target',function()
  local w,ce,we,c,worker,cc,wc=fixture()
  for x=2,6 do w.blocks[x..',0,0']='minecraft:iron_ore' end
  worker:tick(); pump(we,c); pump(ce,worker)
  local ok,id=c:command('mine minecraft:raw_iron 4'); assert(ok,id)
  local rebooted=false
  for i=1,300 do
    ce.now=100+i; we.now=ce.now; w.time=ce.now
    c:tick(); pump(ce,worker); worker:tick(); worker:workStep(); pump(we,c); pump(ce,worker)
    if not rebooted and worker.state.currentTask and worker.state.currentTask.phase=='work' and w.pose.x>=2 then
      c=require('autobuilder.core.runtime').new(cc,ce)
      worker=require('autobuilder.core.runtime').new(wc,we); rebooted=true
    end
    if c.state.jobs[id].status=='completed' and not worker.state.currentTask then break end
  end
  assert(rebooted); eq(w.stock['minecraft:raw_iron'],4); eq(c.state.jobs[id].status,'completed'); eq(worker.state.currentTask,nil)
end)
test('lost completion acknowledgements do not restart finished mining',function()
  local w,ce,we,c,worker=fixture(); w.blocks['2,0,0']='minecraft:iron_ore'; w.blocks['3,0,0']='minecraft:iron_ore'
  worker:tick(); pump(we,c); pump(ce,worker)
  local ok,id=c:command('mine minecraft:raw_iron 1'); assert(ok,id)
  for i=1,100 do
    ce.now=100+i; we.now=ce.now; w.time=ce.now
    c:tick(); pump(ce,worker); worker:tick(); worker:workStep(); pump(we,c)
    -- Drop all completion ACKs, delivering normal registration ACKs.
    local kept={}; for _,packet in ipairs(ce.packets) do if packet.message.type~='mine_ack' then kept[#kept+1]=packet end end
    ce.packets=kept; pump(ce,worker)
  end
  eq(c.state.jobs[id].status,'completed'); eq(worker.state.currentTask.phase,'completed'); eq(w.stock['minecraft:raw_iron'],1)
  for i=1,6 do we.now=we.now+1; ce.now=we.now; worker:tick(); pump(we,c); pump(ce,worker) end
  eq(worker.state.currentTask,nil); eq(w.stock['minecraft:raw_iron'],1)
end)

test('storage consumed during a job is replenished by an idempotent supplemental job',function()
  local w,ce,we,c,worker=fixture(); w.stock['minecraft:raw_iron']=2
  for x=2,7 do w.blocks[x..',0,0']='minecraft:iron_ore' end
  worker:tick(); pump(we,c); pump(ce,worker)
  local ok,id=c:command('mine minecraft:raw_iron 5'); assert(ok,id)
  local consumed=false
  for i=1,350 do
    ce.now=100+i; we.now=ce.now; w.time=ce.now
    c:tick(); pump(ce,worker); worker:tick(); worker:workStep(); pump(we,c); pump(ce,worker)
    if not consumed and worker.state.currentTask and worker.state.currentTask.phase=='work' then w.stock['minecraft:raw_iron']=1; consumed=true end
    if c.state.jobs[id].status=='completed' and not worker.state.currentTask then break end
  end
  assert(consumed); eq(w.stock['minecraft:raw_iron'],5); eq(c.state.jobs[id].status,'completed'); assert(c.state.jobs[id].childId)
end)

test('delayed GPS recovery resumes a pose-blocked mining task automatically',function()
  local w,_,we,_,worker=fixture()
  worker.state.currentTask={id='mine:recover',type='MINE',item='minecraft:raw_iron',quantity=1,
    phase='work',delivered=0,trail={{x=0,y=0,z=0},{x=1,y=0,z=0}}}
  worker.state.position.x=1; w.pose.x=1; worker.state.position.uncertain=true
  worker:workStep(); eq(worker.state.currentTask.phase,'blocked')
  assert(worker:updateGPS()); eq(worker.state.currentTask.phase,'work')
end)

test('controller backup recovers assignment ownership from the workers persisted task',function()
  local w,ce,we,c,worker,cc=fixture(); w.blocks['2,0,0']='minecraft:iron_ore'
  worker:tick(); pump(we,c); pump(ce,worker)
  local ok,id=c:command('mine minecraft:raw_iron 1'); assert(ok,id)
  c:tick(); pump(ce,worker); assert(worker.state.currentTask)
  -- The previous committed snapshot contains the queued job, before ownership save.
  ce.fs.files['/autobuilder/data/controller.state']='corrupt'
  c=require('autobuilder.core.runtime').new(cc,ce)
  for i=1,250 do
    ce.now=120+i; we.now=ce.now; w.time=ce.now
    worker:tick(); pump(we,c); c:tick(); pump(ce,worker); worker:workStep()
    if c.state.jobs[id].status=='completed' and not worker.state.currentTask then break end
  end
  eq(c.state.jobs[id].status,'completed'); eq(w.stock['minecraft:raw_iron'],1)
end)

test('worker rejects resource mismatches and blocks restored assignments after restriction changes',function()
  local _,_,_,_,worker,_,wc=fixture()
  wc.mining.resources={'minecraft:raw_iron'}
  local function assign(item,resources)
    return worker.mining:handle(7,{type='mine_assign',payload={jobId='mine:restricted',item=item,quantity=1,miningResources=resources}})
  end
  assert(not assign('minecraft:coal',nil)); eq(worker.state.currentTask,nil)
  assert(not assign('minecraft:raw_iron',{'minecraft:raw_iron','minecraft:sand'})); eq(worker.state.currentTask,nil)
  assert(assign('minecraft:raw_iron',{'minecraft:raw_iron'}))
  eq(worker.state.currentTask.miningResources[1],'minecraft:raw_iron')
  worker.state.currentTask.phase='work'
  wc.mining.resources={'minecraft:raw_iron','minecraft:sand'}
  worker:workStep(); eq(worker.state.currentTask.phase,'blocked')
  assert(worker.state.currentTask.error:find('resources'))
  wc.mining.resources={'minecraft:raw_iron'}
  assert(worker.mining:handle(7,{type='mine_resume',payload={jobId='mine:restricted'}}))
  eq(worker.state.currentTask.phase,'work')
end)

test('worker accepts legacy assignments while enforcing its local resource eligibility',function()
  local _,_,_,_,worker,_,wc=fixture(); wc.mining.resources={'minecraft:raw_iron'}
  assert(worker.mining:handle(7,{type='mine_assign',payload={jobId='mine:legacy',item='minecraft:raw_iron',quantity=1}}))
  eq(worker.state.currentTask.item,'minecraft:raw_iron')
  eq(worker.state.currentTask.miningResources[1],'minecraft:raw_iron')
end)

test('completed mines retain acknowledgements until fresh cleared telemetry and request retirement',function()
  local w,ce,we,c,worker=fixture(); w.stock['minecraft:raw_iron']=1
  worker:tick(); pump(we,c); pump(ce,worker)
  local job=assert(c.mining.jobs:submit('minecraft:raw_iron',2,0)); c.mining.jobs:assign(c.state.workers)
  c.state.automation.requests.keep={id='keep',status='completed',mines={['minecraft:raw_iron']=job.id}}
  local packet={type='mine_progress',payload={jobId=job.id,phase='completed',delivered=2,held=0}}
  w.stock['minecraft:raw_iron']=2
  assert(c.mining:handle(12,packet)); eq(job.completedAt,100)
  ce.now=101; assert(c.mining:handle(12,packet)); eq(job.completedAt,100)
  eq(ce.packets[#ce.packets].message.type,'mine_ack')
  -- Pre-completion idle telemetry cannot prove the worker consumed its acknowledgement.
  c.state.automation.requests.keep=nil; c.mining:tick(); assert(c.state.jobs[job.id])
  local peer=c.state.workers['12']; peer.lastSeen=102; peer.telemetry.task=job.id
  ce.now=103; c.mining:tick(); assert(c.state.jobs[job.id])
  peer.telemetry.task=nil; peer.online=false; c.mining:tick(); assert(c.state.jobs[job.id])
  peer.online=true; c.state.automation.requests.keep={id='keep',status='running',mines={['minecraft:raw_iron']=job.id}}
  c.mining:tick(); assert(c.state.jobs[job.id])
  c.state.automation.requests.keep=nil; c.mining:tick(); eq(c.state.jobs[job.id],nil)
  local sent=#ce.packets; assert(not c.mining:handle(12,packet)); eq(#ce.packets,sent)
end)

test('mining retirement preserves unfinished supplement chains and releases completed chains together',function()
  local w,ce,we,c,worker=fixture()
  worker:tick(); pump(we,c); pump(ce,worker)
  local parent=assert(c.mining.jobs:submit('minecraft:raw_iron',2,0)); c.mining.jobs:assign(c.state.workers)
  local function completed(id,count)
    return c.mining:handle(12,{type='mine_progress',payload={jobId=id,phase='completed',delivered=count,held=0}})
  end
  w.stock['minecraft:raw_iron']=1; assert(completed(parent.id,2))
  local child=c.state.jobs[parent.childId]; assert(child); eq(parent.status,'blocked')
  c.state.workers['12'].lastSeen=101; ce.now=102; c.mining:tick()
  assert(c.state.jobs[parent.id]); assert(c.state.jobs[child.id]); eq(child.workerId,12)
  w.stock['minecraft:raw_iron']=2; assert(completed(child.id,1))
  eq(parent.status,'completed'); eq(child.status,'completed'); eq(parent.completedAt,102); eq(child.completedAt,102)
  c.state.workers['12'].lastSeen=103; ce.now=104
  c.state.automation.requests.keep={status='completed',mines={iron=parent.id}}
  c.mining:tick(); assert(c.state.jobs[parent.id]); assert(c.state.jobs[child.id])
  c.state.automation.requests.keep=nil; c.mining:tick()
  eq(c.state.jobs[parent.id],nil); eq(c.state.jobs[child.id],nil)
end)

test('legacy completed mines wait for a new observation before retirement',function()
  local _,ce,we,c,worker=fixture()
  worker:tick(); pump(we,c); pump(ce,worker)
  c.state.jobs.legacy={id='legacy',status='completed',workerId=12,physicalComplete=true}
  c.mining:tick(); assert(c.state.jobs.legacy)
  c.state.workers['12'].lastSeen=101; ce.now=102; c.mining:tick(); eq(c.state.jobs.legacy,nil)
end)
test('exploration runtime preserves partial receipts across controller and worker reboot',function()
  local w,ce,we,c,worker,cc,wc=fixture()
  cc.exploration={enabled=true,base={x=0,y=0,z=0},bounds={min={x=0,y=0,z=0},max={x=3,y=1,z=1}},baseProtection={min={x=0,y=-1,z=0},max={x=0,y=-1,z=0}},dimensionMinY=-64,dimensionMaxY=319}
  wc.mining.mode='explore'; wc.mining.exitRoute={}; wc.capabilities.explorationV1=true
  local R=require('autobuilder.core.runtime'); c=R.new(cc,ce); worker=R.new(wc,we)
  w.blocks['3,1,1']='minecraft:iron_ore'
  worker:tick(); pump(we,c); pump(ce,worker)
  local group=assert(c.mining.jobs:requestAcquisition('minecraft:raw_iron',2,0,'test'))
  local rebooted=false; local trip
  for i=1,1000 do
    ce.now=100+i; we.now=ce.now; w.time=ce.now
    c:tick(); pump(ce,worker); worker:tick(); worker:workStep(); pump(we,c); pump(ce,worker)
    if worker.state.currentTask then trip=worker.state.currentTask.id end
    if not rebooted and worker.state.currentTask and worker.state.currentTask.phase=='work' then
      c=R.new(cc,ce); worker=R.new(wc,we); rebooted=true
    end
    if trip and not worker.state.currentTask and c.state.jobs[trip] and c.state.jobs[trip].physicalComplete then break end
  end
  assert(rebooted,'explorer never dispatched'); eq(w.stock['minecraft:raw_iron'],1); eq(w.pose.x,0)
  eq(c.state.exploration.groups[group.id].status,'running'); eq(worker.state.currentTask,nil)
  local receipt=worker.state.completedMining[trip]; eq(receipt.delivered,1); eq(receipt.exploration.result,'survey_exhausted')
  local original=c.state.jobs[trip]
  assert(worker.mining:handle(7,{type='mine_assign',payload={jobId=trip,item=original.item,quantity=original.quantity,exploration=original.exploration}}))
  eq(worker.state.currentTask,nil)
end)
test('explorer rejects a duplicate assignment whose saved geometry changed',function()
  local _,_,_,_,worker,_,wc=fixture(); wc.mining.mode='explore'; wc.capabilities.explorationV1=true
  local g={version=1,groupId='acquire:1',sectorId='0,0,0',bounds={min={x=1,y=0,z=0},max={x=2,y=0,z=0}},envelope={min={x=0,y=0,z=0},max={x=3,y=0,z=0}},depot={x=0,y=0,z=0},entry={x=1,y=0,z=0},exitRoute={},route={{x=1,y=0,z=0}},protectedAreas={},cursor=1}
  local p={jobId='mine:immutable',item='minecraft:raw_iron',quantity=1,exploration=g}
  assert(worker.mining:handle(7,{type='mine_assign',payload=p})); assert(worker.state.currentTask.exploration)
  p.exploration.bounds.max.x=3
  assert(not worker.mining:handle(7,{type='mine_assign',payload=p}))
end)
test('exploration expansion survives restart and refuses shrinking or oversized territory',function()
  local _,ce,_,_,_,cc=fixture()
  cc.exploration={enabled=true,base={x=0,y=0,z=0},bounds={min={x=-8,y=0,z=-8},max={x=8,y=2,z=8}},baseProtection={min={x=0,y=-1,z=0},max={x=0,y=-1,z=0}},dimensionMinY=-64,dimensionMaxY=319}
  local R=require('autobuilder.core.runtime'); local c=R.new(cc,ce)
  assert(c:command('exploration expand 16')); eq(c.state.exploration.bounds.max.x,16)
  assert(not c:command('exploration expand 4')); assert(not c:command('exploration expand 10000'))
  assert(c:command('exploration pause')); assert(c.state.exploration.paused)
  c=R.new(cc,ce); assert(c.state.exploration.paused); eq(c.state.exploration.bounds.min.x,-16)
  assert(c:command('exploration resume')); assert(not c.state.exploration.paused)
end)
test('fresh exploration setup replaces a saved expansion at the same base',function()
  local U=require('autobuilder.core.util'); local _,ce,_,_,_,cc=fixture()
  cc.exploration={enabled=true,base={x=0,y=0,z=0},bounds={min={x=-8,y=0,z=-8},max={x=8,y=2,z=8}},baseProtection={min={x=0,y=-1,z=0},max={x=0,y=-1,z=0}},dimensionMinY=-64,dimensionMaxY=319}
  local original=U.copy(cc); local R=require('autobuilder.core.runtime'); local c=R.new(cc,ce)
  assert(c:command('exploration expand 16'))
  c=R.new(U.copy(original),ce); eq(c.config.exploration.bounds.max.x,16)
  local fresh=U.copy(original); fresh.exploration.bounds.min.y=10; fresh.exploration.bounds.max.y=12
  c=R.new(fresh,ce); eq(fresh.exploration.bounds.max.x,8); eq(fresh.exploration.bounds.min.y,10)
end)
