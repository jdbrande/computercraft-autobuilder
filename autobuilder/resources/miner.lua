local U=require('autobuilder.core.util')
local P=require('autobuilder.core.pathfinding')
local Materials=require('autobuilder.resources.materials')
local M={}
local forbidden={['minecraft:water']=true,['minecraft:lava']=true,['minecraft:bedrock']=true,
  ['minecraft:chest']=true,['minecraft:trapped_chest']=true,['minecraft:barrel']=true,
  ['minecraft:spawner']=true,['minecraft:ender_chest']=true}
local function point(p) return {x=p.x,y=p.y,z=p.z} end
local function same(a,b) return U.position(a) and U.position(b) and P.key(a)==P.key(b) end
function M.new(task,hw,config,nav,inventory,scanner,save,clock)
  assert(Materials.get(task.item) and U.integer(task.quantity) and task.quantity>0,'invalid mining task')
  local c=config.mining; local pose=nav.pose; local t=hw.turtle
  local self={task=task}; local observed,avoided={},{}; local route,routeTarget
  task.phase=task.phase or 'setup'; task.delivered=task.delivered or 0
  task.trail=task.trail or {}; task.survey=task.survey or 1; task.surveySteps=task.surveySteps or 0
  local function persist() local ok,err=save(); assert(ok,err); return true end
  local function block(err)
    if task.phase~='blocked' then task.resumePhase=task.phase end
    task.phase='blocked'; task.error=tostring(err); persist(); return false,task.error
  end
  local function restricted(p)
    for _,box in ipairs(config.restrictedAreas or {}) do if P.inside(p,box) then return true end end
    return false
  end
  local function diggable(name,p)
    return P.inside(p,c.bounds) and not restricted(p) and not forbidden[name]
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
  local function move(p,kind)
    if U.distance(pose,p)~=1 or restricted(p) then return false,'unsafe or nonadjacent move' end
    local suffix=''
    if p.y>pose.y then suffix='Up' elseif p.y<pose.y then suffix='Down'
    else
      local heading=p.x>pose.x and 'east' or p.x<pose.x and 'west' or p.z>pose.z and 'south' or 'north'
      local ok,err=nav:face(heading); if not ok then return false,err end
    end
    local present,b=t['inspect'..suffix]()
    if present then
      observed[P.key(p)]=b.name
      if not diggable(b.name,p) then avoided[P.key(p)]=true; return false,'protected or disallowed obstacle: '..b.name end
      if inventory:freeSlots()==0 then return false,'inventory full before dig' end
      -- Keep scanner/fuel slots reserved even when mining changes the selected slot.
      for slot=1,14 do if t.getItemCount(slot)==0 then t.select(slot); break end end
      local ok,err=t['dig'..suffix]()
      if not ok then return false,err or 'dig failed (diamond pickaxe required)' end
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
    local b=c.bounds; local row=math.floor((task.survey-1)/2); local edge=(task.survey-1)%2
    local z=c.entry.z+row*3
    if z>b.max.z then return nil end
    local x=(row%2==0 and edge==1 or row%2==1 and edge==0) and b.max.x or b.min.x
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
        if task.surveySteps>=c.maxSurveySteps then return startReturn('survey exhausted') end
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
      return block(why)
    end
    table.remove(route,1)
    if task.surveying then task.surveySteps=task.surveySteps+1; task.target=nil
    elseif same(pose,task.target) then task.target=nil end
    return persist()
  end
  function self:resume()
    if task.phase~='blocked' then return false,'task is not blocked' end
    if scanner.recover then local ok,err=scanner:recover(); if not ok then return false,err end end
    task.phase=task.resumePhase or 'setup'; task.error=nil
    observed={}; avoided={}; route=nil; scanner:invalidate()
    if task.returnReason=='survey exhausted' then task.returnReason=nil; task.survey=1; task.surveySteps=0; task.outbound=nil end
    return persist()
  end
  function self:step()
    if task.phase=='completed' then return true end
    if task.phase=='blocked' then return false,task.error end
    if not pose.known or not U.heading(pose.heading) or pose.pending or pose.uncertain then return block('trusted position and heading required') end
    local ok,err=recoverMove(); if not ok then return block(err) end
    ok,err=recoverDeposit(); if not ok then return block(err) end
    if task.phase=='setup' then
      if not same(pose,config.depot) then return block('new mining job must start at configured depot') end
      task.trail={point(pose)}; task.phase='unload'; task.returnReason='initial'; return persist()
    elseif task.phase=='travel' then
      local fuel=t.getFuelLevel()
      if fuel~='unlimited' and fuel<=#task.trail+(config.minimumFuelReserve or 100)+(c.returnMargin or 8) then return startReturn('fuel') end
      local target=c.entry
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
      if task.delivered>=task.quantity then task.phase='completed'; return persist() end
      if task.returnReason=='survey exhausted' then return block('survey exhausted; only '..task.delivered..' / '..task.quantity..' collected') end
      local required=math.max(c.fuelTarget or 1000,math.max(#(task.outbound or {}),U.distance(config.depot,c.entry))*2+(config.minimumFuelReserve or 100)+(c.returnMargin or 8))
      ok,err=inventory:refuel(required,true); if not ok then return block(err) end
      task.phase='travel'; return persist()
    end
    return block('unknown mining phase '..tostring(task.phase))
  end
  return self
end
return M
