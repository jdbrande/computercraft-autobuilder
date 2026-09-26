local U=require('autobuilder.core.util')
local W=require('tests.world')
local function setup(w,task,pose)
  local config={minimumFuelReserve=5,movementRetries=1,depot={x=0,y=0,z=0},restrictedAreas={},
    mining={entry={x=1,y=0,z=0},bounds={min={x=1,y=-1,z=-2},max={x=8,y=1,z=2}},maxSurveySteps=60,pathBudget=1024,returnMargin=8,fuelTarget=100},
    allowedMiningBlocks={['minecraft:stone']=true,['minecraft:iron_ore']=true,['minecraft:deepslate_iron_ore']=true},protectedBlocks={}}
  pose=pose or U.copy(w.pose)
  local n=require('autobuilder.core.navigation').new(w.turtle,pose,config,function() return true end)
  local inv=require('autobuilder.storage.inventory').new(w.turtle,{reservedSlots={15,16}})
  local scan=require('autobuilder.resources.scanner').new({peripheral=w.peripheral},{radius=8,side='left',cooldown=0,ttl=10,maxCost=0},function() return w.time end)
  local miner=require('autobuilder.resources.miner').new(task,{turtle=w.turtle},config,n,inv,scan,function() return true end,function() return w.time end)
  return miner,pose,config
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
