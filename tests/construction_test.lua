local U=require('autobuilder.core.util')
local P=require('autobuilder.core.pathfinding')
local function world()
  local w={pose={x=0,y=2,z=0,heading='north',known=true},blocks={},items={},selected=1,places=0,digs=0}
  local vectors={north={0,-1},east={1,0},south={0,1},west={-1,0}}
  local order={'north','east','south','west'}; local index={north=1,east=2,south=3,west=4}
  local function target(suffix)
    local p=U.copy(w.pose)
    if suffix=='Up' then p.y=p.y+1 elseif suffix=='Down' then p.y=p.y-1
    else local v=vectors[p.heading]; p.x=p.x+v[1]; p.z=p.z+v[2] end
    return p
  end
  local t={}; w.turtle=t
  t.getFuelLevel=function() return 'unlimited' end
  t.select=function(s) w.selected=s; return true end
  t.getItemDetail=function(s) return U.copy(w.items[s or w.selected]) end
  t.getItemCount=function(s) local i=w.items[s or w.selected]; return i and i.count or 0 end
  for _,suffix in ipairs({'','Up','Down'}) do
    t['inspect'..suffix]=function() local b=w.blocks[P.key(target(suffix))]; return b~=nil,b and U.copy(b) or 'No block to inspect' end
    t['place'..suffix]=function()
      w.places=w.places+1
      local p=target(suffix); local key=P.key(p); local item=w.items[w.selected]
      if w.blocks[key] or not item or w.failPlace then return false,'cannot place' end
      local state={}; local name=item.name
      if name:match('_log$') then state.axis=suffix~='' and 'y' or (w.pose.heading=='east' or w.pose.heading=='west') and 'x' or 'z' end
      if name:match('_slab$') or name:match('_stairs$') then
        local support=U.copy(p); support.y=support.y+(suffix=='Down' and -1 or 1)
        local far=w.blocks[P.key(support)]~=nil
        local half=(suffix=='Down' and far or suffix=='Up' and not far) and 'bottom' or 'top'
        state.waterlogged=false
        if name:match('_slab$') then state.type=half else state.half=half; state.facing=w.pose.heading; state.shape='straight' end
      end
      w.blocks[key]={name=name,state=state}; item.count=item.count-1
      if item.count==0 then w.items[w.selected]=nil end
      if w.crashPlace then w.crashPlace=false; error('power lost after placement') end
      return true
    end
    t['dig'..suffix]=function()
      local key=P.key(target(suffix)); local b=w.blocks[key]; if not b then return false end
      local slot
      for n=1,14 do if not w.items[n] then slot=n; break end end
      if not slot then return false,'inventory full' end
      w.items[slot]={name=b.name,count=1}; w.blocks[key]=nil; w.digs=w.digs+1
      if w.crashDig then w.crashDig=false; error('power lost after dig') end
      return true
    end
  end
  for action,suffix in pairs({forward='',up='Up',down='Down'}) do
    t[action]=function() local p=target(suffix); if w.blocks[P.key(p)] then return false,'blocked' end; w.pose.x,w.pose.y,w.pose.z=p.x,p.y,p.z; return true end
  end
  t.turnRight=function() w.pose.heading=order[index[w.pose.heading]%4+1]; return true end
  t.turnLeft=function() w.pose.heading=order[(index[w.pose.heading]-2)%4+1]; return true end
  return w
end
local function harness(w,task,kind,config)
  config=config or {minimumFuelReserve=0}; local saved
  local function save() saved=U.copy(task); return true end
  local nav=require('autobuilder.core.navigation').new(w.turtle,U.copy(w.pose),config,save)
  local ex=require('autobuilder.build.'..(kind or 'builder')).new(task,{turtle=w.turtle},config,nav,save)
  return ex,function() return saved end
end
local function run(ex)
  for _=1,100 do ex:step(); if ex.task.phase=='completed' or ex.task.phase=='blocked' then return end end
  error('construction executor did not terminate')
end
local function block(name,state,x,y,z) return {name='minecraft:'..name,state=state or {},x=x or 1,y=y or 0,z=z or 0} end

test('construction classifies unsafe states instead of assuming arbitrary cubes',function()
  local C=require('autobuilder.build.blockstates')
  eq(C.classify('minecraft:stone',{}),'SUPPORTED')
  eq(C.classify('minecraft:oak_log',{axis='x'}),'PARTIALLY_SUPPORTED')
  eq(C.classify('minecraft:oak_slab',{type='double'}),'UNSUPPORTED')
  eq(C.classify('minecraft:oak_stairs',{half='bottom',facing='north',shape='inner_left'}),'UNSUPPORTED')
  eq(C.classify('minecraft:oak_door',{half='lower'}),'UNSUPPORTED')
  eq(C.classify('minecraft:stone',{facing='north'}),'UNSUPPORTED')
  eq(C.classify('mod:unknown',{}),'UNSUPPORTED')
  eq(C.classify('minecraft:bedrock',{}),'SPECIAL_ACQUISITION')
end)
test('builder places actual blocks and skips inspected existing blocks',function()
  local w=world(); w.items[1]={name='minecraft:stone',count=3}; w.blocks['1,0,0']={name='minecraft:stone',state={}}
  local ex=harness(w,{blocks={block('stone'),block('stone',{},2)},phase='setup'})
  run(ex); eq(ex.task.phase,'completed'); eq(ex.task.progress,2); eq(w.places,1); eq(w.blocks['2,0,0'].name,'minecraft:stone'); eq(w.items[1].count,2)
end)
test('builder exposes shortages and resumes after inventory refill',function()
  local w=world(); local ex=harness(w,{blocks={block('stone')}})
  run(ex); eq(ex.task.phase,'blocked'); eq(ex.task.missingItem,'minecraft:stone'); eq(ex.task.missingCount,1); eq(w.places,0)
  w.items[1]={name='minecraft:stone',count=1}; assert(ex:resume()); run(ex); eq(ex.task.phase,'completed')
end)
test('builder uses support and orientation for slabs stairs and log axes',function()
  for _,b in ipairs({block('oak_slab',{type='bottom',waterlogged=false}),block('oak_slab',{type='top',waterlogged=false}),block('oak_stairs',{half='bottom',facing='east',shape='straight',waterlogged=false}),block('oak_log',{axis='x'})}) do
    local w=world(); w.items[1]={name=b.name,count=1}
    w.blocks[b.state.axis and '2,0,0' or b.state.type=='top' and '1,1,0' or '1,-1,0']={name='minecraft:stone',state={}}
    local ex=harness(w,{blocks={b}}); run(ex); eq(ex.task.phase,'completed')
    for k,v in pairs(b.state) do eq(w.blocks['1,0,0'].state[k],v) end
  end
end)
test('oriented blocks without support block without consuming inventory',function()
  local w=world(); w.items[1]={name='minecraft:oak_slab',count=1}
  local ex=harness(w,{blocks={block('oak_slab',{type='bottom'})}}); run(ex)
  eq(ex.task.phase,'blocked'); eq(w.places,0); eq(w.items[1].count,1)
end)
test('construction restart reconciles physical placement without duplicating consumption',function()
  local w=world(); w.items[1]={name='minecraft:stone',count=2}; w.crashPlace=true
  local ex,saved=harness(w,{blocks={block('stone')}})
  pcall(function() run(ex) end); local task=saved(); assert(task.intent)
  task.phase=task.phase=='blocked' and (task.resumePhase or 'work') or task.phase
  ex=harness(w,task); run(ex); eq(task.phase,'completed'); eq(w.places,1); eq(w.items[1].count,1)
end)
test('construction does not replace wrong blocks and rejects restricted targets',function()
  local w=world(); w.items[1]={name='minecraft:stone',count=2}; w.blocks['1,0,0']={name='minecraft:dirt',state={}}
  local ex=harness(w,{blocks={block('stone')}}); run(ex); eq(ex.task.phase,'blocked'); eq(w.digs,0); eq(w.places,0)
  w.blocks={}; ex=harness(w,{blocks={block('stone')}},nil,{minimumFuelReserve=0,restrictedAreas={{min={x=1,y=0,z=0},max={x=1,y=0,z=0}}}})
  run(ex); eq(ex.task.phase,'blocked'); eq(w.places,0)
end)
test('verification reports missing wrong states unsupported and inaccessible distinctly',function()
  local w=world(); w.blocks['1,0,0']={name='minecraft:oak_log',state={axis='z'}}
  local ex=harness(w,{blocks={block('oak_log',{axis='y'}),block('stone',{},2),block('oak_door',{},3),block('stone',{},4)}},'verification',
    {minimumFuelReserve=0,restrictedAreas={{min={x=4,y=0,z=0},max={x=4,y=0,z=0}}}})
  run(ex); eq(ex.task.phase,'completed'); eq(ex.task.report.counts.wrong,1); eq(ex.task.report.counts.missing,1); eq(ex.task.report.counts.unsupported,1); eq(ex.task.report.counts.inaccessible,1)
end)
test('repair replaces bounded wrong blocks and reconciles interrupted dig',function()
  local w=world(); w.items[1]={name='minecraft:stone',count=1}; w.blocks['1,0,0']={name='minecraft:dirt',state={}}; w.crashDig=true
  local ex,saved=harness(w,{blocks={block('stone')}},'repair'); pcall(function() run(ex) end)
  local task=saved(); assert(task.intent); task.phase='work'; ex=harness(w,task,'repair'); run(ex)
  eq(task.phase,'completed'); eq(w.digs,1); eq(w.places,1); eq(w.blocks['1,0,0'].name,'minecraft:stone')
end)
test('repair refuses protected blocks containers and full inventory before digging',function()
  for _,name in ipairs({'minecraft:bedrock','minecraft:chest','minecraft:dirt'}) do
    local w=world(); w.blocks['1,0,0']={name=name,state={}}
    for s=1,14 do w.items[s]={name='minecraft:stone',count=64} end
    local ex=harness(w,{blocks={block('stone')}},'repair'); run(ex); eq(ex.task.phase,'blocked'); eq(w.digs,0); eq(w.blocks['1,0,0'].name,name)
  end
end)
test('construction placement retries stop at a durable bounded limit',function()
  local w=world(); w.items[1]={name='minecraft:stone',count=1}; w.failPlace=true
  local ex=harness(w,{blocks={block('stone')}}); run(ex)
  eq(ex.task.phase,'blocked'); assert(w.places<=3)
  ex:resume(); run(ex); assert(w.places<=3)
end)
test('gravity blocks require a solid base and are verified after placement',function()
  local w=world(); w.items[1]={name='minecraft:sand',count=1}; w.blocks['1,-1,0']={name='minecraft:stone',state={}}
  local ex=harness(w,{blocks={block('sand')}}); run(ex); eq(ex.task.phase,'completed'); eq(w.blocks['1,0,0'].name,'minecraft:sand')
  w=world(); w.items[1]={name='minecraft:gravel',count=1}; ex=harness(w,{blocks={block('gravel')}}); run(ex); eq(ex.task.phase,'blocked'); eq(w.places,0)
end)
test('construction is limited to the target Minecraft 1.20.1 registry',function()
  local C=require('autobuilder.build.blockstates')
  eq(C.classify('minecraft:pale_oak_planks',{}),'UNSUPPORTED')
  eq(C.classify('minecraft:tuff_bricks',{}),'UNSUPPORTED')
  eq(C.classify('minecraft:polished_tuff_stairs',{}),'UNSUPPORTED')
end)
test('checkpoint failure before placement prevents a world mutation',function()
  local w=world(); w.items[1]={name='minecraft:stone',count=1}
  local task={blocks={block('stone')}}
  local save=function() if task.intent then return false,'disk full' end; return true end
  local nav=require('autobuilder.core.navigation').new(w.turtle,U.copy(w.pose),{minimumFuelReserve=0},save)
  local ex=require('autobuilder.build.builder').new(task,{turtle=w.turtle},{},nav,save)
  pcall(function() run(ex) end); eq(w.places,0); ex:step(); eq(w.places,0)
end)
test('ambiguous consumed item without placed block never retries after restart',function()
  local w=world(); w.items[1]={name='minecraft:stone',count=1}
  local task={blocks={block('stone')},index=1,intent={kind='place',index=1,slot=1,item='minecraft:stone',before=2}}
  local ex=harness(w,task); run(ex); eq(task.phase,'blocked'); eq(task.blockedCategory,'ambiguous'); eq(w.places,0)
end)
test('incorrect block state after a successful hardware call is not accepted',function()
  local w=world(); w.items[1]={name='minecraft:oak_log',count=1}; w.blocks['2,0,0']={name='minecraft:stone',state={}}
  local place=w.turtle.place; w.turtle.place=function() local ok=place(); w.blocks['1,0,0'].state.axis='z'; return ok end
  local ex=harness(w,{blocks={block('oak_log',{axis='x'})}}); run(ex); eq(ex.task.phase,'blocked'); eq(ex.task.progress,0); eq(w.places,1)
end)
test('reserved fuel slots cannot satisfy construction inventory demand',function()
  local w=world(); w.items[15]={name='minecraft:stone',count=64}; local ex=harness(w,{blocks={block('stone')}})
  run(ex); eq(ex.task.phase,'blocked'); eq(ex.task.missingItem,'minecraft:stone'); eq(w.places,0)
end)
test('explicit site clearing is gated and removes only specified cells',function()
  local w=world(); w.blocks['1,0,0']={name='minecraft:dirt',state={}}; w.blocks['2,0,0']={name='minecraft:stone',state={}}
  local task={type='CLEAR',blocks={block('air')}}; local ex=harness(w,task,'repair')
  run(ex); eq(task.phase,'blocked'); eq(w.digs,0)
  task={type='CLEAR',blocks={block('air')}}; ex=harness(w,task,'repair',{minimumFuelReserve=0,clearSite=true})
  run(ex); eq(task.phase,'completed'); eq(w.blocks['1,0,0'],nil); eq(w.blocks['2,0,0'].name,'minecraft:stone'); eq(w.digs,1)
end)
test('construction yields immediately when a descent awaits a movement reservation',function()
  local w=world(); w.items[1]={name='minecraft:stone',count=1}; local task={blocks={block('stone')}}
  local nav=require('autobuilder.core.navigation').new(w.turtle,U.copy(w.pose),{minimumFuelReserve=0},function() return true end)
  local original=nav.goTo; local denied=false; local afterDenied=0
  function nav:goTo(target)
    if denied then afterDenied=afterDenied+1 end
    if target.x==1 and target.y==1 and target.z==0 then denied=true; return false,'movement reservation pending' end
    return original(self,target)
  end
  local ex=require('autobuilder.build.builder').new(task,{turtle=w.turtle},{},nav,function() return true end)
  run(ex); eq(task.phase,'blocked'); eq(afterDenied,0); eq(w.places,0)
end)
