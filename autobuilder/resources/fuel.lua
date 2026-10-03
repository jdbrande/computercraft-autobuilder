local U=require('autobuilder.core.util')
local M={}
M.defaults={enabled=false,item='minecraft:coal',low=200,target=1000,
  values={['minecraft:coal']=80,['minecraft:charcoal']=80,['minecraft:coal_block']=800,['minecraft:lava_bucket']=1000},
  returns={['minecraft:lava_bucket']='minecraft:bucket'},stations={}}
local function bounded(n) return U.integer(n) and n>=0 and n<=100000000 end
function M.validate(policy,config)
  assert(type(policy)=='table' and type(policy.enabled)=='boolean','invalid fuel policy')
  assert(bounded(policy.low) and bounded(policy.target) and policy.target>0 and policy.low<policy.target,'invalid fuel thresholds')
  assert(type(policy.values)=='table' and type(policy.returns)=='table' and type(policy.stations)=='table','invalid fuel maps')
  local total=0
  for item,value in pairs(policy.values) do
    total=total+1; assert(total<=32 and U.shortString(item,128) and bounded(value) and value>0,'invalid fuel value')
  end
  assert(U.shortString(policy.item,128) and policy.values[policy.item],'preferred fuel is not configured')
  total=0
  for item,returned in pairs(policy.returns) do
    total=total+1; assert(total<=32 and policy.values[item] and U.shortString(returned,128),'invalid returned fuel container')
  end
  local ids,inventories,workers={},{},{}
  config=config or {}
  for _,name in ipairs(config.storageInventories or {}) do inventories[name]=true end
  for _,name in ipairs(config.furnaces or {}) do inventories[name]=true end
  for _,field in ipairs({'input','output'}) do
    local name=(config.craftingStation or {})[field]
    if type(name)=='string' and name~='' then inventories[name]=true end
  end
  if config.supply and type(config.supply.inventory)=='string' and config.supply.inventory~='' then inventories[config.supply.inventory]=true end
  total=0
  for index,station in pairs(policy.stations) do
    total=total+1; assert(U.integer(index) and index>=1 and index<=128 and type(station)=='table','invalid fuel station list')
    assert(U.shortString(station.id,64) and not ids[station.id],'invalid/duplicate fuel station ID')
    assert(U.shortString(station.inventory,128) and not inventories[station.inventory],'fuel station needs a dedicated inventory')
    assert(U.integer(station.workerId) and station.workerId>=0 and not workers[station.workerId],'fuel station needs a unique worker')
    assert(U.position(station.position),'fuel station stand requires coordinates')
    assert(policy.values[station.item or policy.item],'unknown station fuel')
    assert(station.targetItems==nil or U.integer(station.targetItems) and station.targetItems>=1 and station.targetItems<=64,'invalid station stock target')
    ids[station.id]=true; inventories[station.inventory]=true; workers[station.workerId]=true
  end
  for index=1,total do assert(policy.stations[index],'sparse fuel station list') end
  return true
end
function M.budget(current,outward,work,returning,reserve)
  assert(current=='unlimited' or bounded(current),'invalid current fuel')
  for _,n in ipairs({outward,work,returning,reserve}) do assert(bounded(n),'invalid fuel budget component') end
  local required=outward+work+returning+reserve; assert(bounded(required),'fuel budget exceeds limit')
  local shortfall=current=='unlimited' and 0 or math.max(0,required-current)
  return {current=current,outward=outward,work=work,returning=returning,reserve=reserve,
    required=required,shortfall=shortfall,allowed=shortfall==0}
end
function M.items(item,current,target,policy)
  policy=policy or M.defaults
  local value=assert(policy.values[item],'unconfigured fuel item')
  local b=M.budget(current,0,0,0,target)
  return math.ceil(b.shortfall/value)
end
function M.allowed(item,config)
  config=config or {}
  if config.fuelItems then return config.fuelItems[item]==true end
  return ((config.fuel or M.defaults).values or {})[item]~=nil
end
function M.returned(item,config)
  for _,returned in pairs(((config or {}).fuel or M.defaults).returns or {}) do if item==returned then return true end end
  return false
end
return M
