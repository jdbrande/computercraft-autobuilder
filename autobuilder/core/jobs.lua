local U=require('autobuilder.core.util')
local Materials=require('autobuilder.resources.materials')
local Coordination=require('autobuilder.core.workflows')
local E=require('autobuilder.resources.exploration')
local M={}
function M.new(state,save,clock,controllerId,config,chunks)
  state.jobs=state.jobs or {}; state.jobSequence=state.jobSequence or 0
  local self={state=state}
  local function persist() local ok,err=save(); assert(ok,err) end
  local function create(item,quantity,stock,parent,consumer)
    state.jobSequence=state.jobSequence+1
    local id='mine:'..controllerId..':'..math.floor(clock()*1000)..':'..state.jobSequence
    local job={id=id,type='MINE',item=item,target=quantity,quantity=math.max(0,quantity-stock),priority=1,
      status=stock>=quantity and 'completed' or 'queued',requiredCapabilities={mining=true},dependencies={},
      progress={delivered=0,held=0},retryCount=0,created=clock(),parent=parent and parent.id,
      depth=parent and ((parent.depth or 0)+1) or 0,paused=parent and parent.paused or nil,consumer=parent and parent.consumer or consumer}
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
  function self:submit(item,quantity,stock,consumer)
    if not Materials.get(item) or not U.integer(quantity) or quantity<1 or quantity>1000000 then return nil,'unsupported material or invalid quantity (1..1000000)' end
    if not U.integer(stock) or stock<0 then return nil,'live storage count required' end
    if consumer~=nil and not U.shortString(consumer,160) then return nil,'invalid production consumer' end
    for _,j in pairs(state.jobs) do if j.item==item and j.status~='completed' then return nil,'an unfinished job already requests '..item end end
    local j=create(item,quantity,stock,nil,consumer); persist(); return j
  end
  state.exploration=state.exploration or {schema=1,sectors={},groups={},sequence=0}
  local exploration=state.exploration
  function self:requestAcquisition(item,target,stock,key)
    if not Materials.get(item) or not U.integer(target) or target<1 or target>1000000 or not U.integer(stock) or stock<0 then return nil,'invalid acquisition demand' end
    for _,g in pairs(exploration.groups) do
      if g.key==key and g.status~='completed' then return g end
    end
    exploration.sequence=(exploration.sequence or 0)+1
    local id='acquire:'..controllerId..':'..exploration.sequence
    local g={id=id,key=key,provider='exploration',item=item,target=target,tripIds={},status=stock>=target and 'completed' or 'running'}
    exploration.groups[id]=g
    local ok,err=save(); if not ok then exploration.groups[id]=nil; error(err) end
    return g
  end
  function self:setAcquisitionPaused(id,paused)
    local g=exploration.groups[id]; if not g then return false,'unknown acquisition' end
    g.paused=paused; persist(); return true
  end
  function self:refreshAcquisition(id,stock)
    local g=assert(exploration.groups[id]); local active=false
    for _,jid in ipairs(g.tripIds) do local j=state.jobs[jid]; if j and not j.physicalComplete then active=true end end
    if stock>=g.target and not active then g.status='completed'; g.error=nil
    elseif g.status=='completed' then g.status='running'; g.error=nil end
    return g
  end
  local function admission(job,w,workers,counts)
    local t=w.telemetry
    if not w.online or not t or not (t.capabilities or {}).mining or job.item and not Materials.accepts(t.miningResources,job.item) then
      return false,'mining worker capability or resources changed'
    end
    if config and config.scaling then return require('autobuilder.core.scaling').canAssign(state,config,job,w,counts,clock(),workers) end
    return not Coordination.workerBusy(state,w.id,job.id),'worker already owns work'
  end
  local planning={}
  local function assignExploration(workers,counts)
    if not config or not (config.exploration or {}).enabled or exploration.paused or Coordination.factoryPending(state) or not counts then return end
    local attempts=0
    local groups={}; for _,g in pairs(exploration.groups) do if not g.paused and g.status~='completed' then groups[#groups+1]=g end end
    table.sort(groups,function(a,b) return a.id<b.id end)
    local ids={}; for _,w in pairs(workers) do ids[#ids+1]=w.id end; table.sort(ids)
    for _,g in ipairs(groups) do
      self:refreshAcquisition(g.id,counts[g.item] or 0)
      local outstanding=0
      for _,id in ipairs(g.tripIds) do local j=state.jobs[id]; if j and not j.physicalComplete then outstanding=outstanding+math.max(0,j.quantity-j.progress.delivered) end end
      local remaining=g.target-(counts[g.item] or 0)-outstanding
      if remaining>0 then
        local eligible=0
        for _,w in pairs(workers) do local t=w.telemetry
          if w.online and t and t.capabilities and t.capabilities.explorationV1 and E.home(t.explorationHome)
            and Materials.accepts(t.miningResources,g.item) and t.status=='idle' and not t.task and not Coordination.workerBusy(state,w.id) then eligible=eligible+1 end
        end
        if config.scaling then
          local allocation=require('autobuilder.core.scaling').snapshot(state,config,counts,clock(),workers).mining
          eligible=math.min(eligible,math.max(0,allocation.desired-allocation.active))
          if eligible==0 then g.error='mining allocation '..allocation.active..'/'..allocation.desired;return end
        end
        local cursor=planning[g.id] or {worker=1,sector=1}
        local reason=cursor.reason or 'No online exploration-capable worker'; local waiting=cursor.waiting or false
        for wi=cursor.worker,#ids do
          local wid=ids[wi]
          local w=workers[tostring(wid)]; local t=w.telemetry; local home=t and t.explorationHome
          if w.online and t and t.capabilities and t.capabilities.explorationV1 and E.home(home) and Materials.accepts(t.miningResources,g.item) then
            if t.fuel~='unlimited' and t.fuel<2*#home.exitRoute+config.minimumFuelReserve+config.mining.returnMargin+2 then
              reason='insufficient round-trip fuel for worker '..wid
            elseif t.status=='idle' and not t.task and not Coordination.workerBusy(state,wid) and admission({type='MINE'},w,workers,counts) then
              local choices=E.candidates(exploration.sectors,config.exploration,g.item,home.exitRoute[#home.exitRoute] or home.depot)
              reason='Search envelope exhausted for '..g.item
              local areas={}
              for _,b in ipairs(require('autobuilder.core.protection').areas(state,config)) do
                if E.overlaps(b,config.exploration.bounds) then areas[#areas+1]=b end
              end
              for _,b in ipairs(home.protectedAreas) do
                if E.overlaps(b,config.exploration.bounds) then areas[#areas+1]=b end
              end
              for ci=cursor.sector,#choices do
                if attempts>=4 then
                  planning[g.id]={worker=wi,sector=ci,reason=reason,waiting=waiting}
                  g.status='running'; g.error='Planning reachable search sectors'; return
                end
                attempts=attempts+1; local sector=choices[ci]
                local geometry,why=E.plan(sector,{config=config,depot=home.depot,exitRoute=home.exitRoute,protectedAreas=areas,activeJobs=state.jobs,availableFuel=t.fuel})
                if geometry then
                  local j=create(g.item,math.min(64,math.ceil(remaining/math.max(1,eligible))),0); geometry.groupId=g.id
                  j.exploration=geometry; j.miningArea=U.copy(geometry.bounds); j.miningResources=U.copy(t.miningResources or {})
                  g.tripIds[#g.tripIds+1]=j.id
                  local oldStatus,oldError=g.status,g.error;g.status='running';g.error=nil
                  local ok,lease,err=pcall(function()
                    if chunks then return chunks:reserve(j,w,true,nil,function(job,worker) return admission(job,worker,workers,counts) end,clock()) end
                    return {status='disabled'}
                  end)
                  if ok and lease and lease.status=='disabled' then
                    local allowed,why=admission(j,w,workers,counts);if not allowed then lease=nil;err=why end
                  end
                  if not ok or not lease then
                    state.jobs[j.id]=nil;table.remove(g.tripIds);g.status=oldStatus;g.error=oldError
                    if not ok then error(lease) end
                    why=err
                  else
                    planning[g.id]=nil;g.status='running';g.error=nil
                    if lease.status=='disabled' then
                      j.workerId=wid;j.status='assigned';j.assignedAt=clock()
                      local saved,why=pcall(persist)
                      if not saved then state.jobs[j.id]=nil;table.remove(g.tripIds);g.status=oldStatus;g.error=oldError;error(why) end
                    end
                    return j
                  end
                end
                reason=why; if why and why:find('owned') then waiting=true end
              end
            else waiting=true end
          end
          cursor.sector=1
        end
        planning[g.id]=nil
        g.status=waiting and 'running' or 'blocked'; g.error=reason
      end
    end
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
    local trip=assignExploration(workers,counts); if trip then return trip end
    local candidates={}
    for _,w in pairs(workers) do
      local t=w.telemetry
      if w.online and t and t.capabilities and t.capabilities.mining and not t.task and t.status=='idle'
        and U.integer(w.id) and miningArea(t)~=false then candidates[#candidates+1]=w end
    end
    table.sort(candidates,function(a,b)
      local Scaling=require('autobuilder.core.scaling');local pa,pb=Scaling.preference(state,config,{type='MINE'},a),Scaling.preference(state,config,{type='MINE'},b)
      return pa<pb or pa==pb and a.id<b.id
    end)
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
      if counts then job.quantity=math.max(0,job.target-(counts[job.item] or 0)) end
      if job.quantity==0 then finish(job);persist()
      else
        for _,w in ipairs(candidates) do
          local bounds=miningArea(w.telemetry)
          if not w.telemetry.capabilities.explorationV1 and Materials.accepts(w.telemetry.miningResources,job.item) and not conflict(w.id,bounds) and admission(job,w,workers,counts) then
            local oldArea,oldResources=job.miningArea,job.miningResources
            job.miningArea=U.copy(bounds);job.miningResources=U.copy(w.telemetry.miningResources)
            local ok,lease,why=pcall(function()
              if chunks then return chunks:reserve(job,w,true,nil,function(j,worker) return admission(j,worker,workers,counts) end,clock()) end
              return {status='disabled'}
            end)
            if ok and lease and lease.status=='disabled' then
              local allowed,reason=admission(job,w,workers,counts);if not allowed then lease=nil;why=reason end
            end
            if not ok or not lease then
              job.miningArea=oldArea;job.miningResources=oldResources
              if not ok then error(lease) end
              job.coverageError=why
            else
              job.coverageError=nil
              if lease.status=='disabled' then
                local oldStatus,oldTime=job.status,job.assignedAt
                job.workerId=w.id;job.status='assigned';job.assignedAt=clock()
                local saved,err=pcall(persist)
                if not saved then
                  job.workerId=nil;job.status=oldStatus;job.assignedAt=oldTime;job.miningArea=oldArea;job.miningResources=oldResources;error(err,0)
                end
              end
              return job
            end
          end
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
        and not Coordination.workerBusy(state,job.workerId,job.id) then
          local lease,why=true
          if chunks then lease,why=chunks:reserve(job,w) end
          job.coverageError=why;if lease then pending[#pending+1]=job end
        end
    end
    table.sort(pending,order)
    if #pending>0 then resendCursor=resendCursor%#pending+1; return pending[resendCursor] end
    return nil
  end
  function self:recoverOwner(workerId,p,workers)
    local j=state.jobs[p.jobId]; local w=workers[tostring(workerId)]; local t=w and w.telemetry
    if not j or j.exploration or j.status~='queued' or j.workerId or not w or not w.online or not t
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
    if j.exploration then
      if not E.report(p.exploration) or p.exploration.cursor>193 or p.delivered<0 then return false,'invalid exploration result' end
      if p.phase=='completed' and (not p.exploration.result or p.held~=0 or stock==nil) then return false,'exploration completion needs unloaded inventory and live stock' end
      if p.phase=='completed' then
        assert(E.record(exploration.sectors,j,p.exploration)); j.physicalComplete=true; j.status='completed'; j.error=nil
      elseif p.phase=='blocked' then j.status='blocked'; j.error=p.error
      else j.status='running' end
      j.progress={delivered=p.delivered,held=p.held,phase=p.phase,exploration=E.cleanReport(p.exploration)}
      if j.physicalComplete then j.physicalCompletedAt=j.physicalCompletedAt or clock() end
      self:refreshAcquisition(j.exploration.groupId,stock or 0); persist(); return true
    end
    j.progress={delivered=p.delivered,held=p.held,phase=p.phase}
    if p.phase=='completed' then
      if p.delivered<j.quantity then return false,'worker completed without its assigned quantity' end
      if stock then
        j.physicalComplete=true
        local request=j.consumer and ((state.automation or {}).requests or {})[j.consumer]
        local root=j
        for _=1,4 do if not root.parent then break end;root=state.jobs[root.parent] or root end
        local acquired=request and request.acquired==true and not root.parent and (request.mines or {})[j.item]==root.id
          and U.integer((request.targets or {})[j.item]) and request.targets[j.item]>=root.target
        if stock>=j.target or acquired then finish(j)
        else j.status='blocked'; supplement(j,stock) end
      else j.status='blocked'; j.error='waiting for live storage to confirm requested stock' end
    elseif p.phase=='blocked' then j.status='blocked'; j.error=p.error or 'worker blocked'
    else j.status='running'; j.error=nil end
    if j.physicalComplete then j.physicalCompletedAt=j.physicalCompletedAt or clock() end
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
