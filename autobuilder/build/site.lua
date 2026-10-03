local U=require('autobuilder.core.util')
local M={}
local away={north={0,1},south={0,-1},east={-1,0},west={1,0}}
local natural={}
for _,name in ipairs({'stone','deepslate','granite','diorite','andesite','tuff','dirt','grass_block','cobblestone','cobbled_deepslate','sand','gravel'}) do natural['minecraft:'..name]=true end
local drops={['minecraft:stone']='minecraft:cobblestone',['minecraft:deepslate']='minecraft:cobbled_deepslate',['minecraft:grass_block']='minecraft:dirt'}
local function key(p) return p.x..','..p.y..','..p.z end
local function equal(a,b)
  if type(a)~=type(b) then return false end
  if type(a)~='table' then return a==b end
  for k,v in pairs(a) do if not equal(v,b[k]) then return false end end
  for k in pairs(b) do if a[k]==nil then return false end end
  return true
end

-- Every waypoint is adjacent. The roof is opened first, then the two
-- footprint layers; the final trip uses only cells already traversed.
function M.plan(pose)
  assert(U.position(pose) and U.heading(pose.heading),'saved position and heading required for site preparation')
  local a=away[pose.heading]; local sx,sz=a[1]==0 and 1 or 0,a[1]==0 and 0 or 1
  local function point(u,v,h) return {x=pose.x+a[1]*u+sx*v,y=pose.y+h,z=pose.z+a[2]*u+sz*v} end
  local first,last=point(2,0,0),point(9,7,0)
  local origin={x=math.min(first.x,last.x),y=pose.y,z=math.min(first.z,last.z)}
  local points={}; local current=point(0,0,0)
  local function add(u,v,h)
    local p=point(u,v,h); assert(U.position(p),'site exceeds world coordinate bounds')
    if U.distance(current,p)==0 then return end
    assert(U.distance(current,p)==1,'nonadjacent site route')
    points[#points+1]=p; current=p
  end
  add(0,0,1); add(0,0,2)
  for v=0,7 do
    if v%2==0 then for u=0,9 do add(u,v,2) end else for u=9,0,-1 do add(u,v,2) end end
  end
  add(1,7,2); add(2,7,2)
  for v=7,0,-1 do
    if v%2==1 then for u=2,9 do add(u,v,1) end else for u=9,2,-1 do add(u,v,1) end end
  end
  for v=0,7 do
    if v%2==0 then for u=2,9 do add(u,v,0) end else for u=9,2,-1 do add(u,v,0) end end
  end
  add(2,7,1); add(2,7,2); add(1,7,2); add(0,7,2)
  for v=6,0,-1 do add(0,v,2) end
  add(0,0,1); add(0,0,0)
  local corner=point(9,7,2)
  return {start=U.copy(pose),origin=origin,points=points,bounds={
    min={x=math.min(pose.x,corner.x),y=pose.y,z=math.min(pose.z,corner.z)},
    max={x=math.max(pose.x,corner.x),y=pose.y+2,z=math.max(pose.z,corner.z)}}}
end

function M.new(task,e,config,nav,save)
  assert(type(task)=='table' and task.type=='PREPARE_SITE','site preparation task required')
  assert(e and e.turtle and nav and type(save)=='function','site hardware/navigation/persistence required')
  config=config or {}; local t=e.turtle; local self={task=task}; local fault
  local plan=task.sitePlan
  local valid,canonical=pcall(M.plan,type(plan)=='table' and plan.start or nil)
  local planValid=valid and equal(canonical,plan)
  task.phase=task.phase or 'work'; task.index=task.index or 1; task.progress=task.progress or 0; task.attempts=task.attempts or {}
  local reserved={[15]=true,[16]=true,[config.fuelSlot or 15]=true}
  for _,slot in ipairs(config.reservedSlots or {}) do reserved[slot]=true end
  local function persist()
    local ok,result,err=pcall(save)
    if not ok or not result then fault='site checkpoint failed: '..tostring(ok and err or result); error(fault,0) end
    return true
  end
  local function blocked(err,category)
    task.phase='blocked'; task.error=tostring(err); task.blockedCategory=category; persist(); return false,task.error
  end
  local function restricted(p)
    for _,a in ipairs(config.restrictedAreas or {}) do
      if p.x>=a.min.x and p.x<=a.max.x and p.y>=a.min.y and p.y<=a.max.y and p.z>=a.min.z and p.z<=a.max.z then return true end
    end
    return false
  end
  local function inventory()
    local out={}
    for s=1,16 do local item=t.getItemDetail(s); if item then out[s]={name=item.name,count=item.count,nbt=item.nbt} end end
    return out
  end
  local function gained(before,after)
    local positive=false
    for s=1,16 do
      local a,b=before[s],after[s]
      if reserved[s] and not equal(a,b) then return false end
      if a and (not b or b.name~=a.name or b.nbt~=a.nbt or b.count<a.count) then return false end
      if b and (not a or b.count>a.count) then positive=true end
    end
    return positive
  end
  local function inspect(suffix)
    local ok,found,b=pcall(t['inspect'..suffix])
    if not ok then return nil,nil,'site inspection failed: '..tostring(found) end
    if type(found)~='boolean' or found and (type(b)~='table' or type(b.name)~='string') then return nil,nil,'invalid site inspection response' end
    return found,b
  end
  local function fuelReady()
    local ok,fuel=pcall(t.getFuelLevel)
    if not ok then return false,'site fuel query failed' end
    local needed=#plan.points-task.index+1+(config.minimumFuelReserve or 100)
    if fuel~='unlimited' and (not U.finite(fuel) or fuel<needed) then return false,'insufficient fuel to clear site and return; refuel before resuming' end
    return true
  end
  local function arrive()
    task.moveIntent=nil; task.progress=task.index; task.index=task.index+1; return persist()
  end
  function self:resume()
    if fault then return false,fault end
    if task.phase~='blocked' then return false,'task is not blocked' end
    task.phase='work'; task.error=nil; task.blockedCategory=nil; return persist()
  end
  function self:step()
    if fault then return false,fault end
    if task.paused then return false,'site preparation paused' end
    if task.phase=='completed' then return true end
    if task.phase=='blocked' then return false,task.error end
    if not planValid or not equal(plan,canonical) then return blocked('site plan differs from bounded canonical plan','invalid') end
    if not U.integer(task.index) or task.index<1 or task.index>#plan.points+1 then return blocked('invalid site waypoint index','invalid') end
    local pose=nav.pose
    if not U.position(pose) or not pose.known or not U.heading(pose.heading) or pose.pending or pose.uncertain then return blocked('trusted saved position and heading required for site preparation','inaccessible') end
    if not task.started then
      local depot=config.depot
      if U.distance(pose,plan.start)~=0 or pose.heading~=plan.start.heading or depot and
          (not U.position(depot) or U.distance(depot,plan.start)~=0 or depot.heading and depot.heading~=plan.start.heading) then
        return blocked('Return turtle to its saved supply position and run setup','inaccessible')
      end
      if task.index~=1 then return blocked('site preparation must start at its first waypoint','invalid') end
      task.started=true; persist()
    end
    local previous=task.index==1 and plan.start or plan.points[task.index-1]
    local target=plan.points[task.index]
    if task.moveIntent then
      local move=task.moveIntent
      if not target or move.index~=task.index or not equal(move.from,{x=previous.x,y=previous.y,z=previous.z}) or not equal(move.to,target) or task.intent then return blocked('invalid pending site move','ambiguous') end
      if U.distance(pose,target)==0 then return arrive() end
    end
    if U.distance(pose,previous)~=0 then return blocked('site position differs from recorded route; reconcile saved position','ambiguous') end
    if not target then
      local ok,err=nav:face(plan.start.heading); if not ok then return blocked(err,'inaccessible') end
      task.phase='completed'; task.error=nil; return persist()
    end
    if restricted(target) or restricted(pose) then return blocked('site target is in a restricted area','inaccessible') end
    local suffix=''; local heading
    if target.y>pose.y then suffix='Up' elseif target.y<pose.y then suffix='Down'
    elseif target.x~=pose.x then heading=target.x>pose.x and 'east' or 'west'
    else heading=target.z>pose.z and 'south' or 'north' end
    if heading then local ok,err=nav:face(heading); if not ok then return blocked(err,'inaccessible') end end
    local found,b,err=inspect(suffix); if err then return blocked(err,'inaccessible') end
    if task.intent then
      local intent=task.intent; local now=inventory()
      if intent.kind~='dig' or intent.index~=task.index or not equal(intent.target,target) then return blocked('invalid site dig intent','ambiguous') end
      if not found and gained(intent.inventory,now) or found and equal(intent.block,b) and equal(intent.inventory,now) then
        task.intent=nil; persist();if nav.workDone then nav.workDone() end
      else return blocked('ambiguous site dig outcome; target and inventory do not prove completion','ambiguous') end
    end
    local ok,why=fuelReady(); if not ok then return blocked(why,'fuel') end
    if found then
      if not natural[b.name] or (config.protectedBlocks or {})[b.name] or b.state and (b.state.waterlogged==true or b.state.waterlogged=='true') then
        return blocked('site clearing refuses protected or non-natural block: '..b.name,'unsupported')
      end
      local empty
      for s=1,16 do if not reserved[s] and t.getItemCount(s)==0 then empty=s; break end end
      if not empty then return blocked('inventory full; empty cargo slots before resuming site preparation','inventory_full') end
      local slot=empty; local drop=drops[b.name] or b.name
      for s=1,16 do
        local item=t.getItemDetail(s)
        -- Gravel may produce flint. Stack gravel only when insertion can
        -- reach the empty cargo slot without crossing any reserved slot.
        local safeFallback=true
        if b.name=='minecraft:gravel' then
          safeFallback=s<empty
          for between=s,empty do if reserved[between] then safeFallback=false end end
        end
        if safeFallback and not reserved[s] and item and item.name==drop and not item.nbt and item.count<64 then slot=s; break end
      end
      local k=key(target); local attempts=task.attempts[k] or 0
      if attempts>=4 then return blocked('site falling block dig limit reached; make terrain safe before resuming','attempt_limit') end
      if not nav.workGuard then return blocked('controller mutation permission required','inaccessible') end
      ok,why=nav.workGuard(target);if not ok then return blocked(why or 'movement reservation pending','inaccessible') end
      local selected=t.select(slot); if not selected then return blocked('cannot select site cargo slot','inventory_full') end
      task.attempts[k]=attempts+1
      task.intent={kind='dig',index=task.index,target=U.copy(target),block=U.copy(b),inventory=inventory()}; persist()
      local callOk,result,detail=pcall(t['dig'..suffix])
      if not callOk then return blocked('site dig hardware error: '..tostring(result),'ambiguous') end
      local present,actual,readError=inspect(suffix); if readError then return blocked(readError,'ambiguous') end
      local after=inventory(); local intent=task.intent
      if result and gained(intent.inventory,after) and (not present or equal(actual,b)) then
        task.intent=nil; persist();if nav.workDone then nav.workDone() end
        -- A falling block may replace the removed block immediately. Never
        -- infer this on reboot, where the physical dig result is unavailable.
        return true
      elseif present and equal(actual,b) and equal(intent.inventory,after) then
        task.intent=nil; persist();if nav.workDone then nav.workDone() end; return blocked(detail or 'site block could not be removed','inaccessible')
      end
      return blocked('ambiguous site dig outcome; drops were not safely collected','ambiguous')
    end
    if not task.moveIntent then
      task.moveIntent={index=task.index,from={x=pose.x,y=pose.y,z=pose.z},to=U.copy(target)}; persist()
    end
    ok,why=nav:goTo(target); if not ok then return blocked(why,'inaccessible') end
    if U.distance(nav.pose,target)~=0 then return blocked('site movement did not reach waypoint','ambiguous') end
    return arrive()
  end
  return self
end
return M
