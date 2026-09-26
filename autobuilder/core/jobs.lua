local U=require('autobuilder.core.util')
local Materials=require('autobuilder.resources.materials')
local Coordination=require('autobuilder.core.workflows')
local M={}
function M.new(state,save,clock,controllerId)
  state.jobs=state.jobs or {}; state.jobSequence=state.jobSequence or 0
  local self={state=state}
  local function persist() local ok,err=save(); assert(ok,err) end
  local function create(item,quantity,stock,parent)
    state.jobSequence=state.jobSequence+1
    local id='mine:'..controllerId..':'..math.floor(clock()*1000)..':'..state.jobSequence
    local job={id=id,type='MINE',item=item,target=quantity,quantity=math.max(0,quantity-stock),priority=1,
      status=stock>=quantity and 'completed' or 'queued',requiredCapabilities={mining=true},dependencies={},
      progress={delivered=0,held=0},retryCount=0,created=clock(),parent=parent and parent.id,
      depth=parent and ((parent.depth or 0)+1) or 0,paused=parent and parent.paused or nil}
    state.jobs[id]=job; return job
  end
  local function finish(j)
    j.status='completed'; j.error=nil
    if j.parent then
      local parent=state.jobs[j.parent]
      parent.progress.delivered=parent.progress.delivered+j.progress.delivered
      finish(parent)
    end
  end
  local function supplement(j,stock)
    if j.childId then return end
    if (j.depth or 0)>=3 then j.error='storage shortfall persists after 3 supplements; use replan <jobId>'; return end
    local child=create(j.item,j.target,stock,j)
    j.childId=child.id; j.quantity=j.quantity+child.quantity
    j.error='storage shortfall; queued '..child.id
  end
  function self:submit(item,quantity,stock)
    if not Materials.get(item) or not U.integer(quantity) or quantity<1 or quantity>1000000 then return nil,'unsupported material or invalid quantity (1..1000000)' end
    if not U.integer(stock) or stock<0 then return nil,'live storage count required' end
    for _,j in pairs(state.jobs) do if j.item==item and j.status~='completed' then return nil,'an unfinished job already requests '..item end end
    local j=create(item,quantity,stock); persist(); return j
  end
  local resendCursor=0
  local function physical(job)
    return job.workerId and job.status~='completed' and not job.physicalComplete
  end
  local function miningArea(telemetry)
    local area=telemetry and telemetry.miningArea
    if area==nil then return nil end -- Legacy telemetry owns an exclusive unknown area.
    if type(area)~='table' or not U.position(area.min) or not U.position(area.max) then return false end
    for _,axis in ipairs({'x','y','z'}) do
      if area.min[axis]>area.max[axis] or area.max[axis]-area.min[axis]>256 then return false end
    end
    return area
  end
  local function overlaps(a,b)
    if not a or not b then return true end
    for _,axis in ipairs({'x','y','z'}) do
      if a.max[axis]<b.min[axis] or b.max[axis]<a.min[axis] then return false end
    end
    return true
  end
  local function conflict(owner,area)
    if Coordination.workerBusy(state,owner) then return true,'worker already owns an active task' end
    for _,job in pairs(state.jobs) do
      if physical(job) then
        if job.workerId==owner then return true,'worker already owns an active physical job' end
        if overlaps(area,job.miningArea) then return true,'mining area overlaps an active physical job' end
      end
    end
    return false
  end
  local function order(a,b)
    if a.priority~=b.priority then return a.priority>b.priority end
    return a.id<b.id
  end
  function self:assign(workers,counts)
    local candidates={}
    for _,w in pairs(workers) do
      local t=w.telemetry
      if w.online and t and t.capabilities and t.capabilities.mining and not t.task and t.status=='idle'
        and U.integer(w.id) and miningArea(t)~=false then candidates[#candidates+1]=w end
    end
    table.sort(candidates,function(a,b) return a.id<b.id end)
    local queued={}
    for _,job in pairs(state.jobs) do
      if job.status=='queued' and not job.paused and not job.workerId and not Coordination.factoryPending(state) then
        local ready=true
        for _,dep in ipairs(job.dependencies) do if not state.jobs[dep] or state.jobs[dep].status~='completed' then ready=false end end
        if ready then queued[#queued+1]=job end
      end
    end
    table.sort(queued,order)
    for _,job in ipairs(queued) do
      local owner,area,resources
      for _,w in ipairs(candidates) do
        local bounds=miningArea(w.telemetry)
        if Materials.accepts(w.telemetry.miningResources,job.item) and not conflict(w.id,bounds) then
          owner=w.id; area=bounds; resources=w.telemetry.miningResources; break
        end
      end
      if owner then
        if counts then job.quantity=math.max(0,job.target-(counts[job.item] or 0)) end
        if job.quantity==0 then finish(job); persist()
        else
          job.workerId=owner; job.miningArea=U.copy(area); job.miningResources=U.copy(resources); job.status='assigned'
          -- Historic miningWorkerId pins are intentionally not used: each durable
          -- active job now owns its area. Unknown legacy areas remain exclusive.
          persist(); return job
        end
      end
    end
    -- Retransmit only assignments which still need their first progress report.
    -- A running or disconnected owner keeps its lease without starving new work.
    local pending={}
    for _,job in pairs(state.jobs) do
      local w=job.workerId and workers[tostring(job.workerId)]
      local t=w and w.telemetry
      if job.status=='assigned' and not job.physicalComplete and w and w.online and t
        and t.capabilities and t.capabilities.mining and (not t.task or t.task==job.id)
        and not Coordination.workerBusy(state,job.workerId,job.id) then pending[#pending+1]=job end
    end
    table.sort(pending,order)
    if #pending>0 then resendCursor=resendCursor%#pending+1; return pending[resendCursor] end
    return nil
  end
  function self:recoverOwner(workerId,p,workers)
    local j=state.jobs[p.jobId]; local w=workers[tostring(workerId)]; local t=w and w.telemetry
    if not j or j.status~='queued' or j.workerId or not w or not w.online or not t
      or t.task~=j.id or not t.capabilities or not t.capabilities.mining then return false,'ownership recovery lacks a matching registered task' end
    if not U.integer(p.assignedQuantity) or p.assignedQuantity<1 or p.assignedQuantity>j.target then return false,'ownership recovery requires original assigned quantity' end
    if not Materials.accepts(t.miningResources,j.item) then return false,'ownership recovery has incompatible mining resources' end
    local area=miningArea(t); if area==false then return false,'ownership recovery has invalid mining bounds' end
    local blocked,why=conflict(workerId,area); if blocked then return false,why end
    j.workerId=workerId; j.miningArea=U.copy(area); j.miningResources=U.copy(t.miningResources); j.quantity=p.assignedQuantity; j.status='assigned'
    persist(); return true
  end
  function self:progress(workerId,p,stock)
    local j=state.jobs[p.jobId]
    if not j or j.workerId~=workerId then return false,'job owner mismatch' end
    if j.status=='completed' or j.physicalComplete then return true end
    if p.delivered<j.progress.delivered then return false,'stale progress' end
    j.progress={delivered=p.delivered,held=p.held,phase=p.phase}
    if p.phase=='completed' then
      if p.delivered<j.quantity then return false,'worker completed without its assigned quantity' end
      if stock then
        j.physicalComplete=true
        if stock>=j.target then finish(j)
        else j.status='blocked'; supplement(j,stock) end
      else j.status='blocked'; j.error='waiting for live storage to confirm requested stock' end
    elseif p.phase=='blocked' then j.status='blocked'; j.error=p.error or 'worker blocked'
    else j.status='running'; j.error=nil end
    persist(); return true
  end
  function self:replan(id,stock)
    local j=state.jobs[id]
    if not j or j.status~='blocked' or not j.physicalComplete or j.childId then return false,'replan requires a finished physical job with no active supplement' end
    if not U.integer(stock) or stock<0 then return false,'live stock required' end
    if stock>=j.target then finish(j) else j.depth=0; supplement(j,stock) end
    persist(); return true
  end
  return self
end
return M
