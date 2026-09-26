local U=require('autobuilder.core.util')
local W=require('tests.build_world')
local N=require('autobuilder.core.navigation')
local function key(p) return p.x..','..p.y..','..p.z end
local function fixture(heading)
  local w=W.new(); w.pose.heading=heading or 'north'; w.fuel=1000
  w.turtle.getFuelLevel=function() return w.fuel end
  for _,action in ipairs({'forward','up','down'}) do
    local move=w.turtle[action]
    w.turtle[action]=function() local ok,err=move(); if ok then w.fuel=w.fuel-1 end; return ok,err end
  end
  for _,suffix in ipairs({'','Up','Down'}) do
    local inspect=w.turtle['inspect'..suffix]
    w.turtle['dig'..suffix]=function()
      local found,b=inspect(); if not found then return false end
      local drops={['minecraft:stone']='minecraft:cobblestone',['minecraft:deepslate']='minecraft:cobbled_deepslate',['minecraft:grass_block']='minecraft:dirt'}
      local drop=w.flint and b.name=='minecraft:gravel' and 'minecraft:flint' or drops[b.name] or b.name; local slot
      for offset=0,15 do
        local s=(w.selected+offset-1)%16+1; local i=w.items[s]
        if not i or i.name==drop and not i.nbt and i.count<64 then slot=s; break end
      end
      if not slot then return false,'inventory full' end
      assert(w.selected~=15 and w.selected~=16,'reserved cargo slot selected')
      local p=U.copy(w.pose)
      if suffix=='Up' then p.y=p.y+1 elseif suffix=='Down' then p.y=p.y-1
      elseif p.heading=='north' then p.z=p.z-1 elseif p.heading=='south' then p.z=p.z+1
      elseif p.heading=='east' then p.x=p.x+1 else p.x=p.x-1 end
      w.items[slot]=w.items[slot] or {name=drop,count=0}; w.items[slot].count=w.items[slot].count+1
      w.blocks[key(p)]=w.falling and U.copy(b) or nil; w.digs=w.digs+1
      if w.crashDig then w.crashDig=false; error('power lost after dig') end
      return true
    end
  end
  return w
end
local function setup(w,task,config,save,pose)
  local Site=require('autobuilder.build.site')
  task=task or {type='PREPARE_SITE',sitePlan=Site.plan(w.pose)}
  config=config or {depot=U.copy(task.sitePlan.start),minimumFuelReserve=5,movementRetries=1}
  pose=pose or U.copy(w.pose); save=save or function() return true end
  local nav=N.new(w.turtle,pose,config,save)
  return Site.new(task,{turtle=w.turtle},config,nav,save),nav,config
end
local function run(engine)
  for _=1,1600 do local ok,err=engine:step(); if not ok then return false,err end; if engine.task.phase=='completed' then return true end end
  return false,'step limit'
end

test('site planner clears bounded pilot volume behind every starting heading',function()
  local Site=require('autobuilder.build.site')
  local origins={north={10,20,32},south={10,20,21},east={1,20,30},west={12,20,30}}
  for h,o in pairs(origins) do
    local p={x=10,y=20,z=30,heading=h,known=true}; local plan=Site.plan(p)
    eq(plan.origin.x,o[1]); eq(plan.origin.y,o[2]); eq(plan.origin.z,o[3]); assert(#plan.points<=512)
    local seen={}; local previous=p
    for _,point in ipairs(plan.points) do
      eq(U.distance(previous,point),1); assert(point.y>=20 and point.y<=22)
      seen[key(point)]=true; previous=point
    end
    eq(U.distance(previous,p),0)
    for x=o[1],o[1]+7 do for z=o[3],o[3]+7 do for y=20,22 do assert(seen[key({x=x,y=y,z=z})]) end end end
    local front=U.copy(p); if h=='north' then front.z=front.z-1 elseif h=='south' then front.z=front.z+1 elseif h=='east' then front.x=front.x+1 else front.x=front.x-1 end
    assert(not seen[key(front)])
  end
end)

test('site engine clears natural terrain, preserves ground and supply chest, returns home',function()
  for _,h in ipairs({'north','south','east','west'}) do
    local w=fixture(h); local m=setup(w); local plan=m.task.sitePlan
    for _,p in ipairs(plan.points) do if U.distance(p,plan.start)>0 then w.blocks[key(p)]={name='minecraft:stone'} end end
    w.blocks['0,1,0']={name='minecraft:bedrock'}
    local chestKeys={north='0,2,-1',south='0,2,1',east='1,2,0',west='-1,2,0'}
    w.blocks[chestKeys[h]]={name='minecraft:chest'}
    w.items[15]={name='minecraft:coal',count=10}; w.items[16]={name='computercraft:wireless_modem_advanced',count=1}
    assert(run(m)); eq(m.task.phase,'completed'); eq(m.task.progress,#plan.points)
    eq(U.distance(w.pose,plan.start),0); eq(w.pose.heading,h); eq(w.blocks['0,1,0'].name,'minecraft:bedrock')
    eq(w.blocks[chestKeys[h]].name,'minecraft:chest')
    eq(w.items[15].count,10); eq(w.items[16].count,1); eq(w.digs,209)
  end
end)

test('site movement recovery advances only after a physically completed checkpointed move',function()
  local w=fixture(); local task={type='PREPARE_SITE',sitePlan=require('autobuilder.build.site').plan(w.pose)}
  local pose=U.copy(w.pose); local savedTask,savedPose
  local m=setup(w,task,nil,function()
    if task.index==2 then error('power lost before waypoint checkpoint') end
    savedTask=U.copy(task); savedPose=U.copy(pose); return true
  end,pose)
  assert(not pcall(function() m:step() end)); eq(w.pose.y,3); eq(savedTask.index,1); assert(savedTask.moveIntent)
  m=setup(w,savedTask,nil,nil,savedPose)
  assert(m:step()); eq(m.task.index,2); eq(w.pose.y,3); assert(run(m)); eq(w.pose.y,2)
  w=fixture(); m=setup(w); local oldMove=w.turtle.up
  w.turtle.up=function() return false,'blocked by entity' end
  assert(not m:step()); eq(m.task.index,1); eq(m.task.progress,0); eq(w.pose.y,2)
  w.turtle.up=oldMove; assert(m:resume()); assert(run(m))
end)

test('site reboot retries an unchanged dig intent but rejects inventory loss',function()
  for _,lost in ipairs({false,true}) do
    local w=fixture(); w.blocks['0,3,0']={name='minecraft:stone'}; w.items[1]={name='minecraft:dirt',count=10}
    local task={type='PREPARE_SITE',sitePlan=require('autobuilder.build.site').plan(w.pose)}
    local m=setup(w,task,nil,function() if task.intent then error('power lost before dig') end; return true end)
    assert(not pcall(function() m:step() end)); eq(w.digs,0)
    if lost then w.items[1].count=9; w.blocks['0,3,0']=nil end
    m=setup(w,U.copy(task))
    if lost then assert(not m:step()); eq(w.digs,0) else assert(run(m)); eq(w.digs,1) end
  end
end)

test('site dig recovery rejects changed item metadata despite positive counts',function()
  local w=fixture(); w.blocks['0,3,0']={name='minecraft:stone'}
  w.items[1]={name='minecraft:dirt',count=1,nbt='original'}
  local task={type='PREPARE_SITE',sitePlan=require('autobuilder.build.site').plan(w.pose)}
  local m=setup(w,task,nil,function() if task.intent then error('power lost before dig') end; return true end)
  assert(not pcall(function() m:step() end))
  w.blocks['0,3,0']=nil; w.items[1].nbt='changed'; w.items[2]={name='minecraft:cobblestone',count=1}
  m=setup(w,U.copy(task)); assert(not m:step()); eq(m.task.blockedCategory,'ambiguous'); eq(w.digs,0)
end)

test('site gravel collects unpredictable flint without spilling into reserved slots',function()
  local w=fixture(); w.flint=true; w.blocks['0,3,0']={name='minecraft:gravel'}
  for s=2,13 do w.items[s]={name='minecraft:dirt',count=64} end
  w.items[14]={name='minecraft:gravel',count=1}; w.items[15]={name='minecraft:coal',count=1}
  local m=setup(w); assert(m:step()); eq(w.digs,1); eq(w.items[1].name,'minecraft:flint'); eq(w.items[16],nil); eq(w.items[15].count,1)
end)

test('site stacks a full gravel volume while retaining safe capacity for flint',function()
  local w=fixture(); local m=setup(w)
  for _,p in ipairs(m.task.sitePlan.points) do
    if U.distance(p,m.task.sitePlan.start)>0 then w.blocks[key(p)]={name='minecraft:gravel'} end
  end
  assert(run(m)); eq(w.digs,209)
  local total,slots=0,0
  for s=1,14 do if w.items[s] then total=total+w.items[s].count; slots=slots+1 end end
  eq(total,209); eq(slots,4); eq(w.items[15],nil); eq(w.items[16],nil)
end)

test('site engine refuses unsafe blocks, restricted targets, low fuel, and full cargo',function()
  for _,b in ipairs({{name='minecraft:chest'},{name='minecraft:water'},{name='minecraft:diamond_ore'},{name='minecraft:stone',state={waterlogged=true}}}) do
    local w=fixture(); w.blocks['0,3,0']=b; local m=setup(w); assert(not run(m)); eq(w.digs,0)
  end
  for _,kind in ipairs({'protected','restricted','fuel','inventory'}) do
    local w=fixture(); w.blocks['0,3,0']={name='minecraft:stone'}; local m,_,c=setup(w)
    if kind=='protected' then c.protectedBlocks={['minecraft:stone']=true}
    elseif kind=='restricted' then c.restrictedAreas={{min={x=0,y=3,z=0},max={x=0,y=3,z=0}}}
    elseif kind=='fuel' then w.fuel=1
    else for s=1,14 do w.items[s]={name='minecraft:dirt',count=64} end end
    assert(not run(m)); eq(w.digs,0)
  end
end)

test('site reservation wait and failed dig checkpoint never remove blocks',function()
  local w=fixture(); w.blocks['0,3,0']={name='minecraft:stone'}; local m,nav=setup(w)
  nav.guard=function() return false,'reservation pending' end
  assert(not m:step()); eq(w.digs,0); eq(m.task.progress,0)
  nav.guard=function() return true end; assert(m:resume()); assert(m:step()); eq(w.digs,1)
  w=fixture(); w.blocks['0,3,0']={name='minecraft:stone'}
  local task={type='PREPARE_SITE',sitePlan=require('autobuilder.build.site').plan(w.pose)}
  m=setup(w,task,nil,function() if task.intent then return false,'disk full' end; return true end)
  pcall(function() m:step() end); eq(w.digs,0)
end)

test('site engine rejects changed plan and incorrect starting pose without hardware digging',function()
  for _,kind in ipairs({'plan','pose','depot','unknown'}) do
    local w=fixture(); local task={type='PREPARE_SITE',sitePlan=require('autobuilder.build.site').plan(w.pose)}
    local pose=U.copy(w.pose); local c={depot=U.copy(w.pose),minimumFuelReserve=0}
    if kind=='plan' then task.sitePlan.points[1].x=10 elseif kind=='pose' then pose.x=1 elseif kind=='depot' then c.depot.x=1 else pose.known=false end
    local ok,m=pcall(setup,w,task,c,nil,pose)
    if ok then assert(not m:step()) end
    eq(w.digs,0)
  end
end)

test('site dig recovery survives reboot exactly once and rejects unexplained disappearance',function()
  local w=fixture(); w.blocks['0,3,0']={name='minecraft:stone'}; w.crashDig=true
  local m,nav=setup(w); assert(not m:step()); eq(w.digs,1); assert(m.task.intent)
  m=setup(w,U.copy(m.task),nil,nil,U.copy(nav.pose)); assert(m:resume()); assert(run(m)); eq(w.digs,1)
  w=fixture(); w.blocks['0,3,0']={name='minecraft:stone'}
  local task={type='PREPARE_SITE',sitePlan=require('autobuilder.build.site').plan(w.pose)}
  m=setup(w,task,nil,function() if task.intent then error('power loss before dig') end; return true end)
  pcall(function() m:step() end); w.blocks['0,3,0']=nil
  m=setup(w,U.copy(task)); assert(not m:step()); eq(w.digs,0)
end)

test('site falling gravel stops after four removals and paused tasks do not dig',function()
  local w=fixture(); w.blocks['0,3,0']={name='minecraft:gravel'}; w.falling=true
  local m=setup(w); assert(not run(m)); eq(w.digs,4); assert(m.task.error:find('falling'))
  w=fixture(); w.blocks['0,3,0']={name='minecraft:stone'}; m=setup(w); m.task.paused=true
  m:step(); eq(w.digs,0); eq(w.pose.y,2)
end)
