local U=require('autobuilder.core.util')
local function mc(x) return 'minecraft:'..x end

test('production planner expands yields and shared surplus in dependency order',function()
  local P=require('autobuilder.blueprint.planner')
  local p=P.expand({[mc('oak_stairs')]=4,[mc('oak_slab')]=6},{[mc('oak_log')]=3})
  eq(p.raw[mc('oak_log')],3); eq(next(p.missing),nil)
  eq(p.available[mc('oak_planks')],3)
  local made={}; for _,op in ipairs(p.operations) do
    for item in pairs(op.ingredients) do if item==mc('oak_planks') then assert(made[item]) end end
    made[op.item]=true
  end
end)
test('production planner honors finished stock and separates fuel reserves',function()
  local p=require('autobuilder.blueprint.planner').expand({[mc('stone_bricks')]=8},
    {[mc('stone_bricks')]=4,[mc('cobblestone')]=4,[mc('coal')]=2},
    {turtleFuelReserveItems={[mc('coal')]=2}})
  eq(p.raw[mc('cobblestone')],4); eq(p.fuel.items,1); eq(p.missing[mc('coal')],1)
  eq(p.operations[1].kind,'smelt'); eq(p.operations[2].kind,'craft')
end)
test('production registry validates grid and planner rejects dependency cycles',function()
  local R=require('autobuilder.factory.recipes')
  assert(not pcall(R.register,'bad',{kind='craft',yield=1,ingredients={a=2},grid={[1]='a'}}))
  local cycle={get=function(item) return {kind='craft',yield=1,ingredients={[item=='a' and 'b' or 'a']=1}} end}
  assert(not pcall(require('autobuilder.blueprint.planner').expand,{a=1},{},{recipes=cycle}))
end)

-- Inventories are isolated snapshots, like CC peripheral.list, and transfers can be partial.
local function hardware()
  local h={inventories={store={},furnace={},input={},output={}},slots={},selected=1,limit=64,calls=0}
  local function put(inv,slot,item,n)
    inv[slot]=inv[slot] or {name=item,count=0}; assert(inv[slot].name==item)
    inv[slot].count=inv[slot].count+n
    if inv[slot].count==0 then inv[slot]=nil end
  end
  local function move(src,slot,dst,target,n)
    if not src[slot] then return 0 end
    local item=src[slot].name
    if not target then for i=1,27 do if not dst[i] or dst[i].name==item and dst[i].count<64 then target=i; break end end end
    if not target or dst[target] and dst[target].name~=item then return 0 end
    n=math.min(n or 64,src[slot].count,64-(dst[target] and dst[target].count or 0),h.limit)
    if n>0 then put(src,slot,item,-n); put(dst,target,item,n) end
    return n
  end
  h.peripheral={call=function(name,method,...)
    if h.offline==name then error('detached') end
    local inv=assert(h.inventories[name],'missing peripheral')
    if method=='list' then return U.copy(inv) end
    if method=='pushItems' then
      local to,slot,n,target=...; h.calls=h.calls+1
      local moved=move(inv,slot,assert(h.inventories[to]),target,n)
      if h.crash then h.crash=false; error('power loss after transfer') end
      return moved
    end
    error('unexpected API '..method)
  end}
  h.turtle={getItemDetail=function(slot) return U.copy(h.slots[slot]) end,
    select=function(slot) h.selected=slot; return true end,
    suckUp=function(n) h.calls=h.calls+1; for slot in pairs(h.inventories.input) do return move(h.inventories.input,slot,h.slots,h.selected,n)>0 end; return false end,
    dropDown=function(n) h.calls=h.calls+1; return move(h.slots,h.selected,h.inventories.output,nil,n)>0 end,
    craft=function(limit)
      h.calls=h.calls+1
      local R=require('autobuilder.factory.recipes'); local recipe=R.get(h.craftItem)
      for slot,item in pairs(recipe.grid) do assert(h.slots[slot] and h.slots[slot].name==item) end
      for slot,item in pairs(recipe.grid) do put(h.slots,slot,item,-1) end
      put(h.slots,h.selected,h.craftItem,recipe.yield)
      if h.craftCrash then h.craftCrash=false; error('power loss after craft') end
      return true
    end}
  function h:smelt()
    local inv=self.inventories.furnace
    if inv[1] and (inv[2] or (self.burn or 0)>0) then
      if (self.burn or 0)==0 then put(inv,2,mc('coal'),-1); self.burn=8 end
      put(inv,1,mc('cobblestone'),-1); put(inv,3,mc('stone'),1); self.burn=self.burn-1
    end
  end
  return h
end
local cfg={storageInventories={'store'},furnaces={'furnace'},smeltingFuelItem=mc('coal'),
  turtleFuelReserveItems={[mc('coal')]=2},craftingStation={input='input',output='output',inputSide='up',outputSide='down'}}
local function drive(executor,h,steps)
  local status,reason
  for i=1,steps or 100 do status,reason=executor:step(); if status=='complete' or status=='blocked' then return status,reason end; if h then h:smelt() end end
  return status,reason
end

test('smelting uses actual transfers and asynchronously delivers stone without turtle fuel',function()
  local h=hardware(); h.limit=2; h.inventories.store={[1]={name=mc('cobblestone'),count=4},[2]={name=mc('coal'),count=3}}
  local task={item=mc('stone'),batches=4}
  local ex=require('autobuilder.factory.smelting').new(task,h,cfg,function() return true end)
  local status,why=drive(ex,h); eq(status,'complete')
  eq(h.inventories.store[2].count,2); eq(task.production.delivered,4)
end)
test('smelting reconciles a crash after input transfer and handles disconnected hardware',function()
  local h=hardware(); h.inventories.store={[1]={name=mc('cobblestone'),count=2},[2]={name=mc('coal'),count=3}}
  local task={item=mc('stone'),batches=2}; local saved
  local function save() saved=U.copy(task); return true end
  local S=require('autobuilder.factory.smelting')
  local ex=S.new(task,h,cfg,save); h.crash=true
  eq(ex:step(),'blocked'); assert(saved.production.intent)
  task=U.copy(saved); ex=S.new(task,h,cfg,save)
  h.offline='furnace'; eq(ex:resume(),'blocked'); h.offline=nil
  eq(drive(ex,h),'complete'); eq(task.production.delivered,2)
end)
test('production refuses hardware effects when saving intent fails',function()
  local h=hardware(); h.inventories.store[1]={name=mc('cobblestone'),count=2}
  local ex=require('autobuilder.factory.smelting').new({item=mc('stone'),batches=2},h,cfg,function() return false,'disk full' end)
  eq(ex:step(),'blocked'); eq(h.calls,0)
end)
test('crafting stages exact slots, recovers crafted output, and delivers all batches',function()
  local h=hardware(); h.craftItem=mc('stone_bricks'); h.inventories.store[1]={name=mc('stone'),count=8}
  local task={item=h.craftItem,batches=2}; local saved
  local function save() saved=U.copy(task); return true end
  local C=require('autobuilder.factory.crafting'); local ex=C.new(task,h,cfg,save)
  h.craftCrash=true
  eq(drive(ex),'blocked'); assert(saved.production.intent)
  task=U.copy(saved); ex=C.new(task,h,cfg,save)
  eq(drive(ex),'complete'); eq(task.production.delivered,8)
  eq(next(h.slots),nil); eq(require('autobuilder.factory.factory').count(h.inventories.store,mc('stone_bricks')),8)
end)
test('crafting blocks contaminated turtle and occupied staging chest',function()
  local C=require('autobuilder.factory.crafting'); local h=hardware(); h.slots[4]={name=mc('dirt'),count=1}
  eq(C.new({item=mc('stone_bricks'),batches=1},h,cfg,function() return true end):step(),'blocked'); eq(h.calls,0)
  h.slots={}; h.inventories.input[1]={name=mc('dirt'),count=1}
  eq(C.new({item=mc('stone_bricks'),batches=1},h,cfg,function() return true end):step(),'blocked'); eq(h.calls,0)
end)
test('production planning acquires missing fuel reserve as well as smelting fuel',function()
  local p=require('autobuilder.blueprint.planner').expand({[mc('stone')]=16},{[mc('cobblestone')]=16},
    {turtleFuelReserveItems={[mc('coal')]=8}})
  eq(p.missing[mc('coal')],10); eq(p.reserveMissing[mc('coal')],8)
end)
test('production substitutions select explicit final recipes without altering their grids',function()
  local p=require('autobuilder.blueprint.planner').expand({[mc('oak_stairs')]=4},{},
    {substitutions={[mc('oak_stairs')]=mc('spruce_stairs')}})
  eq(p.requirements[mc('spruce_stairs')],4); eq(p.raw[mc('spruce_log')],2)
  eq(p.operations[#p.operations].item,mc('spruce_stairs'))
end)
test('recipe registry encodes real pane bar clay and brick yields',function()
  local R=require('autobuilder.factory.recipes')
  eq(R.get(mc('glass_pane')).yield,16); eq(R.get(mc('iron_bars')).ingredients[mc('iron_ingot')],6)
  eq(R.get(mc('clay')).ingredients[mc('clay_ball')],4)
  eq(R.get(mc('bricks')).ingredients[mc('brick')],4)
  eq(R.get(mc('iron_ingot')).ingredients[mc('raw_iron')],1)
  eq(R.get(mc('pale_oak_planks')),nil)
end)
test('production restores intent after post-effect checkpoint failure',function()
  local h=hardware(); h.inventories.store={[1]={name=mc('cobblestone'),count=1},[2]={name=mc('coal'),count=3}}
  local task={item=mc('stone'),batches=1}; local saved; local reject=true
  local function save()
    if reject and h.calls>0 and not task.production.intent then return false,'disk full after effect' end
    saved=U.copy(task); return true
  end
  local S=require('autobuilder.factory.smelting'); local ex=S.new(task,h,cfg,save)
  eq(ex:step(),'blocked'); assert(task.production.intent and saved.production.intent)
  reject=false; eq(drive(ex,h),'complete'); eq(task.production.delivered,1)
end)
test('production completes raw cobblestone to stone bricks through both physical executors',function()
  local h=hardware(); h.craftItem=mc('stone_bricks')
  h.inventories.store={[1]={name=mc('cobblestone'),count=8},[2]={name=mc('coal'),count=3}}
  local p=require('autobuilder.blueprint.planner').expand({[mc('stone_bricks')]=8},
    {[mc('cobblestone')]=8,[mc('coal')]=3},cfg)
  eq(next(p.missing),nil)
  for _,op in ipairs(p.operations) do
    local ex=require('autobuilder.factory.factory').new(op,h,cfg,function() return true end)
    local status,why=drive(ex,op.type=='SMELT' and h or nil,150); assert(status=='complete',why)
  end
  eq(require('autobuilder.factory.factory').count(h.inventories.store,mc('stone_bricks')),8)
  eq(require('autobuilder.factory.factory').count(h.inventories.store,mc('coal')),2)
end)
test('smelting empty fuel supply blocks without spending turtle reserve',function()
  local h=hardware(); h.inventories.store={[1]={name=mc('cobblestone'),count=1},[2]={name=mc('coal'),count=2}}
  local ex=require('autobuilder.factory.smelting').new({item=mc('stone'),batches=1},h,cfg,function() return true end)
  eq(drive(ex),'blocked'); eq(h.inventories.store[2].count,2)
end)
test('crafting partially fills output storage and keeps undelivered output for resume',function()
  local h=hardware(); h.limit=1; h.craftItem=mc('glass_pane'); h.inventories.store[1]={name=mc('glass'),count=6}
  local task={item=h.craftItem,batches=1}
  eq(drive(require('autobuilder.factory.crafting').new(task,h,cfg,function() return true end),nil,100),'complete')
  eq(task.production.delivered,16)
  eq(require('autobuilder.factory.factory').count(h.inventories.store,h.craftItem),16)
end)
test('smelting bounds unobservable processing stalls',function()
  local h=hardware(); h.inventories.store={[1]={name=mc('cobblestone'),count=1},[2]={name=mc('coal'),count=3}}
  local config=U.copy(cfg); config.smeltingWaitSteps=3
  local ex=require('autobuilder.factory.smelting').new({item=mc('stone'),batches=1},h,config,function() return true end)
  local status,why=drive(ex,nil,10); eq(status,'blocked'); assert(why:find('stalled'))
end)
test('smelting refuses output which exceeds its recorded owned inputs',function()
  local h=hardware(); h.inventories.store={[1]={name=mc('cobblestone'),count=1},[2]={name=mc('coal'),count=3}}
  local task={item=mc('stone'),batches=1}; local ex=require('autobuilder.factory.smelting').new(task,h,cfg,function() return true end)
  eq(ex:step(),'running'); h.inventories.furnace[3]={name=mc('stone'),count=2}
  eq(ex:step(),'blocked'); eq(task.production.delivered,0)
end)
test('crafting rejects unowned output instead of crediting it as a completed recipe',function()
  local h=hardware(); h.craftItem=mc('stone_bricks'); h.inventories.store[1]={name=mc('stone'),count=4}
  local task={item=h.craftItem,batches=1}; local ex=require('autobuilder.factory.crafting').new(task,h,cfg,function() return true end)
  for i=1,20 do eq(ex:step(),'running'); if task.production.phase=='deliver' then break end end
  h.inventories.output[1]={name=h.craftItem,count=4}
  eq(ex:step(),'blocked'); eq(task.production.delivered,0)
end)
test('crafting preserves an ambiguous post-crash journal for operator review',function()
  local h=hardware(); h.craftItem=mc('stone_bricks'); h.inventories.store[1]={name=mc('stone'),count=4}
  local task={item=h.craftItem,batches=1}; local ex=require('autobuilder.factory.crafting').new(task,h,cfg,function() return true end)
  h.craftCrash=true; eq(drive(ex),'blocked'); assert(task.production.intent)
  h.slots[13].count=3
  eq(ex:resume(),'blocked'); assert(task.production.intent)
end)

local function productionFixture(stock)
  local h=hardware(); h.inventories.store=stock or {}
  local config=U.copy(cfg); config.treeFarms={}; config.farms={}; config.turtleFuelReserveItems={}
  config.inventoryAreas={} -- Stationary virtual factory is outside every excavation fixture.
  for i,name in ipairs({'store','furnace','input','output'}) do config.inventoryAreas[name]={min={x=-100-i,y=0,z=0},max={x=-100-i,y=0,z=0}} end
  config.heartbeatInterval=1; config.checkpointInterval=1
  local app={state={id=1,role='controller',jobs={},workers={}},saved=nil,now=0,packets={}}
  function app:save() self.saved=U.copy(self.state); return true end
  function app:report() end
  local net={send=function(_,to,kind,payload) app.packets[#app.packets+1]={to=to,kind=kind,payload=payload}; return true end}
  local clock=function() return app.now end
  app.mining=require('autobuilder.core.mining_service').new(app,config,h,net,clock)
  local queue=require('autobuilder.core.workflows').new(app.state,function() return app:save() end,clock,1)
  local service=require('autobuilder.core.production_service').new(app,config,h,queue)
  return app,service,queue,config,h
end
local function miningWorker(id,item,x)
  return {id=id,online=true,telemetry={status='idle',capabilities={mining=true},miningResources={item},
    miningArea={min={x=x,y=0,z=0},max={x=x+10,y=10,z=10}}}}
end
test('autonomous preparation persists project linkage with the request and rejects missing projects atomically',function()
  local app,p,q=productionFixture(); q.state.projects.house={name='house',phase='imported',stockOnly=true}
  local r=p:request({[mc('cobblestone')]=8},'project:house',{projectName='house'})
  eq(app.saved.automation.projects.house.requestId,r.id); eq(app.saved.automation.projects.house.stockOnly,false)
  eq(app.saved.automation.requests[r.id].stockOnly,false)
  local before=q.state.requestSequence
  assert(not pcall(p.request,p,{[mc('dirt')]=1},'missing',{projectName='absent'}))
  eq(q.state.requestSequence,before)
  for _,request in pairs(q.state.requests) do assert(request.key~='missing') end
end)
test('production keeps progress for every material and dispatches different resources in parallel',function()
  local app,p,q=productionFixture()
  app.state.workers['2']=miningWorker(2,mc('raw_iron'),20)
  app.state.workers['3']=miningWorker(3,mc('cobblestone'),40)
  local r=p:request({[mc('raw_iron')]=6,[mc('cobblestone')]=8})
  p:tick(); app.mining:tick(); app.now=2; app.mining:tick(); p:tick()
  assert(r.materials,'all acquisition progress must be visible')
  eq(r.materials[mc('raw_iron')].workerId,2); eq(r.materials[mc('cobblestone')].workerId,3)
  eq(r.materials[mc('raw_iron')].target,6); eq(r.materials[mc('cobblestone')].count,0)
  eq(#app.packets,2); assert(r.materials[mc('raw_iron')].jobId~=r.materials[mc('cobblestone')].jobId)
  eq(next(q.state.jobs),nil)
end)
test('production missing mining workers reports every resource and recovers when eligible workers arrive',function()
  local app,p,q=productionFixture()
  app.state.workers['2']=miningWorker(2,mc('coal'),20)
  local r=p:request({[mc('raw_iron')]=6,[mc('cobblestone')]=8}); p:tick()
  assert(r.error:find('No online mining worker',1,true),r.error)
  assert(r.materials[mc('raw_iron')].error:find('raw_iron',1,true))
  assert(r.materials[mc('cobblestone')].error:find('cobblestone',1,true))
  local ironId=r.materials[mc('raw_iron')].jobId
  app.state.workers['3']=miningWorker(3,mc('raw_iron'),40); p:tick(); app.mining:tick(); p:tick()
  eq(r.materials[mc('raw_iron')].jobId,ironId); eq(r.materials[mc('raw_iron')].workerId,3)
  eq(r.materials[mc('raw_iron')].error,nil)
end)
test('production waits for configured farms and discovers newly configured farms',function()
  local app,p,q,config=productionFixture(); local r=p:request({[mc('oak_log')]=4}); p:tick()
  assert(r.error:find('No configured farm',1,true),r.error); eq(next(q.state.jobs),nil)
  config.treeFarms={{item=mc('oak_log'),base={x=0,y=0,z=0}}}; p:tick()
  local material=r.materials[mc('oak_log')]; eq(q.state.jobs[material.jobId].type,'HARVEST')
  eq(material.error,nil)
end)
test('production recovers after furnaces and crafting workers become available',function()
  local app,p,q,config,h=productionFixture({[1]={name=mc('cobblestone'),count=4},[2]={name=mc('coal'),count=1}})
  config.furnaces={}; local r=p:request({[mc('stone_bricks')]=4}); p:tick()
  assert(r.error:find('No configured furnaces',1,true),tostring(r.error)); eq(next(q.state.jobs),nil)
  config.furnaces={'furnace'}; p:tick(); assert(r.jobIds)
  local job=q.state.jobs[r.jobIds[1]]; eq(job.furnaceLane,'furnace')
  for _=1,30 do p:tick();p:step();h:smelt() end
  eq(job.status,'completed')
  assert(r.error:find('No available crafting',1,true),tostring(r.error)); eq(r.jobId,nil)
  app.state.workers['9']={id=9,online=true,telemetry={capabilities={crafting=true}}}; p:tick()
  eq(q.state.jobs[r.jobId].type,'CRAFT'); eq(r.error,nil); eq(r.status,'running')
end)
test('stock-only preparation reports all missing stock without acquiring or replenishing global reserves',function()
  local app,p,q,config,h=productionFixture({[1]={name=mc('dirt'),count=1}})
  config.turtleFuelReserveItems={[mc('coal')]=32}
  local r=p:request({[mc('dirt')]=2,[mc('oak_planks')]=4},nil,{stockOnly=true}); p:tick()
  eq(r.status,'blocked'); eq(next(app.state.jobs),nil); eq(next(q.state.jobs),nil)
  eq(r.materials[mc('dirt')].count,1); eq(r.materials[mc('oak_planks')].target,4)
  h.inventories.store={[1]={name=mc('dirt'),count=2},[2]={name=mc('oak_planks'),count=4}}; p:tick()
  eq(r.status,'completed'); eq(r.materials[mc('dirt')].status,'ready'); eq(r.error,nil)
end)
test('production refuses an unpersisted project request and rolls back its in-memory link',function()
  local app,p,q=productionFixture(); q.state.projects.house={phase='imported',stockOnly=true}
  function app:save() return false,'disk full' end
  local ok,err=pcall(p.request,p,{[mc('dirt')]=2},'project:house',{projectName='house'})
  assert(not ok and tostring(err):find('disk full',1,true),'request must report checkpoint failure')
  eq(q.state.projects.house.phase,'imported'); eq(q.state.projects.house.requestId,nil)
  eq(q.state.projects.house.stockOnly,true); eq(next(q.state.requests),nil); eq(q.state.requestSequence,0)
end)
test('production resumes saved acquisition without duplicating mining jobs and completes from delivered stock',function()
  local app,p,q,config,h=productionFixture()
  local r=p:request({[mc('cobblestone')]=8}); p:tick(); local id=r.mines[mc('cobblestone')]
  app.state=U.copy(app.saved)
  local clock=function() return app.now end
  app.mining=require('autobuilder.core.mining_service').new(app,config,h,{send=function() return true end},clock)
  q=require('autobuilder.core.workflows').new(app.state,function() return app:save() end,clock,1)
  p=require('autobuilder.core.production_service').new(app,config,h,q); r=q.state.requests[r.id]
  app.state.workers['3']=miningWorker(3,mc('cobblestone'),40); p:tick(); app.mining:tick(); p:tick()
  eq(r.materials[mc('cobblestone')].jobId,id); eq(app.state.jobSequence,1)
  h.inventories.store[1]={name=mc('cobblestone'),count=8}; p:tick()
  eq(r.status,'completed'); eq(r.materials[mc('cobblestone')].count,8)
end)
test('production replans consumed output with new factory jobs instead of reusing completed operations',function()
  local app,p,q,config,h=productionFixture({[1]={name=mc('oak_log'),count=2}})
  app.state.workers['9']={id=9,online=true,telemetry={capabilities={crafting=true}}}
  local r=p:request({[mc('oak_planks')]=4}); p:tick(); local first=r.jobId
  q.state.jobs[first].status='completed'; h.inventories.store[1].count=1
  p:tick(); p:tick(); p:tick()
  assert(r.jobId~=first,'replacement operation must not adopt the already completed craft')
  eq(q.state.jobs[r.jobId].status,'queued')
end)
test('production completion checks the resolved substitution rather than requesting the original item again',function()
  local app,p,q,config=productionFixture({[1]={name=mc('spruce_planks'),count=4}})
  config.substitutions={[mc('oak_planks')]=mc('spruce_planks')}
  local r=p:request({[mc('oak_planks')]=4}); p:tick()
  eq(r.status,'completed'); eq(r.replans,nil)
end)
test('production availability uses the same strict resource eligibility as mining dispatch',function()
  local app,p=productionFixture()
  app.state.workers['2']=miningWorker(2,mc('raw_iron'),20)
  app.state.workers['2'].telemetry.miningResources[3]=mc('coal')
  local r=p:request({[mc('raw_iron')]=6}); p:tick()
  assert(r.materials[mc('raw_iron')].error and r.materials[mc('raw_iron')].error:find('No online mining worker',1,true))
end)
test('material progress keeps live stock counts after acquisition while factory inputs are consumed',function()
  local app,p,q,config,h=productionFixture({[1]={name=mc('coal'),count=1}})
  local r=p:request({[mc('stone')]=4}); p:tick()
  h.inventories.store[2]={name=mc('cobblestone'),count=4}; p:tick()
  eq(r.materials[mc('cobblestone')].status,'ready')
  p:syncClaims();h.limit=2;p:step();p:tick()
  eq(r.materials[mc('cobblestone')].count,2)
  eq(r.materials[mc('cobblestone')].status,'ready'); assert(r.acquired)
end)

test('dependency graph aggregates shared demand without counting planned surplus as original stock',function()
  local p=require('autobuilder.blueprint.planner').expand({[mc('oak_slab')]=6,[mc('oak_stairs')]=8},
    {[mc('oak_planks')]=2,[mc('oak_log')]=2,[mc('oak_stairs')]=4})
  local nodes=assert(p.graph,'explicit dependency graph missing').nodes
  local planks=nodes[mc('oak_planks')]; eq(planks.required,9); eq(planks.available,2)
  eq(planks.deficit,7); eq(planks.produced,8); eq(planks.inputs[mc('oak_log')],2)
  eq(nodes[mc('oak_stairs')].projectRequired,8); eq(nodes[mc('oak_stairs')].produced,4)
  eq(nodes[mc('oak_log')].deficit,0); eq(nodes[mc('oak_log')].provider.type,'storage')
  eq(planks.provider.type,'crafting'); eq(p.available[mc('oak_planks')],1)
  eq(#p.operations,4); eq(#p.operations[1].dependencies,0)
  eq(p.operations[2].dependencies[1],p.operations[1].id)
  eq(#p.operations[4].dependencies,2)
  eq(p.operations[4].dependencies[1],p.operations[1].id)
  eq(p.operations[4].dependencies[2],p.operations[3].id)
end)

test('dependency graph includes reserve and processing fuel without crediting expected output',function()
  local p=require('autobuilder.blueprint.planner').expand({[mc('stone_bricks')]=4},{[mc('coal')]=1},
    {turtleFuelReserveItems={[mc('coal')]=2}})
  local n=assert(p.graph,'explicit dependency graph missing').nodes
  eq(n[mc('coal')].required,3); eq(n[mc('coal')].available,1)
  eq(n[mc('coal')].deficit,2); eq(n[mc('coal')].missing,2)
  eq(n[mc('cobblestone')].required,4); eq(n[mc('cobblestone')].missing,4)
  eq(n[mc('stone')].available,0); eq(n[mc('stone')].produced,4)
  eq(n[mc('stone_bricks')].inputs[mc('stone')],4)
end)

test('planner rejects malformed recipes and bounded expansion before producing a graph',function()
  local P=require('autobuilder.blueprint.planner')
  for _,recipe in ipairs({{kind='craft',yield=0,ingredients={raw=1}},
    {kind='craft',yield=1,ingredients={raw=-1}}, {kind='unknown',yield=1,ingredients={raw=1}},
    {kind='craft',yield=0/0,ingredients={raw=1}}, {kind='craft',yield=1,ingredients={}}}) do
    local registry={get=function(item) if item=='root' then return recipe end end}
    assert(not pcall(P.expand,{root=1},{},{recipes=registry}),'malformed recipe accepted')
  end
  local registry={get=function(item) if item=='root' then return {kind='craft',yield=1,ingredients={raw=64}} end end}
  assert(not pcall(P.expand,{root=100000000},{},{recipes=registry}),'unbounded expanded demand accepted')
  assert(not pcall(P.expand,{a=100000000,b=100000000},{},{substitutions={a='root',b='root'}}),'aggregate overflow accepted')
  local cycle={get=function(item) return {kind='craft',yield=1,ingredients={[item=='a' and 'b' or 'a']=1}} end}
  assert(not pcall(P.expand,{a=1},{a=1},{recipes=cycle}),'stock must not hide an invalid recipe cycle')
end)

test('production honors available farm preference and preserves its offline owner across restart',function()
  local app,p,q,config,h=productionFixture(); local item=mc('dirt')
  config.farms={{item=item,base={x=20,y=0,z=0}}}
  config.providerPreferences={[item]={'farm','mining'}}
  app.state.workers['2']=miningWorker(2,item,40)
  app.state.workers['3']={id=3,online=true,telemetry={capabilities={farming=true}}}
  local r=p:request({[item]=4}); p:tick()
  local material=r.materials[item]; local id=material.jobId
  eq(material.provider,'farm:'..item..':1'); eq(q.state.jobs[id].type,'FARM'); eq(next(app.state.jobs),nil)
  q.state.jobs[id].status='running'; q.state.jobs[id].workerId=3
  app.state.workers['3'].online=false; app:save(); app.state=U.copy(app.saved)
  config.providerPreferences={[item]={'mining'}}; config.farms={}
  q=require('autobuilder.core.workflows').new(app.state,function() return app:save() end,function() return 0 end,1)
  p=require('autobuilder.core.production_service').new(app,config,h,q); r=q.state.requests[r.id]; p:tick()
  eq(r.materials[item].jobId,id); eq(r.materials[item].workerId,3)
  eq(r.materials[item].provider,'farm:'..item..':1'); eq(q.state.jobs[id].farm.base.x,20)
  eq(next(app.state.jobs),nil)
end)

test('production falls back to online mining then retains ownership when preferred farm arrives',function()
  local app,p,q,config=productionFixture(); local item=mc('dirt')
  config.farms={{item=item,base={x=20,y=0,z=0}}}; config.providerPreferences={[item]={'farm','mining'}}
  app.state.workers['2']=miningWorker(2,item,40)
  local r=p:request({[item]=4}); p:tick(); local id=r.mines[item]
  eq(r.materials[item].provider,'mining:'..item); assert(id)
  app.state.workers['3']={id=3,online=true,telemetry={capabilities={farming=true}}}; p:tick()
  eq(r.materials[item].jobId,id); eq(next(q.state.jobs),nil)
end)

test('resource summary reports current physical stock separately from planned demand and output',function()
  local app,p,q,config,h=productionFixture({[1]={name=mc('oak_log'),count=2}})
  local r=p:request({[mc('oak_planks')]=4}); p:tick()
  h.inventories.store[2]={name=mc('oak_planks'),count=1}
  local summary=p:describe(mc('oak_planks'))
  assert(summary:find('stock=1',1,true),summary); assert(summary:find('required=4',1,true),summary)
  assert(summary:find('planned=4',1,true),summary); assert(summary:find('deficit=4',1,true),summary)
  assert(summary:find('crafting:minecraft:oak_planks',1,true),summary)
  eq(next(q.state.jobs),nil); eq(r.operation,1)
  assert(p:describe('mod:unknown'):find('No configured provider',1,true))
end)

test('unassigned unavailable acquisition can switch to a newly online provider without stealing ownership',function()
  local app,p,q,config=productionFixture(); local item=mc('dirt')
  config.farms={{item=item,base={x=20,y=0,z=0}}}; config.providerPreferences={[item]={'mining','farm'}}
  local r=p:request({[item]=4}); p:tick(); local old=r.mines[item]; assert(old)
  app.state.workers['3']={id=3,online=true,telemetry={capabilities={farming=true}}}; p:tick()
  eq(r.materials[item].provider,'farm:'..item..':1'); eq(r.mines[item],nil)
  eq(app.state.jobs[old].status,'completed'); eq(app.state.jobs[old].cancelled,true)
  eq(q.state.jobs[r.materials[item].jobId].type,'FARM')
end)

test('provider switching rolls back if its retirement checkpoint fails',function()
  local app,p,q,config=productionFixture(); local item=mc('dirt')
  config.farms={{item=item,base={x=20,y=0,z=0}}}
  local r=p:request({[item]=4}); p:tick(); local old=r.mines[item]
  app.state.workers['3']={id=3,online=true,telemetry={capabilities={farming=true}}}
  function app:save() return false,'disk full' end
  assert(not pcall(p.tick,p)); eq(r.mines[item],old); eq(app.state.jobs[old].status,'queued')
  eq(next(q.state.jobs),nil)
end)

test('factory jobs require durable ingredient grants and competing claims recover after stock arrives',function()
  local app,p,q,config,h=productionFixture({[1]={name=mc('stone'),count=4}})
  app.state.workers['9']={id=9,online=true,telemetry={status='idle',capabilities={crafting=true}}}
  local r=p:request({[mc('stone_bricks')]=4}); p:tick()
  local first=q.state.jobs[r.jobId]; eq(assert(first.stockInputs,'factory input contract missing')[mc('stone')],4)
  local second=q:submit('CRAFT',{item=mc('stone_bricks'),quantity=4,batches=1,
    stockInputs={[mc('stone')]=4},stockOutputs={[mc('stone_bricks')]=4}},{})
  eq(q:assign(app.state.workers),nil) -- no grant until reconciliation
  p:tick(); assert(app.state.inventoryLedger.leases[first.id]); eq(app.state.inventoryLedger.leases[second.id],nil)
  eq(q:assign(app.state.workers).id,first.id)
  h.inventories.store={[1]={name=mc('stone_bricks'),count=4}}; first.status='completed'; p:tick()
  eq(app.state.inventoryLedger.leases[first.id].status,'released'); eq(q:assign(app.state.workers),nil)
  h.inventories.store[2]={name=mc('stone'),count=4}; p:tick()
  eq(q:assign(app.state.workers).id,second.id)
end)

test('ungranted furnace task makes no physical transfer and recovers from unavailable stock',function()
  local app,p,q,config,h=productionFixture()
  local job=q:submit('SMELT',{item=mc('stone'),quantity=1,batches=1,furnaceLane='furnace',
    stockInputs={[mc('cobblestone')]=1,[mc('coal')]=1},stockOutputs={[mc('stone')]=1}},{})
  p:step(); eq(next(h.inventories.furnace),nil); eq(job.production,nil)
  p:tick(); eq(app.state.inventoryLedger.leases[job.id],nil)
  h.inventories.store={[1]={name=mc('cobblestone'),count=1},[2]={name=mc('coal'),count=1}}
  p:tick(); p:step(); assert(job.production); eq(job.production.loaded,1)
  local lease=app.state.inventoryLedger.leases[job.id]; eq(lease.withdrawn[mc('cobblestone')],1)
end)

test('resource status distinguishes measured stock from reservations and expected output',function()
  local app,p,q,config,h=productionFixture({[1]={name=mc('stone'),count=4}})
  app.state.workers['9']={id=9,online=true,telemetry={capabilities={crafting=true}}}
  local r=p:request({[mc('stone_bricks')]=4}); p:tick(); p:tick()
  local text=p:describe(mc('stone'))
  assert(text:find('stock=4 available=0 reserved=4 transit=0 expected=0 demand=4',1,true),text)
  text=p:describe(mc('stone_bricks'))
  assert(text:find('stock=0 available=0 reserved=0 transit=0 expected=4 demand=4',1,true),text)
end)

test('inventory grants cannot race a yielding storage snapshot against a furnace transfer',function()
  local app,p,q,config,h=productionFixture({[1]={name=mc('cobblestone'),count=4},[2]={name=mc('coal'),count=1}})
  local a=q:submit('SMELT',{item=mc('stone'),quantity=4,batches=4,furnaceLane='furnace',
    stockInputs={[mc('cobblestone')]=4,[mc('coal')]=1},stockOutputs={[mc('stone')]=4}},{})
  p:tick(); assert(app.state.inventoryLedger.leases[a.id])
  local b=q:submit('CRAFT',{item=mc('stone_bricks'),quantity=4,batches=1,
    stockInputs={[mc('cobblestone')]=4},stockOutputs={[mc('stone_bricks')]=4}},{})
  local call=h.peripheral.call; local yielded=false
  h.peripheral.call=function(name,method,...)
    local result=call(name,method,...)
    if name=='store' and method=='list' and not yielded then
      yielded=true; p:step() -- action coroutine runs after list captured its result
    end
    return result
  end
  p:tick(); assert(yielded); eq(app.state.inventoryLedger.leases[b.id],nil)
end)

test('satisfied unowned mining and harvest demand retires durably before stock is spent',function()
 for _,farm in ipairs({false,true}) do
  local app,p,q,config,h=productionFixture();local item=farm and mc('oak_log') or mc('raw_iron')
  if farm then config.treeFarms={{item=item,base={x=2,y=0,z=0}}} end
  local r=p:request({[item]=4});p:tick();local id=(farm and r.harvests or r.mines)[item];local j=(farm and q.state.jobs or app.state.jobs)[id]
  h.inventories.store[1]={name=item,count=4};p:tick();eq(r.status,'completed');eq(j.status,'completed');eq(j.cancelled,true)
  local saved=farm and app.saved.automation.jobs[id] or app.saved.jobs[id];eq(saved.cancelled,true)
  h.inventories.store={};app.state.workers['2']=miningWorker(2,item,20);app.mining:tick();eq(j.workerId,nil)
 end
end)
test('obsolete acquisition retirement rolls back on failed persistence and preserves possible owners',function()
 local app,p,q,config,h=productionFixture();local item=mc('raw_iron');local r=p:request({[item]=4});p:tick();local j=app.state.jobs[r.mines[item]]
 h.inventories.store[1]={name=item,count=4};local save=app.save;app.save=function() return false,'disk full' end
 eq(pcall(p.tick,p),false);eq(j.status,'queued');eq(j.cancelled,nil);eq(r.acquired,nil)
 app.save=save;app.state.workers['2']={id=2,online=false,telemetry={task=j.id}};p:tick();eq(j.status,'queued');eq(j.cancelled,nil)
 local a,service,queue,c,hardware=productionFixture();local req=service:request({[item]=4});service:tick();local job=a.state.jobs[req.mines[item]]
 job.intent={action='owned'};hardware.inventories.store[1]={name=item,count=4};service:tick();eq(job.status,'queued');eq(job.cancelled,nil)
end)
test('satisfied acquisition does not retire demand shared with another unfinished consumer',function()
 local app,p,q,config,h=productionFixture();local item=mc('raw_iron');local r=p:request({[item]=4});p:tick();local id=r.mines[item]
 local other=p:request({[item]=8});other.mines[item]=id
 h.inventories.store[1]={name=item,count=4};p:tick();eq(app.state.jobs[id].status,'queued');eq(app.state.jobs[id].cancelled,nil)
end)

test('unowned farm switches capability contracts durably while preserving existing owners',function()
 for _,mode in ipairs({'switch','save-failure','assigned','offline','journal'}) do
  local app,p,q,c=productionFixture();local item=mc('wheat')
  c.farms={{kind='custom',item=item,sites={{x=20,y=0,z=0}}},{kind='wheat',item=item,sites={{x=25,y=0,z=0}}}}
  c.farmAdapters={custom={mode='crop',block='test:crop',item=item,seed='test:seed',age=4}}
  local modern={capabilities={registeredFarmingV1=true},health={placing=true,movement=true,digging=true,left='unknown',right='unknown',software={status='unmanaged'}}}
  app.state.workers['3']={id=3,online=true,telemetry=modern}
  local r=p:request({[item]=4});p:tick();local id=r.harvests[item];local old=q.state.jobs[id];assert(old)
  modern.health.software.status='modified';app.state.workers['4']={id=4,online=true,telemetry={capabilities={farming=true}}}
  if mode=='assigned' then old.workerId=3 elseif mode=='offline' then modern.task=id;app.state.workers['3'].online=false elseif mode=='journal' then old.intent={kind='dig'} end
  if mode=='save-failure' then function app:save() return false,'disk full' end;eq(pcall(p.tick,p),false);eq(r.harvests[item],id);eq(old.status,'queued')
  else p:tick()
   if mode=='switch' then eq(old.cancelled,true);assert(r.harvests[item]~=id);eq(q.state.jobs[r.harvests[item]].farm.kind,'wheat')
   else eq(r.harvests[item],id);eq(old.cancelled,nil) end
  end
 end
end)

test('priority manufacturing admits one request bank and retires only losing unclaimed preferences',function()
 local app,p,q,config,h=productionFixture({[1]={name=mc('cobblestone'),count=8},[2]={name=mc('coal'),count=2}})
 q.state.projects.low={name='low',priority=20};q.state.projects.high={name='high',priority=80}
 local low=p:request({[mc('stone')]=4},'project:low',{projectName='low'});p:tick()
 local old=q.state.jobs[low.jobIds[1]];assert(old);eq(old.workerId,nil)
 local high=p:request({[mc('stone')]=8},'project:high',{projectName='high'});p:tick()
 eq(old.cancelled,true);eq(old.status,'completed')
 assert(high.jobIds and #high.jobIds>0);eq(low.jobIds,nil)
 for _,j in pairs(q.state.jobs) do if j.status~='completed' then eq(j.productionRequest,high.id) end end
 p:step();assert(not tostring(high.error):find('duplicate ownership',1,true))
end)
test('priority handover preserves held factory inputs and chooses the next uncommitted batch',function()
 local app,p,q,config,h=productionFixture({[1]={name=mc('cobblestone'),count=12},[2]={name=mc('coal'),count=3}})
 q.state.projects.low={name='low',priority=20};q.state.projects.high={name='high',priority=80}
 local low=p:request({[mc('stone')]=4},'project:low',{projectName='low'});p:tick();p:syncClaims()
 local owned=q.state.jobs[low.jobIds[1]];assert(p.ledger.state.leases[owned.id]);local original=U.copy(owned)
 local high=p:request({[mc('stone')]=8},'project:high',{projectName='high'});p:tick()
 eq(high.jobIds,nil);eq(owned.cancelled,nil);eq(owned.quantity,original.quantity);eq(p.ledger.state.leases[owned.id].status,'held')
 for _=1,100 do p:step();h:smelt();p:tick() end
 assert(high.status=='completed',high.error);eq(low.status,'completed')
end)

test('uncommitted factory input loss replans acquisition instead of leaving a mining barrier',function()
 local app,p,q,config,h=productionFixture({[1]={name=mc('cobblestone'),count=4},[2]={name=mc('coal'),count=1}})
 local r=p:request({[mc('stone')]=4});p:tick();local old=q.state.jobs[r.jobIds[1]]
 h.inventories.store[1]=nil;p:tick();eq(old.cancelled,true);eq(old.status,'completed');eq(r.plan,nil)
 app.state.workers['2']=miningWorker(2,mc('cobblestone'),20);p:tick()
 assert(r.mines[mc('cobblestone')]);eq(require('autobuilder.core.workflows').factoryPending(app.state),false)
 h.inventories.store[1]={name=mc('cobblestone'),count=4}
 for _=1,60 do p:tick();p:step();h:smelt() end;eq(r.status,'completed')
end)
test('failed unclaimed factory retirement restores live records and retry survives reboot',function()
 local app,p,q,config,h=productionFixture({[1]={name=mc('cobblestone'),count=8},[2]={name=mc('coal'),count=2}})
 q.state.projects.low={name='low',priority=20};q.state.projects.high={name='high',priority=80}
 local low=p:request({[mc('stone')]=4},'project:low',{projectName='low'});p:tick();local old=q.state.jobs[low.jobIds[1]]
 local high=p:request({[mc('stone')]=8},'project:high',{projectName='high'});local save=app.save
 function app:save() if old.cancelled then return false,'disk full' end;return save(self) end
 assert(not pcall(p.tick,p));eq(old.cancelled,nil);eq(old.status,'queued');assert(low.jobIds);assert(q.state.jobs[old.id]==old)
 app.save=save;p:tick();eq(old.cancelled,true);assert(high.jobIds)
 app.state=U.copy(app.saved);q=require('autobuilder.core.workflows').new(app.state,function() return app:save() end,function() return app.now end,1)
 p=require('autobuilder.core.production_service').new(app,config,h,q)
 for _=1,80 do p:tick();p:step();h:smelt() end
 eq(q.state.requests[high.id].status,'completed');eq(q.state.requests[low.id].status,'completed')
 eq(require('autobuilder.factory.factory').count(h.inventories.store,mc('stone')),8)
end)

test('unavailable high priority crafting leaves feasible furnace admission and claims free',function()
 for _,mode in ipairs({'blocked','busy','lost'}) do
  local app,p,q,config,h=productionFixture({[1]={name=mc('stone'),count=4},[2]={name=mc('cobblestone'),count=8},[3]={name=mc('coal'),count=2}})
  q.state.projects.low={name='low',priority=20};q.state.projects.high={name='high',priority=80}
  local w={id=9,online=true,telemetry={status='idle',capabilities={crafting=true}}};app.state.workers['9']=w
  local low=p:request({[mc('stone')]=8},'project:low',{projectName='low'});p:tick()
  local high=p:request({[mc('stone_bricks')]=4},'project:high',{projectName='high'})
  if mode=='lost' then p:tick();assert(high.jobId) end
  w.telemetry.status=mode=='blocked' and 'blocked' or 'idle';w.telemetry.task=mode~='blocked' and 'unrelated' or nil
  for _=1,80 do p:tick();p:step();h:smelt() end
  eq(low.status,'completed');assert(h.calls>0);eq(high.status=='completed',false)
  for _,j in pairs(q.state.jobs) do if j.productionRequest==high.id then eq(p.ledger.state.leases[j.id],nil) end end
  w.telemetry.status='idle';w.telemetry.task=nil;p:tick();p:syncClaims();assert(high.jobId)
  eq(p.ledger.state.leases[high.jobId].status,'held')
 end
end)
test('priority operation transition admits ready next craft before lower new smelting',function()
 local app,p,q,config,h=productionFixture({[1]={name=mc('cobblestone'),count=8},[2]={name=mc('coal'),count=2}})
 app.state.workers['9']={id=9,online=true,telemetry={status='idle',capabilities={crafting=true}}}
 q.state.projects.low={name='low',priority=20};q.state.projects.high={name='high',priority=80}
 local high=p:request({[mc('stone_bricks')]=4},'project:high',{projectName='high'});p:tick();p:syncClaims()
 local first=q.state.jobs[high.jobIds[1]]
 local low=p:request({[mc('stone')]=8},'project:low',{projectName='low'})
 for _=1,80 do p:step();h:smelt();if first.status=='completed' then break end end
 eq(first.status,'completed');p:tick();p:syncClaims()
 eq(high.operation,2);local craft=assert(q.state.jobs[high.jobId]);eq(craft.type,'CRAFT');eq(p.ledger.state.leases[craft.id].status,'held')
 for _,j in pairs(q.state.jobs) do if j.productionRequest==low.id and j.status~='completed' then error('lower request admitted before ready high craft') end end
end)
test('shared mining follows highest active consumer and survives original project pause and reboot',function()
 local app,p,q,config,h=productionFixture();local S=require('autobuilder.core.scheduling')
 for name,priority in pairs({low=20,medium=50,high=80}) do q.state.projects[name]={name=name,priority=priority,jobs={}} end
 local low=p:request({[mc('raw_iron')]=4},'project:low',{projectName='low'});p:tick();local id=low.mines[mc('raw_iron')]
 local projects=require('autobuilder.blueprint.projects').new(app,config,h,q,p)
 projects:command({'build','pause','low'});eq(app.state.jobs[id].paused,true)
 local medium=p:request({[mc('cobblestone')]=4},'project:medium',{projectName='medium'})
 local high=p:request({[mc('raw_iron')]=4},'project:high',{projectName='high'});p:tick()
 eq(high.mines[mc('raw_iron')],id);eq(S.priority(app.state,app.state.jobs[id]),80);eq(app.state.jobs[id].paused,false)
 app.state=U.copy(app.saved);q=require('autobuilder.core.workflows').new(app.state,function() return app:save() end,function() return 0 end,1)
 app.mining=require('autobuilder.core.mining_service').new(app,config,h,{send=function() return true end},function() return 0 end)
 p=require('autobuilder.core.production_service').new(app,config,h,q)
 local w=miningWorker(2,mc('raw_iron'),40);w.telemetry.miningResources={mc('raw_iron'),mc('cobblestone')};app.state.workers['2']=w
 eq(app.mining.jobs:assign(app.state.workers,{}).id,id)
 local j=app.state.jobs[id];local area=U.copy(j.miningArea)
 projects=require('autobuilder.blueprint.projects').new(app,config,h,q,p)
 projects:command({'build','resume','low'});projects:command({'build','pause','high'})
 eq(j.paused,false);eq(S.priority(app.state,j),20);eq(j.workerId,2);eq(j.miningArea.min.x,area.min.x)
 projects:command({'build','pause','low'});eq(j.paused,true);eq(j.workerId,2)
end)

local function handoffFixture()
 local app,p,q,c,h=productionFixture({[1]={name=mc('glass'),count=1},[2]={name=mc('cobblestone'),count=4},[3]={name=mc('coal'),count=1}})
 c.supply={inventory='stage',side='down',batch=1};c.supplyStations={}
 local j={id='task:1:90',type='BUILD',status='blocked',workerId=2,missingItem=mc('glass'),missingCount=1,supplyId='batch:1'};q.state.jobs[j.id]=j
 app.state.workers['2']={id=2,online=true,telemetry={task=j.id,status='blocked'}}
 local ready=p:request({[mc('glass')]=1},'supply:'..j.id..':'..mc('glass'))
 local nextRequest=p:request({[mc('stone')]=4})
 return app,p,q,c,h,j,ready,nextRequest
end
test('completed finite supply gets a durable handoff before the next empty factory admission',function()
 local app,p,q,c,h,j,ready,later=handoffFixture();p:tick()
 eq(ready.status,'completed');eq(later.jobIds,nil);assert(require('autobuilder.core.workflows').canOfferSupply(app.state,j))
 app.state=U.copy(app.saved);q=require('autobuilder.core.workflows').new(app.state,function() return app:save() end,function() return app.now end,1)
 p=require('autobuilder.core.production_service').new(app,c,h,q);j=q.state.jobs[j.id];later=q.state.requests[later.id]
 p:tick();eq(later.jobIds,nil)
 p:attemptedSupply(j);eq(app.saved.automation.jobs[j.id].supplyHandoffAttempted.request,ready.id)
 p:tick();assert(later.jobIds,'failed station offer must not indefinitely block manufacturing')
end)
test('finite supply handoff ignores unavailable consumers and preserves committed manufacturing',function()
 for _,mode in ipairs({'offline','paused','newer-request','lower-priority','committed'}) do
  local app,p,q,c,h,j,ready,later=handoffFixture()
  if mode=='offline' then app.state.workers['2'].online=false
  elseif mode=='paused' then j.paused=true
  elseif mode=='lower-priority' then q.state.projects.low={name='low',priority=20};j.project='low'
  elseif mode=='newer-request' then ready.status='completed';p:request({[mc('glass')]=2},ready.key)
  else j.paused=true;p:tick();p:syncClaims();j.paused=nil;assert(later.jobIds);assert(p.ledger.state.leases[later.jobIds[1]]) end
  p:tick();assert(later.jobIds,mode..' incorrectly blocked manufacturing')
 end
end)
test('finite supply handoff marker rolls back and a new completed request gets another opportunity',function()
 local app,p,q,c,h,j,ready,later=handoffFixture();p:tick()
 local save=app.save;app.save=function() return false,'disk full' end
 assert(not pcall(p.attemptedSupply,p,j));eq(j.supplyHandoffAttempted,nil);app.save=save
 p:attemptedSupply(j);local r=p:request({[mc('glass')]=1},ready.key);r.status='completed';app:save();p:tick()
 eq(r.status,'completed');eq(later.jobIds,nil)
 p:attemptedSupply(j);p:tick();assert(later.jobIds)
end)
test('finite supply handoff retires an empty factory preference before it becomes a barrier',function()
 local app,p,q,c,h,j,ready,later=handoffFixture();j.paused=true;p:tick();local old=q.state.jobs[later.jobIds[1]]
 eq(p.ledger.state.leases[old.id],nil);j.paused=nil;p:tick()
 eq(old.cancelled,true);eq(later.jobIds,nil);assert(require('autobuilder.core.workflows').canOfferSupply(app.state,j))
 p:attemptedSupply(j);p:tick();assert(later.jobIds);assert(later.jobIds[1]~=old.id)
end)
