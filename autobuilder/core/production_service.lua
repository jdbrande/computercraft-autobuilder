local U=require('autobuilder.core.util')
local Coordination=require('autobuilder.core.workflows')
local Materials=require('autobuilder.resources.materials')
local Providers=require('autobuilder.resources.providers')
local M={}
function M.new(app,config,e,queue)
  local s=queue.state; s.requestSequence=s.requestSequence or 0
  local self={machines={},laneCursor=0}; local save=function() return app:save() end
  self.ledger=require('autobuilder.storage.ledger').new(app.state,save)
  self.parallel=require('autobuilder.factory.parallel').new(app,config,e,queue,self)
  self.logistics=require('autobuilder.core.logistics_service').new(app,config,e,queue,self)
  self.returns=require('autobuilder.core.return_service').new(app,config,e,queue,self)
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
    if self.working or self.reading then return false,'inventory operation in progress' end
    self.reading=true
    local called,ok,why=pcall(app.mining.refresh,app.mining)
    self.reading=false
    if not called then error(ok,0) end
    return ok,why
  end
  function self:acceptReceipt(job,receipt)
    if job.privateStation or job.logistics or job.returning then return true end -- worker receipts describe private stock, not central delivery
    if not job.stockInputs then return true end -- exclusive legacy job
    local ok,err=pcall(self.ledger.receipt,self.ledger,job.id,receipt.withdrawn,receipt.delivered,receipt.transit or {},receipt.sequence)
    return ok,not ok and tostring(err) or nil
  end
  local function localReceipt(job)
    if job.returning then
      local delivered,sequence={},0
      for item,flow in pairs(job.returnFlow.collect) do delivered[item]=flow.delivered or 0;sequence=sequence+(flow.stockSequence or 0) end
      if sequence>0 then return {withdrawn={},delivered=delivered,sequence=sequence} end
      return
    end
    if job.logistics then
      local f=job.logisticsFlow;if not f then return end
      local sequence=(f.stage.stockSequence or 0)+(f.collect.stockSequence or 0)
      if sequence==0 then return end
      local taken=(f.stage.withdrawn or {})[job.item] or 0;local delivered=f.collect.delivered or 0
      return {withdrawn={[job.item]=taken},delivered={[job.item]=delivered},transit={[job.item]=taken-delivered},sequence=sequence}
    end
    if job.privateStation then
      local flow=job.factoryFlow
      if not flow then return end
      local sequence=(flow.stage.stockSequence or 0)+(flow.collect.stockSequence or 0)
      if sequence==0 then return end
      return {withdrawn=U.copy(flow.stage.withdrawn or {}),delivered={[job.item]=flow.collect.delivered or 0},sequence=sequence}
    end
    local p=job.production
    if not p or not p.stockSequence then return end
    local withdrawn=U.copy(p.withdrawn or {})
    if job.type=='SMELT' then
      local recipe=require('autobuilder.factory.recipes').get(job.item)
      withdrawn[next(recipe.ingredients)]=p.loaded or 0
      local fuel=config.smeltingFuelItem or 'minecraft:coal'
      withdrawn[fuel]=(withdrawn[fuel] or 0)+(p.fuelLoaded or 0)
    end
    return {withdrawn=withdrawn,delivered={[job.item]=p.delivered or 0},sequence=p.stockSequence}
  end
  local function syncClaims(allowGrant)
    local jobs={}; for _,j in pairs(s.jobs) do if j.stockInputs and not j.cancelled then jobs[#jobs+1]=j end end
    table.sort(jobs,function(a,b) return a.id<b.id end)
    for _,j in ipairs(jobs) do
      local lease=self.ledger.state.leases[j.id]
      if lease and lease.status=='held' then
        local receipt=localReceipt(j)
        if receipt then self.ledger:receipt(j.id,receipt.withdrawn,receipt.delivered,receipt.transit or {},receipt.sequence) end
        lease=self.ledger.state.leases[j.id]
        if j.status=='completed' then
          -- Older Crafty workers can acknowledge completion without counters.
          -- Their exclusive job completion already guarantees exact output.
          if not require('autobuilder.factory.factory').equal(lease.delivered,j.stockOutputs) then
            assert(not j.privateStation and not j.logistics and not j.returning,'private output has not reached shared storage')
            local withdrawn=j.type=='CRAFT' and j.stockInputs or lease.withdrawn
            self.ledger:receipt(j.id,withdrawn,j.stockOutputs,{},lease.sequence+1)
          end
          self.ledger:release(j.id)
        end
      end
    end
    if allowGrant==false then return end
    for _,j in ipairs(jobs) do if j.status~='completed' and not j.logistics and not j.privateStation and not j.returnManaged and not self.ledger.state.leases[j.id] then
      local lease,why=self.ledger:reserve(j.id,j.stockInputs,j.stockOutputs,
        app.mining.storage.valid and app.mining.storage.counts or nil,{protected=j.type=='FUEL_STATION' and {} or config.turtleFuelReserveItems})
      if j.stockError~=why then j.stockError=why; save() end
    end end
  end
  function self:syncClaims(allowGrant)
    if allowGrant==false then return syncClaims(false) end
    if self.working or self.reading then return end
    -- Peripheral list calls yield in CraftOS. Keep the action coroutine out of
    -- the complete observation/grant interval, and always observe anew here.
    self.reading=true
    local ok,result=pcall(function() app.mining:refresh(); return syncClaims(true) end)
    self.reading=false
    if not ok then error(result,0) end
    return result
  end
  local function hasWorker(capability,item)
    -- Small integrations predating the registry can still drive production.
    if app.state.workers==nil then return true end
    for _,worker in pairs(app.state.workers) do
      local t=worker.telemetry
      if worker.online and t and t.capabilities and t.capabilities[capability]
        and not (capability=='mining' and t.capabilities.explorationV1) then
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
    if legacy and legacy.status=='completed' then legacy=nil end
    if harvest and harvest.status=='completed' then harvest=nil end
    local candidate=Providers.select(item,config,{available=count,required=target,workers=app.state.workers,acquisitionOnly=true})
    local queued=legacy or harvest
    local oldType=legacy and 'mining' or harvest and (harvest.type=='HARVEST' and 'tree_farm' or 'farm')
    local capability=legacy and 'mining' or harvest and (harvest.type=='HARVEST' and 'logging' or 'farming')
    local claimed=queued and queued.workerId
    for _,w in pairs(app.state.workers or {}) do
      if queued and w.telemetry and w.telemetry.task==queued.id then claimed=true end
    end
    if queued and queued.status=='queued' and not claimed and not queued.paused and not groupId
      and candidate and candidate.available and candidate.type~='storage' and candidate.type~=oldType
      and not hasWorker(capability,legacy and item or nil) then
      -- Never-assigned work may change source. Persist retirement before creating
      -- a replacement; assigned/offline owners and their journals never expire.
      local links=legacy and r.mines or r.harvests
      queued.status='completed'; queued.cancelled=true; links[item]=nil
      local called,ok,why=pcall(save)
      if not called or not ok then
        queued.status='queued'; queued.cancelled=nil; links[item]=queued.id
        error(called and (why or 'Provider retirement checkpoint failed') or ok,0)
      end
      legacy=nil; harvest=nil
    end
    local provider
    -- Durable jobs keep their source and saved geometry even when configuration
    -- or online eligibility changes. Only unowned demand selects a new source.
    if legacy and legacy.status~='completed' then provider={type='mining',id='mining:'..item}
    elseif groupId then provider={type='exploration',id='exploration:'..item}
    elseif harvest and harvest.status~='completed' then
      local kind=harvest.type=='HARVEST' and 'tree_farm' or 'farm'
      provider={type=kind,id=material.provider or kind..':'..item,farm=harvest.farm}
    else provider=candidate end
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
    if self.working then return end
    local active
    for _,r in pairs(s.requests) do if r.status=='running' or r.status=='blocked' then active=r; break end end
    if not active then
      local list={}; for _,r in pairs(s.requests) do if r.status=='queued' then list[#list+1]=r end end
      table.sort(list,function(a,b) return tonumber(a.id:match('%d+'))<tonumber(b.id:match('%d+')) end); active=list[1]
    end
    if not active or active.paused then self:refresh(); self:syncClaims(); return end
    local r=active; local ok,err=self:refresh()
    if not ok then r.status='blocked'; r.error=err; return end
    self:syncClaims()
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
              local inputs={}
              for item,n in pairs(op.inputs) do inputs[item]=n/op.batches*lane.batches end
              local fuel=config.smeltingFuelItem or 'minecraft:coal'
              inputs[fuel]=(inputs[fuel] or 0)+math.ceil(lane.batches/require('autobuilder.factory.fuel').capacity(fuel))
              local job=queue:submit('SMELT',{item=op.item,quantity=lane.batches,batches=lane.batches,
                stockInputs=inputs,stockOutputs={[op.item]=lane.batches},
                furnaceLane=lane.furnaceLane,productionRequest=r.id,productionOperation=r.operation},{},r.id..':op:'..r.operation..':lane:'..index..(r.replans and ':replan:'..r.replans or ''))
              r.jobIds[index]=job.id; save()
            end
          end
        end
        local complete=true; local blocked
        for _,id in ipairs(r.jobIds) do
          local job=assert(s.jobs[id],'production furnace lane job is missing')
          if job.status~='completed' then complete=false end
          if job.stockError then blocked=job.stockError
          elseif job.status=='blocked' then blocked=job.error or 'furnace lane blocked' end
        end
        if complete then r.operation=r.operation+1; r.jobId=nil; r.jobIds=nil; r.status='running'; r.error=nil; save()
        elseif blocked then r.status='blocked'; r.error=blocked; save() end
      elseif op.type=='CRAFT' and (r.privateCraft or self.parallel:owns(r) or not r.jobId and #(config.craftingStations or {})>0) then
        self.parallel:schedule(r,op)
      else
        local job=r.jobId and s.jobs[r.jobId]
        if op.type=='CRAFT' and (not job or job.status~='completed') and not hasWorker('crafting') then
          r.status='blocked'; r.error='No online crafting-capable worker for '..op.item; save(); return
        end
        r.status='running'; r.error=nil
        if not job then
          job=queue:submit(op.type,{item=op.item,quantity=op.quantity,batches=op.batches,
            stockInputs=U.copy(op.inputs),stockOutputs={[op.item]=op.quantity}},{},r.id..':op:'..r.operation..(r.replans and ':replan:'..r.replans or ''))
          r.jobId=job.id; save()
        elseif job.status=='completed' then r.operation=r.operation+1; r.jobId=nil; r.error=nil; save()
        elseif job.stockError or job.status=='blocked' then r.status='blocked'; r.error=job.stockError or job.error; save() end
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
    local lines={}
    local requests={}; local demand=0
    for _,r in pairs(s.requests) do
      if r.plan and r.plan.graph and r.plan.graph.nodes[item] then
        requests[#requests+1]=r
        if r.status~='completed' then demand=demand+r.plan.graph.nodes[item].required end
      end
    end
    local v=self.ledger:view(item,ok and app.mining.storage.counts or nil,demand)
    local function value(n) return n==nil and 'unknown' or tostring(n) end
    lines[1]=item..' stock='..value(v.physical)..' available='..value(v.available)..' reserved='..v.reserved..
      ' transit='..v.transit..' expected='..v.expected..' demand='..v.demand
    if not ok then lines[#lines+1]=tostring(err) end
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
    job.error=err; save(); self:syncClaims(false); return true
  end
  local function step()
    for id in pairs(self.machines) do if not s.jobs[id] then self.machines[id]=nil end end
    if app.state.assignmentRecovery then return true end
    if self.returns:step() then return true end
    if self.logistics:step() then return true end
    if self.parallel:step() then return true end
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
  function self:inventoryAction(action)
    if self.reading or self.working then return false end
    self.working=true
    local ok,result=pcall(action)
    self.working=false
    if not ok then error(result,0) end
    return result
  end
  function self:step() return self:inventoryAction(step) end
  return self
end
return M
