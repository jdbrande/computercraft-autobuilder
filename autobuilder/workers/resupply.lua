local U=require('autobuilder.core.util')
local M={}
local containers={['minecraft:chest']=true,['minecraft:trapped_chest']=true,['minecraft:barrel']=true}
function M.snapshot(t)
  local out={}
  for s=1,16 do local i=t.getItemDetail(s); if i then out[s]={name=i.name,count=i.count,nbt=i.nbt} end end
  return out
end
function M.reserved(config)
  local r={[15]=true,[16]=true}; if config.fuelSlot then r[config.fuelSlot]=true end
  for _,s in ipairs(config.reservedSlots or {}) do r[s]=true end
  return r
end
function M.slot(t,config,item,onlyEmpty)
  local reserved=M.reserved(config)
  if not onlyEmpty then
    for s=1,16 do
      local i=t.getItemDetail(s)
      if not reserved[s] and i and i.name==item and not i.nbt then
        local space=t.getItemSpace and t.getItemSpace(s) or 0
        if space>0 then return s,space end
      end
    end
  end
  -- Start an empty stack with one item to discover its actual stack capacity.
  for s=1,16 do if not reserved[s] and t.getItemCount(s)==0 then return s,1 end end
end
function M.delta(t,intent)
  local now=M.snapshot(t); local before=intent.before; local slot=intent.slot
  for s=1,16 do
    local a,b=before[s],now[s]
    if s~=slot then
      if a and not b or b and not a or a and (a.name~=b.name or a.count~=b.count or a.nbt~=b.nbt) then return nil,'unrelated inventory changed during transfer' end
    end
  end
  local a,b=before[slot],now[slot]
  if b and (b.name~=intent.item or b.nbt) then return nil,'foreign item received; preserve inventory for reconciliation' end
  if a and (a.name~=intent.item or a.nbt) then return nil,'invalid recorded transfer inventory' end
  local delta=(b and b.count or 0)-(a and a.count or 0)
  if intent.kind=='drop' then delta=-delta end
  if delta<0 or delta>intent.limit then return nil,'ambiguous transfer inventory delta' end
  return delta
end
function M.container(t,side)
  local suffix=side=='down' and 'Down' or side=='up' and 'Up' or ''
  local found,b=t['inspect'..suffix]()
  if not found or not containers[b.name] then return nil,'expected supply/cargo container is missing; refusing world transfer' end
  return suffix
end
-- Persist the route stages: reservation waits must not restart an overhead ascent.
function M.travel(s,task,nav,target,save)
  if not U.position(target) then return false,'depot/transport position is not configured' end
  if not s.route then
    local pose=nav.pose
    if not pose or not pose.known or pose.pending or pose.uncertain then return false,'trusted position required for logistics' end
    local y=math.max(pose.y,target.y)+2
    for _,b in ipairs(task.blocks or {}) do y=math.max(y,b.y+2) end
    if U.finite(task.clearanceY) then y=math.max(y,task.clearanceY) end
    s.route={index=1,points={{x=pose.x,y=y,z=pose.z},{x=target.x,y=y,z=target.z},{x=target.x,y=target.y,z=target.z}}}; save()
  end
  while s.route.index<=3 do
    local ok,err=nav:goTo(s.route.points[s.route.index]); if not ok then return false,err end
    s.route.index=s.route.index+1; save()
  end
  if target.heading then local ok,err=nav:face(target.heading); if not ok then return false,err end end
  return true
end
function M.new(task,e,config,nav,save)
  local self={task=task}; local t=e.turtle; local fault
  local function persist()
    local ok,v,err=pcall(save)
    if not ok or not v then fault='resupply checkpoint failed: '..tostring(ok and err or v); error(fault,0) end
  end
  local function step()
    local r=task.supplyRequest
    if not r then return true end
    if not r.granted then return false,'waiting for supply grant' end
    assert(U.shortString(r.item,128) and U.integer(r.amount) and r.amount>0 and r.amount<=64 and U.integer(r.count) and r.amount<=r.count,'invalid supply grant')
    local s=task.resupply
    if not s then s={item=r.item,amount=r.amount,received=0}; task.resupply=s; persist() end
    assert(s.item==r.item and s.amount==r.amount,'supply request changed during transfer')
    if s.intent then
      local delta,err=M.delta(t,s.intent); assert(delta,err)
      s.received=s.received+delta; s.intent=nil; persist()
    end
    if s.received>=s.amount then
      task.lastSupply={item=s.item,count=s.received}; task.supplyRequest=nil; task.resupply=nil; persist(); return true
    end
    local ok,err=M.travel(s,task,nav,config.depot,persist); if not ok then return false,err end
    local suffix,why=M.container(t,(config.supply or {}).side or 'front'); if not suffix then return false,why end
    local slot,space=M.slot(t,config,s.item); if not slot then return false,'inventory full before resupply' end
    local limit=math.min(space,s.amount-s.received)
    assert(t.select(slot),'cannot select supply slot')
    s.intent={kind='suck',slot=slot,item=s.item,limit=limit,before=M.snapshot(t)}; persist()
    t['suck'..suffix](limit)
    local delta,detail=M.delta(t,s.intent); assert(delta,detail)
    s.received=s.received+delta; s.intent=nil; persist()
    if delta==0 then return false,'staged supply is missing or unavailable' end
    if s.received==s.amount then
      task.lastSupply={item=s.item,count=s.received}; task.supplyRequest=nil; task.resupply=nil; persist(); return true
    end
    return false,'resupply in progress'
  end
  function self:step()
    if fault then return false,fault end
    local ok,result,err=pcall(step)
    if not ok then return false,tostring(result) end
    return result,err
  end
  return self
end
return M
