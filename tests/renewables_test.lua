local U=require('autobuilder.core.util')
local N=require('autobuilder.core.navigation')
local function world()
  local w={pose={x=0,y=1,z=0,heading='north',known=true},blocks={['0,0,0']={name='minecraft:chest',state={}}},items={},selected=1,fuel=10000,stock={},digs=0,plants=0,capacity=1000}
  local function key(p) return p.x..','..p.y..','..p.z end
  local vectors={north={0,-1},east={1,0},south={0,1},west={-1,0}}
  local function point(suffix)
    local p=U.copy(w.pose)
    if suffix=='Down' then p.y=p.y-1 elseif suffix=='Up' then p.y=p.y+1 else local v=vectors[p.heading]; p.x=p.x+v[1]; p.z=p.z+v[2] end
    return p
  end
  local t={}; w.t=t
  t.getFuelLevel=function() return w.fuel end
  t.getItemDetail=function(s) return U.copy(w.items[s or w.selected]) end
  t.getItemCount=function(s) return w.items[s or w.selected] and w.items[s or w.selected].count or 0 end
  t.select=function(s) w.selected=s; return true end
  local function add(name,n)
    for s=1,14 do
      if not w.items[s] or w.items[s].name==name and w.items[s].count+n<=64 then
        w.items[s]=w.items[s] or {name=name,count=0}; w.items[s].count=w.items[s].count+n; return true
      end
    end
    return false
  end
  for _,suffix in ipairs({'','Up','Down'}) do
    t['inspect'..suffix]=function() local b=w.blocks[key(point(suffix))]; return b~=nil,U.copy(b) end
    t['dig'..suffix]=function()
      local k=key(point(suffix)); local b=w.blocks[k]; if not b then return false end
      local item=b.name=='minecraft:wheat' and 'minecraft:wheat' or b.name
      if b.name:match('_leaves$') then item=nil end
      if item and not add(item,1) then return false,'full' end
      if b.name=='minecraft:wheat' then add('minecraft:wheat_seeds',1) end
      w.blocks[k]=nil; w.digs=w.digs+1
      if w.crashDig then w.crashDig=false; error('power cut after dig') end
      return true
    end
  end
  t.placeDown=function()
    local k=key(point('Down')); local item=w.items[w.selected]; if w.blocks[k] or not item then return false end
    local name=item.name=='minecraft:wheat_seeds' and 'minecraft:wheat' or item.name
    w.blocks[k]={name=name,state={age=0}}; item.count=item.count-1; if item.count==0 then w.items[w.selected]=nil end; w.plants=w.plants+1
    if w.crashPlace then w.crashPlace=false; error('power cut after plant') end
    return true
  end
  t.dropDown=function(amount)
    local item=w.items[w.selected]; if not item then return false end
    local moved=math.min(item.count,amount or item.count,w.capacity); if moved==0 then return false,'full depot' end
    w.stock[item.name]=(w.stock[item.name] or 0)+moved; w.capacity=w.capacity-moved; item.count=item.count-moved; if item.count==0 then w.items[w.selected]=nil end
    if w.crashDrop then w.crashDrop=false; error('power cut after drop') end
    return true
  end
  local headings={'north','east','south','west'}; local index={north=1,east=2,south=3,west=4}
  t.turnRight=function() w.pose.heading=headings[index[w.pose.heading]%4+1]; return true end
  t.turnLeft=function() w.pose.heading=headings[(index[w.pose.heading]+2)%4+1]; return true end
  for action,suffix in pairs({forward='',up='Up',down='Down'}) do t[action]=function() local p=point(suffix); if w.blocks[key(p)] then return false,'blocked' end; w.pose.x,w.pose.y,w.pose.z=p.x,p.y,p.z; w.fuel=w.fuel-1; return true end end
  return w
end
local function setup(kind,quantity)
  local w=world(); local task={type=kind=='oak' and 'HARVEST' or 'FARM',item='minecraft:'..(kind=='oak' and 'oak_log' or kind),quantity=quantity or 1,farm={kind=kind,sites={{x=3,y=1,z=0}},maxHeight=4},phase='setup'}
  local config={depot={x=0,y=1,z=0},minimumFuelReserve=0,maxTravelDistance=100,reservedSlots={15,16}}
  local durable; local function save() durable=U.copy(task); return true end
  local function executor()
    local nav=N.new(w.t,U.copy(w.pose),config,save)
    if not w.noWorkGuard then nav.workGuard=function() return w.permitMutation~=false,'movement reservation pending' end end
    nav.workDone=function() w.releasedMutations=(w.releasedMutations or 0)+1 end
    if w.reservations then
      local key=require('autobuilder.core.pathfinding').key
      nav.guard=function(_,target)
        w.workGrant=nil
        if w.moveGrant==key(target) then return true end
        w.moveGrant=key(target);return false,'movement reservation pending'
      end
      nav.afterMove=function() w.moveGrant=nil end
      nav.workGuard=function(target)
        if w.workGrant==key(target) then return true end
        w.workGrant=key(target);return false,'movement reservation pending'
      end
      nav.workDone=function() w.workGrant=nil;w.releasedMutations=(w.releasedMutations or 0)+1 end
    end
    return require(kind=='oak' and 'autobuilder.resources.logger' or 'autobuilder.resources.farmer').new(task,{turtle=w.t},config,nav,save)
  end
  local function restart() task=U.copy(durable); return executor(),task end
  return w,task,config,executor,restart
end
local function run(executor,task)
  for _=1,200 do if task.phase=='completed' or task.phase=='blocked' then return end; executor:step() end
  error('renewable executor did not terminate in bounded steps')
end
test('wheat harvest replants mature crop and delivers measured output',function()
  local w,task,config,new=setup('wheat'); w.blocks['3,1,0']={name='minecraft:wheat',state={age=7}}; w.blocks['3,0,0']={name='minecraft:farmland',state={}}; w.items[1]={name='minecraft:wheat_seeds',count=1}
  local e=new(); run(e,task); eq(task.phase,'completed'); eq(task.delivered,1); eq(w.stock['minecraft:wheat'],1); eq(w.blocks['3,1,0'].state.age,0); eq(w.plants,1)
end)
test('immature crops block without digging and resume after growth',function()
  local w,task,config,new=setup('wheat'); w.blocks['3,1,0']={name='minecraft:wheat',state={age=2}}; w.blocks['3,0,0']={name='minecraft:farmland',state={}}; w.items[1]={name='minecraft:wheat_seeds',count=1}
  local e=new(); run(e,task); eq(task.phase,'blocked'); eq(w.digs,0); eq(task.blockedCategory,'immature'); w.blocks['3,1,0'].state.age=7; assert(e:resume()); run(e,task); eq(task.phase,'completed')
end)
test('column harvesting retains base and never digs foreign blocks',function()
  local w,task,config,new=setup('sugar_cane',2)
  for y=1,3 do w.blocks['3,'..y..',0']={name='minecraft:sugar_cane',state={}} end
  local e=new(); run(e,task); eq(task.phase,'completed'); eq(task.delivered,2); eq(w.blocks['3,1,0'].name,'minecraft:sugar_cane'); eq(w.digs,2)
  w,task,config,new=setup('bamboo'); w.blocks['3,3,0']={name='minecraft:chest',state={}}; e=new(); run(e,task); eq(task.phase,'blocked'); eq(w.digs,0)
end)
test('managed oak trunks require sapling and replant before completion',function()
  local w,task,config,new=setup('oak',2); w.blocks['3,0,0']={name='minecraft:dirt',state={}}
  for y=1,2 do w.blocks['3,'..y..',0']={name='minecraft:oak_log',state={axis='y'}} end
  local e=new(); run(e,task); eq(task.phase,'blocked'); eq(task.missingItem,'minecraft:oak_sapling'); eq(w.digs,0)
  w.items[1]={name='minecraft:oak_sapling',count=1}; assert(e:resume()); run(e,task); eq(task.phase,'completed'); eq(task.delivered,2); eq(w.blocks['3,1,0'].name,'minecraft:oak_sapling')
end)
test('renewable intents reconcile dig planting and deposit crashes once',function()
  for _,crash in ipairs({'crashDig','crashPlace','crashDrop'}) do
    local w,task,config,new,restart=setup('wheat'); w.blocks['3,1,0']={name='minecraft:wheat',state={age=7}}; w.blocks['3,0,0']={name='minecraft:farmland',state={}}; w.items[1]={name='minecraft:wheat_seeds',count=1}; w[crash]=true
    local e=new(); run(e,task); eq(task.phase,'blocked'); e,task=restart(); assert(e:resume()); run(e,task); eq(task.phase,'completed'); eq(task.delivered,1); eq(w.digs,1); eq(w.plants,1); eq(w.stock['minecraft:wheat'],1)
  end
end)
test('renewable protection and depot capacity block without false completion',function()
  local w,task,config,new=setup('wheat'); w.blocks['3,1,0']={name='minecraft:wheat',state={age=7}}; w.blocks['3,0,0']={name='minecraft:farmland',state={}}; w.items[1]={name='minecraft:wheat_seeds',count=1}; config.protectedBlocks={['minecraft:wheat']=true}
  local e=new(); run(e,task); eq(task.phase,'blocked'); eq(w.digs,0)
  config.protectedBlocks={}; w.capacity=0; assert(e:resume()); run(e,task); eq(task.phase,'blocked'); eq(task.delivered,0); eq(w.plants,1)
end)
test('renewables return and block on low fuel or unusable inventory instead of looping',function()
  local w,task,config,new=setup('wheat'); w.fuel=1; local e=new(); run(e,task); eq(task.phase,'blocked'); eq(task.blockedCategory,'fuel'); eq(w.digs,0)
  w,task,config,new=setup('wheat'); w.blocks['3,1,0']={name='minecraft:wheat',state={age=7}}; w.items[1]={name='minecraft:wheat_seeds',count=1}
  config.reservedSlots={}; for s=2,16 do config.reservedSlots[#config.reservedSlots+1]=s end
  e=new(); run(e,task); eq(task.phase,'blocked'); eq(task.blockedCategory,'inventory_full'); eq(w.digs,0)
end)
test('harvest cannot report success when hardware leaves its target unchanged',function()
  local w,task,config,new=setup('wheat'); w.blocks['3,1,0']={name='minecraft:wheat',state={age=7}}; w.items[1]={name='minecraft:wheat_seeds',count=1}; w.t.digDown=function() return true end
  local e=new(); run(e,task); eq(task.phase,'blocked'); eq(task.progress,0); eq(task.delivered,0)
end)
test('branching logs and unsupported species stop managed logging',function()
  local w,task,config,new=setup('oak'); w.items[1]={name='minecraft:oak_sapling',count=1}; w.blocks['3,2,0']={name='minecraft:oak_log',state={axis='y'}}; w.blocks['3,1,0']={name='minecraft:oak_log',state={axis='y'}}; w.blocks['4,2,0']={name='minecraft:oak_log',state={axis='x'}}
  local e=new(); run(e,task); eq(task.phase,'blocked'); eq(task.blockedCategory,'unsupported'); eq(w.blocks['4,2,0'].name,'minecraft:oak_log'); eq(task.delivered,0)
  w,task,config,new=setup('oak'); task.farm.kind='dark_oak'; e=new(); run(e,task); eq(task.phase,'blocked'); eq(w.digs,0)
end)
test('multiple mature plots are replanted individually before depot delivery',function()
  local w,task,config,new=setup('wheat',2); task.farm.sites[2]={x=5,y=1,z=0}; w.items[1]={name='minecraft:wheat_seeds',count=2}
  for _,x in ipairs({3,5}) do w.blocks[x..',1,0']={name='minecraft:wheat',state={age=7}}; w.blocks[x..',0,0']={name='minecraft:farmland',state={}} end
  local e=new(); run(e,task); eq(task.phase,'completed'); eq(task.delivered,2); eq(w.plants,2); eq(w.blocks['5,1,0'].state.age,0)
end)
test('failed renewable checkpoint prevents the physical harvest action',function()
  local w,task,config=setup('wheat'); w.blocks['3,1,0']={name='minecraft:wheat',state={age=7}}; w.items[1]={name='minecraft:wheat_seeds',count=1}
  local nav=N.new(w.t,U.copy(w.pose),config,function() return true end)
  local e=require('autobuilder.resources.farmer').new(task,{turtle=w.t},config,nav,function() return false,'disk full' end)
  assert(not pcall(function() e:step() end)); eq(w.digs,0); assert(not e:step())
end)

test('managed farm requires a separate mutation grant for harvesting and replanting',function()
 for _,missing in ipairs({true,false}) do
  local w,task,config,new=setup('wheat');w.noWorkGuard=missing;w.permitMutation=false
  w.blocks['3,1,0']={name='minecraft:wheat',state={age=7}};w.blocks['3,0,0']={name='minecraft:farmland',state={}};w.items[1]={name='minecraft:wheat_seeds',count=1}
  local engine=new();run(engine,task);eq(w.digs,0);eq(task.phase,'blocked');assert(not task.intent)
  w.noWorkGuard=false;w.permitMutation=true;engine=new();assert(engine:resume())
  assert(engine:step());eq(w.digs,1);eq(w.plants,0)
  w.permitMutation=false;run(engine,task);eq(task.phase,'blocked');eq(w.plants,0);assert(not task.intent)
  w.permitMutation=true;assert(engine:resume());run(engine,task)
  eq(task.phase,'completed');eq(w.digs,1);eq(w.plants,1);eq(w.releasedMutations,2)
 end
end)

test('farm soil inspection and planting resume with independent movement and mutation grants',function()
 local w,task,config,new,restart=setup('wheat');w.reservations=true
 w.blocks['3,1,0']={name='minecraft:wheat',state={age=7}};w.blocks['3,0,0']={name='minecraft:farmland',state={}};w.items[1]={name='minecraft:wheat_seeds',count=1}
 local engine=new();local rebooted=false
 for _=1,600 do
  if task.phase=='blocked' then assert(task.error:find('movement reservation pending',1,true),task.error);assert(engine:resume()) end
  engine:step()
  if task.plantSoilSite and not rebooted then engine,task=restart();rebooted=true end
  if task.phase=='completed' then break end
 end
 eq(task.phase,'completed');assert(rebooted);eq(w.digs,1);eq(w.plants,1);eq(task.delivered,1)
end)

test('renewable forecast follows collected cargo partial delivery and reboot without losing coverage',function()
  for _,kind in ipairs({'oak','sugar_cane'}) do
    local w,task,config,new,restart=setup(kind,2);task.id='harvest'
    if kind=='oak' then
      w.blocks['3,0,0']={name='minecraft:dirt',state={}};w.items[1]={name='minecraft:oak_sapling',count=1}
      for y=1,2 do w.blocks['3,'..y..',0']={name=task.item,state={axis='y'}} end
    else for y=1,3 do w.blocks['3,'..y..',0']={name=task.item,state={}} end end
    config.automation={enabled=true};config.capabilities={};config.mining={}
    local e=new();w.capacity=1;local collected=false
    local function forecast()
      local agent=require('autobuilder.workers.agent').new({id=12,position=U.copy(w.pose),currentTask=task},config,{},w.t,function() return true end)
      local t=agent:telemetry()
      local scope={project={name='p',requirements={[task.item]=2},jobs={}},work={harvest={id=task.id,type=task.type,item=task.item,quantity=2,progress=task.progress,status=task.phase=='completed' and 'completed' or 'running',workerId=12}}}
      return require('autobuilder.resources.material_forecast').build({workers={['12']={online=true,telemetry=t}}},w.stock,{scope}).p
    end
    for _=1,200 do
      e:step()
      if task.progress==2 and task.delivered==0 and not task.intent and not collected then
        local f=forecast();eq(f.items[task.item].held,2);eq(f.items[task.item].harvesting,0);eq(f.items[task.item].deficit,0);collected=true
      end
      if task.phase=='blocked' then break end
    end
    assert(collected);eq(task.delivered,1);eq(task.blockedCategory,'depot_full')
    local f=forecast();eq(f.items[task.item].held,1);eq(f.items[task.item].stored,1);eq(f.items[task.item].harvesting,0);eq(f.items[task.item].deficit,0)
    e,task=restart();f=forecast();eq(f.items[task.item].deficit,0)
    w.capacity=10;assert(e:resume());run(e,task);eq(task.phase,'completed');eq(task.delivered,2)
    f=forecast();eq(f.items[task.item].held,0);eq(f.items[task.item].stored,2);eq(f.items[task.item].deficit,0)
  end
end)
