local U=require('autobuilder.core.util')
local function fixture()
  local f={size=5,items={},queries=0}
  f.config={build={enabled=true},autoDepotExpansion={enabled=true,freeSlots=2},storageInventories={'store'},
    depotExpansion={{x=10,y=64,z=10,name='minecraft:stone',state={}}}}
  f.app={state={id=7}}
  function f.app:save() if f.failSave then return false,'disk full' end; f.saved=U.copy(self.state); return true end
  f.e={peripheral={call=function(name,method)
    eq(name,'store'); assert(method=='size' or method=='list','capacity checks must never mutate storage')
    f.queries=f.queries+1; if f.offline then error('detached') end
    return method=='size' and f.size or U.copy(f.items)
  end}}
  function f:new()
    f.queue=require('autobuilder.core.workflows').new(f.app.state,function() return f.app:save() end,function() return 100 end,7)
    f.service=require('autobuilder.core.infrastructure').new(f.app,f.config,f.e,f.queue)
    return f.service
  end
  function f:fill(n) for i=1,n do self.items[i]={name='minecraft:dirt',count=64} end end
  function f:jobs() local n=0; for _ in pairs(self.queue.state.jobs) do n=n+1 end; return n end
  f:new(); return f
end

test('depot capacity trigger reads storage without effects until threshold is reached',function()
  local f=fixture(); f.service:tick(); eq(f:jobs(),0); eq(f.service.state.freeSlots,5)
  f:fill(3); f.service:tick(); eq(f:jobs(),1); eq(f.service.state.status,'building')
  local j=f.queue.state.jobs[f.service.state.buildId]; eq(j.type,'BUILD'); eq(j.blocks[1].x,10)
  for _=1,5 do f.service:tick() end; eq(f:jobs(),1)
end)

test('depot expansion snapshots its plan and adopts a durable submission after interrupted bookkeeping',function()
  local f=fixture(); f:fill(5)
  local original=f.queue.submit
  function f.queue:submit(...) local job=original(self,...); error('restart after durable queue submission') end
  assert(not pcall(function() f.service:tick() end)); eq(f:jobs(),1)
  f.app.state=U.copy(f.saved); f.config.depotExpansion[1].x=200; f:new(); f.service:tick()
  eq(f:jobs(),1); eq(f.service.state.plan[1].x,10)
  eq(f.queue.state.jobs[f.service.state.buildId].blocks[1].x,10)
end)

test('depot expansion completes only after exact verification and never triggers a second plan',function()
  local f=fixture(); assert(f.service:request()); eq(f:jobs(),1)
  local build=f.queue.state.jobs[f.service.state.buildId]; build.status='completed'; f.service:tick()
  eq(f:jobs(),2); eq(f.service.state.status,'verifying')
  local verify=f.queue.state.jobs[f.service.state.verifyId]; eq(verify.type,'VERIFY'); eq(verify.blocks[1].x,10)
  verify.status='completed'; verify.report={counts={correct=1},entries={}}; f.service:tick()
  eq(f.service.state.status,'completed'); f.app:save(); f.app.state=U.copy(f.saved); f:new()
  f:fill(5); f.service:tick(); assert(f.service:request()); eq(f:jobs(),2)
end)

test('depot verification defects and missing reports remain visible instead of claiming completion',function()
  for _,report in ipairs({{counts={correct=0,wrong=1}}, {counts={correct=0}}, {}}) do
    local f=fixture(); f.service:request(); f.queue.state.jobs[f.service.state.buildId].status='completed'; f.service:tick()
    local verify=f.queue.state.jobs[f.service.state.verifyId]; verify.status='completed'; verify.report=report; f.service:tick()
    eq(f.service.state.status,'blocked'); assert(f.service.state.error); eq(f:jobs(),2)
    local ok,why=f.service:request(); assert(not ok and why); eq(f:jobs(),2)
  end
end)

test('depot verification submission survives a crash without creating another verifier',function()
  local f=fixture(); f.service:request(); f.queue.state.jobs[f.service.state.buildId].status='completed'
  local original=f.queue.submit
  function f.queue:submit(...) local job=original(self,...); error('restart after verification submission') end
  assert(not pcall(function() f.service:tick() end)); eq(f:jobs(),2)
  f.app.state=U.copy(f.saved); f:new(); f.service:tick(); eq(f:jobs(),2)
  eq(f.queue.state.jobs[f.service.state.verifyId].type,'VERIFY')
end)

test('depot monitoring counts partially filled stacks as occupied and refuses protected footprints',function()
  local f=fixture(); f:fill(3); for _,item in pairs(f.items) do item.count=1 end
  f.service:tick(); eq(f.service.state.freeSlots,2); eq(f:jobs(),1)
  f=fixture(); f.config.restrictedAreas={{min={x=10,y=65,z=10},max={x=10,y=65,z=10}}}
  assert(not f.service:request()); eq(f:jobs(),0)
end)

test('invalid and unsupported expansion plans never enter the task queue',function()
  local plans={{},{{x=0,y=0,z=0,name='minecraft:chest',state={}}},{{x=0,y=0,z=0,name='minecraft:stone',state={bad='yes'}}}}
  local duplicate={{x=0,y=0,z=0,name='minecraft:stone',state={}}}; duplicate[2]=U.copy(duplicate[1]); plans[#plans+1]=duplicate
  local huge={}; for i=1,513 do huge[i]={x=i,y=0,z=0,name='minecraft:stone',state={}} end; plans[#plans+1]=huge
  for _,plan in ipairs(plans) do
    local f=fixture(); f.config.depotExpansion=plan; local ok,why=f.service:request()
    assert(not ok and why); eq(f:jobs(),0); eq(f.service.state.status,'blocked')
  end
end)

test('disabled automatic expansion and unreadable storage never dispatch construction',function()
  local f=fixture(); f.config.autoDepotExpansion.enabled=false; f.service:tick(); eq(f.queries,0); eq(f:jobs(),0)
  f.config.autoDepotExpansion.enabled=true; f.offline=true; f.service:tick(); eq(f:jobs(),0); assert(f.service.state.error:find('detached'))
  f.offline=false; f.size=0; f.service:tick(); eq(f:jobs(),0); assert(f.service.state.error)
  f.size=5; f.config.build.enabled=false; f:fill(5); f.service:tick(); eq(f:jobs(),0); assert(f.service.state.error)
end)

test('failed expansion intent checkpoint prevents a job from being dispatched',function()
  local f=fixture(); f.failSave=true
  assert(not pcall(function() f.service:request() end)); eq(f:jobs(),0)
end)
