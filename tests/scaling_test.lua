local U=require('autobuilder.core.util')
local function fixture(n)
  local c=require('autobuilder.config').load({minimumFuelReserve=5})
  local s={workers={},jobs={},automation={jobs={},projects={}},exploration={groups={}}}
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
