local U=require('autobuilder.core.util')
local P=require('autobuilder.core.pathfinding')
local Materials=require('autobuilder.resources.materials')
local E=require('autobuilder.resources.exploration')
local M={}
local forbidden={['minecraft:water']=true,['minecraft:lava']=true,['minecraft:bedrock']=true,
  ['minecraft:chest']=true,['minecraft:trapped_chest']=true,['minecraft:barrel']=true,
  ['minecraft:spawner']=true,['minecraft:ender_chest']=true}
local function point(p) return {x=p.x,y=p.y,z=p.z} end
local function same(a,b) return U.position(a) and U.position(b) and P.key(a)==P.key(b) end
function M.new(task,hw,config,nav,inventory,scanner,save,clock)
  assert(Materials.get(task.item) and U.integer(task.quantity) and task.quantity>0,'invalid mining task')
  local g=task.exploration
  local c=config.mining; local pose=nav.pose; local t=hw.turtle
  local routeCells,exitCells,travel={},{},{}
  if g then
    assert(E.geometry(g),'invalid saved exploration geometry')
    c=U.copy(config.mining); c.bounds=g.bounds; c.entry=g.entry
    for _,p in ipairs(g.exitRoute) do travel[#travel+1]=p; exitCells[P.key(p)]=true end
    exitCells[P.key(g.depot)]=true
    for _,p in ipairs(g.route) do travel[#travel+1]=p; routeCells[P.key(p)]=true end
    task.explorationProgress=task.explorationProgress or {cursor=g.cursor,observations={},clearedRouteCount=0}
    task.survey=task.explorationProgress.cursor
    nav.clearExit=function(p) return task.phase~='completed' and exitCells[P.key(p)]==true end
  end
  local self={task=task}; local observed,avoided={},{}; local route,routeTarget
  task.phase=task.phase or 'setup'; task.delivered=task.delivered or 0
  task.trail=task.trail or {}; task.survey=task.survey or 1; task.surveySteps=task.surveySteps or 0
  local function persist()
    if g then task.explorationProgress.cursor=task.survey end
    local ok,err=save(); assert(ok,err); return true
  end
  local function block(err)
    if task.phase~='blocked' then task.resumePhase=task.phase end
    task.phase='blocked'; task.error=tostring(err); persist(); return false,task.error
  end
  local function restricted(p)
    for _,box in ipairs(config.restrictedAreas or {}) do if P.inside(p,box) then return true end end
    return g and E.protected(p,g.protectedAreas) or false
  end
  local function diggable(name,p)
    return (P.inside(p,c.bounds) or g and routeCells[P.key(p)]) and not (g and exitCells[P.key(p)]) and not restricted(p) and not forbidden[name]
      and not name:find('turtle') and not name:match('^computercraft:') and not (config.protectedBlocks or {})[name]
      and (config.allowedMiningBlocks or {})[name]==true
  end
  local function passable(p)
    if not P.inside(p,c.bounds) or restricted(p) or avoided[P.key(p)] then return false end
    local name=observed[P.key(p)]
    return not name or name=='minecraft:air' or name=='minecraft:cave_air' or diggable(name,p)
  end
  local function recoverMove()
    local m=task.pendingMove; if not m then return true end
    if same(pose,m.to) then
      if m.kind=='return' then
        if same(task.trail[#task.trail],m.from) then table.remove(task.trail) end
      elseif not same(task.trail[#task.trail],m.to) then task.trail[#task.trail+1]=point(m.to) end
    elseif not same(pose,m.from) then return false,'cannot reconcile mining movement; pose is outside recorded move' end
    task.pendingMove=nil; persist(); return true
  end
  local function recoverDeposit()
    local d=task.depositIntent; if not d then return true end
    local item=t.getItemDetail(d.slot)
    if item and item.name~=d.name then return false,'deposit slot changed during recovery' end
    local current=item and item.count or 0
    if current>d.before then return false,'deposit inventory grew during recovery' end
    if d.name==task.item then task.delivered=task.delivered+d.before-current end
    task.depositIntent=nil; persist(); return true
  end
  local function equal(a,b)
    if type(a)~=type(b) then return false end
    if type(a)~='table' then return a==b end
    for k,v in pairs(a) do if not equal(v,b[k]) then return false end end
    for k in pairs(b) do if a[k]==nil then return false end end
    return true
  end
  local function snapshot()
    local out={}; for i=1,16 do out[i]=t.getItemDetail(i) or false end; return out
  end
  local function gained(before,after)
    local gain=false
    for i=1,16 do
      local a,b=before[i],after[i]
      if i>=15 then if not equal(a,b) then return false end
      elseif a then
        if not b or a.name~=b.name or a.nbt~=b.nbt or b.count<a.count then return false end
        local copy=U.copy(b); copy.count=a.count; if not equal(a,copy) then return false end
        gain=gain or b.count>a.count
      elseif b then gain=true end
    end
    return gain
  end
  local function move(p,kind)
    if U.distance(pose,p)~=1 or restricted(p) and not (g and exitCells[P.key(p)]) then return false,'unsafe or nonadjacent move' end
    local suffix=''
    if p.y>pose.y then suffix='Up' elseif p.y<pose.y then suffix='Down'
    else
      local heading=p.x>pose.x and 'east' or p.x<pose.x and 'west' or p.z>pose.z and 'south' or 'north'
      local ok,err=nav:face(heading); if not ok then return false,err end
    end
    -- Excavation changes the destination too: reserve it before any dig,
    -- then navigation rechecks the grant before committing movement.
    if nav.guard then local ok,err=nav.guard(pose,p); if not ok then return false,err end end
    local present,b=t['inspect'..suffix]()
    if g and task.digIntent then
      local intent=task.digIntent; local now=snapshot()
      if not same(p,intent.target) then return false,'pending dig target changed' end
      if not present and gained(intent.inventory,now) or present and equal(b,intent.block) and equal(now,intent.inventory) then task.digIntent=nil; persist()
      else return false,'ambiguous exploration dig outcome; preserve target and inventory' end
    end
    if present then
      if g and kind=='return' then return false,'return route obstructed; no excavation authorized' end
      if g and b.state and (b.state.waterlogged==true or b.state.waterlogged=='true') then return false,'waterlogged exploration obstacle' end
      observed[P.key(p)]=b.name
      if not diggable(b.name,p) then avoided[P.key(p)]=true; return false,'protected or disallowed obstacle: '..b.name end
      if inventory:freeSlots()==0 then return false,'inventory full before dig' end
      -- Keep scanner/fuel slots reserved even when mining changes the selected slot.
      for slot=1,14 do if t.getItemCount(slot)==0 then t.select(slot); break end end
      local ok,err
      if g then
        task.digAttempts=task.digAttempts or {}; local key=P.key(p)
        if (task.digAttempts[key] or 0)>=4 then return false,'falling block dig limit reached' end
        task.digAttempts[key]=(task.digAttempts[key] or 0)+1
        task.digIntent={target=point(p),block=U.copy(b),inventory=snapshot(),moveKind=kind}; persist()
        local called; called,ok,err=pcall(t['dig'..suffix])
        if not called then return false,'uncertain exploration dig: '..tostring(ok) end
        local found,actual=t['inspect'..suffix](); local after=snapshot(); local intent=task.digIntent
        if ok and gained(intent.inventory,after) and (not found or equal(actual,b)) then
          task.digIntent=nil; persist()
          if found then return true end
        elseif found and equal(actual,b) and equal(intent.inventory,after) then task.digIntent=nil; persist(); return false,err or 'dig failed'
        else return false,'ambiguous exploration dig outcome; preserve target and inventory' end
      else ok,err=t['dig'..suffix](); if not ok then return false,err or 'dig failed (diamond pickaxe required)' end end
      scanner:invalidate(p); observed[P.key(p)]='minecraft:air'
      local still,obstacle=t['inspect'..suffix]()
      if still then return false,'obstacle remains after dig: '..tostring(obstacle.name) end
    end
    task.pendingMove={from=point(pose),to=point(p),kind=kind}; persist()
    local ok,err
    if suffix=='Up' then ok,err=nav:up() elseif suffix=='Down' then ok,err=nav:down() else ok,err=nav:forward() end
    if not ok then
      if pose.uncertain or pose.pending then return false,err end
      task.pendingMove=nil; persist(); return false,err
    end
    if g and routeCells[P.key(p)] then task.explorationProgress.clearedRouteCount=math.max(task.explorationProgress.clearedRouteCount,#task.trail-#g.exitRoute) end
    return recoverMove()
  end
  local function startReturn(reason)
    task.returnReason=reason; task.outbound=U.copy(task.trail); task.phase='return'; task.target=nil
    return persist()
  end
  local function travelStep(target,kind)
    -- The depot corridor is player-cleared; no speculative excavation outside bounds.
    local p=point(pose)
    if p.y~=target.y then p.y=p.y+(target.y>p.y and 1 or -1)
    elseif p.x~=target.x then p.x=p.x+(target.x>p.x and 1 or -1)
    elseif p.z~=target.z then p.z=p.z+(target.z>p.z and 1 or -1)
    else return true end
    return move(p,kind)
  end
  local function surveyTarget()
    local b=c.bounds
    if g then
      local nx=b.max.x-b.min.x+1; local nz=b.max.z-b.min.z+1; local i=task.survey-1
      if i>=nx*nz*(b.max.y-b.min.y+1) then return nil end
      local y=math.floor(i/(nx*nz)); local z=math.floor(i/nx)%nz; local x=i%nx
      if z%2==1 then x=nx-1-x end
      return {x=b.min.x+x,y=b.min.y+y,z=b.min.z+z}
    end
    local row=math.floor((task.survey-1)/2); local edge=(task.survey-1)%2
    local direction=c.entry.z==b.max.z and b.min.z<b.max.z and -1 or 1
    local z=c.entry.z+row*3*direction
    if z<b.min.z or z>b.max.z then return nil end
    local east=row%2==0 and edge==1 or row%2==1 and edge==0
    if c.entry.x==b.max.x then east=not east end
    local x=east and b.max.x or b.min.x
    return {x=x,y=c.entry.y,z=z}
  end
  local function adjacentTargets()
    local results={}; local original=pose.heading
    for _,p in ipairs(P.neighbors(pose)) do
      if P.inside(p,c.bounds) then
        local suffix=''
        if p.y>pose.y then suffix='Up' elseif p.y<pose.y then suffix='Down'
        else
          local heading=p.x>pose.x and 'east' or p.x<pose.x and 'west' or p.z>pose.z and 'south' or 'north'
          local ok,err=nav:face(heading); if not ok then return nil,err end
        end
        local found,b=t['inspect'..suffix]()
        observed[P.key(p)]=found and b.name or 'minecraft:air'
        if found and Materials.get(task.item).blocks[b.name] and diggable(b.name,p) then results[#results+1]=p end
      end
    end
    local ok,err=nav:face(original); if not ok then return nil,err end
    return results
  end
  local function work()
    local held=inventory:getCount(task.item)
    if task.delivered+held>=task.quantity then return startReturn('complete') end
    if inventory:freeSlots()<2 then return startReturn('inventory') end
    local fuel=t.getFuelLevel()
    if fuel~='unlimited' and fuel<=#task.trail+(config.minimumFuelReserve or 100)+(c.returnMargin or 8) then return startReturn('fuel') end
    if not task.target then
      local blocks,err,wait,fault=scanner:scan(pose)
      if fault=='hardware' then return block(err) end
      if wait then task.waitUntil=clock()+wait; return true end
      local candidates={}
      if blocks then
        if g then
          local observations={}
          for _,b in ipairs(blocks) do if P.inside(b,g.bounds) and #observations<64 then observations[#observations+1]=U.copy(b) end end
          task.explorationProgress.observations=observations
        end
        for _,b in ipairs(blocks) do observed[P.key(b)]=b.name end
        for _,vein in ipairs(scanner:veins(blocks,Materials.get(task.item).blocks,pose)) do
          for _,p in ipairs(vein) do if passable(p) and not same(p,pose) then candidates[#candidates+1]=point(p) end end
        end
      elseif c.fallback==false then return block(err)
      else
        task.scannerWarning=err
        local why; candidates,why=adjacentTargets(); if not candidates then return block(why) end
      end
      for _,p in ipairs(candidates) do
        local path=P.find(pose,p,passable,c.pathBudget)
        if path then task.target=p; break end
        avoided[P.key(p)]=true
      end
      if not task.target then
        if not g and task.surveySteps>=c.maxSurveySteps then return startReturn('survey exhausted') end
        local target=surveyTarget()
        while target and same(target,pose) do task.survey=task.survey+1; target=surveyTarget() end
        if not target then return startReturn('survey exhausted') end
        task.target=target; task.surveying=true
      else task.surveying=false end
      persist()
    end
    if same(pose,task.target) then task.target=nil; return persist() end
    if not route or routeTarget~=P.key(task.target) or #route==0 or U.distance(pose,route[1])~=1 then
      local err; route,err=P.find(pose,task.target,passable,c.pathBudget)
      routeTarget=P.key(task.target)
      if not route or #route==0 then return block(err or 'target unreachable') end
    end
    local nextPosition=route[1]
    local ok,why=move(nextPosition,'work')
    if not ok then
      route=nil
      if avoided[P.key(nextPosition)] and not pose.pending and not pose.uncertain then
        if same(nextPosition,task.target) then task.target=nil end
        return persist()
      end
      if g and not task.digIntent and not pose.pending and not pose.uncertain and not tostring(why):find('reservation',1,true) then return startReturn('route_blocked') end
      return block(why)
    end
    table.remove(route,1)
    if task.surveying then task.surveySteps=task.surveySteps+1; task.target=nil
    elseif same(pose,task.target) then task.target=nil end
    return persist()
  end
  function self:requestReturn() task.returnRequested=true; return persist() end
  function self:resume()
    if task.phase~='blocked' then return false,'task is not blocked' end
    if scanner.recover then local ok,err=scanner:recover(); if not ok then return false,err end end
    task.phase=task.resumePhase or 'setup'; task.error=nil
    observed={}; avoided={}; route=nil; scanner:invalidate()
    if not g and task.returnReason=='survey exhausted' then task.returnReason=nil; task.survey=1; task.surveySteps=0; task.outbound=nil end
    return persist()
  end
  function self:step()
    if task.phase=='completed' then return true end
    if task.phase=='blocked' then return false,task.error end
    if not pose.known or not U.heading(pose.heading) or pose.pending or pose.uncertain then return block('trusted position and heading required') end
    local ok,err=recoverMove(); if not ok then return block(err) end
    ok,err=recoverDeposit(); if not ok then return block(err) end
    if g and task.digIntent then
      ok,err=move(task.digIntent.target,task.digIntent.moveKind); if not ok then return block(err) end; return true
    end
    if g and task.returnRequested and task.phase~='return' and task.phase~='unload' and task.phase~='setup' then return startReturn('paused') end
    if task.phase=='setup' then
      if not same(pose,config.depot) then return block('new mining job must start at configured depot') end
      task.trail={point(pose)}; task.phase='unload'; task.returnReason='initial'; return persist()
    elseif task.phase=='travel' then
      local fuel=t.getFuelLevel()
      if fuel~='unlimited' and fuel<=#task.trail+(config.minimumFuelReserve or 100)+(c.returnMargin or 8) then return startReturn('fuel') end
      local target=c.entry
      if g then
        target=travel[#task.trail]
        if not target then task.phase='work'; return persist() end
        ok,err=move(target,'travel')
        if not ok then
          if not task.digIntent and not pose.pending and not pose.uncertain and not tostring(err):find('reservation',1,true) then return startReturn('route_blocked') end
          return block(err)
        end
        return true
      end
      if task.outbound and #task.outbound>1 then
        local index=#task.trail+1; target=task.outbound[index]
        if not target then task.outbound=nil; task.phase='work'; return persist() end
      elseif same(pose,target) then task.phase='work'; return persist() end
      ok,err=travelStep(target,'travel'); if not ok then return block(err) end
      return true
    elseif task.phase=='work' then return work()
    elseif task.phase=='return' then
      if #task.trail<=1 then
        if not same(pose,config.depot) then return block('return route did not end at depot') end
        task.phase='unload'; return persist()
      end
      ok,err=move(task.trail[#task.trail-1],'return'); if not ok then return block(err) end
      return true
    elseif task.phase=='unload' then
      if not same(pose,config.depot) then return block('unload requires depot position') end
      local slot=inventory:nextDeposit()
      if slot then
        local item=t.getItemDetail(slot)
        task.depositIntent={slot=slot,name=item.name,before=item.count}; persist()
        local moved,why=inventory:depositSlot(slot)
        if not moved then
          -- Reconcile any partial transfer before exposing the failure.
          recoverDeposit(); return block(why)
        end
        recoverDeposit(); return true
      end
      if g and task.returnReason~='initial' then
        local reason=({complete='quota',['survey exhausted']='survey_exhausted',inventory='cargo',fuel='fuel',paused='paused',route_blocked='route_blocked'})[task.returnReason]
        task.explorationProgress.result=assert(reason,'unknown exploration return result'); task.phase='completed'; return persist()
      end
      if g and task.returnRequested then task.returnReason='paused'; return persist() end
      if task.delivered>=task.quantity then
        if g then task.explorationProgress.result='quota' end
        task.phase='completed'; return persist()
      end
      if task.returnReason=='survey exhausted' then return block('survey exhausted; only '..task.delivered..' / '..task.quantity..' collected') end
      local required=math.max(c.fuelTarget or 1000,math.max(#(task.outbound or {}),U.distance(config.depot,c.entry))*2+(config.minimumFuelReserve or 100)+(c.returnMargin or 8))
      if g then required=math.max(required,#travel*2+(config.minimumFuelReserve or 100)+(c.returnMargin or 8)+2) end
      ok,err=inventory:refuel(required,true); if not ok then return block(err) end
      task.phase='travel'; return persist()
    end
    return block('unknown mining phase '..tostring(task.phase))
  end
  return self
end
return M
