local U=require('autobuilder.core.util')
local M={}
function M.new(state,config,network,turtle,save)
  local self={connected=false}; local lastRegister,lastHeartbeat,lastAck=-math.huge,-math.huge,-math.huge
  local pending={}
  state.status=state.status or 'idle'; state.position=state.position or {known=false}
  function self:telemetry()
    local used=0
    for slot=1,16 do if turtle.getItemCount(slot)>0 then used=used+1 end end
    local p=state.position
    return {label=config.label or ('Turtle '..tostring(state.id or '?')),status=state.status,
      position={known=p.known==true,x=p.x,y=p.y,z=p.z,heading=p.heading,source=p.source or 'unknown'},
      fuel=turtle.getFuelLevel(),inventory={used=used,slots=16},
      miningArea=config.mining and config.mining.enabled and U.copy(config.mining.bounds) or nil,
      capabilities=U.copy(config.capabilities or {telemetry=true}),task=state.currentTask and tostring(state.currentTask.id)}
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
      pending[m.payload.requestId]=nil; lastAck=now; self.connected=true; return true
    elseif m.type=='register_required' then lastRegister=-math.huge; self.connected=false; return true end
    return false,'unexpected or stale controller response'
  end
  return self
end
return M
