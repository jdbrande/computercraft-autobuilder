local U=require('autobuilder.core.util')
local W=require('tests.world')
local function setup(w,task,pose)
  local config={minimumFuelReserve=5,movementRetries=1,depot={x=0,y=0,z=0},restrictedAreas={},
    mining={entry={x=1,y=0,z=0},bounds={min={x=1,y=-1,z=-2},max={x=8,y=1,z=2}},maxSurveySteps=60,pathBudget=1024,returnMargin=8,fuelTarget=100},
    allowedMiningBlocks={['minecraft:stone']=true,['minecraft:iron_ore']=true,['minecraft:deepslate_iron_ore']=true},protectedBlocks={}}
  pose=pose or U.copy(w.pose)
  local n=require('autobuilder.core.navigation').new(w.turtle,pose,config,function() return true end)
  n.workGuard=function() return true end
  local inv=require('autobuilder.storage.inventory').new(w.turtle,{reservedSlots={15,16}})
  local scan=require('autobuilder.resources.scanner').new({peripheral=w.peripheral},{radius=8,side='left',cooldown=0,ttl=10,maxCost=0},function() return w.time end)
  local miner=require('autobuilder.resources.miner').new(task,{turtle=w.turtle},config,n,inv,scan,function() return true end,function() return w.time end)
  return miner,pose,config,n
end
local function run(m,w,limit)
  for _=1,limit or 500 do w.time=w.time+1; local ok,err=m:step(); if not ok then return false,err end; if m.task.phase=='completed' then return true end end
  return false,'step limit'
end

test('miner gathers requested drops, returns to depot, deposits and stops',function()
  local w=W.new(); w.blocks['3,0,0']='minecraft:iron_ore'; w.blocks['4,0,0']='minecraft:deepslate_iron_ore'; w.blocks['5,0,0']='minecraft:iron_ore'
  local m,p=setup(w,{id='mine:1',item='minecraft:raw_iron',quantity=2})
  assert(run(m,w)); eq(w.stock['minecraft:raw_iron'],2); eq(m.task.delivered,2)
  eq(p.x,0); eq(p.y,0); eq(p.z,0); assert(w.blocks['5,0,0'])
end)
test('miner checkpoints survive recreation mid-trip without losing return route',function()
  local w=W.new(); w.blocks['3,0,0']='minecraft:iron_ore'
  local m,p=setup(w,{id='mine:2',item='minecraft:raw_iron',quantity=1})
  for _=1,5 do w.time=w.time+1; assert(m:step()) end
  local restored=setup(w,U.copy(m.task),U.copy(p))
  assert(run(restored,w)); eq(w.stock['minecraft:raw_iron'],1); eq(w.pose.x,0)
end)
test('full depot blocks job without discarding cargo or reporting completion',function()
  local w=W.new(); w.blocks['2,0,0']='minecraft:iron_ore'; w.capacity=0
  local m=setup(w,{id='mine:3',item='minecraft:raw_iron',quantity=1})
  local ok,err=run(m,w); assert(not ok and err); eq(m.task.phase,'blocked'); eq(m.task.delivered,0)
  assert((w.items[1] or {}).count==1)
  w.capacity=100; assert(m:resume()); assert(run(m,w)); eq(w.stock['minecraft:raw_iron'],1)
end)
test('miner will not dig a protected target even if also allowlisted',function()
  local w=W.new(); w.blocks['2,0,0']='minecraft:iron_ore'
  local m,_,c=setup(w,{id='mine:4',item='minecraft:raw_iron',quantity=1})
  c.protectedBlocks['minecraft:iron_ore']=true
  local ok=run(m,w); assert(not ok); eq(#w.dug,0)
end)
test('deposit intent reconciles a crash after hardware drop exactly once',function()
  local w=W.new(); w.stock['minecraft:raw_iron']=3
  local task={id='mine:5',item='minecraft:raw_iron',quantity=3,phase='unload',delivered=0,trail={{x=0,y=0,z=0}},depositIntent={slot=1,name='minecraft:raw_iron',before=3}}
  local m=setup(w,task); assert(run(m,w)); eq(task.delivered,3); eq(w.stock['minecraft:raw_iron'],3)
end)
test('move intent reconciles a completed physical move into the return breadcrumb',function()
  local w=W.new(); w.pose.x=1
  local task={id='mine:6',item='minecraft:raw_iron',quantity=1,phase='return',delivered=0,
    trail={{x=0,y=0,z=0}},pendingMove={from={x=0,y=0,z=0},to={x=1,y=0,z=0},kind='work'}}
  local m=setup(w,task); assert(m:step()); eq(w.pose.x,0); eq(#task.trail,1)
end)

test('fallback strip survey detects adjacent ore along the corridor',function()
  local w=W.new(); w.blocks['3,1,0']='minecraft:iron_ore'
  w.peripheral.getType=function() return nil end
  local m=setup(w,{id='mine:fallback',item='minecraft:raw_iron',quantity=1})
  assert(run(m,w)); eq(w.stock['minecraft:raw_iron'],1)
end)
test('fuel shortage during travel returns to depot instead of blocking far away',function()
  local w=W.new(); local m,_,c=setup(w,{id='mine:fuel',item='minecraft:raw_iron',quantity=1})
  c.mining.entry={x=8,y=0,z=0}; w.fuel=100
  -- Prepare initial trip, then model unexpected consumption outside this program.
  assert(m:step()); assert(m:step()); assert(m:step()); eq(w.pose.x,1)
  w.fuel=15
  run(m,w); eq(w.pose.x,0); eq(m.task.phase,'blocked')
end)

test('failed scanner tool restoration blocks rather than entering fallback',function()
  local w=W.new(); local m,pose,c=setup(w,{id='mine:scanner-fault',item='minecraft:raw_iron',quantity=1,phase='work',trail={{x=0,y=0,z=0},{x=1,y=0,z=0}}})
  w.pose.x=1; pose.x=1
  local inv=require('autobuilder.storage.inventory').new(w.turtle,{})
  local nav=require('autobuilder.core.navigation').new(w.turtle,pose,c,function() return true end)
    nav.workGuard=function() return true end
  local scanner={scan=function() return nil,'tool recovery failed',nil,'hardware' end,invalidate=function() end}
  m=require('autobuilder.resources.miner').new(m.task,{turtle=w.turtle},c,nav,inv,scanner,function() return true end,function() return 0 end)
  local ok=m:step(); assert(not ok); eq(m.task.phase,'blocked'); eq(w.pose.x,1)
end)

test('inventory pressure unloads incidental items then resumes the same mining job',function()
  local w=W.new(); w.blocks['4,0,0']='minecraft:iron_ore'; w.blocks['5,0,0']='minecraft:iron_ore'
  local m=setup(w,{id='mine:inventory',item='minecraft:raw_iron',quantity=2})
  for _=1,4 do w.time=w.time+1; assert(m:step()) end
  for slot=1,13 do w.items[slot]={name='minecraft:cobblestone',count=64} end
  assert(run(m,w,700)); eq(w.stock['minecraft:raw_iron'],2); eq(w.stock['minecraft:cobblestone'],832); eq(w.pose.x,0)
end)

test('miner replans a cached route around a newly obstructed cell',function()
  local w=W.new(); w.blocks['5,0,0']='minecraft:iron_ore'
  local m=setup(w,{id='mine:reroute',item='minecraft:raw_iron',quantity=1})
  for _=1,30 do w.time=w.time+1; assert(m:step()); if w.pose.x==2 and m.task.target then break end end
  eq(w.pose.x,2); w.blocks['3,0,0']='minecraft:bedrock'
  assert(run(m,w)); eq(w.stock['minecraft:raw_iron'],1); eq(w.blocks['3,0,0'],'minecraft:bedrock')
end)

test('miner reserves destination before digging and resumes after reservation is granted',function()
  for _,target in ipairs({{x=2,y=0,z=0},{x=1,y=1,z=0},{x=1,y=-1,z=0}}) do
    local w=W.new(); w.pose.x=1
    local key=require('autobuilder.core.pathfinding').key(target); w.blocks[key]='minecraft:iron_ore'
    local task={id='mine:reserve',item='minecraft:raw_iron',quantity=1,phase='work',target=target,trail={{x=0,y=0,z=0},{x=1,y=0,z=0}}}
    local _,pose,c=setup(w,task)
    local nav=require('autobuilder.core.navigation').new(w.turtle,pose,c,function() return true end)
    nav.workGuard=function() return true end
    local granted=false
    nav.guard=function(_,to) eq(to.x,target.x); eq(to.y,target.y); eq(to.z,target.z); return granted,'movement reservation pending' end
    nav.workGuard=function(to) return nav.guard(pose,to) end
    local inv=require('autobuilder.storage.inventory').new(w.turtle,{reservedSlots={15,16}})
    local scan={invalidate=function() end}
    local miner=require('autobuilder.resources.miner').new(task,{turtle=w.turtle},c,nav,inv,scan,function() return true end,function() return 0 end)
    assert(not miner:step()); eq(w.blocks[key],'minecraft:iron_ore'); eq(#w.dug,0); eq(task.phase,'blocked')
    granted=true; assert(miner:resume()); assert(miner:step())
    eq(w.blocks[key],nil); eq(#w.dug,1); eq(pose.x,target.x); eq(pose.y,target.y)
  end
end)

test('fallback survey covers northward rows and westward rows from either entry corner',function()
  for _,case in ipairs({
    {entry={x=1,y=0,z=2},ore={x=5,y=1,z=-1}},
    {entry={x=8,y=0,z=-2},ore={x=4,y=1,z=1}},
  }) do
    local w=W.new(); w.peripheral.getType=function() return nil end
    local key=require('autobuilder.core.pathfinding').key(case.ore); w.blocks[key]='minecraft:iron_ore'
    local m,_,c=setup(w,{id='mine:corners',item='minecraft:raw_iron',quantity=1})
    c.mining.entry=case.entry
    assert(run(m,w,700)); eq(w.stock['minecraft:raw_iron'],1)
  end
end)
local function explorer(w,task,save,pose)
  task=task or {id='mine:explore',item='minecraft:raw_iron',quantity=2,exploration={version=1,groupId='acquire:1',sectorId='0,0,0',
    depot={x=0,y=0,z=0},bounds={min={x=2,y=0,z=0},max={x=3,y=1,z=1}},envelope={min={x=0,y=0,z=0},max={x=8,y=3,z=3}},
    entry={x=2,y=0,z=0},exitRoute={},route={{x=1,y=0,z=0},{x=2,y=0,z=0}},cursor=1,protectedAreas={}}}
  local _,p,c=setup(w,task,pose); c.mining.mode='explore'
  c.mining.bounds={min={x=99,y=0,z=0},max={x=100,y=0,z=0}}
  local n=require('autobuilder.core.navigation').new(w.turtle,p,c,save or function() return true end)
  n.workGuard=function() return true end
  local inv=require('autobuilder.storage.inventory').new(w.turtle,{reservedSlots={15,16}})
  local scan=require('autobuilder.resources.scanner').new({peripheral=w.peripheral},{radius=8,side='left',cooldown=0,ttl=10,maxCost=0},function() return w.time end)
  return require('autobuilder.resources.miner').new(task,{turtle=w.turtle},c,n,inv,scan,save or function() return true end,function() return w.time end),p,c
end
test('explorer digs assigned route and returns a measured partial survey result',function()
  local w=W.new(); w.blocks['1,0,0']='minecraft:stone'; w.blocks['3,1,1']='minecraft:iron_ore'
  local m=explorer(w); assert(run(m,w,2000)); eq(m.task.delivered,1); eq(w.pose.x,0)
  eq(m.task.explorationProgress.result,'survey_exhausted'); eq(w.stock['minecraft:raw_iron'],1)
end)
test('explorer skips forbidden survey cells and can return from a reconciled outward block',function()
  local w=W.new(); w.blocks['3,0,0']='minecraft:bedrock'; local m=explorer(w)
  assert(run(m,w,2000)); eq(w.pose.x,0); eq(w.blocks['3,0,0'],'minecraft:bedrock')
  w=W.new(); m=explorer(w); for _=1,5 do assert(m:step()) end
  m.task.resumePhase='work'; m.task.phase='blocked'; m.task.error='no safe path'
  assert(m:requestReturn()); assert(run(m,w)); eq(w.pose.x,0)
  w=W.new(); m=explorer(w); m.task.phase='blocked'; m.task.resumePhase='return'; m.task.error='obstructed return'
  assert(m:requestReturn()); assert(not m:step()); eq(m.task.phase,'blocked')
end)
test('explorer does not revisit covered survey cells after clipped expansion',function()
  local w=W.new(); local m=explorer(w); local task=U.copy(m.task)
  task.exploration.surveyed={{x=3,y=0,z=0}}; w.peripheral.getType=function() return nil end
  m=explorer(w,task)
  for _=1,10 do assert(m:step()); if task.phase=='work' then break end end
  assert(m:step()); assert(task.survey>=3,'survey selected already covered cell')
  assert(run(m,w,2000))
end)
test('explorer inspection fallback surveys all layers and respects safe return request',function()
  local w=W.new(); w.peripheral.getType=function() return nil end; w.blocks['3,1,1']='minecraft:iron_ore'
  local m=explorer(w); assert(run(m,w,2000)); eq(m.task.delivered,1)
  w=W.new(); m=explorer(w); for _=1,4 do assert(m:step()) end
  assert(m:requestReturn()); assert(run(m,w)); eq(m.task.explorationProgress.result,'paused'); eq(w.pose.x,0)
end)
test('exploration dig intent reconciles a crash after dig without another dig',function()
  local w=W.new(); w.blocks['1,0,0']='minecraft:stone'; local saved,pp
  local task={id='mine:crash',item='minecraft:raw_iron',quantity=1,exploration={version=1,groupId='acquire:1',sectorId='0,0,0',depot={x=0,y=0,z=0},
    bounds={min={x=2,y=0,z=0},max={x=2,y=0,z=0}},envelope={min={x=0,y=0,z=0},max={x=2,y=0,z=0}},entry={x=2,y=0,z=0},route={{x=1,y=0,z=0},{x=2,y=0,z=0}},exitRoute={},protectedAreas={},cursor=1}}
  local m,p=explorer(w,task,function() saved=U.copy(task); if pp then saved.pose=U.copy(pp) end; return true end); pp=p
  local dig=w.turtle.dig; w.turtle.dig=function() dig(); error('power cut') end
  for _=1,10 do local ok=pcall(m.step,m); if not ok or task.phase=='blocked' then break end end
  assert(saved.digIntent,'dig intent must precede hardware')
  w.turtle.dig=dig; local restored=explorer(w,saved,nil,saved.pose or p)
  if restored.task.phase=='blocked' then assert(restored:resume()) end
  assert(run(restored,w)); eq(#w.dug,1); eq(w.stock['minecraft:cobblestone'],1)
end)
test('explorer traverses declared protected exits but never excavates them',function()
  for _,blocked in ipairs({false,true}) do
    local w=W.new(); local m,p,c=explorer(w)
    local g=m.task.exploration; g.exitRoute={{x=1,y=0,z=0}}; g.route={{x=2,y=0,z=0}}
    c.restrictedAreas={{min={x=1,y=0,z=0},max={x=1,y=0,z=0}}}; g.protectedAreas=U.copy(c.restrictedAreas)
    local nav=require('autobuilder.core.navigation').new(w.turtle,p,c,function() return true end)
    nav.workGuard=function() return true end
    local inv=require('autobuilder.storage.inventory').new(w.turtle,{reservedSlots={15,16}})
    local scan={scan=function() return nil,'no scanner' end,invalidate=function() end}
    m=require('autobuilder.resources.miner').new(m.task,{turtle=w.turtle},c,nav,inv,scan,function() return true end,function() return 0 end)
    if blocked then w.blocks['1,0,0']='minecraft:stone' end
    assert(run(m,w,2000)); eq(w.pose.x,0); eq(#w.dug,0)
    eq(m.task.explorationProgress.result,blocked and 'route_blocked' or 'survey_exhausted')
  end
end)
test('explorer unloading existing requested cargo completes with a valid terminal result',function()
  local w=W.new(); w.items[1]={name='minecraft:raw_iron',count=2}
  local m=explorer(w); assert(run(m,w)); eq(w.pose.x,0); eq(m.task.delivered,2)
  eq(m.task.explorationProgress.result,'quota')
end)
test('exploration low fuel returns a partial trip and refuses obstructed return excavation',function()
  local w=W.new(); local m=explorer(w)
  for _=1,5 do assert(m:step()) end
  assert(w.pose.x>0); w.fuel=#m.task.trail+13
  assert(run(m,w)); eq(m.task.explorationProgress.result,'fuel'); eq(w.pose.x,0)
  w=W.new(); m=explorer(w); for _=1,5 do assert(m:step()) end
  assert(m:requestReturn()); w.blocks['1,0,0']='minecraft:stone'
  local ok,why=run(m,w); assert(not ok and why:find('return route obstructed')); eq(#w.dug,0)
end)
test('exploration refuses waterlogged route blocks without digging',function()
  local w=W.new(); w.blocks['1,0,0']='minecraft:stone'
  local inspect=w.turtle.inspect
  w.turtle.inspect=function() local found,b=inspect(); if found and b.name=='minecraft:stone' then b.state.waterlogged=true end; return found,b end
  local m=explorer(w); assert(run(m,w)); eq(m.task.explorationProgress.result,'route_blocked'); eq(#w.dug,0)
end)


test('miners need separate mutation permission and resume a delayed grant without digging early',function()
  local w=W.new();w.pose.x=1;w.blocks['2,0,0']='minecraft:iron_ore'
  local task={id='mine:mutation',item='minecraft:raw_iron',quantity=1,phase='work',target={x=2,y=0,z=0},trail={{x=0,y=0,z=0},{x=1,y=0,z=0}}}
  local m,pose,c,nav=setup(w,task);local allowed=false;local released=0
  nav.guard=function() return true end
  nav.workGuard=function(target) eq(target.x,2);return allowed,'movement reservation pending' end
  nav.workDone=function() released=released+1 end
  assert(not m:step());eq(#w.dug,0);eq(w.blocks['2,0,0'],'minecraft:iron_ore')
  allowed=true;assert(m:resume());assert(m:step());eq(#w.dug,1);eq(released,1)
end)


test('explorers retain bounded inspection and scanner resource sightings with reconciled clear travel',function()
  for _,scanner in ipairs({false,true}) do
    local w=W.new();if not scanner then w.peripheral.getType=function() return nil end end
    w.blocks['3,1,1']='minecraft:iron_ore'
    local m=explorer(w);assert(run(m,w,2000));eq(m.task.delivered,1)
    local found=false;for _,p in ipairs(m.task.explorationProgress.observations) do
      if p.name=='minecraft:iron_ore' and p.x==3 and p.y==1 and p.z==1 then found=true end
    end
    assert(found,'resource sighting lost');local clear={}
    for _,p in ipairs(m.task.explorationProgress.evidence or {}) do if p.kind=='clear' then clear[require('autobuilder.core.pathfinding').key(p)]=true end end
    assert(clear['1,0,0'] and clear['3,1,1'] and clear['0,0,0'],'reconciled travel evidence missing')
    assert(require('autobuilder.resources.exploration').report(m.task.explorationProgress,m.task.exploration))
  end
end)

test('explorers retain liquid protected and failed-dig evidence without inventing cleared cells',function()
  for _,case in ipairs({{name='minecraft:water',kind='liquid'},{name='minecraft:lava',kind='liquid'},
    {name='minecraft:stone',waterlogged=true,kind='liquid'},{name='minecraft:bedrock',kind='protected'},
    {name='minecraft:stone',failed=true,kind='blocked'}}) do
    local w=W.new();w.blocks['1,0,0']=case.name
    if case.waterlogged then local inspect=w.turtle.inspect;w.turtle.inspect=function()
      local ok,b=inspect();if ok then b.state.waterlogged=true end;return ok,b
    end end
    if case.failed then w.turtle.dig=function() return false,'tool cannot dig this block' end end
    local m=explorer(w);assert(run(m,w,2000));eq(#w.dug,0)
    local found;for _,p in ipairs(m.task.explorationProgress.evidence or {}) do if p.x==1 and p.y==0 and p.z==0 then found=p end end
    assert(found,'obstruction evidence missing');eq(found.kind,case.kind);eq(found.name,case.name);assert(found.reason)
  end
end)

test('exploration clear evidence follows movement reconciliation and excludes reservation denial',function()
  local w=W.new();local base=explorer(w);local task=U.copy(base.task)
  task.phase='return';task.trail={{x=0,y=0,z=0}};task.pendingMove={from={x=0,y=0,z=0},to={x=1,y=0,z=0},kind='work'}
  w.pose.x=1;local m=explorer(w,task,nil,U.copy(w.pose));assert(m:step())
  local found=false;for _,p in ipairs(task.explorationProgress.evidence or {}) do if p.x==1 and p.kind=='clear' then found=true end end
  assert(found,'reconciled move was not retained')
  w=W.new();m=explorer(w);w.turtle.forward=function() return false,'movement reservation pending: worker occupies destination' end
  local ok=run(m,w);assert(not ok);eq(w.pose.x,0)
  for _,p in ipairs(m.task.explorationProgress.evidence or {}) do assert(p.x~=1,'denied move became geological evidence') end
end)
