local U=require('autobuilder.core.util')
local M={}
function M.new(state,config,save,record)
  record=record or function() end
  state.workers=state.workers or {}
  for _,w in pairs(state.workers) do w.online=false end
  local self={state=state}
  function self:handle(m,now)
    if m.type~='register' and m.type~='heartbeat' then return false,'unexpected worker message' end
    local key=tostring(m.sender); local old=state.workers[key]
    if m.type=='heartbeat' and not old then return false,'registration required' end
    if old and (m.boot<old.boot or (m.boot==old.boot and m.sequence<=old.sequence)) then return false,'stale message' end
    if not old then
      local count=0; for _ in pairs(state.workers) do count=count+1 end
      if count>=(config.maxWorkers or 128) then return false,'worker registry full' end
    end
    state.workers[key]={id=m.sender,boot=m.boot,sequence=m.sequence,
      online=true,lastSeen=now,telemetry=U.copy(m.payload)}
    local called,ok,err=pcall(save)
    if not called or not ok then state.workers[key]=old;return false,called and err or ok end
    if not old or not old.online or old.boot~=m.boot then record('worker_online',{worker=m.sender,boot=m.boot,status=m.payload.status}) end
    return true
  end
  function self:expire(now)
    local changed={}
    for _,w in pairs(state.workers) do
      if w.online and now-w.lastSeen>(config.workerTimeout or 30) then w.online=false;changed[#changed+1]=w end
    end
    if #changed>0 then
      local called,ok,err=pcall(save)
      if not called or not ok then for _,w in ipairs(changed) do w.online=true end;return false,called and err or ok end
      for _,w in ipairs(changed) do record('worker_offline',{worker=w.id,lastSeen=w.lastSeen}) end
    end
    return true
  end
  return self
end
return M
