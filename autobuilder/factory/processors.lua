local U=require('autobuilder.core.util')
local M={}
local function fields(t,allowed)
 assert(type(t)=='table','processor configuration must be a table')
 for k in pairs(t) do assert(allowed[k],'unknown processor field: '..tostring(k)) end
end
local function list(t,minimum,maximum)
 assert(type(t)=='table' and #t>=minimum and #t<=maximum,'invalid processor list size')
 local n=0;for k in pairs(t) do n=n+1;assert(U.integer(k) and k>=1 and k<=#t,'invalid processor list index') end
 assert(n==#t,'sparse processor list')
end
local function positive(n,max) return U.integer(n) and n>=1 and n<=max end
function M.machine(config,id)
 for _,m in ipairs((config.processors or {}).machines or {}) do if m.id==id then return m end end
end
function M.recipe(config,item)
 local r=((config.processors or {}).recipes or {})[item];if not r then return end
 local out=U.copy(r);out.kind='process';out.ingredients={}
 for ingredient,input in pairs(r.inputs) do out.ingredients[ingredient]=input.count end
 return out
end
function M.lanes(r,batches)
 local out={};local left=batches;local size=math.min(64,math.ceil(batches/#r.machines))
 while left>0 do
  assert(#out<4096,'processor lane limit exceeded')
  local n=math.min(size,left);out[#out+1]={machineId=r.machines[#out%#r.machines+1],batches=n};left=left-n
 end
 return out
end
function M.validate(config)
 local p=config.processors;fields(p,{machines=true,recipes=true});list(p.machines,0,128)
 local occupied,ids={},{}
 for _,names in ipairs({config.storageInventories,config.furnaces}) do for _,name in ipairs(names) do occupied[name]=true end end
 occupied[config.supply.inventory]=true
 for _,stations in ipairs({config.supplyStations,config.fuel.stations,config.craftingStations,{config.craftingStation}}) do
  for _,s in ipairs(stations) do for _,key in ipairs({'inventory','buffer','input','output'}) do if s[key] then occupied[s[key]]=true end end end
 end
 for _,node in ipairs(config.logistics.nodes) do for _,b in ipairs(node.buffers) do occupied[b.inventory]=true end end
 for _,m in ipairs(p.machines) do
  fields(m,{id=true,inventory=true})
  assert(U.shortString(m.id,64) and not ids[m.id],'invalid or duplicate processor ID');ids[m.id]=true
  assert(U.shortString(m.inventory,128) and not occupied[m.inventory],'processor inventory must be distinct and private');occupied[m.inventory]=true
 end
 assert(type(p.recipes)=='table','processor recipes must be a map');local count=0
 for item,r in pairs(p.recipes) do
  count=count+1;assert(count<=4096 and U.shortString(item,128),'invalid processor recipe item')
  fields(r,{yield=true,inputs=true,outputSlot=true,seconds=true,machines=true,fuel=true})
  assert(positive(r.yield,64) and positive(r.outputSlot,256) and U.finite(r.seconds) and r.seconds>0 and r.seconds<=86400,'invalid processor output or duration')
  list(r.machines,1,128);local seen={}
  for _,id in ipairs(r.machines) do assert(ids[id] and not seen[id],'unknown or repeated processor machine');seen[id]=true end
  assert(type(r.inputs)=='table','processor inputs required');local slots={[r.outputSlot]=true};local n=0
  for ingredient,input in pairs(r.inputs) do
   n=n+1;fields(input,{count=true,slot=true})
   assert(n<=16 and U.shortString(ingredient,128) and ingredient~=item and positive(input.count,64) and positive(input.slot,256) and not slots[input.slot],'invalid processor input');slots[input.slot]=true
  end
  assert(n>0,'processor inputs required')
  if r.fuel then
   local f=r.fuel;fields(f,{item=true,slot=true,batchesPerItem=true})
   assert(U.shortString(f.item,128) and f.item~=item and not r.inputs[f.item] and positive(f.slot,256) and not slots[f.slot] and positive(f.batchesPerItem,1000000),'invalid processor fuel')
  end
 end
 return true
end
function M.validateSaved(config,state)
 local F=require('autobuilder.factory.factory')
 for _,j in pairs((state.automation or {}).jobs or {}) do
  local lease=(state.capacityLedger or {}).leases and state.capacityLedger.leases[j.id]
  if j.type=='PROCESS' and (j.status~='completed' or lease and lease.status=='held') then
   assert(F.equal(M.machine(config,j.machineId),j.processor) and F.equal(M.recipe(config,j.item),j.processRecipe),'owned processor configuration changed')
  end
 end
end
return M
