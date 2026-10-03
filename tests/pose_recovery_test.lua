local U=require('autobuilder.core.util')
local S=require('tests.support')
local N=require('autobuilder.core.navigation')
local function origin() return {x=0,y=64,z=0,heading='north',known=true} end
local function pending(action)
  local p=origin();local to=origin()
  if action=='up' then to.y=65 elseif action=='turnRight' then to.heading='east' else to.z=-1 end
  p.pending={action=action,from=origin(),to=to};p.uncertain=true;return p
end

test('GPS settles interrupted translations only at their journaled endpoints',function()
  for _,action in ipairs({'forward','up'}) do for _,endpoint in ipairs({'from','to'}) do
    local p=pending(action);local fix=U.copy(p.pending[endpoint]);local nav=N.new(S.turtle(),p,{},function() return true end)
    assert(nav:reconcile(fix));eq(p.pending,nil);eq(p.uncertain,nil);eq(p.heading,'north');eq(U.distance(p,fix),0)
  end end
  local p=pending('forward');local journal=U.copy(p.pending);local nav=N.new(S.turtle(),p,{},function() return true end)
  local ok,why=nav:reconcile({x=10,y=64,z=0});assert(not ok and why:find('journal',1,true),'unexpected GPS relocation accepted')
  assert(require('autobuilder.factory.factory').equal(p.pending,journal));eq(p.x,0);assert(p.uncertain)
  assert(nav:reconcile({x=10,y=64,z=0},'east'),'explicit operator correction refused')
end)

test('GPS refuses malformed translation intent and retains it on checkpoint failure',function()
  local p=pending('forward');p.pending.to.z=-3
  local nav=N.new(S.turtle(),p,{},function() return true end)
  assert(not nav:reconcile(origin()),'malformed movement envelope accepted')
  p=pending('up');local before=U.copy(p)
  nav=N.new(S.turtle(),p,{},function() return false,'disk full' end)
  assert(not nav:reconcile(p.pending.to));assert(p.pending,'failed checkpoint erased physical intent')
  eq(p.y,before.y);assert(p.uncertain)
end)

test('interrupted turns require coordinates at the turn origin and leave heading unknown',function()
  local p=pending('turnRight');local nav=N.new(S.turtle(),p,{},function() return true end)
  assert(not nav:reconcile({x=3,y=64,z=0}),'turn accepted unrelated GPS relocation')
  assert(nav:reconcile(origin()));eq(p.heading,nil);eq(p.pending,nil);eq(p.known,true)
end)

test('saved controller coverage remains binding when current enforcement is disabled',function()
  local cfg=require('autobuilder.config').load({chunkLoading={enabled=false}})
  local state={workers={},automation={jobs={}}};local chunks=require('autobuilder.core.chunks').new(state,cfg,function() return true end)
  local job={id='task:7:1',workerId=12,loadedArea={minX=0,maxX=0,minZ=0,maxZ=0}}
  state.chunkLedger.leases[job.id]={status='held',workerId=12,area=U.copy(job.loadedArea)}
  assert(chunks:allows(job,{x=8,y=64,z=8},{x=9,y=64,z=8}))
  assert(not chunks:allows(job,{x=15,y=64,z=8},{x=16,y=64,z=8}),'disabled policy bypassed durable coverage')
end)

test('an unresolved heading prevents normal loaded mission effects',function()
  local config=require('autobuilder.config').load({role='worker',controllerId=7,depot=origin()})
  local p=origin();p.heading=nil
  local state={position=p,currentTask={id='task:7:1',type='TRANSPORT',loadedArea={minX=-1,maxX=0,minZ=-1,maxZ=0}}}
  assert(not require('autobuilder.core.chunks').execution(config,state),'unknown heading admitted normal execution')
end)
