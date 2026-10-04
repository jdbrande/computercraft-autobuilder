local U=require('autobuilder.core.util')
local Types=require('autobuilder.core.task_messages').types
local M={}
local caps={RESCUE='courier',CRAFT='crafting',BUILD='building',VERIFY='building',REPAIR='building',CLEAR='building',PREPARE_SITE='sitePreparation',SURVEY_SITE='siteSurveyV1',PREPARE_REGION='siteWorkV1',TRANSPORT='courier',HARVEST='logging',FARM='farming',REFUEL='telemetry',RETURN_HOME='telemetry'}
local function key(p) return p.x..','..p.y..','..p.z end
local function intersects(a,b)
  if not a or not b then return false end
  for _,axis in ipairs({'x','y','z'}) do if a.max[axis]+1<b.min[axis] or b.max[axis]+1<a.min[axis] then return false end end
  return true
end
-- Durable ownership is shared by the mining and generic queues. Heartbeats may
-- still say idle immediately after either queue has saved an assignment.
local storageWorkers={HARVEST=true,FARM=true,TRANSPORT=true,REFUEL=true}
local function factory(job) return job.type=='PROCESS' or job.type=='SMELT' or job.type=='CRAFT' end
function M.workerBusy(state,owner,exceptId)
  if require('autobuilder.core.chunks').holdsAnchor(state,owner) then return true end
  for _,job in pairs(state.jobs or {}) do
    if job.id~=exceptId and job.workerId==owner and job.status~='completed' and not job.physicalComplete then return true end
  end
  for _,job in pairs((state.automation or {}).jobs or {}) do
    if job.id~=exceptId and job.type=='RESCUE' and not job.rescueSettled
      and (job.preferredWorker==owner and job.status~='completed' or job.targetWorker==owner) then return true end
    if job.id~=exceptId and (job.workerId==owner or (job.managedFuel or job.returnManaged and job.returnReady or job.privateStation and job.factoryFlow or job.logistics and job.logisticsFlow) and job.preferredWorker==owner) and job.status~='completed' then return true end
  end
  return false
end
function M.logisticsActive(state)
  for _,job in pairs((state.automation or {}).jobs or {}) do
    if job.logistics and job.logisticsFlow and job.status~='completed' then return true end
  end
  return false
end
function M.returnActive(state)
  for _,job in pairs((state.automation or {}).jobs or {}) do
    if job.returning and job.returnReady and job.status~='completed' then return true end
  end
  return false
end
function M.factoryPending(state)
  if M.logisticsActive(state) or M.returnActive(state) then return true end
  for _,job in pairs((state.automation or {}).jobs or {}) do
    if factory(job) and (job.status~='completed' or job.production and job.production.intent) then return true end
  end
  return false
end
function M.factoryActive(state)
  for _,job in pairs((state.automation or {}).jobs or {}) do
    local p=job.production
    if factory(job) and (job.status~='completed' or p and p.intent)
      and (job.workerId or job.status=='running' or p and (p.machine or p.furnace or p.intent or (p.loaded or 0)>0 or (p.crafted or 0)>0)) then return true end
  end
  return false
end
function M.canOfferSupply(state,job)
  if not M.factoryPending(state) then return true end
  -- Drain seed/sapling requirements of an actor assigned before the factory was
  -- queued. The factory cannot take physical ownership until this actor finishes.
  return storageWorkers[job.type] and job.workerId~=nil and job.status~='completed' and not M.factoryActive(state)
end
function M.storageBusy(state,ignoreReturns)
  if not ignoreReturns and M.returnActive(state) then return true,'waiting for home cargo collection' end
  for _,job in pairs(state.jobs or {}) do
    if job.workerId and job.status~='completed' and not job.physicalComplete then return true,'waiting for active mining job '..job.id end
  end
  local automation=state.automation or {}
  for _,job in pairs(automation.jobs or {}) do
    if (storageWorkers[job.type] and job.workerId or job.logistics and job.logisticsFlow or job.type=='FUEL_STATION' and job.production) and job.status~='completed' then return true,'waiting for active storage job '..job.id end
  end
  if automation.supply then return true,'waiting for outstanding supply batch '..tostring(automation.supply.jobId) end
  return false
end
function M.factoryCanRun(state,job,preparing)
  if job.privateStation and not job.privateReady and not preparing then return false,'waiting for staged private crafting inputs' end
  if job.stockInputs and not (preparing and (job.privateStation or job.type=='PROCESS') and not (state.capacityLedger and state.capacityLedger.leases[job.id])) then
    local lease=state.inventoryLedger and state.inventoryLedger.leases[job.id]
    if not lease or lease.status~='held' then return false,job.stockError or 'waiting for durable ingredient reservation' end
  end
  local busy,why=M.storageBusy(state); if busy then return false,why end
  for _,other in pairs((state.automation or {}).jobs or {}) do
    if other.id~=job.id and factory(other) and other.status~='completed' then
      local p=other.production
      local active=other.workerId or other.status=='running' or p and (p.machine or p.furnace or p.intent or (p.loaded or 0)>0 or (p.crafted or 0)>0)
      local sameBank=job.type=='SMELT' and other.type=='SMELT' and job.productionRequest
        and job.productionRequest==other.productionRequest and job.productionOperation==other.productionOperation
      if active and not (job.type=='PROCESS' and other.type=='PROCESS') and not sameBank and not (job.privateStation and other.privateStation) then return false,'waiting for factory operation '..other.id end
    end
  end
  return true
end
function M.canDispatch(state,j)
  local allowed=not (storageWorkers[j.type] and M.factoryPending(state))
  if j.returnManaged then allowed=j.returnReady==true end
  if j.type=='RESCUE' then allowed=j.rescueReady==true and not M.factoryActive(state) end
  if j.logistics then allowed=j.logisticsReady==true and not M.factoryActive(state) end
  if j.managedFuel then allowed=j.fuelReady==true and not M.factoryActive(state) end
  if j.type=='CRAFT' then allowed=M.factoryCanRun(state,j) end
  return allowed
end
function M.poseCells(origin)
  if not U.position(origin) then return nil end
  local cells={{x=origin.x,y=origin.y,z=origin.z}}
  for _,d in ipairs({{-1,0},{1,0},{0,-1},{0,1}}) do
    local p={x=origin.x+d[1],y=origin.y,z=origin.z+d[2]}
    if not U.position(p) then return nil end;cells[#cells+1]=p
  end
  return cells
end
function M.new(state,save,clock,id,chunks,config)
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
    if (j.type=='FARM' or j.type=='HARVEST') and j.farm then j.requiredCapability=require('autobuilder.resources.renewables').capability(j.farm,j.type=='HARVEST') end
    if j.type=='PREPARE_REGION' then
      assert(require('autobuilder.build.site_work').validContract(j),'invalid preparation region contract')
      if j.siteAccess then j.requiredCapability='siteAccessV1' end
    end
    if require('autobuilder.build.blockstates').requiresModern(j.blocks,j.siteSurvey) then j.requiredCapability='placementV1' end
    if require('autobuilder.build.blockstates').requiresMetadata(j.blocks) then j.requiredCapability='metadataV1' end
    if j.blocks and #j.blocks>0 and j.type~='PREPARE_REGION' then
      j.bounds={min={x=math.huge,y=math.huge,z=math.huge},max={x=-math.huge,y=-math.huge,z=-math.huge}}
      for _,b in ipairs(j.blocks) do
        local plan=require('autobuilder.build.placement').plan(b)
        local footprint={b,plan and plan.pair};for _,cell in ipairs(plan and plan.neighbors or {}) do footprint[#footprint+1]=cell end
        for _,cell in ipairs(footprint) do for _,a in ipairs({'x','y','z'}) do j.bounds.min[a]=math.min(j.bounds.min[a],cell[a]);j.bounds.max[a]=math.max(j.bounds.max[a],cell[a]) end end
      end
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
    local Scaling=require('autobuilder.core.scaling')
    local function admit(j,w)
      local healthy,healthError=require('autobuilder.workers.health').eligible(w.telemetry,j)
      if not healthy then return false,healthError end
      local fueled,why=require('autobuilder.resources.fuel_budget').admit(config,j,w)
      if not fueled then return false,why end
      if config and config.scaling then return Scaling.canAssign(state,config,j,w,nil,clock(),workers) end
      return not M.workerBusy(state,w.id,j.id),'worker already owns work'
    end
    local ordered={}; for _,j in pairs(s.jobs) do ordered[#ordered+1]=j end
    local allocation=config and config.scaling and Scaling.snapshot(state,config,nil,clock(),workers)
    table.sort(ordered,function(a,b)
      if allocation then local pa,pb=Scaling.priority(allocation,a),Scaling.priority(allocation,b);if pa~=pb then return pa>pb end end
      return a.created<b.created or (a.created==b.created and a.id<b.id)
    end)
    for _,j in ipairs(ordered) do
      local allowed=M.canDispatch(state,j)
      if j.requiresSite and not j.workerId and j.status=='queued' then
        local prepared,why=false,'preparation verifier is unavailable'
        if self.preparationReady then prepared,why=self.preparationReady(j) end
        j.preparationError=why;allowed=allowed and prepared
      end
      if allowed and j.status=='queued' and not j.workerId and j.requiredCapability and self:ready(j) and not j.paused then
        local conflict=false
        for _,other in ipairs(ordered) do if other.workerId and other.status~='completed' and intersects(j.bounds,other.bounds) then conflict=true end end
        if not conflict then
          local ids={}
          for wid,w in pairs(workers) do
            local t=w.telemetry
            if w.online and t and t.status=='idle' and not t.task and t.capabilities and t.capabilities[j.requiredCapability]
              and (not j.privateStation or t.capabilities.isolatedCraftingV1)
              and (not j.logistics or t.capabilities.logisticsV1)
              and (not j.returnManaged or t.capabilities.returnCargoV1)
              and (not j.preferredWorker or j.preferredWorker==w.id)
              and not M.workerBusy(state,w.id,j.id) then ids[#ids+1]=tonumber(wid) end
          end
          table.sort(ids,function(a,b)
            local pa,pb=Scaling.preference(state,config,j,workers[tostring(a)]),Scaling.preference(state,config,j,workers[tostring(b)])
            return pa<pb or pa==pb and a<b
          end)
          for _,wid in ipairs(ids) do
            local lease,why
            local admission,reason=require('autobuilder.core.protection').canOwn(state,j,wid)
            if admission then admission,reason=admit(j,workers[tostring(wid)]) end
            if not admission then why=reason
            elseif chunks then lease,why=chunks:reserve(j,workers[tostring(wid)],true,self.preparationReady,admit,clock()) else lease={status='disabled'} end
            j.coverageError=why
            if lease then
              if lease.status~='disabled' then return j end
              admission,reason=require('autobuilder.core.protection').canOwn(state,j,wid)
              if admission and j.requiresSite then
                admission,reason=false,'preparation verifier is unavailable'
                if self.preparationReady then admission,reason=self.preparationReady(j) end
              end
              if admission then admission,reason=admit(j,workers[tostring(wid)]) end
              if admission then
                local before={workerId=j.workerId,status=j.status,assignedAt=j.assignedAt}
                j.workerId=wid;j.status='assigned';j.assignedAt=clock()
                local ok,err=pcall(persist)
                if not ok then j.workerId=before.workerId;j.status=before.status;j.assignedAt=before.assignedAt;error(err,0) end
                return j
              end
              j.coverageError=reason
            end
          end
        end
      end
    end
    -- Existing storage workers must receive their original assignments so they
    -- can finish and release the barrier. Retransmissions never create owners.
    local pending={}
    for _,j in ipairs(ordered) do
      local w=j.workerId and workers[tostring(j.workerId)]; local t=w and w.telemetry
      if j.status=='assigned' and not j.paused and w and w.online and t and (not t.task or t.task==j.id)
        and not M.workerBusy(state,j.workerId,j.id) then
          local lease,why=true
          if chunks then lease,why=chunks:reserve(j,w) end
          j.coverageError=why;if lease then pending[#pending+1]=j end
        end
    end
    if #pending>0 then resendCursor=resendCursor%#pending+1; return pending[resendCursor] end
  end
  function self:progress(owner,p)
    local j=s.jobs[p.jobId]
    if not j or j.workerId~=owner then return false,'task owner mismatch' end
    if j.status=='completed' or j.workerFinished then return true end
    local materials=p.report and p.report.materials
    if materials~=nil then
      local R=require('autobuilder.core.reports')
      if not R.validMaterials(materials) or not j.blocks then return false,'invalid material progress' end
      local limits,total={},0
      for _,b in ipairs(j.blocks) do local item=R.materialItem(b);if item then limits[item]=(limits[item] or 0)+1 end end
      for item,n in pairs(materials) do
        if n>(limits[item] or 0) then return false,'material progress exceeds task blocks' end;total=total+n
      end
      if total>(p.progress or 0) then return false,'material progress exceeds correct positions' end
      for item,n in pairs(j.materials or {}) do if (materials[item] or 0)<n then return false,'material progress regressed' end end
    end
    if j.type=='PREPARE_REGION' and not require('autobuilder.build.site_work').validProgress(j,p) then return false,'preparation receipt differs from inspected work' end
    if j.type=='SURVEY_SITE' then
      local r=p.siteReport
      if not require('autobuilder.build.site_survey').validReport(j,r,p.phase=='completed')
        or #r.observations~=(p.progress or 0) then return false,'site survey receipt differs from contract' end
      for i,old in ipairs(j.siteReport and j.siteReport.observations or {}) do
        if not require('autobuilder.factory.factory').equal(old,r.observations[i]) then return false,'site observation changed or regressed' end
      end
    end
    if j.returning then
      local r=p.homeReceipt;local old=j.homeReceipt
      if not require('autobuilder.storage.returns').validReceipt(r) then return false,'home deposit receipt required' end
      local total=0
      for item,n in pairs(r.deposited) do
        if n>(j.returning.items[item] or 0) then return false,'home deposit exceeds cargo contract' end;total=total+n
      end
      if total~=(p.progress or 0) then return false,'home progress differs from deposited cargo' end
      if p.phase=='completed' and not require('autobuilder.factory.factory').equal(r.deposited,j.returning.items) then return false,'home completion lacks exact cargo receipt' end
      if old then
        if r.sequence<old.sequence then return false,'stale home deposit receipt' end
        if r.sequence==old.sequence and not require('autobuilder.factory.factory').equal(r,old) then return false,'changed duplicate home deposit receipt' end
        for item,n in pairs(old.deposited) do if (r.deposited[item] or 0)<n then return false,'home deposit regressed' end end
      end
    end
    if j.logistics then
      local r=p.transportReceipt;local old=j.transportReceipt
      if type(r)~='table' or not U.integer(r.sequence) or r.sequence<0
        or not U.integer(r.pickedUp) or r.pickedUp<0 or r.pickedUp>j.quantity
        or not U.integer(r.delivered) or r.delivered<0 or r.delivered>r.pickedUp then return false,'invalid transport receipt' end
      if p.phase=='completed' and (r.pickedUp~=j.quantity or r.delivered~=j.quantity) then return false,'transport completion lacks exact receipt' end
      if old then
        if r.sequence<old.sequence then return false,'stale transport receipt' end
        if r.sequence==old.sequence and not require('autobuilder.factory.factory').equal(old,r) then return false,'changed duplicate transport receipt' end
        if r.pickedUp<old.pickedUp or r.delivered<old.delivered then return false,'regressed transport receipt' end
      end
      if (p.progress or 0)~=r.delivered then return false,'transport progress disagrees with delivery' end
    end
    if (p.progress or 0)<j.progress then return false,'stale task progress' end
    if j.type=='RESCUE' and p.fuelDelivered~=nil and (p.fuelDelivered<(j.fuelDelivered or 0) or p.fuelDelivered>j.quantity) then return false,'invalid rescue delivery counter' end
    if j.type=='SURVEY_SITE' then j.siteReport=U.copy(p.siteReport) end
    if j.returning then j.homeReceipt=U.copy(p.homeReceipt) end
    if j.logistics then j.transportReceipt=U.copy(p.transportReceipt) end
    if materials then j.materials=U.copy(materials) end
    j.progress=p.progress or 0; j.phase=p.phase; j.error=p.error; j.missingItem=p.missingItem
    if j.type=='RESCUE' and p.fuelDelivered~=nil then j.fuelDelivered=p.fuelDelivered end
    j.missingCount=p.missingCount; j.supplyId=p.supplyId; j.report=U.copy(p.report)
    j.status=p.phase=='completed' and 'completed' or p.phase=='blocked' and 'blocked' or p.phase=='paused' and 'paused' or 'running'
    if (j.privateStation or j.logistics or j.returning) and p.phase=='completed' then j.workerFinished=true; j.status='collecting' end
    persist(); return true
  end
  function self:reserve(owner,jobId,from,target,workers,work)
    if state.assignmentRecovery then return false,'controller backup ownership reconciliation pending' end
    local j=s.jobs[jobId] or (state.jobs or {})[jobId]
    if not j or j.workerId~=owner or j.status=='completed' then return false,'reservation requires active task ownership' end
    if j.poseRecovery and j.poseRecovery.status=='held' then return false,'pose recovery owns movement cells' end
    local targets={target}
    if work then
      if not config or not ({BUILD=true,REPAIR=true,CLEAR=true,PREPARE_REGION=true,PREPARE_SITE=true,MINE=true,FARM=true,HARVEST=true})[j.type]
        or j.siteWork and j.siteWork.stage=='verify' then return false,'task cannot reserve physical changes' end
      if j.type~='MINE' and j.type~='FARM' and j.type~='HARVEST' and j.type~='PREPARE_SITE' then
        local planned;for _,b in ipairs(j.blocks or {}) do if U.distance(b,target)==0 then planned=b;break end end
        if not planned then return false,'mutation target is not in the immutable task' end
        local placement=require('autobuilder.build.placement').plan(planned)
        if placement and placement.pair and not placement.observeOnly then targets[#targets+1]=placement.pair end
      end
    else
      for id,other in pairs(s.jobs) do
        if id~=jobId and other.workerId~=owner and other.workerId and other.status~='completed'
          and (other.siteSurvey or other.siteWork or other.type=='PREPARE_SITE') and other.bounds
          and (not other.clearanceY or target.y<other.clearanceY)
          and require('autobuilder.core.pathfinding').inside(target,other.bounds) then return false,'active preparation region owned by '..id end
      end
    end
    if chunks then for _,p in ipairs(targets) do local ok,why=chunks:allows(j,from,p);if not ok then return false,why end end end
    if U.distance(from,target)>1 then return false,'reservation requires adjacent position' end
    local reservations={}
    for _,destination in ipairs(targets) do
      if work then
        local ok,why=require('autobuilder.core.protection').canModify(state,config,j,destination);if not ok then return false,why end
        -- Keep neighboring turtles out for the entire physical action, including
        -- a movement grant arriving after this mutation grant was checkpointed.
        for _,dy in ipairs({-1,1}) do reservations[#reservations+1]={x=destination.x,y=destination.y+dy,z=destination.z} end
      end
      reservations[#reservations+1]=destination
    end
    for _,destination in ipairs(reservations) do
      local occupied=s.cells[key(destination)]
      if occupied and occupied.owner~=owner then return false,'position reserved by worker '..occupied.owner,occupied.owner end
      for _,w in pairs(workers or {}) do
        local p=w.telemetry and w.telemetry.position
        if w.id~=owner and p and p.known and key(p)==key(destination) then return false,'worker occupies destination',w.id end
      end
    end
    local before=U.copy(s.cells)
    local keep={[key(from)]=true};s.cells[key(from)]={owner=owner,jobId=jobId}
    for _,p in ipairs(reservations) do keep[key(p)]=true;s.cells[key(p)]={owner=owner,jobId=jobId} end
    -- A fresh adjacent request confirms the worker's current position, also
    -- reconciling a lost previous movement-confirmation packet.
    for k,cell in pairs(s.cells) do if cell.owner==owner and not keep[k] then s.cells[k]=nil end end
    local ok,why=pcall(persist);if not ok then s.cells=before;error(why,0) end
    return true
  end
  local function poseCommit(j,change)
    local prior,cells=U.copy(j.poseRecovery),U.copy(s.cells)
    change();local ok,why=pcall(persist)
    if not ok then j.poseRecovery=prior;s.cells=cells;error(why,0) end
  end
  function self:reservePose(owner,jobId,sequence,origin,workers,restoring)
    if state.assignmentRecovery and not restoring then return false,'controller backup ownership reconciliation pending' end
    local j=s.jobs[jobId] or (state.jobs or {})[jobId]
    local cells=M.poseCells(origin)
    if not config or not cells or not U.integer(sequence) or sequence<1 or sequence>9007199254740991 then return false,'invalid pose reservation' end
    if not j or j.workerId~=owner or j.status=='completed' or j.paused and not restoring then return false,'pose recovery requires active unpaused ownership' end
    local old=j.poseRecovery
    if old and (sequence<old.sequence or sequence==old.sequence and (old.status~='held' or U.distance(old.origin,origin)~=0)
      or sequence~=old.sequence and old.status=='held') then return false,'changed or stale pose reservation' end
    local boxes=U.copy(config.restrictedAreas or {})
    for _,box in ipairs(require('autobuilder.storage.nodes').protected(config,state)) do boxes[#boxes+1]=box end
    local E=require('autobuilder.resources.exploration')
    local function conflicts(other,p)
      if other.workerId and other.workerId~=owner and other.status~='completed' and not other.physicalComplete then
        local g=other.exploration
        local box=g and g.bounds or other.miningArea or other.bounds
        if box and E.protected(p,{box}) then return true end
        if g then for _,route in ipairs({g.route or {},g.exitRoute or {}}) do
          for _,q in ipairs(route) do if U.distance(p,q)==0 then return true end end
        end end
      end
    end
    for i,p in ipairs(cells) do
      if chunks then local ok,why=chunks:allows(j,origin,p);if not ok then return false,why end end
      if i>1 and (E.protected(p,boxes) or j.exploration and E.protected(p,j.exploration.protectedAreas)) then return false,'pose probe enters protected area' end
      local cell=s.cells[key(p)]
      if cell and cell.owner~=owner then return false,'pose probe cell owned by '..cell.owner end
      for _,w in pairs(workers or {}) do
        local at=w.telemetry and w.telemetry.position
        if w.id~=owner and at and at.known and U.position(at) and U.distance(at,p)==0 then return false,'worker occupies pose probe cell' end
      end
      for _,jobs in ipairs({s.jobs,state.jobs or {}}) do
        for _,other in pairs(jobs) do if conflicts(other,p) then return false,'pose probe enters another task region' end end
      end
    end
    if old and old.sequence==sequence then return true end
    poseCommit(j,function()
      j.poseRecovery={sequence=sequence,origin=U.copy(origin),status='held'}
      for _,p in ipairs(cells) do s.cells[key(p)]={owner=owner,jobId=jobId} end
    end)
    return true
  end
  function self:finishPose(owner,jobId,sequence,origin)
    local j=s.jobs[jobId] or (state.jobs or {})[jobId];local r=j and j.poseRecovery
    if not j or j.workerId~=owner or not r or r.sequence~=sequence or not U.position(origin)
      or U.distance(origin,r.origin)~=0 then return false,'pose receipt does not match owned origin' end
    if r.status=='settled' then return true end
    poseCommit(j,function()
      r.status='settled'
      for k,cell in pairs(s.cells) do if cell.owner==owner and k~=key(origin) then s.cells[k]=nil end end
      s.cells[key(origin)]={owner=owner,jobId=jobId}
    end)
    return true
  end
  function self:recoverOwner(owner,p,workers)
    local j=s.jobs[p.jobId]; local w=workers[tostring(owner)]
    if not j or j.workerId or j.status~='queued' or not w or not w.online or w.telemetry.task~=j.id
      or j.preferredWorker and j.preferredWorker~=owner then return false,'no registered task ownership evidence' end
    if M.workerBusy(state,owner,j.id) then return false,'worker has conflicting ownership in another task' end
    for _,other in pairs(s.jobs) do
      if other.workerId and other.status~='completed' and (other.workerId==owner or intersects(j.bounds,other.bounds)) then return false,'conflicting recovered ownership' end
    end
    j.workerId=owner; j.status='assigned'; persist(); return true
  end
  function self:position(owner,jobId,from,target)
    local j=s.jobs[jobId] or (state.jobs or {})[jobId]
    if j and j.poseRecovery and j.poseRecovery.status=='held' then return false,'pose recovery owns movement cells' end
    local cell=s.cells[key(target)]
    if not cell or cell.owner~=owner then return false,'position was not reserved' end
    if key(from)~=key(target) then local old=s.cells[key(from)]; if old and old.owner==owner then s.cells[key(from)]=nil end end
    cell.jobId=jobId; persist(); return true
  end
  return self
end
return M
