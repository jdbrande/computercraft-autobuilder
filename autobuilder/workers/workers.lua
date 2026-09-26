local U=require('autobuilder.core.util')
local M={}
function M.new(state,config,save)
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
    local ok,err=save()
    if not ok then state.workers[key]=old; return false,err end
    return true
  end
  function self:expire(now)
    local changed=false
    for _,w in pairs(state.workers) do
      if w.online and now-w.lastSeen>(config.workerTimeout or 30) then w.online=false; changed=true end
    end
    if changed then return save() end
    return true
  end
  return self
end
return M
