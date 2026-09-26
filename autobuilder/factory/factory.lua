local U=require('autobuilder.core.util')
local M={}
function M.new(task,environment,config,save)
  local r=require('autobuilder.factory.recipes').get(task.item)
  assert(r,'no recipe for '..tostring(task.item))
  return require('autobuilder.factory.'..(r.kind=='smelt' and 'smelting' or 'crafting')).new(task,environment,config,save)
end
function M.count(items,name)
  local n=0; for _,item in pairs(items) do if item.name==name then n=n+item.count end end; return n
end
function M.list(e,name)
  assert(type(name)=='string' and name~='','inventory is not configured')
  local result=e.peripheral.call(name,'list'); assert(type(result)=='table','inventory unavailable: '..name)
  local clean={}
  for slot,item in pairs(result) do
    assert(U.integer(slot) and slot>=1 and U.shortString(item.name,128) and U.integer(item.count) and item.count>0,'invalid inventory response')
    clean[slot]={name=item.name,count=item.count,nbt=item.nbt}
  end
  return clean
end
function M.turtleItems(e)
  assert(e.turtle and e.turtle.getItemDetail,'local Crafty turtle is required')
  local out={}; for slot=1,16 do local item=e.turtle.getItemDetail(slot); if item then out[slot]={name=item.name,count=item.count,nbt=item.nbt} end end
  return out
end
function M.equal(a,b)
  if type(a)~=type(b) then return false end
  if type(a)~='table' then return a==b end
  for k,v in pairs(a) do if not M.equal(v,b[k]) then return false end end
  for k in pairs(b) do if a[k]==nil then return false end end
  return true
end
function M.commit(state,save,change)
  local before=U.copy(state); change()
  local ok,result,why=pcall(save)
  if not ok or not result then
    for k in pairs(state) do state[k]=nil end; for k,v in pairs(before) do state[k]=v end
    error('production checkpoint failed: '..tostring(ok and why or result),0)
  end
end
function M.sources(e,config,item)
  local found,total,seen={},0,{}
  for _,name in ipairs(config.storageInventories or {}) do
    assert(not seen[name],'duplicate storage inventory'); seen[name]=true
    local inv=M.list(e,name)
    for slot,stack in pairs(inv) do if stack.name==item and not stack.nbt then
      total=total+stack.count; found[#found+1]={name=name,slot=slot,count=stack.count}
    end end
  end
  table.sort(found,function(a,b) return a.name==b.name and a.slot<b.slot or a.name<b.name end)
  return found,total
end
-- Exactly one side effect per call. The journal watches the endpoint which cannot
-- mutate by itself: the source chest for furnace inputs, destination chest for output.
function M.reconcileTransfer(state,e,save)
  local i=assert(state.intent); assert(i.action=='transfer','unexpected transfer journal')
  M.list(e,i.from); M.list(e,i.to) -- A disconnected endpoint cannot be reconciled safely.
  local current=M.list(e,i.observe)
  local delta=M.count(current,i.item)-i.beforeCount
  local moved=i.sign*delta
  assert(U.integer(moved) and moved>=0 and moved<=i.limit,'ambiguous transfer; preserve inventories and journal')
  -- Changes to other item types indicate a broken exclusive inventory lease.
  local before=U.copy(i.before); local after=U.copy(current)
  for slot,item in pairs(before) do if item.name==i.item then before[slot]=nil end end
  for slot,item in pairs(after) do if item.name==i.item then after[slot]=nil end end
  assert(M.equal(before,after),'inventory changed during transfer; operator reconciliation required')
  M.commit(state,save,function()
    if moved>0 then state.waits=0 end
    if i.counter then state[i.counter]=(state[i.counter] or 0)+moved end
    if i.patch and moved==i.limit then for k,v in pairs(i.patch) do state[k]=v end end
    state.intent=nil
  end)
  if moved==0 then return 'blocked','inventory transfer made no progress; check capacity and supply' end
  return 'running'
end
function M.transfer(state,e,save,from,slot,to,target,item,limit,observe,sign,counter,patch)
  assert(from~=to,'source and destination inventory must differ')
  local before=M.list(e,observe)
  M.commit(state,save,function() state.intent={action='transfer',from=from,slot=slot,to=to,target=target,item=item,
    limit=limit,observe=observe,sign=sign,before=before,beforeCount=M.count(before,item),counter=counter,patch=patch} end)
  local moved=e.peripheral.call(from,'pushItems',to,slot,limit,target)
  assert(U.integer(moved) and moved>=0 and moved<=limit,'invalid transfer result; reconcile journal')
  return M.reconcileTransfer(state,e,save)
end
function M.protect(fn)
  local ok,status,reason=pcall(fn)
  if not ok then return 'blocked',tostring(status) end
  return status,reason
end
return M
