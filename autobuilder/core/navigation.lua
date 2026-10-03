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
  function self:reconcile(fix,heading)
    if not U.position(fix) or (heading and not U.heading(heading)) then return false,'invalid pose' end
    -- GPS can resolve a translation, but cannot resolve a turn interrupted by reboot.
    if pose.pending and pose.pending.action:find('turn') and not heading then pose.heading=nil end
    pose.x,pose.y,pose.z=fix.x,fix.y,fix.z
    pose.heading=heading or pose.heading; pose.known=true; pose.pending=nil; pose.uncertain=nil
    local ok,err=persist(); if not ok then pose.uncertain=true end; return ok,err
  end
  function self:goTo(target)
    if type(target)=='string' then target=(config.locations or {})[target] end
    if not U.position(target) then return false,'invalid target' end
    if not U.position(pose) or not pose.known or pose.uncertain or pose.pending then return false,'pose unknown or uncertain' end
    if U.distance(pose,target)>(config.maxTravelDistance or 256) then return false,'travel distance exceeds limit' end
    -- Conservative axis route; stops at obstacles. A* is a later milestone.
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
