local U=require('autobuilder.core.util')
local Materials=require('autobuilder.resources.materials')
local Recipes=require('autobuilder.factory.recipes')
local M={}
local types={storage=true,exploration=true,mining=true,tree_farm=true,farm=true,crafting=true,smelting=true,processing=true}
function M.validatePreferences(preferences)
  assert(type(preferences)=='table','provider preferences must be a map')
  local items=0
  for item,order in pairs(preferences) do
    items=items+1; assert(items<=4096 and U.shortString(item,128),'invalid provider preference item')
    assert(type(order)=='table','provider preference must be a list')
    local count,seen=0,{}
    for index,kind in pairs(order) do
      assert(U.integer(index) and index>=1 and index<=8 and types[kind] and not seen[kind],'invalid/duplicate provider type')
      seen[kind]=true; count=count+1
    end
    for index=1,count do assert(order[index],'sparse provider preference') end
  end
  return true
end
function M.candidates(item,config)
  assert(U.shortString(item,128),'invalid provider item'); config=config or {}
  local out={}
  local function add(kind,capability,extra)
    local p=extra or {}; p.item=item; p.type=kind; p.capability=capability
    p.id=kind..':'..item..(p.index and ':'..p.index or ''); out[#out+1]=p
  end
  add('storage')
  local recipe=require('autobuilder.factory.processors').recipe(config,item) or (config.recipes or Recipes).get(item)
  if recipe then add(recipe.kind=='craft' and 'crafting' or recipe.kind=='process' and 'processing' or 'smelting',recipe.kind=='craft' and 'crafting' or nil,{recipe=recipe}) end
  if Materials.get(item) then
    local explore=(config.exploration or {}).enabled
    add(explore and 'exploration' or 'mining',explore and 'explorationV1' or 'mining')
  end
  for index,farm in ipairs(config.treeFarms or {}) do if farm.item==item then add('tree_farm','logging',{index=index,farm=require('autobuilder.resources.renewables').freeze(farm,config)}) end end
  for index,farm in ipairs(config.farms or {}) do if farm.item==item then add('farm','farming',{index=index,farm=require('autobuilder.resources.renewables').freeze(farm,config)}) end end
  return out
end
local function available(p,config,context)
  if p.type=='storage' then return (context.available or 0)>=(context.required or 1) end
  if p.type=='processing' then return #p.recipe.machines>0 end
  if p.type=='smelting' then return #(config.furnaces or {})>0 end
  if not context.workers then return true end
  for _,w in pairs(context.workers) do
    local t=w.telemetry
    if w.online and t and t.capabilities and t.capabilities[p.capability]
      and not (p.type=='mining' and t.capabilities.explorationV1)
      and require('autobuilder.workers.health').eligible(t,{type=({tree_farm='HARVEST',farm='FARM',crafting='CRAFT',mining='MINE',exploration='MINE'})[p.type]}) then
      if (p.type~='mining' and p.type~='exploration') or Materials.accepts(t.miningResources,p.item) then return true end
    end
  end
  return false
end
function M.select(item,config,context)
  config=config or {}; context=context or {}
  assert(context.workers==nil or type(context.workers)=='table','invalid provider workers')
  for _,field in ipairs({'available','required'}) do
    local n=context[field]
    assert(n==nil or U.integer(n) and n>=(field=='required' and 1 or 0) and n<=100000000,'invalid provider '..field)
  end
  M.validatePreferences(config.providerPreferences or {})
  local order=(config.providerPreferences or {})[item] or {}; local ranked={}
  for index,p in ipairs(M.candidates(item,config)) do
    p.available=available(p,config,context)
    if p.type=='storage' and p.available then return p end
    if p.type~='storage' and not (context.acquisitionOnly and p.recipe) then
      local rank=#order+index
      for i,kind in ipairs(order) do if p.type==kind then rank=i; break end end
      ranked[#ranked+1]={rank=rank,index=index,provider=p}
    end
  end
  table.sort(ranked,function(a,b)
    if a.provider.available~=b.provider.available then return a.provider.available end
    if a.rank~=b.rank then return a.rank<b.rank end
    return a.index<b.index
  end)
  if ranked[1] then return ranked[1].provider end
  return nil,'No configured provider for '..item
end
return M
