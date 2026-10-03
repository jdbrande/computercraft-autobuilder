local U=require('autobuilder.core.util')
local M={}
local order={'north','east','south','west'}
local headings={north=1,east=2,south=3,west=4}
local vectors={north={0,-1},east={1,0},south={0,1},west={-1,0}}
function M.new(turtle,pose,config,save)
  assert(type(pose)=='table' and type(save)=='function','pose and persistence callback required')
  config=config or {}; local self={pose=pose}
  local function persist()
    local ok,result,err=pcall(save)
    if not ok then return false,tostring(result) end
    return result,err
  end
  local function allowed(p)
    for _,area in ipairs(config.restrictedAreas or {}) do
      if p.x>=area.min.x and p.x<=area.max.x and p.y>=area.min.y and p.y<=area.max.y and p.z>=area.min.z and p.z<=area.max.z then
        if not self.clearExit or not self.clearExit(p) then return false,'destination is protected' end
      end
    end
    return true
  end
  local function step(action)
    if pose.pending or pose.uncertain then return false,'position uncertain; reconcile GPS and heading first' end
    if not pose.known or not U.position(pose) or not U.heading(pose.heading) then return false,'position/heading unknown' end
    local target=U.copy(pose); local turn=action=='turnLeft' or action=='turnRight'
    if turn then target.heading=order[(headings[pose.heading]-1+(action=='turnRight' and 1 or -1))%4+1]
    elseif action=='up' then target.y=target.y+1
    elseif action=='down' then target.y=target.y-1
    else local d=vectors[pose.heading]; local sign=action=='back' and -1 or 1; target.x=target.x+d[1]*sign; target.z=target.z+d[2]*sign end
    if not turn then
      if self.coverageGuard then local ok,why=self.coverageGuard(pose,target); if not ok then return false,why end end
      local permitted,why=allowed(target); if not permitted then return false,why end
      local ok,fuel=pcall(turtle.getFuelLevel); if not ok then return false,'fuel query failed: '..tostring(fuel) end
      local home=config.depot; local distance=home and U.distance(target,home) or 0
      if fuel~='unlimited' and (not U.finite(fuel) or fuel<1+distance+(config.minimumFuelReserve or 100)) then return false,'insufficient fuel for movement and return reserve' end
      if self.guard then local ok,err=self.guard(pose,target); if not ok then return false,err end end
    end
    pose.pending={action=action,from={x=pose.x,y=pose.y,z=pose.z,heading=pose.heading},to={x=target.x,y=target.y,z=target.z,heading=target.heading}}
    local saved,why=persist(); if not saved then pose.uncertain=true; return false,why end
    local success,reason=false,'movement failed'
    for _=1,config.movementRetries or 2 do
      local ok,result,err=pcall(turtle[action])
      if not ok then pose.uncertain=true; return false,'hardware error; pose uncertain: '..tostring(result) end
      if result then success=true; break end
      reason=err or reason
    end
    if success then pose.x,pose.y,pose.z,pose.heading=target.x,target.y,target.z,target.heading end
    pose.pending=nil
    saved,why=persist(); if not saved then pose.uncertain=true; return false,'post-movement '..tostring(why) end
    if success and not turn and self.afterMove then self.afterMove(target) end
    if not success then
      local inspect=action=='up' and turtle.inspectUp or action=='down' and turtle.inspectDown or action=='forward' and turtle.inspect
      if inspect then local ok,found,block=pcall(inspect); if ok and found then reason=reason..': '..tostring(block.name) end end
      return false,reason
    end
    return true
  end
  for _,action in ipairs({'forward','back','up','down','turnLeft','turnRight'}) do self[action]=function() return step(action) end end
  function self:face(heading)
    if pose.pending or pose.uncertain or not pose.known then return false,'pose unknown or uncertain' end
    if not U.heading(heading) then return false,'invalid heading' end
    if not U.heading(pose.heading) then return false,'heading unknown' end
    local turns=(headings[heading]-headings[pose.heading])%4
    for _=1,(turns==3 and 1 or turns) do local ok,err=step(turns==3 and 'turnLeft' or 'turnRight'); if not ok then return false,err end end
    return true
  end
  function self:reconcile(fix,heading,validateJournal)
    if not U.position(fix) or (heading and not U.heading(heading)) then return false,'invalid pose' end
    local before=U.copy(pose)
    local intent=pose.pending
    if intent and (not heading or validateJournal) then
      local turn=intent.action=='turnLeft' or intent.action=='turnRight'
      local from=intent.from or (turn and pose)
      local to=intent.to or (turn and pose)
      local valid=U.position(from) and U.position(to)
      if valid and turn then valid=U.distance(from,to)==0
      elseif valid then
        local dx,dy,dz=to.x-from.x,to.y-from.y,to.z-from.z
        local v=vectors[from.heading]
        valid=intent.action=='up' and dx==0 and dy==1 and dz==0
          or intent.action=='down' and dx==0 and dy==-1 and dz==0
          or v and (intent.action=='forward' or intent.action=='back') and dy==0
            and dx==v[1]*(intent.action=='back' and -1 or 1) and dz==v[2]*(intent.action=='back' and -1 or 1)
      end
      if not valid or U.distance(fix,from)~=0 and U.distance(fix,to)~=0 then
        return false,'GPS fix does not match the movement journal; inspect turtle and confirm pose'
      end
    end
    -- GPS can resolve a translation, but cannot resolve a turn interrupted by reboot.
    if pose.pending and pose.pending.action:find('turn') and not heading then pose.heading=nil end
    pose.x,pose.y,pose.z=fix.x,fix.y,fix.z
    pose.heading=heading or pose.heading; pose.known=true; pose.pending=nil; pose.uncertain=nil
    local ok,err=persist()
    if not ok then
      for k in pairs(pose) do pose[k]=nil end;for k,v in pairs(before) do pose[k]=v end
      pose.uncertain=true
    end
    return ok,err
  end
  function self:goTo(target)
    if type(target)=='string' then target=(config.locations or {})[target] end
    if not U.position(target) then return false,'invalid target' end
    if not U.position(pose) or not pose.known or pose.uncertain or pose.pending then return false,'pose unknown or uncertain' end
    if U.distance(pose,target)>(config.maxTravelDistance or 256) then return false,'travel distance exceeds limit' end
    -- Reuse bounded pathfinding only after confirmed traffic denial. Every
    -- physical step still obtains a fresh reservation and obeys fuel/coverage.
    -- ponytail: 256-node detours; larger global routes need hierarchical planning.
    local P=require('autobuilder.core.pathfinding')
    if pose.detour and U.distance(pose.detour.target,target)>0 then pose.detour=nil end
    local obstacle=self.trafficObstacle and self.trafficObstacle()
    if obstacle then
      local d=pose.detour or {target={x=target.x,y=target.y,z=target.z},blocked={},count=0}
      if not d.blocked[P.key(obstacle)] then
        if d.count>=16 then return false,'movement reservation pending: traffic detour limit reached' end
        d.blocked[P.key(obstacle)]=true;d.count=d.count+1;d.path=nil
      end
      if not d.path then
        local box={min={},max={}}
        for _,axis in ipairs({'x','y','z'}) do box.min[axis]=math.min(pose[axis],target[axis])-2;box.max[axis]=math.max(pose[axis],target[axis])+2 end
        local path=P.find(pose,target,function(p) return U.position(p) and P.inside(p,box) and not d.blocked[P.key(p)] and allowed(p) end,256)
        if not path then
          pose.detour=nil;local ok,why=persist();if not ok then return false,why end
          return false,'movement reservation pending: no bounded traffic detour'
        end
        d.path=path;d.index=1
      end
      pose.detour=d;local ok,why=persist();if not ok then return false,why end
    end
    if pose.detour then
      local d=pose.detour
      while d.index<=#d.path do
        local point=d.path[d.index]
        if U.distance(pose,point)==0 then d.index=d.index+1
        else
          if U.distance(pose,point)~=1 then pose.detour=nil;local ok,why=persist();if not ok then return false,why end;return self:goTo(target) end
          local action
          if point.y~=pose.y then action=point.y>pose.y and 'up' or 'down'
          else
            local heading=point.x~=pose.x and (point.x>pose.x and 'east' or 'west') or (point.z>pose.z and 'south' or 'north')
            local ok,why=self:face(heading);if not ok then return false,why end;action='forward'
          end
          local ok,why=step(action);if not ok then return false,why end
        end
      end
      pose.detour=nil;local ok,why=persist();if not ok then return false,why end
      return true
    end
    -- Ordinary unobstructed travel keeps the inexpensive axis route.
    for _,axis in ipairs({'y','x','z'}) do
      while pose[axis]~=target[axis] do
        local positive=target[axis]>pose[axis]
        if axis~='y' then local ok,err=self:face(axis=='x' and (positive and 'east' or 'west') or (positive and 'south' or 'north')); if not ok then return false,err end end
        local ok,err=step(axis=='y' and (positive and 'up' or 'down') or 'forward'); if not ok then return false,err end
      end
    end
    return true
  end
  function self:goHome()
    if not config.depot then return false,'depot not configured' end
    return self:goTo(config.depot)
  end
  return self
end
return M
