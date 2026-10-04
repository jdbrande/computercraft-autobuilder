local U=require('autobuilder.core.util')
local F=require('autobuilder.factory.factory')
local Q=require('autobuilder.core.workflows')
local Registry=require('autobuilder.factory.processors')
local M={}
function M.new(app,config,e,queue,production)
 local save=function() return app:save() end
 local capacity=require('autobuilder.storage.capacity').new(app.state,save)
 local self={cursor=0}
 function self:schedule(r,op)
  if not r.jobIds then F.commit(r,save,function() r.jobIds={} end) end
  for i,lane in ipairs(op.lanes) do if not r.jobIds[i] then
   local recipe=op.processRecipe;local inputs={}
   for item,input in pairs(recipe.inputs) do inputs[item]=input.count*lane.batches end
   if recipe.fuel then inputs[recipe.fuel.item]=lane.batches end
   local machine=assert(Registry.machine(config,lane.machineId),'planned processor removed')
   local j=queue:submit('PROCESS',{item=op.item,batches=lane.batches,quantity=lane.batches*recipe.yield,
    machineId=lane.machineId,processor=U.copy(machine),processRecipe=U.copy(recipe),stockInputs=inputs,stockOutputs={[op.item]=lane.batches*recipe.yield},
    productionRequest=r.id,productionOperation=r.operation},{},r.id..':op:'..r.operation..':processor:'..i..':replan:'..(r.replans or 0))
   F.commit(r,save,function() r.jobIds[i]=j.id end)
  end end
  local complete,why=true
  for _,id in ipairs(r.jobIds) do local j=assert(queue.state.jobs[id]);if j.status~='completed' then complete=false;if j.status=='blocked' then why=why or j.error end end end
  F.commit(r,save,function()
   r.status=why and 'blocked' or 'running';r.error=why
   if complete then r.operation=r.operation+1;r.jobIds=nil;r.status='running';r.error=nil end
  end)
 end
 local function claim(j)
  local old=capacity.state.leases[j.id];if old then assert(old.status=='held' or j.production and j.production.completed==j.batches,'processor machine lease closed');return end
  local allowed,why=Q.factoryCanRun(app.state,j,true);assert(allowed,why)
  Registry.validateSaved(config,app.state)
  local observed=require('autobuilder.storage.capacity').observe(e)
  assert(not next(F.list(observed,j.processor.inventory)),'processor must start empty')
  local size=observed.peripheral.call(j.processor.inventory,'size');local r=j.processRecipe
  assert(r.outputSlot<=size and observed.peripheral.call(j.processor.inventory,'getItemLimit',r.outputSlot)>=r.yield,'processor output slot too small')
  for _,input in pairs(r.inputs) do assert(input.slot<=size and observed.peripheral.call(j.processor.inventory,'getItemLimit',input.slot)>=input.count,'processor input slot too small') end
  if r.fuel then assert(r.fuel.slot<=size and observed.peripheral.call(j.processor.inventory,'getItemLimit',r.fuel.slot)>=1,'processor fuel slot unavailable') end
  -- Whole-inventory exclusion is the machine claim. Streaming batches validate
  -- their exact slots separately and reserve destination capacity before loading.
  local first=next(r.inputs)
  local lease=assert(capacity:preview(j.id,{{inventory=j.processor.inventory,items={[first]=1},exclusive=true}},observed))
  assert(app.mining:refresh());allowed,why=Q.factoryCanRun(app.state,j,true);assert(allowed,why)
  assert(not j.paused and j.status~='completed','processor paused during observation')
  local stock=production.ledger.state.leases[j.id];local before=U.copy(j)
  local ok,err=pcall(function()
   capacity.state.leases[j.id]=lease
   assert(require('autobuilder.storage.ledger').new(app.state,function() return true end):reserve(j.id,j.stockInputs,j.stockOutputs,app.mining.storage.counts,{protected=config.turtleFuelReserveItems}))
   j.production={withdrawn={},delivered=0,completed=0,machine=j.processor.inventory};assert(save())
  end)
  if not ok then
   capacity.state.leases[j.id]=nil;production.ledger.state.leases[j.id]=stock
   for k in pairs(j) do j[k]=nil end;for k,v in pairs(before) do j[k]=v end;error(err,0)
  end
 end
 local function execute(j,reconcile)
  local status,why=F.protect(function()
   if reconcile then return F.reconcileTransfer(j.production,e,save) end
   claim(j);local allowed,reason=Q.factoryCanRun(app.state,j);assert(allowed,reason)
   return require('autobuilder.factory.processing').new(j,e,config,save,capacity):step()
  end)
  j.status=status=='complete' and 'completed' or status=='blocked' and 'blocked' or 'running';j.error=why
  assert(save());production:syncClaims(false);return status~='blocked' or j.production and j.production.intent~=nil
 end
 function self:step()
  local jobs={}
  for _,j in pairs(queue.state.jobs) do if j.type=='PROCESS' then jobs[#jobs+1]=j end end
  table.sort(jobs,function(a,b) return a.id<b.id end)
  for _,j in ipairs(jobs) do if j.production and j.production.intent then return execute(j,true) end end
  local ready={};for _,j in ipairs(jobs) do if j.status~='completed' and not j.paused then ready[#ready+1]=j end end
  if #ready==0 then return false end
  self.cursor=self.cursor%#ready+1;return execute(ready[self.cursor])
 end
 return self
end
return M
