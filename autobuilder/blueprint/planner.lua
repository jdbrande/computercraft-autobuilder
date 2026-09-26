local U=require('autobuilder.core.util')
local Recipes=require('autobuilder.factory.recipes')
local Fuel=require('autobuilder.factory.fuel')
local M={}
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
    resolved[item]=(resolved[item] or 0)+n
  end
  requirements=resolved
  local registry=options.recipes or Recipes
  local p={raw={},operations={},missing={},reserveMissing={},available=U.copy(stock),requirements=U.copy(requirements)}
  local visiting,visited={},{}
  local function validate(item,depth)
    assert(depth<=128,'recipe dependency depth exceeded'); assert(not visiting[item],'recipe cycle at '..item)
    if visited[item] then return end
    visiting[item]=true
    local r=registry.get(item)
    if r then for _,ingredient in ipairs(keys(r.ingredients)) do validate(ingredient,depth+1) end end
    visiting[item]=nil; visited[item]=true
  end
  for _,item in ipairs(keys(requirements)) do validate(item,1) end
  -- Reserves are removed from usable stock before any production demand is allocated.
  for item,n in pairs(options.turtleFuelReserveItems or {}) do
    assert(U.integer(n) and n>=0,'invalid turtle fuel reserve')
    local shortage=math.max(0,n-(p.available[item] or 0))
    if shortage>0 then p.reserveMissing[item]=shortage; p.missing[item]=shortage end
    p.available[item]=math.max(0,(p.available[item] or 0)-n)
  end
  local smelts=0
  local function need(item,n)
    if n==0 then return end
    local r=registry.get(item)
    if not r then p.raw[item]=(p.raw[item] or 0)+n end
    local used=math.min(p.available[item] or 0,n)
    p.available[item]=(p.available[item] or 0)-used; n=n-used
    if n==0 then return end
    if not r then p.missing[item]=(p.missing[item] or 0)+n; return end
    local batches=math.ceil(n/r.yield); local inputs={}
    for _,ingredient in ipairs(keys(r.ingredients)) do inputs[ingredient]=r.ingredients[ingredient]*batches; need(ingredient,inputs[ingredient]) end
    p.operations[#p.operations+1]={type=r.kind=='craft' and 'CRAFT' or 'SMELT',kind=r.kind,item=item,batches=batches,
      quantity=batches*r.yield,inputs=inputs,ingredients=U.copy(inputs)}
    p.available[item]=(p.available[item] or 0)+batches*r.yield-n
    if r.kind=='smelt' then smelts=smelts+batches end
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
  if fuel.missing>0 then p.missing[fuel.item]=(p.missing[fuel.item] or 0)+fuel.missing end
  p.available[fuel.item]=math.max(0,(p.available[fuel.item] or 0)-fuel.items)
  return p
end
return M
