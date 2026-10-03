local S=require('tests.support')
local U=require('autobuilder.core.util')
local Config=require('autobuilder.config')
local R=require('autobuilder.core.runtime')
local function pos(x) return {x=x,y=64,z=8,heading='east',known=true} end
local function env(id)
  local e={fs=S.fs(),textutils=S.codec(),turtle=S.turtle(),now=100}
  e.os={getComputerID=function() return id end,epoch=function() return e.now*1000 end}
  e.peripheral={getNames=function() return {'right'} end,getType=function() return 'modem' end,call=function() return true end}
  e.rednet={isOpen=function() return true end,open=function() end,send=function() return true end}
  e.gps={locate=function() end};return e
end
local function worker(id,x,anchor)
  local w={id=id,online=true,telemetry={status='idle',position=pos(x),depot=pos(x),fuel=2000,capabilities={telemetry=true,building=true,mining=true,chunkCoverageV1=true}}}
  if anchor then w.telemetry.chunkAnchor={provider='advanced_peripherals_chunky',x=math.floor(x/16),z=0} end
  return w
end
local function controller(areas)
  local e=env(7);local c=R.new(Config.load({chunkLoading={areas=areas or {{minX=0,maxX=0,minZ=0,maxZ=0}}}}),e)
  c.state.workers['12']=worker(12,8);return c,e
end
local function task(q,x) return q:submit('BUILD',{blocks={{x=x,y=64,z=8,name='minecraft:stone',state={}}}}) end
local function builder(anchor)
  local e=env(12);e.turtle.fuel=1000
  local cfg=Config.load({role='worker',controllerId=7,initialPosition=pos(8),depot=pos(8),minimumFuelReserve=0,
    automation={building=not anchor},chunkLoading={anchor=anchor or false}})
  local w=R.new(cfg,e);return w,e,cfg
end
local function assign(w,j,n)
  return w.automation:handle(7,{boot=1,sequence=n or 1,type='task_assign',payload={job=U.copy(j)}})
end
local function grant(x) return {id='task:7:1',type='BUILD',blocks={{x=x or 9,y=64,z=8,name='minecraft:stone',state={}}},loadedArea={minX=0,maxX=0,minZ=0,maxZ=0}} end

test('runtime coverage rejects unknown terrain but dispatches independent covered work',function()
  local c=controller();local q=c.automation.queue;local far=task(q,40);local near=task(q,9)
  eq(q:assign(c.state.workers).id,near.id);eq(far.workerId,nil);assert(far.coverageError:find('MISSION_BLOCKED_UNLOADED_AREA',1,true))
  eq(c.state.chunkLedger.leases[near.id].workerId,12);eq(c.state.chunkLedger.leases[far.id],nil)
  local ok,why=q:reserve(12,near.id,pos(15),pos(16),c.state.workers);assert(not ok and why:find('UNLOADED_AREA'))
  assert(q:progress(12,{jobId=near.id,phase='completed',progress=1}));c.chunks:reconcile();eq(c.state.chunkLedger.leases[near.id].status,'released')
end)

test('coverage and queue ownership checkpoint atomically and retry after failed save',function()
  local c,e=controller();local q=c.automation.queue;local j=task(q,9)
  e.fs.fault.open='/autobuilder/data/controller.state.tmp'
  assert(not pcall(q.assign,q,c.state.workers));eq(j.workerId,nil);eq(j.status,'queued');eq(j.loadedArea,nil);eq(c.state.chunkLedger.leases[j.id],nil)
  e.fs.fault.open=nil;assert(q:assign(c.state.workers));local saved=assert(require('autobuilder.core.checkpoint').new(e.fs,e.textutils,'/autobuilder/data/controller.state'):load())
  eq(saved.automation.jobs[j.id].workerId,12);eq(saved.chunkLedger.leases[j.id].workerId,12)
end)

test('coverage refuses old workers and protects stationary providers after going offline',function()
  local c=controller({});local q=c.automation.queue;local j=task(q,9)
  c.state.workers['20']=worker(20,8,true);c.state.workers['12'].telemetry.capabilities.chunkCoverageV1=nil
  eq(q:assign(c.state.workers),nil);eq(j.workerId,nil)
  c.state.workers['12'].telemetry.capabilities.chunkCoverageV1=true;eq(q:assign(c.state.workers).id,j.id)
  c.state.workers['20'].online=false
  assert(require('autobuilder.core.workflows').workerBusy(c.state,20),'offline loader lost ownership')
  local restored=U.copy(c.state);local chunks=require('autobuilder.core.chunks').new(restored,c.config,function() return true end)
  assert(chunks:reserve(restored.automation.jobs[j.id],restored.workers['12']))
  c.state.workers['13']=worker(13,8);local more=task(q,12);eq(q:assign(c.state.workers).id,j.id);eq(more.workerId,nil)
end)

test('strict workers refuse ungranted moves before traffic intent and retain envelope over reboot',function()
  local w,e,cfg=builder();local ok,why=w.navigation:forward();assert(not ok and why:find('UNLOADED_AREA'));eq(e.turtle.calls,0);eq(w.state.position.pending,nil)
  local j=grant();assert(assign(w,j));w.state.position.x=15;w:save();w=R.new(cfg,e)
  ok,why=w.navigation:forward();assert(not ok and why:find('UNLOADED_AREA'));eq(w.state.motionReservation,nil);eq(e.turtle.calls,0)
  -- Coverage remains a separate guard even if the traffic engine changes its guard.
  w.navigation.guard=function() return true end;w.state.position.x=8;assert(w.navigation:forward());eq(w.state.position.x,9)
end)

test('workers reject missing undersized changed grants and anchor assignments',function()
  local w=builder();local j=grant();j.loadedArea=nil;assert(not assign(w,j));eq(w.state.currentTask,nil)
  j=grant(32);assert(not assign(w,j,2));eq(w.state.currentTask,nil)
  j=grant();assert(assign(w,j,3));j.loadedArea.maxX=1;assert(not assign(w,j,4));eq(w.state.currentTask.loadedArea.maxX,0)
  local a,e=builder(true);assert(not assign(a,grant()));assert(not a.navigation:forward());eq(e.turtle.calls,0)
end)

test('chunk telemetry discovers real hardware and assignment validators bound grants',function()
  local w,e=builder(true);eq(w.agent:telemetry().chunkAnchor,nil)
  e.peripheral.getType=function(side) return side=='left' and 'chunky' or 'modem' end
  local t=w.agent:telemetry();eq(t.chunkAnchor.x,0);eq(t.capabilities.chunkCoverageV1,true);eq(t.depot.x,8)
  local n=require('autobuilder.core.network');local msg={version=1,id='12:1:1',sender=12,boot=1,sequence=1,type='register',payload=t}
  assert(n.validate(12,msg));t.chunkAnchor.x=0.5;assert(not n.validate(12,msg))
  local j=grant();j.loadedArea.maxX=1024
  assert(not require('autobuilder.core.task_messages').validate('task_assign',{job=j}))
  assert(not require('autobuilder.core.mining_messages').validate('mine_assign',{jobId='mine:7:1',item='minecraft:cobblestone',quantity=1,loadedArea=j.loadedArea}))
end)

test('fixed mining coverage includes worker bounds and missing coverage creates no owner',function()
  local c=controller();local w=c.state.workers['12'];w.telemetry.miningArea={min=pos(8),max=pos(24)}
  local j=assert(c.mining.jobs:submit('minecraft:cobblestone',2,0));eq(c.mining.jobs:assign(c.state.workers,{}),nil);eq(j.workerId,nil)
  c.config.chunkLoading.areas[1].maxX=1
  eq(c.mining.jobs:assign(c.state.workers,{}).id,j.id);eq(j.loadedArea.maxX,1)
end)

test('recovered queue ownership acquires coverage before granting movement',function()
  local c=controller();local q=c.automation.queue;local j=task(q,9)
  c.state.workers['12'].telemetry.task=j.id
  assert(q:recoverOwner(12,{jobId=j.id},c.state.workers))
  assert(q:reserve(12,j.id,pos(8),pos(9),c.state.workers))
  eq(c.state.chunkLedger.leases[j.id].workerId,12)
end)

test('legacy active jobs need explicit assured geometry before migration allows movement',function()
  local c=controller();local q=c.automation.queue;local j=task(q,9);j.workerId=12;j.status='running'
  c.state.workers['12'].telemetry.task=j.id
  assert(q:reserve(12,j.id,pos(8),pos(9),c.state.workers))
  local bad=task(q,40);bad.workerId=13;bad.status='running';c.state.workers['13']=worker(13,8)
  local ok,why=q:reserve(13,bad.id,pos(8),pos(9),c.state.workers);assert(not ok and why:find('UNLOADED_AREA'))
  eq(c.state.chunkLedger.leases[bad.id],nil)
end)

test('private crafting keeps loader ownership until central collection settles',function()
  local c=controller();local q=c.automation.queue;local j=task(q,9);assert(q:assign(c.state.workers))
  j.privateStation={id='test'};assert(q:progress(12,{jobId=j.id,phase='completed',progress=1}));c.chunks:reconcile()
  eq(j.status,'collecting');eq(c.state.chunkLedger.leases[j.id].status,'held')
  j.status='completed';c.chunks:reconcile();eq(c.state.chunkLedger.leases[j.id].status,'released')
end)

test('fixed mining failed coverage checkpoint leaves neither assignment nor candidate geometry',function()
  local c,e=controller();local w=c.state.workers['12'];w.telemetry.miningArea={min=pos(8),max=pos(10)}
  local j=assert(c.mining.jobs:submit('minecraft:cobblestone',2,0));e.fs.fault.open='/autobuilder/data/controller.state.tmp'
  assert(not pcall(c.mining.jobs.assign,c.mining.jobs,c.state.workers,{}));eq(j.workerId,nil);eq(j.miningArea,nil);eq(j.miningResources,nil)
end)

test('legacy opt out does not advertise enforced coverage or erase a saved active grant',function()
  local w,e=builder();assert(assign(w,grant()));w.config.chunkLoading.enabled=false
  eq(w.agent:telemetry().capabilities.chunkCoverageV1,false)
  w.state.position.x=15;local ok,why=w.navigation:forward();assert(not ok and why:find('UNLOADED_AREA'));eq(e.turtle.calls,0)
  local changed=grant();changed.loadedArea=nil;assert(not assign(w,changed,2))
end)

test('chunks status shows exact missing coverage and offline retained providers',function()
  local c=controller({});local q=c.automation.queue;c.state.workers['20']=worker(20,8,true)
  local j=task(q,9);assert(q:assign(c.state.workers));c.state.workers['20'].online=false
  c.state.workers['13']=worker(13,8);local far=task(q,40);q:assign(c.state.workers)
  local ok,text=c:command('chunks');assert(ok,text);assert(text:find('enforced') and text:find('held') and text:find('offline') and text:find(j.id) and text:find('UNLOADED_AREA'),text)
  eq(c.state.view,'chunks');assert(#c.state.chunksLines>0)
  c.config.chunkLoading.enabled=false;assert(select(2,c:command('chunks')):find('DISABLED'))
end)
