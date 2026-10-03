local U=require('autobuilder.core.util')
local Fuel=require('autobuilder.resources.fuel')
local M={}
local containers={['minecraft:chest']=true,['minecraft:trapped_chest']=true,['minecraft:barrel']=true}
function M.new(turtle,config)
  config=config or {}; local self={}; local reserved={}
  for _,slot in ipairs(config.reservedSlots or {15,16}) do reserved[slot]=true end
  function self:snapshot()
    local result={}
    for slot=1,16 do
      local item=turtle.getItemDetail(slot)
      if item then result[slot]={name=item.name,count=item.count} end
    end
    return result
  end
  function self:getCount(name)
    local total=0
    for slot,item in pairs(self:snapshot()) do if not reserved[slot] and item.name==name then total=total+item.count end end
    return total
  end
  function self:freeSlots()
    local total=0
    for slot=1,16 do if not reserved[slot] and turtle.getItemCount(slot)==0 then total=total+1 end end
    return total
  end
  function self:findItem(name)
    for slot,item in pairs(self:snapshot()) do if not reserved[slot] and item.name==name then return slot,item.count end end
  end
  function self:nextDeposit()
    for slot=1,16 do if not reserved[slot] and turtle.getItemCount(slot)>0 then return slot end end
  end
  function self:depositSlot(slot)
    if not U.integer(slot) or slot<1 or slot>16 or reserved[slot] then return nil,'invalid or reserved deposit slot' end
    local present,block=turtle.inspectDown()
    if not present or not containers[block.name] then return nil,'depot chest missing below turtle; refusing world drop' end
    local before=turtle.getItemCount(slot)
    if before==0 then return 0 end
    assert(turtle.select(slot),'cannot select deposit slot')
    local ok,err=turtle.dropDown()
    local moved=before-turtle.getItemCount(slot)
    if moved==0 then return nil,err or 'depot chest full' end
    if not ok then return nil,err or 'deposit failed' end
    return moved
  end
  function self:refuel(target,atDepot,managedBatch)
    assert(U.integer(target) and target>=0 and target<=100000000,'invalid refuel target')
    local fuel=turtle.getFuelLevel()
    if fuel=='unlimited' or fuel>=target and not managedBatch then return true end
    if turtle.getFuelLimit and target>turtle.getFuelLimit() then return false,'requested fuel exceeds turtle capacity' end
    local slot=config.fuelSlot or 15
    for _=1,2048 do
      local item=turtle.getItemDetail(slot)
      if turtle.getFuelLevel()>=target and not (managedBatch and item and Fuel.returned(item.name,config)) then return true end
      if not item and atDepot then
        local found,b=turtle.inspectUp()
        if found and containers[b.name] then
          turtle.select(slot); turtle.suckUp(1)
          -- A managed job owns one finite station batch. Its completion releases
          -- the chest for a durable refill before the next consumption job.
          if managedBatch and turtle.getItemCount(slot)==0 then return true end
        end
      end
      item=turtle.getItemDetail(slot)
      if item and Fuel.returned(item.name,config) then
        if not atDepot or item.nbt then return false,'returned fuel container must be unloaded at the depot' end
        local found,block=turtle.inspectDown()
        if not found or not containers[block.name] then return false,'depot return container missing; refusing world drop' end
        local before=turtle.getItemCount(slot); turtle.select(slot); turtle.dropDown(before)
        if turtle.getItemCount(slot)>=before then return false,'depot return container is full' end
      else
        if not item or item.nbt or not Fuel.allowed(item.name,config) then
          return false,'fuel supply missing in reserved slot or chest above depot'
        end
        turtle.select(slot)
        local before=turtle.getFuelLevel()
        local ok,err=turtle.refuel(1)
        if not ok then return false,err or 'refuel failed' end
        if turtle.getFuelLevel()<=before then return false,'refuel made no progress' end
      end
    end
    return false,'refuel operation limit reached'
  end

  return self
end
return M
