local U=require('autobuilder.core.util')
local M={}
function M.new(state,config,network,turtle,save,chunkProbe)
  local self={connected=false}; local lastRegister,lastHeartbeat,lastAck=-math.huge,-math.huge,-math.huge
  local pending={}
  state.status=state.status or 'idle'; state.position=state.position or {known=false}
  function self:telemetry()
    local used=0
    for slot=1,16 do if turtle.getItemCount(slot)>0 then used=used+1 end end
    local p=state.position
    local capabilities=U.copy(config.capabilities or {telemetry=true})
    capabilities.returnCargoV1=config.automation and config.automation.enabled==true and type(turtle.getItemDetail)=='function' or false
    capabilities.supplyStationV1=config.automation and config.automation.enabled==true or false
    local cargo=capabilities.returnCargoV1 and require('autobuilder.storage.returns').observe(turtle,config) or nil
    capabilities.fuelV1=config.fuel and config.fuel.enabled or false
    capabilities.chunkCoverageV1=config.chunkLoading and config.chunkLoading.enabled==true or false
    local task=state.currentTask
    local need=config.fuel and config.fuel.enabled and task and not task.paused
      and require('autobuilder.workers.fuel_recovery').needsFuel(task)
      and math.max(config.fuel.target,config.mining.fuelTarget,task.requiredFuel or 0) or nil
    local limit=turtle.getFuelLimit and turtle.getFuelLimit() or nil
    if limit=='unlimited' then limit=nil end
    local current=turtle.getFuelLevel();local budget,budgetError
    if task then budget,budgetError=require('autobuilder.resources.fuel_budget').mission(config,task,{fuel=current,position=p,depot=config.depot}) end
    return {cargo=cargo,controllerBoot=state.controllerBoot,poseRecovery=require('autobuilder.core.task_messages').poseReport(state.poseRecovery or state.poseReceipt),
      fuelBudget=budget,fuelBudgetError=budgetError,
      chunkAnchor=chunkProbe and chunkProbe() or nil,fuelRequired=need,fuelLimit=limit,label=config.label or ('Turtle '..tostring(state.id or '?')),status=state.status,
      position={known=p.known==true,x=p.x,y=p.y,z=p.z,heading=p.heading,source=p.source or 'unknown'},
      fuel=current,depot=U.copy(config.depot),inventory={used=used,slots=16},
      miningResources=config.mining and config.mining.enabled and U.copy(config.mining.resources or {}) or nil,
      miningArea=config.mining and config.mining.enabled and U.copy(config.mining.bounds) or nil,
      explorationHome=config.capabilities and config.capabilities.explorationV1 and {depot=U.copy(config.depot),exitRoute=U.copy(config.mining.exitRoute),protectedAreas=U.copy(config.restrictedAreas)} or nil,
      capabilities=capabilities,task=state.currentTask and tostring(state.currentTask.id)}
  end
  function self:tick(now)
    self.connected=now-lastAck<config.workerTimeout
    for id,at in pairs(pending) do if now-at>config.workerTimeout then pending[id]=nil end end
    local kind
    if now-lastRegister>=config.registrationInterval then kind='register'
    elseif now-lastHeartbeat>=config.heartbeatInterval then kind='heartbeat' end
    if not kind then return true end
    -- Rate limit failed sends too, including a missing modem.
    if kind=='register' then lastRegister=now end
    lastHeartbeat=now
    local ok,info=pcall(self.telemetry,self)
    if not ok then return false,'telemetry failed: '..tostring(info) end
    state.telemetry=info
    local saved,err=save(); if not saved then return false,err end
    local sent,id=network:send(config.controllerId,kind,info)
    if sent then pending[id]=now end
    return sent,id
  end
  function self:handle(sender,m,now)
    if sender~=config.controllerId then return false,'not configured controller' end
    if m.type=='ack' and pending[m.payload.requestId] then
      if m.boot and m.boot<(state.controllerBoot or 0) then return false,'stale controller acknowledgement' end
      if m.boot and m.boot~=(state.controllerBoot or 0) then
        state.controllerBoot=m.boot
        if state.poseRecovery and state.poseRecovery.stage=='ready' then state.poseRecovery.granted=false end
        local ok,why=save();if not ok then return false,why end
      end
      pending[m.payload.requestId]=nil; lastAck=now; self.connected=true; return true
    elseif m.type=='register_required' then lastRegister=-math.huge; self.connected=false; return true end
    return false,'unexpected or stale controller response'
  end
  return self
end
return M
