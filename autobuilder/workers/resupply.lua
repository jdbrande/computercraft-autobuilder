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
-- Leaving an underside/side stand may require stepping out from under its
-- support first. Inspect adjacent cells and persist the selected waypoint with
-- the ordinary route; movement still uses navigation's reservations/protection.
function M.overheadPoints(task,nav,turtle,config,target,height)
  local pose=nav.pose; local departure=pose; local points={}
  local access=task.siteAccess;local fromIndex,toIndex
  if access then
    height=math.max(height,access.entry.y)
    local function point(i) return i==0 and access.entry or access.cells[i] end
    for i=0,#access.cells do
      if U.distance(pose,point(i))==0 then fromIndex=i end
      if U.distance(target,point(i))==0 then toIndex=i end
    end
    if fromIndex and toIndex then
      local step=fromIndex<toIndex and 1 or -1
      for i=fromIndex+step,toIndex,step do points[#points+1]=U.copy(point(i)) end
      return points
    end
    if fromIndex then
      for i=fromIndex-1,0,-1 do points[#points+1]=U.copy(point(i)) end
      departure=access.entry
    end
  end
  if not fromIndex and turtle and turtle.inspectUp and pose.y<height then
    local ok,occupied=pcall(turtle.inspectUp)
    if not ok then return nil,'cannot inspect construction departure clearance' end
    if occupied then
      local directions={{heading='west',x=-1,z=0},{heading='east',x=1,z=0},{heading='north',x=0,z=-1},{heading='south',x=0,z=1}}
      for _,direction in ipairs(directions) do
        local candidate={x=pose.x+direction.x,y=pose.y,z=pose.z+direction.z}; local protected=false
        for _,area in ipairs((config or {}).restrictedAreas or {}) do
          if candidate.x>=area.min.x and candidate.x<=area.max.x and candidate.y>=area.min.y and candidate.y<=area.max.y
            and candidate.z>=area.min.z and candidate.z<=area.max.z then protected=true end
        end
        if not protected then
          local faced,why=nav:face(direction.heading); if not faced then return nil,why end
          local inspected,blocked=pcall(turtle.inspect)
          if not inspected then return nil,'cannot inspect construction escape cell' end
          if not blocked then departure=candidate; points[#points+1]=candidate; break end
        end
      end
      if departure==pose then return nil,'No clear unprotected side exit from construction stand; leave nearby blocks intact.' end
    end
  end
  points[#points+1]={x=departure.x,y=height,z=departure.z}
  local arrival=toIndex and access.entry or target
  points[#points+1]={x=arrival.x,y=height,z=arrival.z}
  points[#points+1]={x=arrival.x,y=arrival.y,z=arrival.z}
  if toIndex then for i=1,toIndex do points[#points+1]=U.copy(access.cells[i]) end end
  return points
end
-- Persist the route stages: reservation waits must not restart an overhead ascent.
function M.travel(s,task,nav,target,save,turtle,config)
  if not U.position(target) then return false,'depot/transport position is not configured' end
  if not s.route then
    local pose=nav.pose
    if not pose or not pose.known or pose.pending or pose.uncertain then return false,'trusted position required for logistics' end
    if U.distance(pose,target)==0 then
      if target.heading then return nav:face(target.heading) end
      return true
    end
    local y=math.max(pose.y,target.y)+2
    -- Construction already defines an overhead corridor. Stay within it when
    -- returning for materials, including when a previous step ended up there.
    if ({BUILD=true,VERIFY=true,REPAIR=true,CLEAR=true})[task.type] and U.finite(task.clearanceY) then
      y=math.max(pose.y,target.y+2,task.clearanceY)
    end
    for _,b in ipairs(task.blocks or {}) do y=math.max(y,b.y+2) end
    if U.finite(task.clearanceY) then y=math.max(y,task.clearanceY) end
    local points,why=M.overheadPoints(task,nav,turtle,config,target,y)
    if not points then return false,why end
    s.route={index=1,points=points}; save()
  end
  while s.route.index<=#s.route.points do
    local ok,err=nav:goTo(s.route.points[s.route.index]); if not ok then return false,err end
    s.route.index=s.route.index+1; save()
  end
  if target.heading then local ok,err=nav:face(target.heading); if not ok then return false,err end end
  return true
end
-- A fuel chest occupies the block above its stand. Descend beside it and
-- enter horizontally; the ordinary overhead route would hit the chest.
function M.stationTravel(s,task,nav,target,save,turtle,config)
  if not U.position(target) then return false,'fuel station position is missing' end
  if U.distance(nav.pose,target)==0 then return true end
  if not s.stationApproach then
    for _,offset in ipairs({{-1,0},{1,0},{0,-1},{0,1}}) do
      local p={x=target.x+offset[1],y=target.y,z=target.z+offset[2]}; local protected=false
      for _,area in ipairs(config.restrictedAreas or {}) do
        if p.x>=area.min.x and p.x<=area.max.x and p.y>=area.min.y and p.y<=area.max.y
          and p.z>=area.min.z and p.z<=area.max.z then protected=true end
      end
      if not protected then s.stationApproach=p; break end
    end
    if not s.stationApproach then return false,'fuel station has no unprotected side approach' end
    s.route=nil; save()
  end
  if not s.stationApproached then
    local ok,why=M.travel(s,task,nav,s.stationApproach,save,turtle,config)
    if not ok then return false,why end
    s.stationApproached=true; s.route=nil; save()
  end
  local ok,why=nav:goTo(target); if not ok then return false,why end
  if target.heading then return nav:face(target.heading) end
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
    if r and r.station then assert(require('autobuilder.storage.supply').matchesWorker(r.station,config,r.station.workerId),'owned supply station differs from worker configuration') end
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
    local ok,err=M.travel(s,task,nav,config.depot,persist,t,config); if not ok then return false,err end
    local suffix,why=M.container(t,(config.supply or {}).side or 'front'); if not suffix then return false,why end
    local slot,space
    if r.fuel then
      assert(s.item=='minecraft:coal','invalid construction fuel supply item')
      local held=t.getItemDetail(15)
      assert(not held or held.name==s.item and not held.nbt,'Empty slot 15 before accepting fuel; foreign or NBT-tagged item present')
      slot=15; space=held and t.getItemSpace and t.getItemSpace(15) or 1
      if space<=0 then return false,'reserved fuel slot 15 is full' end
    else slot,space=M.slot(t,config,s.item) end
    if not slot then return false,'inventory full before resupply' end
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
