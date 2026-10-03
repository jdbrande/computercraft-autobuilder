local U=require('autobuilder.core.util')
local R=require('autobuilder.workers.resupply')
local M={}
local function quantities(t,positive)
  if type(t)~='table' then return false end
  local n=0
  for item,count in pairs(t) do
    n=n+1
    if n>16 or not U.shortString(item,128) or not U.integer(count) or count<(positive and 1 or 0) or count>16000000 then return false end
  end
  return true
end
function M.validCargo(c)
  if type(c)~='table' or not quantities(c.items,true) or not quantities(c.limits,true)
    or c.error~=nil and not U.shortString(c.error,512) then return false end
  for item in pairs(c.items) do if not c.limits[item] or c.limits[item]>1000000 then return false end end
  for item in pairs(c.limits) do if not c.items[item] then return false end end
  return true
end
function M.cleanCargo(c)
  if not c then return nil end
  local out={items={},limits={},error=c.error}
  for item,n in pairs(c.items) do out.items[item]=n;out.limits[item]=c.limits[item] end
  return out
end
function M.observe(t,config)
  local c={items={},limits={}};local reserved=R.reserved(config)
  for slot=1,16 do if not reserved[slot] then
    local v=t.getItemDetail(slot)
    if v then
      assert(U.shortString(v.name,128) and U.integer(v.count) and v.count>0,'invalid native cargo item')
      if v.nbt then c.error='unsupported NBT cargo in slot '..slot..': '..v.name end
      local limit=v.maxCount or (t.getItemSpace and t.getItemSpace(slot)+v.count) or 1
      assert(U.integer(limit) and limit>=1 and limit<=1000000,'invalid native cargo stack limit')
      c.items[v.name]=(c.items[v.name] or 0)+v.count
      c.limits[v.name]=math.min(c.limits[v.name] or limit,limit)
    end
  end end
  assert(M.validCargo(c),'native cargo manifest exceeds bounds');return c
end
function M.validContract(j)
  local c=j.returning
  return j.type=='RETURN_HOME' and U.position(j.home) and type(c)=='table'
    and type(c.node)=='table' and U.shortString(c.node.id,64) and U.shortString(c.node.inventory,128) and U.position(c.node.position)
    and type(c.buffer)=='table' and U.shortString(c.buffer.inventory,128) and U.position(c.buffer.position)
    and c.node.inventory~=c.buffer.inventory and U.distance(c.buffer.position,j.home)==0
    and quantities(c.items,true) and next(c.items)~=nil
end
function M.validReceipt(r)
  return type(r)=='table' and U.integer(r.sequence) and r.sequence>=0 and r.sequence<=9007199254740991 and quantities(r.deposited,false)
end
return M
