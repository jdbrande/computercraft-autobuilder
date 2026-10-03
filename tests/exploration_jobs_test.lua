local U=require('autobuilder.core.util')
local C=require('autobuilder.config')
local function fixture(save)
  local config=C.load({exploration={enabled=true,base={x=0,y=0,z=0},bounds={min={x=0,y=0,z=0},max={x=31,y=2,z=7}},baseProtection={min={x=-1,y=0,z=0},max={x=-1,y=0,z=7}}},minimumFuelReserve=0})
  local state={}; local jobs=require('autobuilder.core.jobs').new(state,save or function() return true end,function() return 1 end,1,config)
  local workers={}
  for id=1,2 do workers[tostring(id)]={id=id,online=true,telemetry={status='idle',fuel=1000,capabilities={mining=true,explorationV1=true},
    explorationHome={depot={x=(id-1)*16-1,y=0,z=(id-1)*7},exitRoute={{x=(id-1)*16,y=0,z=(id-1)*7}},protectedAreas={}},miningResources={}}} end
  return jobs,state,workers,config
end
test('exploration splits same material without spending outstanding quotas twice',function()
  local j,s,w=fixture(); assert(j.requestAcquisition,'missing acquisition interface')
  local g=assert(j:requestAcquisition('minecraft:cobblestone',128,0,'project:a'))
  local a=assert(j:assign(w,{['minecraft:cobblestone']=0})); eq(a.quantity,64)
  local b=assert(j:assign(w,{['minecraft:cobblestone']=0})); eq(b.quantity,64); assert(a.workerId~=b.workerId)
  assert(a.exploration.sectorId~=b.exploration.sectorId)
  a.status='running'; b.status='running'; eq(j:assign(w,{['minecraft:cobblestone']=64}),nil)
  w[tostring(a.workerId)].online=false; eq(j:assign(w,{['minecraft:cobblestone']=64}),nil)
  local p={jobId=a.id,phase='completed',delivered=10,held=0,exploration={result='survey_exhausted',cursor=193,observations={},clearedRouteCount=0}}
  assert(j:progress(a.workerId,p,10)); eq(a.status,'completed'); eq(j:refreshAcquisition(g.id,10).status,'running')
  assert(j:progress(a.workerId,p,10)); eq(a.progress.delivered,10)
  p={jobId=b.id,phase='completed',delivered=64,held=0,exploration={result='quota',cursor=2,observations={},clearedRouteCount=0}}
  assert(j:progress(b.workerId,p,128)); eq(j:refreshAcquisition(g.id,128).status,'completed')
end)
test('candidate planning yields across ticks and continues after failed candidates',function()
  local j,s,w,c=fixture(); w['2']=nil; c.exploration.bounds.max.x=255
  j:requestAcquisition('minecraft:coal',1,0,'budget')
  local E=require('autobuilder.resources.exploration'); local original=E.plan; local calls=0; local seen={}
  E.plan=function(sector,ctx) calls=calls+1; assert(not seen[sector.id],'repeated failed candidate'); seen[sector.id]=true
    if calls<=10 then return nil,'blocked path' end; return original(sector,ctx) end
  local ok,err=pcall(function()
    eq(j:assign(w,{}),nil); assert(calls<=4,'unbounded planning tick')
    local trip; for _=1,10 do trip=j:assign(w,{}); if trip then break end end
    assert(trip,'planner did not resume past failed candidates')
  end)
  E.plan=original; assert(ok,err)
end)
test('an unfueled explorer does not delay another ready worker',function()
  local j,s,w,c=fixture(); c.exploration.bounds.max.x=255; w['1'].telemetry.fuel=0
  j:requestAcquisition('minecraft:coal',1,0,'fuel-ready')
  local trip=assert(j:assign(w,{}),'ready worker was delayed by unfueled candidates'); eq(trip.workerId,2)
end)
test('acquisition reopens when live stock disappears before production starts',function()
  local jobs,state,workers=fixture(); state.workers=workers; state.id=1
  local config=C.load({exploration={enabled=true,base={x=0,y=0,z=0},bounds={min={x=0,y=0,z=0},max={x=31,y=2,z=7}},baseProtection={min={x=-1,y=0,z=0},max={x=-1,y=0,z=7}}},turtleFuelReserveItems={}})
  local stock={}; local app={state=state,save=function() return true end,mining={jobs=jobs,storage={counts=stock,getCount=function(_,item) return stock[item] or 0 end},refresh=function() return true end}}
  local q=require('autobuilder.core.workflows').new(state,app.save,function() return 1 end,1)
  local ps=require('autobuilder.core.production_service').new(app,config,{},q)
  local r=ps:request({['minecraft:glass']=1},'stock-loss'); ps:tick()
  stock['minecraft:sand']=1; ps:tick()
  stock['minecraft:sand']=nil; stock['minecraft:coal']=64; ps:tick()
  assert(not r.acquired,'missing sand falsely ready')
  local g=state.exploration.groups[r.acquisitions['minecraft:sand']]; assert(g.status~='completed')
end)
test('exploration failed ownership save cannot leave a dispatchable trip',function()
  local fail=false; local j,s,w=fixture(function() return not fail,'disk full' end)
  local g=assert(j:requestAcquisition('minecraft:coal',64,0,'coal')); fail=true
  assert(not pcall(j.assign,j,w,{['minecraft:coal']=0})); eq(next(s.jobs),nil); eq(#g.tripIds,0)
end)
test('exploration pauses new trips and retains uncertain owners',function()
  local j,s,w=fixture(); local g=assert(j:requestAcquisition('minecraft:coal',128,0,'coal'))
  local a=assert(j:assign(w,{['minecraft:coal']=0})); a.status='running'
  assert(j:setAcquisitionPaused(g.id,true)); eq(j:assign(w,{['minecraft:coal']=0}),nil); assert(s.jobs[a.id].workerId)
  assert(not j:progress(a.workerId,{jobId=a.id,phase='completed',delivered=0,held=0},0))
  eq(a.status,'running')
end)
test('production requests use exploration groups and wait for physical returns',function()
  local jobs,state,workers=fixture(); state.workers=workers; state.id=1
  local config=C.load({exploration={enabled=true,base={x=0,y=0,z=0},bounds={min={x=0,y=0,z=0},max={x=31,y=2,z=7}},baseProtection={min={x=-1,y=0,z=0},max={x=-1,y=0,z=7}}},turtleFuelReserveItems={}})
  local stock={}; local app={state=state,save=function() return true end,mining={jobs=jobs,storage={counts=stock,getCount=function(_,item) return stock[item] or 0 end},refresh=function() return true end}}
  local q=require('autobuilder.core.workflows').new(state,app.save,function() return 1 end,1)
  local ps=require('autobuilder.core.production_service').new(app,config,{},q)
  local r=ps:request({['minecraft:cobblestone']=128},'project:test'); ps:tick()
  assert(r.acquisitions and r.acquisitions['minecraft:cobblestone'],'production must retain its provider group')
  local trip=assert(jobs:assign(workers,stock)); stock['minecraft:cobblestone']=128; ps:tick()
  assert(not r.acquired,'live stock does not release an outstanding physical trip')
  assert(jobs:progress(trip.workerId,{jobId=trip.id,phase='completed',delivered=64,held=0,exploration={result='quota',cursor=2,observations={},clearedRouteCount=0}},128))
  ps:tick(); assert(r.acquired)
end)
test('small exploration demands share finite quotas across eligible idle workers',function()
  local j,s,w=fixture(); j:requestAcquisition('minecraft:cobblestone',4,0,'small')
  local a=assert(j:assign(w,{})); eq(a.quantity,2)
  local b=assert(j:assign(w,{})); eq(b.quantity,2); assert(a.workerId~=b.workerId)
end)
