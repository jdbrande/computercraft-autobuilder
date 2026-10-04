local U=require('autobuilder.core.util')
local Recipes=require('autobuilder.factory.recipes')
local Fuel=require('autobuilder.factory.fuel')
local Providers=require('autobuilder.resources.providers')
local Processors=require('autobuilder.factory.processors')
local M={}
local function bounded(n) assert(U.integer(n) and n>=0 and n<=100000000,'expanded item count exceeds limit'); return n end
local function keys(t) local out={}; for k in pairs(t) do out[#out+1]=k end; table.sort(out); return out end
local function counts(t)
  assert(type(t)=='table','item counts required')
  for k,v in pairs(t) do assert(U.shortString(k,128) and U.integer(v) and v>=0 and v<=100000000,'invalid item count') end
end
function M.expand(requirements,stock,options)
  options=options or {}; stock=stock or {}; counts(requirements); counts(stock)
  local resolved={}
  for item,n in pairs(requirements) do
    local seen={}
    while (options.substitutions or {})[item] do
      assert(not seen[item],'material substitution cycle'); seen[item]=true
      item=options.substitutions[item]; assert(U.shortString(item,128),'invalid substitute item')
    end
    resolved[item]=bounded((resolved[item] or 0)+n)
  end
  requirements=resolved
  local registry=options.recipes or Recipes
  local function recipe(item) return Processors.recipe(options,item) or registry.get(item) end
  local p={raw={},operations={},missing={},reserveMissing={},available=U.copy(stock),requirements=U.copy(requirements),graph={nodes={}}}
  local visiting,visited={},{}
  local visitedCount=0
  local function validate(item,depth)
    assert(depth<=128,'recipe dependency depth exceeded'); assert(not visiting[item],'recipe cycle at '..item)
    if visited[item] then return end
    visiting[item]=true
    local r=recipe(item)
    visitedCount=visitedCount+1; assert(visitedCount<=4096,'recipe graph item limit exceeded')
    if r then
      assert((r.kind=='craft' or r.kind=='smelt' or r.kind=='process') and U.integer(r.yield) and r.yield>=1 and r.yield<=64,'invalid planner recipe')
      assert(type(r.ingredients)=='table' and next(r.ingredients),'recipe needs ingredients')
      for ingredient,n in pairs(r.ingredients) do
        assert(U.shortString(ingredient,128) and U.integer(n) and n>=1 and n<=64,'invalid planner ingredient')
      end
      for _,ingredient in ipairs(keys(r.ingredients)) do validate(ingredient,depth+1) end
      if r.fuel then validate(r.fuel.item,depth+1) end
    end
    visiting[item]=nil; visited[item]=true
  end
  for _,item in ipairs(keys(requirements)) do validate(item,1) end
  local nodeCount=0
  local function demand(item,n)
    local node=p.graph.nodes[item]
    if not node then
      nodeCount=nodeCount+1; assert(nodeCount<=4096,'resource graph item limit exceeded')
      node={item=item,required=0,available=stock[item] or 0,produced=0,projectRequired=requirements[item] or 0,inputs={}}
      p.graph.nodes[item]=node
    end
    node.required=bounded(node.required+n); return node
  end
  -- Reserves are removed from usable stock before any production demand is allocated.
  for item,n in pairs(options.turtleFuelReserveItems or {}) do
    assert(U.shortString(item,128),'invalid turtle fuel reserve item'); bounded(n)
    if n>0 then demand(item,n).reserved=n end
    local shortage=math.max(0,n-(p.available[item] or 0))
    if shortage>0 then p.reserveMissing[item]=shortage; p.missing[item]=shortage end
    p.available[item]=math.max(0,(p.available[item] or 0)-n)
  end
  local physical=U.copy(p.available); local lots={}; local steps=0
  local smelts=0
  local function need(item,n)
    bounded(n); if n==0 then return {} end
    steps=steps+1; assert(steps<=65536,'resource expansion step limit exceeded')
    local node=demand(item,n); local dependencies={}
    local r=recipe(item)
    if not r then p.raw[item]=bounded((p.raw[item] or 0)+n) end
    local used=math.min(p.available[item] or 0,n)
    p.available[item]=(p.available[item] or 0)-used; n=n-used
    local original=math.min(physical[item] or 0,used)
    physical[item]=(physical[item] or 0)-original; local planned=used-original
    for _,lot in ipairs(lots[item] or {}) do
      local take=math.min(planned,lot.count)
      if take>0 then dependencies[lot.id]=true; lot.count=lot.count-take; planned=planned-take end
      if planned==0 then break end
    end
    assert(planned==0,'planned inventory provenance mismatch')
    if n==0 then return dependencies end
    if not r then p.missing[item]=bounded((p.missing[item] or 0)+n); return dependencies end
    local batches=math.ceil(n/r.yield); local inputs={}
    local before={};local lanes=r.kind=='process' and Processors.lanes(r,batches) or nil
    if r.fuel then
      local fuel=batches -- Streaming and outages cannot promise residual burn between batches.
      inputs[r.fuel.item]=fuel;node.inputs[r.fuel.item]=(node.inputs[r.fuel.item] or 0)+fuel
      for id in pairs(need(r.fuel.item,fuel)) do before[id]=true end
    end
    for _,ingredient in ipairs(keys(r.ingredients)) do
      inputs[ingredient]=bounded(r.ingredients[ingredient]*batches)
      node.inputs[ingredient]=bounded((node.inputs[ingredient] or 0)+inputs[ingredient])
      for id in pairs(need(ingredient,inputs[ingredient])) do before[id]=true end
    end
    local id=#p.operations+1; assert(id<=4096,'resource plan operation limit exceeded')
    local quantity=bounded(batches*r.yield); node.produced=bounded(node.produced+quantity)
    p.operations[id]={id=id,dependencies=keys(before),type=r.kind=='craft' and 'CRAFT' or r.kind=='process' and 'PROCESS' or 'SMELT',kind=r.kind,item=item,batches=batches,
      quantity=quantity,inputs=inputs,ingredients=U.copy(inputs),lanes=lanes,processRecipe=lanes and U.copy(r) or nil}
    dependencies[id]=true; lots[item]=lots[item] or {}; lots[item][#lots[item]+1]={id=id,count=quantity-n}
    p.available[item]=(p.available[item] or 0)+batches*r.yield-n
    if r.kind=='smelt' then smelts=bounded(smelts+batches) end
    return dependencies
  end
  for _,item in ipairs(keys(requirements)) do need(item,requirements[item]) end
  -- Reserves were already deducted above. Round for each separately scheduled furnace task.
  local fuel=Fuel.plan(smelts,p.available,{smeltingFuelItem=options.smeltingFuelItem})
  fuel.items=0
  for _,op in ipairs(p.operations) do
    if op.kind=='smelt' then
      op.lanes=Fuel.partition(op.batches,options.furnaces)
      for _,lane in ipairs(op.lanes) do fuel.items=fuel.items+math.ceil(lane.batches/fuel.capacity) end
    end
  end
  fuel.reserved=(options.turtleFuelReserveItems or {})[fuel.item] or 0
  fuel.missing=math.max(0,fuel.items-(p.available[fuel.item] or 0)); p.fuel=fuel
  if fuel.missing>0 then p.missing[fuel.item]=bounded((p.missing[fuel.item] or 0)+fuel.missing) end
  p.available[fuel.item]=math.max(0,(p.available[fuel.item] or 0)-fuel.items)
  if fuel.items>0 then demand(fuel.item,fuel.items).fuel=fuel.items end
  for item,node in pairs(p.graph.nodes) do
    node.deficit=math.max(0,node.required-node.available); node.missing=p.missing[item] or 0
    if node.produced>0 then
      -- Describe the recipe actually expanded, not an alternative acquisition.
      for _,candidate in ipairs(Providers.candidates(item,options)) do if candidate.recipe then node.provider=candidate; break end end
    else node.provider,node.error=Providers.select(item,options,{available=node.available,required=node.required,acquisitionOnly=true}) end
  end
  return p
end
return M
