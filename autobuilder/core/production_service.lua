local U=require('autobuilder.core.util')
local Coordination=require('autobuilder.core.workflows')
local Materials=require('autobuilder.resources.materials')
local Providers=require('autobuilder.resources.providers')
local M={}
function M.new(app,config,e,queue)
  local s=queue.state; s.requestSequence=s.requestSequence or 0
  local self={machines={},laneCursor=0}; local save=function() return app:save() end
  function self:request(requirements,key,options)
    options=options or {}
    assert(type(requirements)=='table' and next(requirements),'resource request needs item quantities')
    for item,n in pairs(requirements) do assert(U.shortString(item,128) and U.integer(n) and n>=1 and n<=1000000,'invalid resource request') end
    local project=options.projectName and assert(s.projects[options.projectName],'Preparation project missing')
    for _,r in pairs(s.requests) do if key and r.key==key and r.status~='completed' then return r end end
    s.requestSequence=s.requestSequence+1
    local r={id='request:'..s.requestSequence,key=key,requirements=U.copy(requirements),status='queued',operation=1,mines={},harvests={},stockOnly=options.stockOnly==true}
    s.requests[r.id]=r
    local previous
    if project then
      -- Capture the old linkage so a failed checkpoint cannot leave a request
      -- that callers might subsequently mistake for a durable preparation.
      previous={stockOnly=project.stockOnly,requestId=project.requestId,phase=project.phase}
      project.stockOnly=r.stockOnly; project.requestId=r.id; project.phase='preparing'
    end
    local called,ok,err=pcall(save)
    if not called or not ok then
      if project then project.stockOnly=previous.stockOnly; project.requestId=previous.requestId; project.phase=previous.phase end
      s.requests[r.id]=nil; s.requestSequence=s.requestSequence-1
      error(called and (err or 'Failed to save resource request') or ok,0)
    end
    return r
  end
  function self:refresh()
    return app.mining:refresh()
  end
  local function hasWorker(capability,item)
    -- Small integrations predating the registry can still drive production.
    if app.state.workers==nil then return true end
    for _,worker in pairs(app.state.workers) do
      local t=worker.telemetry
      if worker.online and t and t.capabilities and t.capabilities[capability] then
        if not item or Materials.accepts(t.miningResources,item) then return true end
      end
    end
    return false
  end
  local function progress(r,item,target)
    r.materials=r.materials or {}
    local prior=r.materials[item] or {}
    local material={count=app.mining.storage:getCount(item) or 0,target=target,status='queued',jobId=prior.jobId,workerId=prior.workerId,provider=prior.provider}
    r.materials[item]=material; return material
  end
  local function blocked(material,reason)
    material.status='blocked'; material.error=reason; return false
  end
  local function acquire(r,item,target)
    local material=progress(r,item,target); local count=material.count
    r.acquisitions=r.acquisitions or {}
    local groupId=r.acquisitions[item]
    local legacy=r.mines[item] and app.state.jobs[r.mines[item]]
    local harvest=r.harvests[item] and s.jobs[r.harvests[item]]
    local provider
    -- Durable jobs keep their source and saved geometry even when configuration
    -- or online eligibility changes. Only unowned demand selects a new source.
    if legacy and legacy.status~='completed' then provider={type='mining',id='mining:'..item}
    elseif groupId then provider={type='exploration',id='exploration:'..item}
    elseif harvest and harvest.status~='completed' then
      local kind=harvest.type=='HARVEST' and 'tree_farm' or 'farm'
      provider={type=kind,id=material.provider or kind..':'..item,farm=harvest.farm}
    else provider=Providers.select(item,config,{available=count,required=target,workers=app.state.workers,acquisitionOnly=true}) end
    material.provider=provider and provider.id or nil
    if provider and provider.type=='exploration' then
      local group=groupId and app.state.exploration.groups[groupId]
      if not group then
        local why; group,why=app.mining.jobs:requestAcquisition(item,target,count,r.id..':'..item)
        if not group then return blocked(material,why) end
        r.acquisitions[item]=group.id; save()
      end
      group=app.mining.jobs:refreshAcquisition(group.id,count)
      material.groupId=group.id; material.status=group.status; material.workers={}
      for _,id in ipairs(group.tripIds) do local j=app.state.jobs[id]; if j and j.workerId and not j.physicalComplete then material.workers[#material.workers+1]=j.workerId end end
      if group.status=='completed' then material.status='ready'; return true end
      if not hasWorker('explorationV1',item) then return blocked(material,'No online exploration-capable worker for '..item) end
      material.error=group.error; return false
    end
    if count>=target then material.status='ready'; return true end
    if provider and provider.type=='mining' then
      local id=r.mines[item]; local existing=id and app.state.jobs[id]
      if not existing or existing.status=='completed' then
        local job,why=app.mining.jobs:submit(item,target,count)
        if not job then
          for _,j in pairs(app.state.jobs) do if j.item==item and j.status~='completed' then job=j; break end end
        end
        if not job then return blocked(material,why) end
        r.mines[item]=job.id; save()
      end
      local job=app.state.jobs[r.mines[item]]
      material.jobId=job.id; material.workerId=job.workerId; material.status=job.status
      if job.status=='blocked' then return blocked(material,job.error or 'Mining job blocked: '..item) end
      if not hasWorker('mining',item) then return blocked(material,'No online mining worker eligible for '..item) end
      return false
    end
    local farm=provider and provider.farm
    local kind=provider and (provider.type=='tree_farm' and 'HARVEST' or 'FARM')
    if farm then
      local prior=r.harvests[item] and s.jobs[r.harvests[item]]
      if not prior or prior.status=='completed' then
        local job=queue:submit(kind,{item=item,quantity=target-count,farm=U.copy(farm)},{},r.id..':'..item..':'..(prior and prior.id or 'first'))
        r.harvests[item]=job.id; save()
      end
      local job=s.jobs[r.harvests[item]]
      material.jobId=job.id; material.workerId=job.workerId; material.status=job.status; material.error=job.error
      return false
    end
    return blocked(material,'No configured farm or acquisition source for '..item..' ('..(target-count)..' missing)')
  end
  local function acquisitionSummary(r)
    local errors,waiting={},{}
    for item,material in pairs(r.materials) do
      if material.error then errors[#errors+1]=material.error
      elseif material.status~='ready' then waiting[#waiting+1]='Acquiring '..item..' '..material.count..'/'..material.target end
    end
    table.sort(errors); table.sort(waiting)
    return table.concat(#errors>0 and errors or waiting,'; ')
  end
  function self:tick()
    local active
    for _,r in pairs(s.requests) do if r.status=='running' or r.status=='blocked' then active=r; break end end
    if not active then
      local list={}; for _,r in pairs(s.requests) do if r.status=='queued' then list[#list+1]=r end end
      table.sort(list,function(a,b) return tonumber(a.id:match('%d+'))<tonumber(b.id:match('%d+')) end); active=list[1]
    end
    if not active or active.paused then return end
    local r=active; local ok,err=self:refresh()
    if not ok then r.status='blocked'; r.error=err; return end
    if r.stockOnly then
      -- The beginner test is supplied by the user. It must not queue mining,
      -- crafting, or a global fuel-stock replenishment as a side effect.
      r.materials={}; local ready=true
      for item,n in pairs(r.requirements) do
        local need=n+(config.turtleFuelReserveItems[item] or 0)
        local material=progress(r,item,need); local have=material.count
        if have<need then
          ready=false; blocked(material,'Put '..(need-have)..' more '..item:gsub('^.-:',''):gsub('_',' ')..' in the stock chest.')
        else material.status='ready' end
      end
      if not ready then r.status='blocked'; r.error=acquisitionSummary(r); save(); return end
      r.status='completed'; r.error=nil; save(); return
    end
    if not r.plan then
      local plan=require('autobuilder.blueprint.planner').expand(r.requirements,app.mining.storage.counts,config)
      r.plan=plan; r.targets={}; r.materials={}
      for item,n in pairs(plan.missing) do r.targets[item]=(app.mining.storage.counts[item] or 0)+n end
      r.status='running'; save()
    end
    if not r.acquired then
      local ready=true
      for item,target in pairs(r.targets) do if not acquire(r,item,target) then ready=false end end
      if not ready then r.status='blocked'; r.error=acquisitionSummary(r); save(); return end
      r.acquired=true; r.status='running'; r.error=nil; save()
    end
    -- Ready records describe completed acquisition, even as the factory spends
    -- those inputs. Continue showing their live counts without mining them again.
    for item,material in pairs(r.materials or {}) do
      material.count=app.mining.storage:getCount(item) or 0
      local job=material.jobId and (app.state.jobs[material.jobId] or s.jobs[material.jobId])
      if job then material.workerId=job.workerId end
    end
    local op=r.plan.operations[r.operation]
    if op then
      -- Finish/recover an existing supply batch before reserving factory storage.
      -- Otherwise a pre-grant supply journal could never finish once offers are
      -- gated by a newly queued factory operation.
      if not r.jobId and not r.jobIds and s.supply then
        r.error='waiting for outstanding supply batch '..tostring(s.supply.jobId); save(); return
      end
      if op.type=='SMELT' then
        if not r.jobIds and not r.jobId and #(config.furnaces or {})==0 then
          r.status='blocked'; r.error='No configured furnaces for '..op.item; save(); return
        end
        -- A request may have been planned before its first furnace was configured.
        if not r.jobIds and not r.jobId and op.lanes then
          for index,lane in ipairs(op.lanes) do
            if not lane.furnaceLane then lane.furnaceLane=config.furnaces[index] end
          end
        end
        r.status='running'; r.error=nil
        -- Adopt an older unsplit task unchanged. New plans persist each lane's
        -- exact batches and peripheral name before any lane is allowed to run.
        if not r.jobIds then
          if r.jobId then r.jobIds={r.jobId}
          else
            -- Plans written before lane metadata budgeted fuel for one furnace.
            -- Keep that exact tranche rather than silently raising its fuel demand.
            op.lanes=op.lanes or {{batches=op.batches,furnaceLane=config.furnaces[1]}}
            r.jobIds={}
          end
          save()
        end
        local lanes=op.lanes or {{batches=op.batches}}
        if not r.jobId then
          for index,lane in ipairs(lanes) do
            if not r.jobIds[index] then
              local job=queue:submit('SMELT',{item=op.item,quantity=lane.batches,batches=lane.batches,
                furnaceLane=lane.furnaceLane,productionRequest=r.id,productionOperation=r.operation},{},r.id..':op:'..r.operation..':lane:'..index..(r.replans and ':replan:'..r.replans or ''))
              r.jobIds[index]=job.id; save()
            end
          end
        end
        local complete=true; local blocked
        for _,id in ipairs(r.jobIds) do
          local job=assert(s.jobs[id],'production furnace lane job is missing')
          if job.status~='completed' then complete=false end
          if job.status=='blocked' then blocked=job.error or 'furnace lane blocked' end
        end
        if complete then r.operation=r.operation+1; r.jobId=nil; r.jobIds=nil; r.status='running'; r.error=nil; save()
        elseif blocked then r.status='blocked'; r.error=blocked; save() end
      else
        local job=r.jobId and s.jobs[r.jobId]
        if op.type=='CRAFT' and (not job or job.status~='completed') and not hasWorker('crafting') then
          r.status='blocked'; r.error='No online crafting-capable worker for '..op.item; save(); return
        end
        r.status='running'; r.error=nil
        if not job then
          job=queue:submit(op.type,{item=op.item,quantity=op.quantity,batches=op.batches},{},r.id..':op:'..r.operation..(r.replans and ':replan:'..r.replans or ''))
          r.jobId=job.id; save()
        elseif job.status=='completed' then r.operation=r.operation+1; r.jobId=nil; r.error=nil; save()
        elseif job.status=='blocked' then r.status='blocked'; r.error=job.error; save() end
      end
    else
      for item,n in pairs(r.plan.requirements or r.requirements) do
        if (app.mining.storage:getCount(item) or 0)<n then
          r.replans=(r.replans or 0)+1
          if r.replans>3 then r.status='blocked'; r.error='Finished items were consumed externally; pause competing consumers and retry request'; save(); return end
          r.plan=nil; r.acquired=nil; r.operation=1; r.jobId=nil; r.jobIds=nil; r.status='running'; save(); return
        end
      end
      r.status='completed'; r.error=nil; save()
    end
  end
  function self:describe(item)
    assert(U.shortString(item,128),'Usage: resource <namespaced-item>')
    local ok,err=self:refresh()
    local lines={item..' stock='..(ok and tostring(app.mining.storage:getCount(item) or 0) or 'unknown ('..tostring(err)..')')}
    local requests={}
    for _,r in pairs(s.requests) do
      if r.plan and r.plan.graph and r.plan.graph.nodes[item] then requests[#requests+1]=r end
    end
    table.sort(requests,function(a,b) return tonumber(a.id:match('%d+'))<tonumber(b.id:match('%d+')) end)
    for _,r in ipairs(requests) do
      local node=r.plan.graph.nodes[item]; local material=(r.materials or {})[item]
      lines[#lines+1]=r.id..' '..r.status..' required='..node.required..' initial='..node.available..
        ' planned='..node.produced..' deficit='..node.deficit..' missing='..node.missing..
        ' provider='..tostring(material and material.provider or node.provider and node.provider.id or node.error)
    end
    local candidates=Providers.candidates(item,config)
    for _,p in ipairs(candidates) do if p.type~='storage' then lines[#lines+1]='candidate='..p.id end end
    if #candidates==1 then lines[#lines+1]='No configured provider for '..item end
    return table.concat(lines,'; ')
  end
  local function execute(job)
    local allowed,why=Coordination.factoryCanRun(app.state,job)
    if not allowed then
      if job.error~=why then job.error=why; save() end
      return true
    end
    local machine=self.machines[job.id]
    if not machine or machine.task~=job then
      machine=require('autobuilder.factory.smelting').new(job,e,config,save); self.machines[job.id]=machine
    end
    local status,err=machine:step()
    job.status=status=='complete' and 'completed' or status=='blocked' and 'blocked' or 'running'
    job.error=err; save(); return true
  end
  function self:step()
    for id in pairs(self.machines) do if not s.jobs[id] then self.machines[id]=nil end end
    if app.state.assignmentRecovery then return true end
    local all={}
    for _,job in pairs(s.jobs) do if job.type=='SMELT' then all[#all+1]=job end end
    table.sort(all,function(a,b) return a.id<b.id end)
    -- A journal watches shared storage. Reconcile it before any other lane can
    -- change that observation, even if its owner was marked blocked or paused.
    for _,job in ipairs(all) do
      if job.production and job.production.intent then return execute(job) end
    end
    local owners={}; local duplicate=false
    for _,job in ipairs(all) do
      if job.status~='completed' then
        local lane=job.furnaceLane or job.production and job.production.furnace
        if lane then
          local other=owners[lane]
          if other then
            job.status='blocked'; other.status='blocked'
            job.error='duplicate ownership of furnace lane '..lane; other.error=job.error; duplicate=true
          else owners[lane]=job end
        end
      end
    end
    if duplicate then save(); return true end
    local ready={}
    for _,job in ipairs(all) do
      if (job.status=='queued' or job.status=='running') and not job.paused and queue:ready(job) then ready[#ready+1]=job end
    end
    if #ready==0 then return true end
    self.laneCursor=self.laneCursor%#ready+1
    local job=ready[self.laneCursor]
    if not job.furnaceLane then
      local chosen=job.production and job.production.furnace
      if not chosen then for _,name in ipairs(config.furnaces) do if not owners[name] then chosen=name; break end end end
      if not chosen then job.status='blocked'; job.error='no unowned configured furnace lane'; save(); return true end
      job.furnaceLane=chosen; save()
    end
    return execute(job)
  end
  return self
end
return M
