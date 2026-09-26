local U=require('autobuilder.core.util')
local M={}
-- Furnace items per fuel, deliberately excludes buckets and recipe-return containers.
local fuels={['minecraft:coal']=8,['minecraft:charcoal']=8,['minecraft:coal_block']=80,['minecraft:blaze_rod']=12}
function M.capacity(item) return fuels[item] end
function M.partition(batches,furnaces)
  assert(U.integer(batches) and batches>0,'positive smelting batch count required')
  furnaces=furnaces or {}; local seen={}
  for _,name in ipairs(furnaces) do
    assert(U.shortString(name,128) and not seen[name],'invalid or duplicate furnace lane'); seen[name]=true
  end
  local count=math.min(batches,math.max(1,#furnaces)); local lanes={}
  local base,extra=math.floor(batches/count),batches%count
  for i=1,count do lanes[i]={batches=base+(i<=extra and 1 or 0),furnaceLane=furnaces[i]} end
  return lanes
end
function M.plan(smelts,stock,options)
  options=options or {}; stock=stock or {}
  local item=options.smeltingFuelItem or 'minecraft:coal'; local capacity=assert(fuels[item],'unsupported furnace fuel')
  assert(U.integer(smelts) and smelts>=0,'invalid smelting demand')
  local reserve=(options.turtleFuelReserveItems or {})[item] or 0
  assert(U.integer(reserve) and reserve>=0,'invalid turtle fuel reserve')
  local count=math.ceil(smelts/capacity)
  return {item=item,items=count,smelts=smelts,capacity=capacity,reserved=reserve,
    missing=math.max(0,count-math.max(0,(stock[item] or 0)-reserve))}
end
function M.available(item,stock,options)
  return math.max(0,(stock[item] or 0)-(((options or {}).turtleFuelReserveItems or {})[item] or 0))
end
return M
