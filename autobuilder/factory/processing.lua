local U=require('autobuilder.core.util')
local F=require('autobuilder.factory.factory')
local Registry=require('autobuilder.factory.processors')
local M={}
function M.new(task,e,config,save,capacity)
 local r=assert(task.processRecipe);local machine=assert(task.processor).inventory
 local s=assert(task.production);local self={task=task}
 local function reserveOutput(item,n,key)
  local id=task.id..':'..key
  local old=capacity.state.leases[id]
  if old then assert(old.status=='held','processor output tranche already released');return old end
  local limits={};local sources=F.sources(e,config,item)
  if sources[1] then local detail=e.peripheral.call(sources[1].name,'getItemDetail',sources[1].slot);limits[item]=detail and detail.maxCount end
  if item==task.item and not limits[item] then limits[item]=r.outputStackLimit end
  local observed=require('autobuilder.storage.capacity').observe(e)
  local requests,left={},n
  for _,name in ipairs(config.storageInventories) do
   if #requests>=128 then break end
   local low,high,best=1,left,0
   while low<=high do
    local amount=math.floor((low+high)/2);local trial=U.copy(requests)
    trial[#trial+1]={inventory=name,items={[item]=amount},limits=limits}
    if capacity:preview(id,trial,observed) then best=amount;low=amount+1 else high=amount-1 end
   end
   if best>0 then requests[#requests+1]={inventory=name,items={[item]=best},limits=limits};left=left-best end
   if left==0 then return assert(capacity:reserve(id,requests,observed)) end
  end
  error(not limits[item] and 'processor output stack limit unknown; configure outputStackLimit or provide a measured sample/more storage' or 'insufficient combined processor output capacity',0)
 end
 local function collect(slot,item,left,lease,counter,offset)
  local inv=F.list(e,machine);local stack=assert(inv[slot],'processor output disappeared')
  local detail=e.peripheral.call(machine,'getItemDetail',slot)
  assert(detail and U.integer(detail.maxCount) and detail.maxCount>0,'processor output stack limit unavailable')
  for _,request in ipairs(lease.contract) do
   local destination=request.inventory
   for _,a in ipairs(lease.nodes[destination].allocations) do
   if offset<a.count then
    local target=F.list(e,destination)[a.slot]
    assert(not target or target.name==item and not target.nbt,'processor destination contaminated')
    local room=math.min(e.peripheral.call(destination,'getItemLimit',a.slot),detail.maxCount)-(target and target.count or 0)
    assert(room>0,'processor destination full')
    assert(not task.paused,'processor paused during observation')
    return F.transfer(s,e,save,machine,slot,destination,a.slot,item,math.min(left,stack.count,a.count-offset,room),destination,1,counter)
   end
   offset=offset-a.count
   end
  end
  error('processor delivery exceeds reserved capacity')
 end
 local function advance()
  if s.intent then return F.reconcileTransfer(s,e,save) end
  assert(F.equal(Registry.machine(config,task.machineId),task.processor) and F.equal(Registry.recipe(config,task.item),r),'owned processor configuration changed')
  local inv=F.list(e,machine);local slots={[r.outputSlot]=task.item}
  for item,input in pairs(r.inputs) do slots[input.slot]=item end
  if r.fuel then slots[r.fuel.slot]=r.fuel.item end
  for slot,stack in pairs(inv) do assert(slots[slot]==stack.name and not stack.nbt,'processor inventory contamination') end
  local completed=s.completed or 0;local delivered=s.delivered or 0;local withdrawn=s.withdrawn or {}
  local ready=task.batches
  for item,input in pairs(r.inputs) do
   local loaded=withdrawn[item] or 0;ready=math.min(ready,math.floor(loaded/input.count))
   assert((inv[input.slot] and inv[input.slot].count or 0)<=loaded-completed*input.count,'processor contains unowned inputs')
  end
  assert(delivered+(inv[r.outputSlot] and inv[r.outputSlot].count or 0)<=ready*r.yield,'processor output exceeds owned input')
  if r.fuel then assert((inv[r.fuel.slot] and inv[r.fuel.slot].count or 0)+(s.fuelReturned or 0)<=(withdrawn[r.fuel.item] or 0),'processor contains unowned fuel') end
  if completed==task.batches then
   for _,input in pairs(r.inputs) do assert(not inv[input.slot],'processor inputs remain after output completion') end
   assert(not inv[r.outputSlot],'processor output remains after completion')
   if r.fuel and inv[r.fuel.slot] then
    if not s.refundCount then F.commit(s,save,function() s.refundCount=inv[r.fuel.slot].count end) end
    local lease=reserveOutput(r.fuel.item,s.refundCount,'fuel-return')
    return collect(r.fuel.slot,r.fuel.item,s.refundCount-(s.fuelReturned or 0),lease,'fuelReturned',s.fuelReturned or 0)
   end
   if s.refundCount then
    assert((s.fuelReturned or 0)==s.refundCount,'processor return fuel disappeared')
    capacity:release(task.id..':fuel-return')
   end
   capacity:release(task.id);return 'complete'
  end
  local key='output:'..completed;local tranche=capacity.state.leases[task.id..':'..key]
  if delivered==(completed+1)*r.yield then
   for _,input in pairs(r.inputs) do assert(not inv[input.slot],'processor did not consume recipe inputs') end
   assert(tranche,'processor output capacity missing');capacity:release(tranche.id)
   F.commit(s,save,function() s.completed=completed+1;s.waits=0 end);return 'running'
  end
  tranche=reserveOutput(task.item,r.yield,key)
  if inv[r.outputSlot] then return collect(r.outputSlot,task.item,(completed+1)*r.yield-delivered,tranche,'delivered',delivered-completed*r.yield) end
  local ingredients={};for item in pairs(r.inputs) do ingredients[#ingredients+1]=item end;table.sort(ingredients)
  for _,item in ipairs(ingredients) do
   local input=r.inputs[item];local left=(completed+1)*input.count-(withdrawn[item] or 0)
   if left>0 then
    local source=assert(F.sources(e,config,item)[1],'processor input unavailable: '..item)
    local detail=e.peripheral.call(source.name,'getItemDetail',source.slot)
    assert(detail and detail.maxCount and math.min(detail.maxCount,e.peripheral.call(machine,'getItemLimit',input.slot))>=input.count,'processor recipe does not fit input slot')
    assert(not task.paused,'processor paused during observation')
    return F.transfer(s,e,save,source.name,source.slot,machine,input.slot,item,math.min(left,source.count),source.name,-1,nil,nil,true)
   end
  end
  if r.fuel and not inv[r.fuel.slot] and (withdrawn[r.fuel.item] or 0)<task.stockInputs[r.fuel.item] then
   local source=assert(F.sources(e,config,r.fuel.item)[1],'processor fuel unavailable')
   assert(not task.paused,'processor paused during observation')
   return F.transfer(s,e,save,source.name,source.slot,machine,r.fuel.slot,r.fuel.item,1,source.name,-1,nil,nil,true)
  end
  if r.fuel and not inv[r.fuel.slot] and (withdrawn[r.fuel.item] or 0)>=task.stockInputs[r.fuel.item] and (s.waits or 0)>=config.smeltingWaitSteps then
   error('processor item fuel budget exhausted; preserve owned inputs and inspect interrupted processing',0)
  end
  F.commit(s,save,function() s.waits=(s.waits or 0)+1 end)
  assert(s.waits<=config.smeltingWaitSteps,'processor stalled; check power, fuel, recipe and loaded chunks')
  return 'waiting','processor running; expected '..r.seconds..' seconds per batch'..(r.fuel and '; nominal '..r.fuel.batchesPerItem..' batches/fuel item, conservative budget '..task.stockInputs[r.fuel.item] or '')
 end
 function self:step() return F.protect(advance) end
 return self
end
return M
