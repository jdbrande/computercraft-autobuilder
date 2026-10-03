local U=require('autobuilder.core.util')
local Chunks=require('autobuilder.core.chunks')
local M={}
function M.new(app,config,e,network,clock,gps)
  local s=app.state;local self={};local last=-math.huge
  local function save() assert(app:save()) end
  local function send(kind,r)
    return network:send(config.controllerId,kind,{jobId=r.jobId,sequence=r.sequence,origin=U.copy(r.origin)})
  end
  local function errorStatus(why)
    s.status='recovery_required';s.poseError=tostring(why);save();return false,why
  end
  local function enabled()
    local t=s.currentTask
    local mining=t and (not t.type or t.type=='MINE')
    return t and not t.paused and (mining and (config.mining.enabled or t.exploration) or not mining and config.automation.enabled)
  end
  function self:needed()
    local p=s.position
    return s.poseRecovery~=nil or s.currentTask and s.currentTask.phase~='completed'
      and p.known and not p.pending and not p.uncertain and not U.heading(p.heading)
  end
  function self:guard(from,target)
    local r=s.poseRecovery
    return r and r.granted and r.stage=='return' and U.distance(target,r.origin)==0
      and U.distance(from,r.origin)==1 or false,'pose recovery owns movement'
  end
  function self:handle(kind,p)
    local r=s.poseRecovery
    if not r or p.jobId~=r.jobId or p.sequence~=r.sequence or U.distance(p.origin,r.origin)~=0 then return false,'pose contract mismatch' end
    if kind=='task_pose_grant' and r.stage=='ready' then
      r.granted=p.granted==true;s.poseError=not r.granted and (p.reason or 'waiting for controller pose reservation') or nil;save();return true
    elseif kind=='task_pose_ack' and r.stage=='settling' then
      s.poseReceipt={jobId=r.jobId,sequence=r.sequence,origin=U.copy(r.origin),stage='settled',granted=true}
      s.poseRecovery=nil;s.motionReservation=nil;s.poseError=nil;save();app:poseRecovered();return true
    end
    return false,'unexpected pose response'
  end
  function self:observe(fix)
    local r=s.poseRecovery;if not r then return false,'no pose recovery' end
    if not U.position(fix) then return errorStatus('GPS unavailable for pose recovery') end
    local distance=U.distance(fix,r.origin)
    if r.stage=='probe' then
      if distance==0 then
        local ok,why=app.navigation:reconcile(fix);if not ok then return errorStatus(why) end
        r.stage='ready';save();return true
      end
      local heading=require('autobuilder.core.gps').heading(r.origin,fix)
      if not heading then return errorStatus('GPS probe fix differs from its origin and adjacent destinations') end
      local ok,why=app.navigation:reconcile(fix,heading);if not ok then return errorStatus(why) end
      r.heading=heading;r.stage='return';save();return true
    elseif r.stage=='return' then
      if distance~=0 and require('autobuilder.core.gps').heading(r.origin,fix)~=r.heading then
        return errorStatus('GPS backtrack fix differs from its recorded probe path')
      end
      local ok,why=app.navigation:reconcile(fix,r.heading,true);if not ok then return errorStatus(why) end
      if distance==0 then r.stage='settling';save() end
      return true
    elseif distance~=0 then return errorStatus('GPS pose recovery origin changed before probe or settlement') end
    return true
  end
  local function permitted(r)
    local cells=require('autobuilder.core.workflows').poseCells(r.origin)
    if not cells then return false,'invalid pose probe origin' end
    for i,p in ipairs(cells) do
      local ok,why=Chunks.guard(config,s,r.origin,p);if not ok then return false,why end
      if i>1 and (require('autobuilder.resources.exploration').protected(p,config.restrictedAreas)
        or s.currentTask.exploration and require('autobuilder.resources.exploration').protected(p,s.currentTask.exploration.protectedAreas)) then
        return false,'pose probe enters protected area'
      end
    end
    local fuel=e.turtle.getFuelLevel()
    local need=2+(config.depot and U.distance(r.origin,config.depot) or 0)+(config.minimumFuelReserve or 100)
    if fuel~='unlimited' and (not U.finite(fuel) or fuel<need) then return false,'pose probe needs fuel for forward, backtrack and return reserve' end
    if e.turtle.inspect() then return false,'pose probe front obstructed; clear the accessible recovery cell' end
    return true
  end
  function self:step()
    if not self:needed() or not enabled() then return true end
    if clock()-last<config.heartbeatInterval then return true end;last=clock()
    local r=s.poseRecovery
    if r and (not s.currentTask or s.currentTask.id~=r.jobId) then return errorStatus('pose recovery task ownership changed') end
    if r and r.stage=='settling' then send('task_pose_done',r);return true end
    local fix,why=gps:locate();if not fix then return errorStatus(why or 'GPS unavailable') end
    if not r then
      local ok,err=app.navigation:reconcile(fix);if not ok then return errorStatus(err) end
      s.poseSequence=(s.poseSequence or 0)+1
      r={jobId=s.currentTask.id,sequence=s.poseSequence,origin={x=fix.x,y=fix.y,z=fix.z},stage='ready',granted=false}
      s.poseRecovery=r;s.status='recovery_required';save();send('task_pose_reserve',r);return true
    end
    local ok,err=self:observe(fix);if not ok then return false,err end
    if r.stage=='settling' then send('task_pose_done',r);return true end
    if r.stage=='return' then
      local covered,reason=Chunks.guard(config,s,s.position,r.origin);if not covered then return errorStatus(reason) end
      if not enabled() then return true end
      local moved,reason=app.navigation:back();if not moved then return errorStatus(reason) end
      return true
    end
    if r.stage~='ready' then return true end
    if not r.granted then send('task_pose_reserve',r);return true end
    ok,err=permitted(r);if not ok then return errorStatus(err) end
    if not enabled() then return true end
    r.stage='probe';s.position.uncertain=true;save()
    local called,moved,reason=pcall(e.turtle.forward)
    if not called or not moved then return errorStatus(called and (reason or 'pose probe movement blocked') or moved) end
    -- No local direction assumption: fresh GPS must settle this physical effect.
    return true
  end
  return self
end
return M
