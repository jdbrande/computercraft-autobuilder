local U=require('autobuilder.core.util')
local Types=require('autobuilder.core.task_messages').types
local M={}
local caps={CRAFT='crafting',BUILD='building',VERIFY='building',REPAIR='building',CLEAR='building',TRANSPORT='courier',HARVEST='logging',FARM='farming',REFUEL='telemetry',RETURN_HOME='telemetry'}
local function key(p) return p.x..','..p.y..','..p.z end
local function intersects(a,b)
  if not a or not b then return false end
  for _,axis in ipairs({'x','y','z'}) do if a.max[axis]+1<b.min[axis] or b.max[axis]+1<a.min[axis] then return false end end
  return true
end
-- Durable ownership is shared by the mining and generic queues. Heartbeats may
-- still say idle immediately after either queue has saved an assignment.
local storageWorkers={HARVEST=true,FARM=true,TRANSPORT=true,REFUEL=true}
local function factory(job) return job.type=='SMELT' or job.type=='CRAFT' end
function M.workerBusy(state,owner,exceptId)
  for _,job in pairs(state.jobs or {}) do
    if job.id~=exceptId and job.workerId==owner and job.status~='completed' and not job.physicalComplete then return true end
  end
  for _,job in pairs((state.automation or {}).jobs or {}) do
    if job.id~=exceptId and job.workerId==owner and job.status~='completed' then return true end
  end
  return false
end
function M.factoryPending(state)
  for _,job in pairs((state.automation or {}).jobs or {}) do
    if factory(job) and (job.status~='completed' or job.production and job.production.intent) then return true end
  end
  return false
end
function M.factoryActive(state)
  for _,job in pairs((state.automation or {}).jobs or {}) do
    local p=job.production
    if factory(job) and (job.status~='completed' or p and p.intent)
      and (job.workerId or job.status=='running' or p and (p.furnace or p.intent or (p.loaded or 0)>0 or (p.crafted or 0)>0)) then return true end
  end
  return false
end
function M.canOfferSupply(state,job)
  if not M.factoryPending(state) then return true end
  -- Drain seed/sapling requirements of an actor assigned before the factory was
  -- queued. The factory cannot take physical ownership until this actor finishes.
  return storageWorkers[job.type] and job.workerId~=nil and job.status~='completed' and not M.factoryActive(state)
end
function M.storageBusy(state)
  for _,job in pairs(state.jobs or {}) do
    if job.workerId and job.status~='completed' and not job.physicalComplete then return true,'waiting for active mining job '..job.id end
  end
  local automation=state.automation or {}
  for _,job in pairs(automation.jobs or {}) do
    if storageWorkers[job.type] and job.workerId and job.status~='completed' then return true,'waiting for active storage job '..job.id end
  end
  if automation.supply then return true,'waiting for outstanding supply batch '..tostring(automation.supply.jobId) end
  return false
end
function M.factoryCanRun(state,job)
  local busy,why=M.storageBusy(state); if busy then return false,why end
  for _,other in pairs((state.automation or {}).jobs or {}) do
    if other.id~=job.id and factory(other) and other.status~='completed' then
      local p=other.production
      local active=other.workerId or other.status=='running' or p and (p.furnace or p.intent or (p.loaded or 0)>0 or (p.crafted or 0)>0)
      local sameBank=job.type=='SMELT' and other.type=='SMELT' and job.productionRequest
        and job.productionRequest==other.productionRequest and job.productionOperation==other.productionOperation
      if active and not sameBank then return false,'waiting for factory operation '..other.id end
    end
  end
  return true
end
function M.new(state,save,clock,id)
  state.automation=state.automation or {jobs={},sequence=0,requests={},projects={},cells={}}
  local s=state.automation; s.cells=s.cells or {}; local self={state=s}
  local function persist() local ok,err=save(); assert(ok,err) end
  function self:submit(kind,payload,deps,dedup)
    assert(Types[kind],'unsupported task type')
    for _,j in pairs(s.jobs) do if dedup and j.key==dedup then return j end end
    s.sequence=s.sequence+1
    local j=U.copy(payload or {}); j.id='task:'..id..':'..s.sequence; j.type=kind
    j.key=dedup; j.status='queued'; j.progress=0; j.dependencies=U.copy(deps or {}); j.retryCount=0
    j.created=clock(); j.requiredCapability=caps[kind]
    if j.blocks and #j.blocks>0 then
      j.bounds={min={x=math.huge,y=math.huge,z=math.huge},max={x=-math.huge,y=-math.huge,z=-math.huge}}
      for _,b in ipairs(j.blocks) do for _,a in ipairs({'x','y','z'}) do j.bounds.min[a]=math.min(j.bounds.min[a],b[a]); j.bounds.max[a]=math.max(j.bounds.max[a],b[a]) end end
      j.bounds.max.y=j.bounds.max.y+2
    end
    s.jobs[j.id]=j; persist(); return j
  end
  function self:ready(j)
    for _,dep in ipairs(j.dependencies) do if not s.jobs[dep] or s.jobs[dep].status~='completed' then return false end end
    return true
  end
  local resendCursor=0
  function self:assign(workers)
    local ordered={}; for _,j in pairs(s.jobs) do ordered[#ordered+1]=j end
    table.sort(ordered,function(a,b) return a.created<b.created or (a.created==b.created and a.id<b.id) end)
    local factoryPending=M.factoryPending(state)
    for _,j in ipairs(ordered) do
      local allowed=not (storageWorkers[j.type] and factoryPending)
      if j.type=='CRAFT' then allowed=M.factoryCanRun(state,j) end
      if allowed and j.status=='queued' and not j.workerId and j.requiredCapability and self:ready(j) and not j.paused then
        local conflict=false
        for _,other in ipairs(ordered) do if other.workerId and other.status~='completed' and intersects(j.bounds,other.bounds) then conflict=true end end
        if not conflict then
          local ids={}
          for wid,w in pairs(workers) do
            local t=w.telemetry
            if w.online and t and t.status=='idle' and not t.task and t.capabilities and t.capabilities[j.requiredCapability]
              and not M.workerBusy(state,w.id,j.id) then ids[#ids+1]=tonumber(wid) end
          end
          table.sort(ids)
          if ids[1] then j.workerId=ids[1]; j.status='assigned'; persist(); return j end
        end
      end
    end
    -- Existing storage workers must receive their original assignments so they
    -- can finish and release the barrier. Retransmissions never create owners.
    local pending={}
    for _,j in ipairs(ordered) do
      local w=j.workerId and workers[tostring(j.workerId)]; local t=w and w.telemetry
      if j.status=='assigned' and not j.paused and w and w.online and t and (not t.task or t.task==j.id)
        and not M.workerBusy(state,j.workerId,j.id) then pending[#pending+1]=j end
    end
    if #pending>0 then resendCursor=resendCursor%#pending+1; return pending[resendCursor] end
  end
  function self:progress(owner,p)
    local j=s.jobs[p.jobId]
    if not j or j.workerId~=owner then return false,'task owner mismatch' end
    if j.status=='completed' then return true end
    if (p.progress or 0)<j.progress then return false,'stale task progress' end
    j.progress=p.progress or 0; j.phase=p.phase; j.error=p.error; j.missingItem=p.missingItem
    j.missingCount=p.missingCount; j.supplyId=p.supplyId; j.report=U.copy(p.report)
    j.status=p.phase=='completed' and 'completed' or p.phase=='blocked' and 'blocked' or p.phase=='paused' and 'paused' or 'running'
    persist(); return true
  end
  function self:reserve(owner,jobId,from,target,workers)
    local j=s.jobs[jobId] or (state.jobs or {})[jobId]
    if not j or j.workerId~=owner or j.status=='completed' then return false,'reservation requires active task ownership' end
    if U.distance(from,target)>1 then return false,'reservation requires adjacent position' end
    local occupied=s.cells[key(target)]
    if occupied and occupied.owner~=owner then return false,'position reserved by worker '..occupied.owner end
    for _,w in pairs(workers or {}) do
      local p=w.telemetry and w.telemetry.position
      if w.id~=owner and p and p.known and key(p)==key(target) then return false,'worker occupies destination' end
    end
    s.cells[key(from)]={owner=owner,jobId=jobId}; s.cells[key(target)]={owner=owner,jobId=jobId}
    -- A fresh adjacent request confirms the worker's current position, also
    -- reconciling a lost previous movement-confirmation packet.
    for k,cell in pairs(s.cells) do if cell.owner==owner and k~=key(from) and k~=key(target) then s.cells[k]=nil end end
    persist(); return true
  end
  function self:recoverOwner(owner,p,workers)
    local j=s.jobs[p.jobId]; local w=workers[tostring(owner)]
    if not j or j.workerId or j.status~='queued' or not w or not w.online or w.telemetry.task~=j.id then return false,'no registered task ownership evidence' end
    if M.workerBusy(state,owner,j.id) then return false,'worker has conflicting ownership in another task' end
    for _,other in pairs(s.jobs) do
      if other.workerId and other.status~='completed' and (other.workerId==owner or intersects(j.bounds,other.bounds)) then return false,'conflicting recovered ownership' end
    end
    j.workerId=owner; j.status='assigned'; persist(); return true
  end
  function self:position(owner,jobId,from,target)
    local cell=s.cells[key(target)]
    if not cell or cell.owner~=owner then return false,'position was not reserved' end
    if key(from)~=key(target) then local old=s.cells[key(from)]; if old and old.owner==owner then s.cells[key(from)]=nil end end
    cell.jobId=jobId; persist(); return true
  end
  return self
end
return M
