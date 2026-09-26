local U=require('autobuilder.core.util')
local function fixture(blocks)
  local w={pose={x=0,y=4,z=0,heading='north',known=true},blocks={},items={},selected=1,places=0}
  local vectors={north={0,-1},east={1,0},south={0,1},west={-1,0}}; local order={'north','east','south','west'}; local index={north=1,east=2,south=3,west=4}
  local function key(p) return p.x..','..p.y..','..p.z end
  local function target(suffix)
    local p=U.copy(w.pose)
    if suffix=='Down' then p.y=p.y-1 elseif suffix=='Up' then p.y=p.y+1 else local d=vectors[p.heading]; p.x=p.x+d[1]; p.z=p.z+d[2] end
    return p
  end
  local function connected(name) return name:match('_pane$') or name=='minecraft:iron_bars' or name:match('_fence$') end
  local function refresh()
    for k,b in pairs(w.blocks) do
      if connected(b.name) then
        local x,y,z=k:match('([^,]+),([^,]+),([^,]+)'); x,y,z=tonumber(x),tonumber(y),tonumber(z)
        for dir,v in pairs(vectors) do local n=w.blocks[key({x=x+v[1],y=y,z=z+v[2]})]; b.state[dir]=n~=nil and (n.name==b.name or n.name=='minecraft:stone') end
      end
    end
  end
  local t={}; w.t=t
  t.getFuelLevel=function() return 'unlimited' end
  t.select=function(s) w.selected=s; return true end
  t.getItemDetail=function(s) return U.copy(w.items[s or w.selected]) end
  t.getItemCount=function(s) local i=w.items[s or w.selected]; return i and i.count or 0 end
  for _,suffix in ipairs({'','Up','Down'}) do
    t['inspect'..suffix]=function() refresh(); local b=w.blocks[key(target(suffix))]; return b~=nil,U.copy(b) end
    t['place'..suffix]=function()
      local p=target(suffix); local i=w.items[w.selected]; if not i or w.blocks[key(p)] then return false end
      local state={}; local name=i.name
      if name:match('_door$') then
        local upper={x=p.x,y=p.y+1,z=p.z}; if w.blocks[key(upper)] or key(w.pose)==key(upper) then return false,'upper door cell occupied' end
        if not w.blocks[key({x=p.x,y=p.y-1,z=p.z})] then return false,'missing floor' end
        state={half='lower',facing=w.pose.heading,hinge='left',open=false,powered=false}
        local top=U.copy(state); top.half='upper'; w.blocks[key(upper)]={name=name,state=top}
        if w.badPair then w.blocks[key(upper)]=nil end
      elseif name:match('_slab$') then state={type=suffix=='Down' and 'bottom' or 'top',waterlogged=false}
      elseif connected(name) then state={north=false,east=false,south=false,west=false,waterlogged=false}
      elseif name=='minecraft:lantern' or name=='minecraft:soul_lantern' then state={hanging=suffix=='Up',waterlogged=false}
      elseif name=='minecraft:ladder' then state={facing=order[(index[w.pose.heading]+1)%4+1],waterlogged=false}
      end
      w.blocks[key(p)]={name=name,state=state}; i.count=i.count-1; if i.count==0 then w.items[w.selected]=nil end; w.places=w.places+1; refresh()
      if w.crash then w.crash=false; error('power lost after place') end
      return true
    end
  end
  for action,suffix in pairs({forward='',up='Up',down='Down'}) do t[action]=function() local p=target(suffix); if w.blocks[key(p)] then return false,'blocked' end; w.pose.x,w.pose.y,w.pose.z=p.x,p.y,p.z; return true end end
  t.turnRight=function() w.pose.heading=order[index[w.pose.heading]%4+1]; return true end
  t.turnLeft=function() w.pose.heading=order[(index[w.pose.heading]+2)%4+1]; return true end
  local task={blocks=blocks}; local saved
  local function create(existing,config,mode)
    task=existing or task; config=config or {minimumFuelReserve=0}
    local function save() saved=U.copy(task); return true end
    local nav=require('autobuilder.core.navigation').new(t,U.copy(w.pose),config,save)
    if w.gated then nav.guard=function() if (w.allowance or 0)<1 then return false,'movement reservation pending' end; w.allowance=w.allowance-1; return true end end
    return require('autobuilder.build.builder').new(task,{turtle=t},config,nav,save,mode)
  end
  return w,task,create,function() return U.copy(saved) end
end
local function block(name,state,x,y,z) return {name='minecraft:'..name,state=state or {},x=x or 3,y=y or 1,z=z or 0} end
local function door(half) return block('oak_door',{half=half,facing='north',hinge='left',open='false',powered='false'},3,half=='upper' and 2 or 1,0) end
local function run(ex)
  for _=1,100 do ex:step(); if ex.task.phase=='completed' or ex.task.phase=='blocked' then return end end; error('advanced placement did not terminate')
end
test('complete closed door pair uses one item without occupying its upper cell',function()
  local w,task,new=fixture({door('lower'),door('upper')}); w.items[1]={name='minecraft:oak_door',count=2}; w.blocks['3,0,0']={name='minecraft:stone',state={}}
  run(new()); eq(task.phase,'completed'); eq(task.progress,2); eq(w.places,1); eq(w.items[1].count,1); eq(w.blocks['3,2,0'].state.half,'upper')
end)
test('door placement recovery verifies both halves and never consumes twice',function()
  local w,task,new,saved=fixture({door('lower'),door('upper')}); w.items[1]={name='minecraft:oak_door',count=2}; w.blocks['3,0,0']={name='minecraft:stone',state={}}; w.crash=true
  run(new()); task=saved(); assert(task.intent); task.phase='work'; local ex=new(task); run(ex); eq(task.phase,'completed'); eq(w.places,1); eq(w.items[1].count,1)
  w,task,new=fixture({door('lower'),door('upper')}); w.items[1]={name='minecraft:oak_door',count=2}; w.blocks['3,0,0']={name='minecraft:stone',state={}}; w.badPair=true
  run(new()); eq(task.phase,'blocked'); eq(task.progress,0); assert(task.intent); eq(w.places,1)
end)
test('upper door without lower and protected upper space never place an item',function()
  local w,task,new=fixture({door('upper')}); w.items[1]={name='minecraft:oak_door',count=2}; run(new()); eq(task.phase,'blocked'); eq(w.places,0)
  w,task,new=fixture({door('lower'),door('upper')}); w.items[1]={name='minecraft:oak_door',count=2}; w.blocks['3,0,0']={name='minecraft:stone',state={}}
  run(new(nil,{minimumFuelReserve=0,restrictedAreas={{min={x=3,y=2,z=0},max={x=3,y=2,z=0}}}})); eq(task.phase,'blocked'); eq(w.places,0)
end)
test('carpet placement requires floor and preserves block state checks',function()
  local w,task,new=fixture({block('red_carpet')}); w.items[1]={name='minecraft:red_carpet',count=1}; w.blocks['3,0,0']={name='minecraft:stone',state={}}
  run(new()); eq(task.phase,'completed'); eq(w.blocks['3,1,0'].name,'minecraft:red_carpet')
  w,task,new=fixture({block('red_carpet')}); w.items[1]={name='minecraft:red_carpet',count=1}; run(new()); eq(task.phase,'blocked'); eq(w.places,0)
end)
test('panes and fences verify final connections after all neighboring cells are placed',function()
  for _,name in ipairs({'glass_pane','oak_fence'}) do
    local a=block(name,{north='false',south='false',west='false',east='true',waterlogged='false'})
    local b=block(name,{north='false',south='false',west='true',east='false',waterlogged='false'},4)
    local w,task,new=fixture({a,b}); w.items[1]={name='minecraft:'..name,count=2}
    w.blocks['3,0,0']={name='minecraft:stone',state={}}; w.blocks['4,0,0']={name='minecraft:stone',state={}}
    run(new()); eq(task.phase,'completed'); eq(task.progress,2); eq(task.report.counts.correct,2); eq(w.places,2)
  end
end)
test('wrong final pane connections are reported and cannot become completed',function()
  local w,task,new=fixture({block('glass_pane',{north='false',south='false',west='false',east='true',waterlogged='false'})}); w.items[1]={name='minecraft:glass_pane',count=1}; w.blocks['3,0,0']={name='minecraft:stone',state={}}
  run(new()); eq(task.phase,'blocked'); eq(task.progress,0); eq(w.places,1)
end)
test('lantern and ladder strategies verify support facing and hanging state',function()
  for _,case in ipairs({{block('lantern',{hanging='false',waterlogged='false'}),'3,0,0'}, {block('soul_lantern',{hanging='true',waterlogged='false'}),'3,2,0'}, {block('ladder',{facing='west',waterlogged='false'}),'4,1,0'}}) do
    local w,task,new=fixture({case[1]}); w.items[1]={name=case[1].name,count=1}; w.blocks[case[2]]={name='minecraft:stone',state={}}
    run(new()); eq(task.phase,'completed'); eq(w.places,1)
  end
end)
test('ambiguous door states and unsupported paired furniture remain explicit',function()
  local C=require('autobuilder.build.blockstates'); eq(C.classify('minecraft:oak_door',{half='lower'}),'UNSUPPORTED')
  eq(C.classify('minecraft:oak_door',{half='lower',facing='north',hinge='right',open='false',powered='false'}),'UNSUPPORTED')
  eq(C.classify('minecraft:red_bed',{part='foot',facing='north'}),'UNSUPPORTED')
  eq(C.classify('minecraft:glass_pane',{east='true',waterlogged='true'}),'UNSUPPORTED')
end)
test('connected placement resumes between cells and rechecks changed earlier neighbors',function()
  local a=block('glass_pane',{north='false',south='false',west='false',east='true',waterlogged='false'})
  local b=block('glass_pane',{north='false',south='false',west='true',east='false',waterlogged='false'},4)
  local w,task,new,saved=fixture({a,b}); w.items[1]={name='minecraft:glass_pane',count=2}; w.blocks['3,0,0']={name='minecraft:stone',state={}}; w.blocks['4,0,0']={name='minecraft:stone',state={}}
  local ex=new(); ex:step(); eq(task.progress,0); eq(task.report.counts.pending,1)
  task=saved(); ex=new(task); run(ex); eq(task.phase,'completed'); eq(w.places,2); eq(task.progress,2)
  a.state.east='false'; w,task,new=fixture({a,block('stone',{},4)}); w.items[1]={name='minecraft:glass_pane',count=1}; w.items[2]={name='minecraft:stone',count=1}; w.blocks['3,0,0']={name='minecraft:stone',state={}}
  run(new()); eq(task.phase,'blocked'); eq(task.progress,1); eq(task.report.counts.pending,1)
end)
test('door hinge clearance and contradictory paired blueprint prevent placement',function()
  local w,task,new=fixture({door('lower'),door('upper')}); w.items[1]={name='minecraft:oak_door',count=2}; w.blocks['3,0,0']={name='minecraft:stone',state={}}; w.blocks['4,1,0']={name='minecraft:stone',state={}}
  run(new()); eq(task.phase,'blocked'); eq(w.places,0)
  local upper=door('upper'); upper.state.facing='south'; w,task,new=fixture({door('lower'),upper}); w.items[1]={name='minecraft:oak_door',count=2}; w.blocks['3,0,0']={name='minecraft:stone',state={}}
  run(new()); eq(task.phase,'blocked'); eq(w.places,0)
end)
test('door orientation is verified for all horizontal directions',function()
  for _,facing in ipairs({'north','east','south','west'}) do
    local lower,upper=door('lower'),door('upper'); lower.state.facing=facing; upper.state.facing=facing
    local w,task,new=fixture({lower,upper}); w.items[1]={name='minecraft:oak_door',count=1}; w.blocks['3,0,0']={name='minecraft:stone',state={}}
    run(new()); eq(task.phase,'completed'); eq(w.blocks['3,1,0'].state.facing,facing)
  end
end)
test('region connection deferral completes physical work but final verification checks neighbors',function()
  local a=block('glass_pane',{north='false',south='false',west='false',east='true',waterlogged='false'})
  local b=block('glass_pane',{north='false',south='false',west='true',east='false',waterlogged='false'},4)
  local w,task,new=fixture({a}); task.deferConnections=true; w.items[1]={name='minecraft:glass_pane',count=2}; w.blocks['3,0,0']={name='minecraft:stone',state={}}; w.blocks['4,0,0']={name='minecraft:stone',state={}}
  run(new()); eq(task.phase,'completed'); eq(task.progress,1); eq(task.report.counts.pending,1); eq(task.report.counts.correct,nil)
  local early={blocks={a},deferConnections=true}; run(new(early,nil,'verify')); eq(early.report.counts.wrong,1)
  local nextRegion={blocks={b},deferConnections=true}; run(new(nextRegion)); eq(nextRegion.phase,'completed')
  local verify={blocks={a,b},deferConnections=true}; run(new(verify,nil,'verify')); eq(verify.phase,'completed'); eq(verify.report.counts.correct,2); eq(w.places,2)
end)
local function gatedRun(w,task,new,saved,reboot)
  w.gated=true
  local ex=new(task)
  for tick=1,240 do
    w.allowance=1
    if task.phase=='blocked' then
      assert(tostring(task.error):find('reservation',1,true),task.error)
      assert(ex:resume())
    end
    ex:step()
    if task.phase=='completed' then return task end
    if reboot then task=saved(); ex=new(task) end
  end
  error('one-step reservation traversal did not converge; pose='..w.pose.x..','..w.pose.y..','..w.pose.z..' index='..tostring(task.index))
end
test('door verification waits for paired inspection reservations through every reboot',function()
  for _,reboot in ipairs({false,true}) do
    local lower,upper=door('lower'),door('upper')
    local w,task,new,saved=fixture({lower,upper})
    w.blocks['3,1,0']={name=lower.name,state=U.copy(lower.state)}
    w.blocks['3,2,0']={name=upper.name,state=U.copy(upper.state)}
    local function verify(t) return new(t,nil,'verify') end
    task=gatedRun(w,task,verify,saved,reboot)
    eq(task.report.counts.correct,2); eq(task.report.counts.inaccessible,nil); eq(w.places,0)
  end
end)
test('fixed construction waypoints converge with one adjacent reservation granted per tick',function()
  for _,reboot in ipairs({false,true}) do
    local w,task,new,saved=fixture({block('stone',{},1,0,0),block('stone',{},2,1,0)}); w.pose.y=2; w.items[1]={name='minecraft:stone',count=2}
    task=gatedRun(w,task,new,saved,reboot); eq(task.phase,'completed'); eq(w.places,2); eq(task.progress,2)
  end
end)
test('support inspection resumes its return stage across reservation yields and reboot',function()
  for _,reboot in ipairs({false,true}) do
    local w,task,new,saved=fixture({block('oak_slab',{type='bottom',waterlogged='false'},1,0,0)}); w.pose.y=2; w.items[1]={name='minecraft:oak_slab',count=1}; w.blocks['1,-1,0']={name='minecraft:stone',state={}}
    task=gatedRun(w,task,new,saved,reboot); eq(task.phase,'completed'); eq(w.places,1); eq(task.progress,1)
  end
end)
test('door pair and hinge inspections resume before stand approach after reservation yields',function()
  for _,reboot in ipairs({false,true}) do
    local w,task,new,saved=fixture({door('lower'),door('upper')}); w.items[1]={name='minecraft:oak_door',count=2}; w.blocks['3,0,0']={name='minecraft:stone',state={}}
    task=gatedRun(w,task,new,saved,reboot); eq(task.phase,'completed'); eq(w.places,1); eq(w.items[1].count,1); eq(task.progress,2)
  end
end)
test('top slab side-approach waypoints survive collision and one-step reservation yields',function()
  local w,task,new,saved=fixture({block('oak_slab',{type='top',waterlogged='false'},1,0,0)}); w.pose.y=2; w.items[1]={name='minecraft:oak_slab',count=1}; w.blocks['1,1,0']={name='minecraft:stone',state={}}
  task=gatedRun(w,task,new,saved,true); eq(task.phase,'completed'); eq(w.places,1); eq(w.blocks['1,0,0'].state.type,'top')
end)
test('paired placement power loss invalidates pre-placement inspection cache under gated recovery',function()
  local w,task,new,saved=fixture({door('lower'),door('upper')}); w.gated=true; w.crash=true; w.items[1]={name='minecraft:oak_door',count=2}; w.blocks['3,0,0']={name='minecraft:stone',state={}}
  local ex=new(); local sawCrash=false
  for _=1,240 do
    w.allowance=1
    if task.phase=='blocked' then
      if tostring(task.error):find('power lost',1,true) then sawCrash=true; assert(task.intent)
      else assert(tostring(task.error):find('reservation',1,true),task.error) end
      assert(ex:resume())
    end
    ex:step(); if task.phase=='completed' then break end
    task=saved(); ex=new(task)
  end
  eq(task.phase,'completed'); assert(sawCrash); eq(w.places,1); eq(w.items[1].count,1); eq(task.progress,2)
end)
