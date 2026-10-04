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
      elseif name:match('_bed$') then
        local v=vectors[w.pose.heading];local head={x=p.x+v[1],y=p.y,z=p.z+v[2]}
        if w.blocks[key(head)] or key(w.pose)==key(head) then return false,'bed head occupied' end
        for _,at in ipairs({p,head}) do if not w.blocks[key({x=at.x,y=at.y-1,z=at.z})] then return false,'bed floor missing' end end
        state={part='foot',facing=w.pose.heading,occupied=false};local top=U.copy(state);top.part='head'
        if not w.badPair then w.blocks[key(head)]={name=name,state=top} end
      elseif name=='minecraft:chest' or name=='minecraft:trapped_chest' then
        state={facing=order[(index[w.pose.heading]+1)%4+1],type='single',waterlogged=false}
      elseif name=='minecraft:barrel' then state={facing=suffix~='' and 'up' or w.pose.heading,open=false}
      elseif name=='minecraft:furnace' or name=='minecraft:blast_furnace' or name=='minecraft:smoker' then state={facing=order[(index[w.pose.heading]+1)%4+1],lit=false}
      elseif name:match('_sign$') then
        if suffix=='' then name=name:gsub('_sign$','_wall_sign');state={facing=order[(index[w.pose.heading]+1)%4+1],waterlogged=false}
        else state={rotation=(index[w.pose.heading]-1)*4,waterlogged=false} end
      elseif name:match('_slab$') then state={type=suffix=='Down' and 'bottom' or 'top',waterlogged=false}
      elseif connected(name) then state={north=false,east=false,south=false,west=false,waterlogged=false}
      elseif name:match('_button$') or name=='minecraft:lever' then
        state={face=suffix=='Down' and 'floor' or suffix=='Up' and 'ceiling' or 'wall',facing=suffix=='' and order[(index[w.pose.heading]+1)%4+1] or w.pose.heading,powered=w.powered or false}
      elseif name:match('rail$') then state={shape=(w.pose.heading=='east' or w.pose.heading=='west') and 'east_west' or 'north_south',waterlogged=false};if name~='minecraft:rail' then state.powered=false end
      elseif name=='minecraft:repeater' then state={facing=order[(index[w.pose.heading]+1)%4+1],delay=1,locked=false,powered=w.powered or false}
      elseif name=='minecraft:comparator' then state={facing=order[(index[w.pose.heading]+1)%4+1],mode='compare',powered=w.powered or false}
      elseif name=='minecraft:redstone' then name='minecraft:redstone_wire';state={north='side',east='side',south='side',west='side',power=0}
      elseif name=='minecraft:redstone_torch' then state={lit=true};if suffix=='' then name='minecraft:redstone_wall_torch';state.facing=order[(index[w.pose.heading]+1)%4+1] end
      elseif name=='minecraft:wheat_seeds' then
        local soil=w.blocks[key({x=p.x,y=p.y-1,z=p.z})];if not soil or soil.name~='minecraft:farmland' then return false,'cannot plant here' end
        name='minecraft:wheat';state={age=0}
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
    nav.workGuard=function() return true end
    if w.gated then nav.guard=function() if (w.allowance or 0)<1 then return false,'movement reservation pending' end; w.allowance=w.allowance-1; return true end end
    return require('autobuilder.build.builder').new(task,{turtle=t,peripheral=w.peripheral},config,nav,save,mode)
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
test('project-wide clearance lets a low region cross previously built taller regions',function()
  local w,task,new,saved=fixture({block('stone',{},3,1,0)})
  task.clearanceY=6; w.items[1]={name='minecraft:stone',count=1}
  w.blocks['1,4,0']={name='minecraft:stone',state={}}
  task=gatedRun(w,task,new,saved,true)
  eq(task.phase,'completed'); eq(w.places,1)
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

local function bed(facing)
 local v=({north={0,-1},east={1,0},south={0,1},west={-1,0}})[facing]
 return block('red_bed',{part='foot',facing=facing,occupied='false'}),block('red_bed',{part='head',facing=facing,occupied='false'},3+v[1],1,v[2])
end
test('paired beds consume one item verify both cells and recover placement once',function()
 for _,facing in ipairs({'north','east','south','west'}) do for _,crash in ipairs({false,true}) do
  local foot,head=bed(facing);local w,task,new,saved=fixture({foot,head});w.items[1]={name=foot.name,count=2};w.crash=crash
  w.blocks['3,0,0']={name='minecraft:stone',state={}};w.blocks[head.x..',0,'..head.z]={name='minecraft:stone',state={}}
  run(new());if crash then task=saved();assert(task.intent);task.phase='work';run(new(task)) end
  eq(task.phase,'completed');eq(task.progress,2);eq(w.places,1);eq(w.items[1].count,1)
  eq(require('autobuilder.core.reports').materials(task.report)[foot.name],1)
 end end
end)
test('beds require both floors empty paired space and matching blueprint halves',function()
 for _,failure in ipairs({'floor','occupied','mismatch','protected','pair'}) do
  local foot,head=bed('east');local w,task,new=fixture({foot,head});w.items[1]={name=foot.name,count=1};w.blocks['3,0,0']={name='minecraft:stone',state={}}
  if failure~='floor' then w.blocks['4,0,0']={name='minecraft:stone',state={}} end
  if failure=='occupied' then w.blocks['4,1,0']={name='minecraft:stone',state={}} end
  if failure=='mismatch' then head.state.facing='west' end
  w.badPair=failure=='pair'
  local config={minimumFuelReserve=0};if failure=='protected' then config.restrictedAreas={{min={x=4,y=1,z=0},max={x=4,y=1,z=0}}} end
  run(new(nil,config));eq(task.phase,'blocked');eq(task.progress,0);eq(w.places,failure=='pair' and 1 or 0)
 end
end)
test('bed inspections resume across per-cell reservations and reboot',function()
 local foot,head=bed('north');local w,task,new,saved=fixture({foot,head});w.items[1]={name=foot.name,count=1}
 w.blocks['3,0,0']={name='minecraft:stone',state={}};w.blocks['3,0,-1']={name='minecraft:stone',state={}}
 task=gatedRun(w,task,new,saved,true);eq(task.phase,'completed');eq(w.places,1);eq(task.progress,2)
end)

test('native basic adapter states have deterministic plans and strict unsupported variants',function()
 local C=require('autobuilder.build.blockstates');local P=require('autobuilder.build.placement')
 for _,case in ipairs({
  {'stone_button',{face='floor',facing='east',powered='false'},'down','east'},
  {'lever',{face='wall',facing='west',powered='false'},'forward','east'},
  {'oak_button',{face='ceiling',facing='south',powered='false'},'up','south'},
  {'rail',{shape='east_west',waterlogged='false'},'down','east'},
  {'powered_rail',{shape='north_south',powered='false',waterlogged='false'},'down','north'},
  {'repeater',{facing='east',delay='1',locked='false',powered='false'},'down','west'},
  {'comparator',{facing='west',mode='compare',powered='false'},'down','east'},
  {'redstone_torch',{lit='true'},'down','north'},
  {'redstone_wall_torch',{lit='true',facing='east'},'forward','west'},
  {'redstone_wire',{power='0',north='side',east='side',south='side',west='side'},'down','north'},
  {'wheat',{age='0'},'down','north'},{'dandelion',{},'down','north'},{'oak_sapling',{stage='0'},'down','north'},
 }) do local b=block(case[1],case[2]);local plan=assert(P.plan(b),case[1]);eq(plan.direction,case[3]);eq(plan.heading,case[4]) end
 for _,case in ipairs({{'rail',{shape='ascending_east'}},{'lever',{face='wall',facing='west',powered='true'}},
  {'repeater',{facing='east',delay='2',locked='false',powered='false'}},{'comparator',{facing='east',mode='subtract',powered='false'}},
  {'wheat',{age='7'}},{'redstone_wire',{power='1'}},{'redstone_torch',{lit='false'}}}) do eq(C.classify('minecraft:'..case[1],case[2]),'UNSUPPORTED') end
 eq(C.item(block('wheat',{age='0'})),'minecraft:wheat_seeds');eq(C.item(block('redstone_wire',{})),'minecraft:redstone')
end)

test('basic native adapters execute support journals and final verification across reboot',function()
 for _,case in ipairs({
  {block('stone_button',{face='floor',facing='east',powered='false'}),'3,0,0'},
  {block('lever',{face='wall',facing='west',powered='false'}),'4,1,0'},
  {block('oak_button',{face='ceiling',facing='south',powered='false'}),'3,2,0'},
  {block('rail',{shape='east_west',waterlogged='false'}),'3,0,0'},
  {block('repeater',{facing='east',delay='1',locked='false',powered='false'}),'3,0,0'},
  {block('comparator',{facing='west',mode='compare',powered='false'}),'3,0,0'},
  {block('redstone_wall_torch',{facing='east',lit='true'}),'2,1,0'},
  {block('redstone_wire',{power='0',north='side',east='side',south='side',west='side'}),'3,0,0'},
 }) do
  local w,task,new,saved=fixture({case[1]});w.items[1]={name=require('autobuilder.build.blockstates').item(case[1]),count=1};w.blocks[case[2]]={name='minecraft:stone',state={}}
  task=gatedRun(w,task,new,saved,true);eq(task.phase,'completed');eq(task.report.counts.correct,1);eq(w.places,1)
 end
end)
test('plant placement relies on native substrate checks without occupying crop soil',function()
 for _,soil in ipairs({'minecraft:farmland','minecraft:dirt'}) do
  local b=block('wheat',{age='0'});local w,task,new=fixture({b});w.items[1]={name='minecraft:wheat_seeds',count=1};w.blocks['3,0,0']={name=soil,state={}}
  run(new());eq(task.phase,soil=='minecraft:farmland' and 'completed' or 'blocked');eq(w.places,soil=='minecraft:farmland' and 1 or 0)
 end
end)
test('redstone final verification rejects actual powered state after successful placement',function()
 local b=block('repeater',{facing='north',delay='1',locked='false',powered='false'})
 local w,task,new=fixture({b});w.powered=true;w.items[1]={name=b.name,count=1};w.blocks['3,0,0']={name='minecraft:stone',state={}}
 run(new());eq(task.phase,'blocked');eq(task.progress,0);eq(w.places,1)
end)

test('repair refuses destructive bed halves even when desired block has no pair',function()
 for _,part in ipairs({'foot','head'}) do for _,desired in ipairs({'stone','air'}) do
  local b=block(desired);local w,task,new=fixture({b});local foot,head=bed('east');local actual=part=='foot' and foot or head
  w.blocks['3,1,0']={name=actual.name,state=actual.state};w.items[1]={name='minecraft:stone',count=1}
  w.t.digDown=function() w.dugBed=true;error('must not dig a paired bed') end
  run(new(nil,{minimumFuelReserve=0},'repair'));eq(task.phase,'blocked');eq(w.places,0);eq(w.blocks['3,1,0'].name,'minecraft:red_bed');eq(w.dugBed,nil)
 end end
end)

local function container(name,facing)
 local state={facing=facing or 'south'}
 if name=='chest' or name=='trapped_chest' then state.type='single';state.waterlogged='false'
 elseif name=='barrel' then state.open='false' else state.lit='false' end
 return block(name,state)
end
local function reader(w)
 w.peripheral={call=function(side,method)
  assert(({bottom=true,top=true,front=true})[side]);eq(method,'list');w.reads=(w.reads or 0)+1
  if w.readerError then error('disconnected') end
  return U.copy(w.contents or {})
 end}
end
test('empty containers recover one placement and verify inventory through adjacent peripherals',function()
 for _,name in ipairs({'chest','trapped_chest','furnace','blast_furnace','smoker','barrel'}) do
  local b=container(name,name=='barrel' and 'up' or 'south');local w,task,new,saved=fixture({b});reader(w)
  w.items[1]={name=b.name,count=2};w.crash=true
  run(new());task=saved();assert(task.intent,task.error);task.phase='work';run(new(task))
  eq(task.phase,'completed');eq(task.progress,1);eq(w.places,1);eq(w.items[1].count,1);assert(w.reads>0)
  local verify={blocks={b}};w.contents={[1]={name='minecraft:diamond',count=1}};run(new(verify,nil,'verify'))
  eq(verify.report.counts.correct,nil);eq(verify.report.counts.wrong,1);eq(w.places,1)
 end
end)
test('container placement refuses neighbor merges tagged items and destructive repairs',function()
 for _,failure in ipairs({'neighbor','tagged','repair'}) do
  local b=container('chest');local w,task,new=fixture({b});reader(w);w.items[1]={name=b.name,count=1}
  if failure=='neighbor' then w.blocks['4,1,0']={name=b.name,state=U.copy(b.state)}
  elseif failure=='tagged' then w.items[1].nbt='stored contents'
  else task.blocks={block('air')};w.blocks['3,1,0']={name=b.name,state=U.copy(b.state)};w.t.digDown=function() error('must not destroy container') end end
  run(new(nil,nil,failure=='repair' and 'repair' or nil));eq(task.phase,'blocked');eq(w.places,0)
  assert(tostring(task.error):find(failure=='neighbor' and 'adjacent' or failure=='tagged' and 'missing inventory' or 'refusing',1,true),task.error)
 end
end)
test('container verification never infers empty contents from missing or failed readers',function()
 for _,case in ipairs({'missing','error','malformed'}) do
  local b=container('furnace');local w,task,new=fixture({b});w.blocks['3,1,0']={name=b.name,state=b.state}
  if case~='missing' then reader(w);w.readerError=case=='error';if case=='malformed' then w.peripheral.call=function() return false end end end
  run(new(nil,nil,'verify'));eq(task.report.counts.correct,nil);eq(task.report.counts.wrong,1)
  assert(task.report.entries[1].reason:find('inventory',1,true))
 end
end)
test('isolated chest preflight resumes through movement reservations and reboot',function()
 local b=container('chest');local w,task,new,saved=fixture({b});reader(w);w.items[1]={name=b.name,count=1}
 task=gatedRun(w,task,new,saved,true);eq(task.phase,'completed');eq(w.places,1)
end)
test('cardinal standing and wall signs preserve geometry and item aliases',function()
 local C=require('autobuilder.build.blockstates');
 for _,case in ipairs({{block('oak_sign',{rotation='0',waterlogged='false'}),'3,0,0'},
  {block('oak_sign',{rotation='4',waterlogged='false'}),'3,0,0'},
  {block('spruce_wall_sign',{facing='east',waterlogged='false'}),'2,1,0'}}) do
  local b=case[1];local w,task,new,saved=fixture({b});w.items[1]={name=C.item(b),count=1};w.blocks[case[2]]={name='minecraft:stone',state={}}
  task=gatedRun(w,task,new,saved,true);eq(task.phase,'completed');eq(w.places,1)
 end
 eq(C.item(block('spruce_wall_sign',{})),'minecraft:spruce_sign')
 for _,b in ipairs({container('chest'),block('oak_sign',{rotation='0',waterlogged='false'})}) do assert(C.requiresMetadata({b})) end
 for _,b in ipairs({block('oak_sign',{rotation='1',waterlogged='false'}),block('oak_hanging_sign',{}),block('chest',{facing='north',type='left',waterlogged='false'}),block('furnace',{facing='north',lit='true'})}) do eq(C.classify(b.name,b.state),'UNSUPPORTED') end
end)

test('native barrel probe limits vertical placement and preserves horizontal look direction',function()
 local C=require('autobuilder.build.blockstates');eq(C.classify('minecraft:barrel',{facing='down',open='false'}),'UNSUPPORTED')
 for _,facing in ipairs({'north','east','south','west','up'}) do
  local b=container('barrel',facing);local w,task,new=fixture({b});reader(w);w.items[1]={name=b.name,count=1}
  run(new());eq(task.phase,'completed');eq(w.blocks['3,1,0'].state.facing,facing)
 end
end)

test('repair preserves unobservable sign text for air stone and orientation replacements',function()
 for _,name in ipairs({'oak_sign','oak_wall_sign'}) do for _,desired in ipairs({'air','stone','orientation'}) do
  local state=name=='oak_sign' and {rotation='0',waterlogged='false'} or {facing='north',waterlogged='false'}
  local actual=block(name,state);local wanted=block(desired=='orientation' and name or desired,U.copy(state))
  if desired=='orientation' then if name=='oak_sign' then wanted.state.rotation='4' else wanted.state.facing='east' end else wanted.state={} end
  local w,task,new=fixture({wanted});w.blocks['3,1,0']=actual;w.items[1]={name='minecraft:stone',count=1};w.items[2]={name='minecraft:oak_sign',count=1}
  for _,suffix in ipairs({'','Up','Down'}) do w.t['dig'..suffix]=function() w.lostText=true;return false end end
  run(new(nil,nil,'repair'));eq(task.phase,'blocked');eq(w.lostText,nil);assert(task.error:find('refusing',1,true),task.error)
 end end
end)
test('standing signs accept stable retained grass as native support',function()
 local b=block('oak_sign',{rotation='0',waterlogged='false'});local w,task,new=fixture({b})
 w.blocks['3,0,0']={name='minecraft:grass_block',state={snowy=false}};w.items[1]={name=b.name,count=1}
 run(new());eq(task.phase,'completed');eq(w.places,1);eq(w.blocks['3,0,0'].name,'minecraft:grass_block')
end)
