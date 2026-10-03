local U=require('autobuilder.core.util')
local function fixture(n)
  local c=require('autobuilder.config').load({minimumFuelReserve=5})
  local s={workers={},jobs={},automation={jobs={},projects={},sequence=0,cells={}},exploration={groups={}}}
  for id=1,n or 4 do s.workers[tostring(id)]={id=id,online=true,telemetry={status='idle',fuel=1000,
    capabilities={mining=true,explorationV1=true,building=true,siteWorkV1=true,siteSurveyV1=true,crafting=true,courier=true},
    position={x=0,y=1,z=0,known=true},depot={x=0,y=1,z=0}}} end
  return s,c
end
local function job(s,id,kind,n)
  local j={id=id,type=kind,status='queued',quantity=n,dependencies={}}
  if kind=='BUILD' or kind=='PREPARE_REGION' then
    j.blocks={};for x=1,n do j.blocks[x]={x=x,y=1,z=0,name='minecraft:stone',state={}} end
    if kind=='PREPARE_REGION' then j.siteWork={stage='clear'} end
  end
  s.automation.jobs[id]=j;return j
end

test('scaling role limits validate all five roles and never deploy minimum workers without demand',function()
  local C=require('autobuilder.config');local S=require('autobuilder.core.scaling')
  for _,role in ipairs(S.roles) do
    local c=C.load({scaling={roles={[role]={min=2,max=3}}}})
    local s=fixture();eq(S.snapshot(s,c,{},100)[role].desired,0)
    for _,bounds in ipairs({{min=-1,max=2},{min=3,max=2},{min=0,max=129},{min=0,max=1.5}}) do
      assert(not pcall(C.load,{scaling={roles={[role]=bounds}}}))
    end
  end
end)

test('scaling grows with independent useful work and drains without cancelling owners',function()
  local s,c=fixture(6);local S=require('autobuilder.core.scaling')
  local first=job(s,'first','BUILD',1);eq(S.snapshot(s,c,{},100).building.desired,1)
  for i=2,6 do job(s,'build'..i,'BUILD',64) end
  local view=S.snapshot(s,c,{},100).building;eq(view.desired,6);eq(view.idle,6);eq(view.queue,6)
  c.scaling.roles.building.max=2;eq(S.snapshot(s,c,{},100).building.desired,2)
  first.workerId=1;first.status='running';s.workers['1'].online=false
  c.scaling.roles.building.max=0
  view=S.snapshot(s,c,{},100).building;eq(view.active,1);eq(view.desired,0)
  assert(not S.canAssign(s,c,s.automation.jobs.build2,s.workers['2'],{},100))
  assert(S.canAssign(s,c,first,s.workers['1'],{},100),'scale down revoked an offline owner')
  for _,j in pairs(s.automation.jobs) do j.status='completed' end
  view=S.snapshot(s,c,{},100).building;eq(view.active,0);eq(view.desired,0)
end)

test('mining allocation accounts for shortages travel and observed zero-yield time without double counting trips',function()
  local s,c=fixture(6);local S=require('autobuilder.core.scaling')
  s.exploration.groups.g={id='g',item='minecraft:cobblestone',target=16,status='running',tripIds={}}
  local near=S.snapshot(s,c,{},100).mining
  for _,w in pairs(s.workers) do w.telemetry.explorationHome={depot=w.telemetry.depot,exitRoute={{x=120,y=1,z=0}}} end
  local far=S.snapshot(s,c,{},100).mining;assert(far.desired>near.desired,'travel cost did not affect useful capacity')
  local j={id='mine',type='MINE',workerId=1,status='completed',assignedAt=10,completedAt=90,quantity=8,
    exploration={groupId='g'},progress={delivered=0,held=0}}
  s.jobs.mine=j;S.record(s,j,function() return true end)
  eq(s.fleet.metrics.mining.units,0);eq(s.fleet.metrics.mining.seconds,80)
  local view=S.snapshot(s,c,{},100).mining;eq(view.remaining,16);assert(view.desired>=far.desired)
  eq(S.snapshot(s,c,{['minecraft:cobblestone']=16},100).mining.desired,0)
  S.record(s,j,function() return true end);eq(s.fleet.metrics.mining.seconds,80)
end)

test('scaling completion metrics roll back atomically and retain bounded physical samples',function()
  local s,c=fixture();local S=require('autobuilder.core.scaling')
  local j=job(s,'haul','TRANSPORT',20);j.logistics={};j.workerId=1;j.status='completed';j.assignedAt=10;j.completedAt=30;j.delivered=7
  assert(not pcall(S.record,s,j,function() return false,'disk full' end));assert(not j.scalingSampled)
  assert(not s.fleet or not next(s.fleet.metrics or {}))
  S.record(s,j,function() return true end);eq(s.fleet.metrics.hauling.units,7)
  s=U.copy(s);j=s.automation.jobs.haul;S.record(s,j,function() return true end);eq(s.fleet.metrics.hauling.units,7)
  for i=1,50 do
    j=job(s,'haul'..i,'TRANSPORT',1);j.workerId=1;j.status='completed';j.assignedAt=i;j.completedAt=i+1;j.delivered=1
    S.record(s,j,function() return true end)
  end
  assert(#s.fleet.metrics.hauling.samples<=32);eq(s.fleet.metrics.hauling.units,57)
end)

test('scaling excludes unfueled busy and incapable workers and preserves mandatory recovery',function()
  local s,c=fixture();local S=require('autobuilder.core.scaling')
  local build=job(s,'build','BUILD',64);s.workers['2'].telemetry.fuel=0
  s.workers['3'].telemetry.capabilities={courier=true};s.workers['4'].telemetry.task='unknown'
  eq(S.snapshot(s,c,{},100).building.idle,1)
  c.scaling.roles.building.max=0;c.scaling.roles.hauling.max=0;c.scaling.roles.clearing.max=0
  assert(not S.canAssign(s,c,build,s.workers['1'],{},100))
  for _,kind in ipairs({'RESCUE','REFUEL','RETURN_HOME'}) do
    assert(S.canAssign(s,c,{type=kind},s.workers['1'],{},100),'role quota stranded '..kind)
  end
  assert(S.canAssign(s,c,{type='PREPARE_REGION',siteAccess={}},s.workers['1'],{},100),'role quota stranded temporary access restoration')
end)

test('scaling counts dependencies and specializes idle workers while exposing all five role backlogs',function()
  local s,c=fixture(2);local S=require('autobuilder.core.scaling')
  s.workers['2'].telemetry.capabilities={building=true}
  local build=job(s,'build','BUILD',64);local blocked=job(s,'blocked','BUILD',64);blocked.dependencies={'missing'}
  job(s,'craft','CRAFT',128);job(s,'haul','TRANSPORT',128);job(s,'clear','PREPARE_REGION',64)
  s.exploration.groups.g={id='g',item='minecraft:coal',target=64,status='running',tripIds={}}
  local view=S.snapshot(s,c,{},100);eq(view.building.ready,1);eq(view.building.queue,2)
  eq(S.preference(s,c,build,s.workers['2'])<S.preference(s,c,build,s.workers['1']),true)
  for _,role in ipairs(S.roles) do assert(view[role].remaining>0,role..' demand missing');assert(view[role].desired>=1) end
  local ready=S.window(s,c,'building');assert(ready>=2 and ready<=64)
end)

test('measured delivery rate changes useful allocation without crediting held or expected stock',function()
  local s,c=fixture(6);local S=require('autobuilder.core.scaling')
  s.exploration.groups.g={id='g',item='minecraft:coal',target=60,status='running',tripIds={}}
  local slow=S.snapshot(s,c,{},100).mining.desired
  local j={id='rate',type='MINE',workerId=1,status='completed',assignedAt=10,completedAt=70,
    progress={delivered=60,held=500},quantity=60}
  s.jobs.rate=j;S.record(s,j,function() return true end)
  eq(s.fleet.metrics.mining.units,60)
  local fast=S.snapshot(s,c,{},100).mining;assert(fast.desired<slow);eq(fast.remaining,60);eq(fast.rate,1)
  c.scaling.roles.mining.min=3;eq(S.snapshot(s,c,{},100).mining.desired,3)
end)

test('workflow dispatch obeys role caps selects specialized idle workers and rechecks after a yielding claim',function()
  local s,c=fixture(3);local S=require('autobuilder.core.scaling')
  c.scaling.roles.building.max=1;s.workers['3'].telemetry.capabilities={building=true}
  local Q=require('autobuilder.core.workflows').new(s,function() return true end,function() return 100 end,7,nil,c)
  local a=Q:submit('BUILD',{blocks={{x=100,y=1,z=0,name='minecraft:stone',state={}}}})
  local b=Q:submit('BUILD',{blocks={{x=200,y=1,z=0,name='minecraft:stone',state={}}}})
  eq(Q:assign(s.workers).id,a.id);eq(a.workerId,3);eq(a.assignedAt,100)
  a.status='running';s.workers['3'].telemetry.task=a.id
  eq(Q:assign(s.workers),nil);assert(not b.workerId)
  a.status='completed';s.workers['3'].telemetry.task=nil
  local chunks={reserve=function() c.scaling.roles.building.max=0;return {status='disabled'} end}
  Q=require('autobuilder.core.workflows').new(s,function() return true end,function() return 101 end,7,chunks,c)
  eq(Q:assign(s.workers),nil);assert(not b.workerId,'stale role target assigned after yielding coverage')
end)

test('failed workflow ownership checkpoint leaves an idle worker and unchanged job for retry',function()
  local s,c=fixture(1);local fail=false
  local Q=require('autobuilder.core.workflows').new(s,function() return not fail,'disk full' end,function() return 100 end,7,nil,c)
  local j=Q:submit('BUILD',{blocks={{x=100,y=1,z=0,name='minecraft:stone',state={}}}});fail=true
  assert(not pcall(Q.assign,Q,s.workers));assert(not j.workerId);eq(j.status,'queued');eq(j.assignedAt,nil)
  fail=false;eq(Q:assign(s.workers).id,j.id)
end)

test('loaded ownership applies the final scaling check and checkpoints its assignment time atomically',function()
  local s,c=fixture(1);c.chunkLoading.areas={{minX=-1,maxX=10,minZ=-1,maxZ=1}}
  s.workers['1'].telemetry.capabilities.chunkCoverageV1=true
  local fail=false;local save=function() return not fail,'disk full' end
  local chunks=require('autobuilder.core.chunks').new(s,c,save)
  local Q=require('autobuilder.core.workflows').new(s,save,function() return 100 end,7,chunks,c)
  local j=Q:submit('BUILD',{requiresSite=true,blocks={{x=100,y=1,z=0,name='minecraft:stone',state={}}}})
  local calls=0;Q.preparationReady=function() calls=calls+1;if calls==2 then c.scaling.roles.building.max=0 end;return true end
  eq(Q:assign(s.workers),nil);assert(not j.workerId);eq(s.chunkLedger.leases[j.id],nil)
  c.scaling.roles.building.max=1;Q.preparationReady=function() return true end;fail=true
  assert(not pcall(Q.assign,Q,s.workers));assert(not j.workerId);eq(j.assignedAt,nil);eq(s.chunkLedger.leases[j.id],nil)
  fail=false;eq(Q:assign(s.workers).id,j.id);eq(j.assignedAt,100);eq(s.chunkLedger.leases[j.id].workerId,1)
end)

test('stationary crafting remains useful without movement fuel and larger fleets widen bounded region windows',function()
  local s,c=fixture(12);local S=require('autobuilder.core.scaling')
  for _,w in pairs(s.workers) do w.telemetry.fuel=0 end
  job(s,'craft','CRAFT',100);eq(S.snapshot(s,c,{},100).crafting.idle,12)
  eq(S.snapshot(s,c,{},100).building.idle,0)
  eq(S.window(s,c,'clearing'),24);c.scaling.roles.clearing.max=6;eq(S.window(s,c,'clearing'),12)
end)

test('delivery rates include collection after worker completion and exclude unfinished private stock',function()
  local s,c=fixture();local S=require('autobuilder.core.scaling')
  local j=job(s,'collect','TRANSPORT',8);j.logistics={};j.workerId=1;j.assignedAt=10;j.completedAt=20
  j.status='collecting';j.delivered=8;assert(not S.record(s,j,function() return true end,30))
  j.status='completed';assert(S.record(s,j,function() return true end,40));eq(s.fleet.metrics.hauling.seconds,30)
end)

test('idle multirole workers balance ready bottlenecks without withholding upstream work for missing ingredients',function()
  local s,c=fixture(4);local S=require('autobuilder.core.scaling')
  s.exploration.groups.g={id='g',item='minecraft:coal',target=1000,status='running',tripIds={}}
  for i=1,4 do job(s,'build'..i,'BUILD',64) end
  local mine={id='mine',type='MINE',status='running',workerId=1,quantity=64,progress={delivered=0},exploration={groupId='g'}}
  s.jobs.mine=mine;s.workers['1'].telemetry.task=mine.id
  assert(not S.canAssign(s,c,{type='MINE'},s.workers['2'],{},100),'mining took every multirole worker before ready construction')
  assert(S.canAssign(s,c,s.automation.jobs.build1,s.workers['2'],{},100))
  for _,j in pairs(s.automation.jobs) do j.requiresSite=true;j.preparationError='region not prepared' end
  assert(S.canAssign(s,c,{type='MINE'},s.workers['2'],{},100),'unready construction withheld useful upstream mining')
  local craft=job(s,'craft','CRAFT',128);craft.stockInputs={['minecraft:stone']=128};craft.stockError='missing ingredients'
  assert(S.canAssign(s,c,{type='MINE'},s.workers['2'],{},100),'unreserved craft ingredients withheld upstream work')
end)

test('fleet limit commands persist effective bounds across restart and yield to changed settings',function()
  local s,c=fixture();local S=require('autobuilder.core.scaling');local j=job(s,'build','BUILD',64)
  S.setLimits(s,c,'building',0,0,function() return true end)
  eq(S.snapshot(s,c,{},100).building.desired,0)
  local restored=U.copy(s);eq(S.limits(restored,c,'building').max,0)
  assert(not pcall(S.setLimits,s,c,'building',3,2,function() return true end));eq(S.limits(s,c,'building').max,0)
  assert(not pcall(S.setLimits,s,c,'building',0,2,function() return false,'disk full' end));eq(S.limits(s,c,'building').max,0)
  c.scaling.roles.building.max=3;eq(S.limits(restored,c,'building').max,3)
  assert(S.canAssign(restored,c,j,restored.workers['1'],{},100))
end)

test('fleet diagnostics keep bounded significant allocation history and roll back failed saves',function()
  local s,c=fixture();local S=require('autobuilder.core.scaling');local j=job(s,'build','BUILD',64)
  assert(not pcall(S.update,s,c,{},100,function() return false,'disk full' end));eq(s.fleet,nil)
  S.update(s,c,{},100,function() return true end);local initial=#s.fleet.decisions;assert(initial>0)
  S.update(s,c,{},101,function() return true end);eq(#s.fleet.decisions,initial)
  for i=1,100 do j.status=i%2==0 and 'queued' or 'completed';S.update(s,c,{},101+i,function() return true end) end
  assert(#s.fleet.decisions<=32)
  local lines=S.describe(s,c,{},300);local text=table.concat(lines,'\n')
  for _,name in ipairs({'mining','hauling','crafting','clearing','building','active=','idle=','queue=','remaining=','rate='}) do assert(text:find(name,1,true),name) end
end)

test('large project backlog drives allocation beyond the currently expanded region payloads',function()
  local s,c=fixture(4);local S=require('autobuilder.core.scaling')
  s.automation.projects.large={name='large',phase='building',total=400,completed=0,
    site={status='surveyed',columnCount=200,regionCount=100,estimatedCells=800,work={status='working',completed=0}}}
  for i=1,4 do local j=job(s,'build'..i,'BUILD',2);j.project='large';local q=job(s,'clear'..i,'PREPARE_REGION',8);q.project='large' end
  local view=S.snapshot(s,c,{},100);eq(view.building.remaining,400);eq(view.building.desired,4)
  eq(view.clearing.remaining,800);eq(view.clearing.desired,4)
end)

test('role priority cannot wait on a courier excluded by the existing factory storage gate',function()
  local s,c=fixture(1);local S=require('autobuilder.core.scaling')
  local craft=job(s,'craft','CRAFT',64);job(s,'haul','TRANSPORT',64)
  assert(require('autobuilder.core.workflows').factoryCanRun(s,craft))
  assert(S.canAssign(s,c,craft,s.workers['1'],{},100),'crafting waited on a courier that its own stock gate excludes')
end)

test('private crafting rates use centrally collected output and the durable factory interval',function()
  local s,c=fixture();local S=require('autobuilder.core.scaling')
  local j=job(s,'private','CRAFT',8);j.workerId=1;j.privateStation={};j.status='completed'
  j.factoryStartedAt=10;j.assignedAt=15;j.completedAt=20;j.factoryCompletedAt=30
  j.factoryFlow={collect={delivered=8}}
  assert(S.record(s,j,function() return true end,100));eq(s.fleet.metrics.crafting.units,8);eq(s.fleet.metrics.crafting.seconds,20)
end)


test('region lookahead exposes enough separated work for every useful builder',function()
  local s,c=fixture(4);local S=require('autobuilder.core.scaling')
  s.automation.projects.large={phase='building',total=1000,completed=0}
  for i=1,S.window(s,c,'building') do
    local j=job(s,'region'..i,'BUILD',4);j.project='large';j.created=i;j.requiredCapability='building'
    j.bounds={min={x=4*i,y=1,z=0},max={x=4*i+3,y=3,z=0}}
  end
  local q=require('autobuilder.core.workflows').new(s,function() return true end,function() return 100 end,7,nil,c)
  for _=1,4 do q:assign(s.workers) end
  local n=0;for _,j in pairs(s.automation.jobs) do if j.workerId then n=n+1 end end
  eq(n,4)
end)
