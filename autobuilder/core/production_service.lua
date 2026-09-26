local U=require('autobuilder.core.util')
local Coordination=require('autobuilder.core.workflows')
local M={}
function M.new(app,config,e,queue)
  local s=queue.state; s.requestSequence=s.requestSequence or 0
  local self={machines={},laneCursor=0}; local save=function() return app:save() end
  function self:request(requirements,key)
    assert(type(requirements)=='table' and next(requirements),'resource request needs item quantities')
    for item,n in pairs(requirements) do assert(U.shortString(item,128) and U.integer(n) and n>=1 and n<=1000000,'invalid resource request') end
    for _,r in pairs(s.requests) do if key and r.key==key and r.status~='completed' then return r end end
    s.requestSequence=s.requestSequence+1
    local r={id='request:'..s.requestSequence,key=key,requirements=U.copy(requirements),status='queued',operation=1,mines={},harvests={}}
    s.requests[r.id]=r; save(); return r
  end
  function self:refresh()
    return app.mining:refresh()
  end
  local function acquire(r,item,target)
    local count=app.mining.storage:getCount(item) or 0
    if count>=target then return true end
    if require('autobuilder.resources.materials').get(item) then
      local id=r.mines[item]; local existing=id and app.state.jobs[id]
      if not existing or existing.status=='completed' then
        local job,why=app.mining.jobs:submit(item,target,count)
        if not job then
          for _,j in pairs(app.state.jobs) do if j.item==item and j.status~='completed' then job=j; break end end
        end
        if not job then r.error=why; return false end
        r.mines[item]=job.id; save()
      end
      r.error='Acquiring '..item..' '..count..'/'..target; return false
    end
    local farm,kind
    for _,f in ipairs(config.treeFarms) do if f.item==item then farm=f; kind='HARVEST'; break end end
    if not farm then for _,f in ipairs(config.farms) do if f.item==item then farm=f; kind='FARM'; break end end end
    if farm then
      local prior=r.harvests[item] and s.jobs[r.harvests[item]]
      if not prior or prior.status=='completed' then
        local job=queue:submit(kind,{item=item,quantity=target-count,farm=U.copy(farm)},{},r.id..':'..item..':'..(prior and prior.id or 'first'))
        r.harvests[item]=job.id; save()
      end
      r.error='Waiting for managed farm: '..item; return false
    end
    r.error='Special acquisition required: '..item..' ('..(target-count)..' missing)'; return false
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
    if not r.plan then
      local plan=require('autobuilder.blueprint.planner').expand(r.requirements,app.mining.storage.counts,config)
      r.plan=plan; r.targets={}
      for item,n in pairs(plan.missing) do r.targets[item]=(app.mining.storage.counts[item] or 0)+n end
      r.status='running'; save()
    end
    if not r.acquired then
      local ready=true
      for item,target in pairs(r.targets) do if not acquire(r,item,target) then ready=false end end
      if not ready then r.status='blocked'; save(); return end
      r.acquired=true; r.status='running'; r.error=nil; save()
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
                furnaceLane=lane.furnaceLane,productionRequest=r.id,productionOperation=r.operation},{},r.id..':op:'..r.operation..':lane:'..index)
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
        if not job then
          job=queue:submit(op.type,{item=op.item,quantity=op.quantity,batches=op.batches},{},r.id..':op:'..r.operation)
          r.jobId=job.id; save()
        elseif job.status=='completed' then r.operation=r.operation+1; r.jobId=nil; r.error=nil; save()
        elseif job.status=='blocked' then r.status='blocked'; r.error=job.error; save() end
      end
    else
      for item,n in pairs(r.requirements) do
        if (app.mining.storage:getCount(item) or 0)<n then
          r.replans=(r.replans or 0)+1
          if r.replans>3 then r.status='blocked'; r.error='Finished items were consumed externally; pause competing consumers and retry request'; save(); return end
          r.plan=nil; r.acquired=nil; r.operation=1; r.jobId=nil; r.jobIds=nil; r.status='running'; save(); return
        end
      end
      r.status='completed'; r.error=nil; save()
    end
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
