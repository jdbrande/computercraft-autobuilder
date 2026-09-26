local U=require('autobuilder.core.util')
local Materials=require('autobuilder.resources.materials')
local M={}
function M.new(app,config,e,network,clock)
  local s=app.state; local self={}; local lastSend=-math.huge; local lastStorage=-math.huge
  local function save() return app:save() end
  local function send(to,kind,payload)
    local ok,err=network:send(to,kind,payload)
    if not ok then app:report('WARN',err) end
    return ok,err
  end
  if s.role=='controller' then
    self.storage=require('autobuilder.storage.storage').new(e.peripheral,config.storageInventories)
    self.jobs=require('autobuilder.core.jobs').new(s,save,clock,s.id)
    function self:refresh()
      local ok,err=self.storage:refresh(); s.storageError=err
      if ok then s.resourceCounts=U.copy(self.storage.counts) else s.resourceCounts={} end
      lastStorage=clock(); return ok,err
    end
    function self:command(line)
      local args={}; for word in line:gmatch('%S+') do args[#args+1]=word end
      if args[1]=='mine' then
        if #args~=3 then return false,'Usage: mine minecraft:raw_iron 100' end
        local ok,err=self:refresh(); if not ok then return false,err end
        local job,why=self.jobs:submit(args[2],tonumber(args[3]),self.storage:getCount(args[2]))
        if not job then return false,why end
        s.view='jobs'; return true,job.id
      elseif args[1]=='replan' and #args==2 then
        local job=s.jobs[args[2]]; if not job then return false,'unknown job ID' end
        local ok,err=self:refresh(); if not ok then return false,err end
        return self.jobs:replan(job.id,self.storage:getCount(job.item))
      elseif args[1]=='resume' and #args==2 then
        local job=s.jobs[args[2]]
        if not job or job.status~='blocked' or not job.workerId then return false,'no blocked assigned job with that ID' end
        job.retryCount=job.retryCount+1; save()
        return send(job.workerId,'mine_resume',{jobId=job.id})
      elseif args[1]=='resources' then local ok,err=self:refresh(); s.view='resources'; return ok,err or 'resource counts refreshed'
      elseif args[1]=='jobs' then s.view='jobs'; return true,'job queue'
      elseif args[1]=='workers' or args[1]=='status' then s.view='workers'; return true,'worker status' end
      return false,'Commands: mine <item> <count>, jobs, resources, workers, resume <jobId>'
    end
    function self:retireCompleted()
      -- A completion packet may be retransmitted until its acknowledgement arrives.
      -- Retain its whole supplement chain until newer worker telemetry proves every
      -- physical owner has cleared the task, and production no longer references it.
      local referenced={}
      for _,request in pairs((s.automation or {}).requests or {}) do
        for _,id in pairs(request.mines or {}) do referenced[id]=true end
      end
      for _,job in pairs(s.jobs) do
        if job.status~='completed' then
          for _,id in ipairs(job.dependencies or {}) do referenced[id]=true end
        end
      end
      local stamped,removed,visited={},{},{}
      local now=clock(); local count=0
      for id,job in pairs(s.jobs) do
        if job.status=='completed' and not job.completedAt then
          job.completedAt=now; stamped[#stamped+1]=job
        end
      end
      for id in pairs(s.jobs) do
        if not visited[id] then
          local pending={id}; local chain={}; local eligible=true
          while #pending>0 do
            local current=table.remove(pending)
            if not visited[current] then
              visited[current]=true
              local job=s.jobs[current]
              if not job then eligible=false
              else
                chain[#chain+1]=job
                if referenced[current] or job.status~='completed' or not job.completedAt or now<=job.completedAt then eligible=false end
                if job.workerId then
                  local worker=s.workers[tostring(job.workerId)]
                  if not job.physicalComplete or not worker or not worker.online or not worker.telemetry
                    or not U.finite(worker.lastSeen) or not job.completedAt or worker.lastSeen<=job.completedAt
                    or worker.telemetry.task==job.id then eligible=false end
                end
                if job.parent then pending[#pending+1]=job.parent end
                if job.childId then pending[#pending+1]=job.childId end
              end
            end
          end
          -- Limit checkpoint churn for a controller upgraded with a large history.
          if eligible and count+#chain<=64 then
            for _,job in ipairs(chain) do removed[job.id]=job; count=count+1 end
          end
        end
      end
      if count>0 or #stamped>0 then
        for id in pairs(removed) do s.jobs[id]=nil end
        local ok,err=save()
        if not ok then
          for id,job in pairs(removed) do s.jobs[id]=job end
          for _,job in ipairs(stamped) do job.completedAt=nil end
          return false,err
        end
      end
      return true,count
    end
    function self:tick()
      local retired,why=self:retireCompleted(); if not retired then return false,why end
      if #config.storageInventories>0 and clock()-lastStorage>=config.checkpointInterval then self:refresh() end
      if not self.storage.valid then return true end
      if s.assignmentRecovery then return true end
      if clock()-lastSend<config.heartbeatInterval then return true end
      local job=self.jobs:assign(s.workers,self.storage.counts)
      if job then
        lastSend=clock()
        send(job.workerId,'mine_assign',{jobId=job.id,item=job.item,quantity=job.quantity,miningArea=job.miningArea,miningResources=job.miningResources})
      end
      return true
    end
    function self:handle(sender,m)
      if m.type~='mine_progress' then return false,'unexpected mining message for controller' end
      local stock
      if m.payload.phase=='completed' then
        self:refresh(); local job=s.jobs[m.payload.jobId]
        if job then stock=self.storage:getCount(job.item) end
      end
      local job=s.jobs[m.payload.jobId]
      if job and not job.workerId and job.status=='queued' then
        local recovered,why=self.jobs:recoverOwner(sender,m.payload,s.workers)
        if not recovered then return false,why end
      end
      local ok,err=self.jobs:progress(sender,m.payload,stock)
      if not ok then return false,err end
      local completed=s.jobs[m.payload.jobId]; local stamped=false
      while completed and completed.status=='completed' do
        if not completed.completedAt then completed.completedAt=clock(); stamped=true end
        completed=completed.parent and s.jobs[completed.parent]
      end
      if stamped then local saved,why=save(); if not saved then return false,why end end
      if s.jobs[m.payload.jobId].physicalComplete or s.jobs[m.payload.jobId].status=='completed' then return send(sender,'mine_ack',{jobId=m.payload.jobId}) end
      return true
    end
    function self:step() return true end
  else
    s.completedMining=s.completedMining or {}
    if config.mining.enabled then
      self.inventory=require('autobuilder.storage.inventory').new(e.turtle,{reservedSlots={15,16},fuelSlot=15})
      self.scanner=require('autobuilder.resources.scanner').new(e,config.scanner,clock)
      local ok,err=self.scanner:recover(); assert(ok,err)
    end
    local function miner()
      if not self.miner or self.miner.task~=s.currentTask then
        self.miner=require('autobuilder.resources.miner').new(s.currentTask,e,config,app.navigation,self.inventory,self.scanner,save,clock)
      end
      return self.miner
    end
    function self:command() return false,'Enter mining commands on the controller' end
    function self:handle(sender,m)
      if sender~=config.controllerId then return false,'not configured controller' end
      if not config.mining.enabled then return false,'mining disabled on worker' end
      local p=m.payload
      if m.type=='mine_assign' then
        if not Materials.accepts(config.mining.resources,p.item) then return false,'assigned item is outside configured mining resources' end
        if p.miningResources~=nil and not Materials.sameResources(p.miningResources,config.mining.resources) then return false,'assigned mining resources differ from local config' end
        if s.completedMining[p.jobId] then
          return send(sender,'mine_progress',{jobId=p.jobId,phase='completed',delivered=s.completedMining[p.jobId],held=0})
        end
        if require('autobuilder.core.receipts').archived(s,'completedMining',p.jobId) then return false,'Old acknowledged mine was archived; restore the matching controller checkpoint' end
        if s.currentTask then
          if s.currentTask.id==p.jobId and s.currentTask.item==p.item and s.currentTask.quantity==p.quantity then return true end
          return false,'worker already owns a different task'
        end
        s.currentTask={id=p.jobId,type='MINE',item=p.item,quantity=p.quantity,phase='setup',delivered=0,miningArea=U.copy(p.miningArea),miningResources=U.copy(p.miningResources or config.mining.resources or {})}
        s.status='setup'; save(); return true
      elseif m.type=='mine_ack' then
        if s.currentTask and s.currentTask.id==p.jobId and s.currentTask.phase=='completed' then
          require('autobuilder.core.receipts').record(s,'completedMining',p.jobId,s.currentTask.delivered); s.currentTask=nil; self.miner=nil; s.status='idle'; save(); return true
        end
        return false,'unexpected job acknowledgement'
      elseif m.type=='mine_resume' and s.currentTask and s.currentTask.id==p.jobId then
        return miner():resume()
      end
      return false,'unexpected mining message'
    end
    function self:tick()
      if s.currentTask and (not s.currentTask.type or s.currentTask.type=='MINE') and config.mining.enabled and clock()-lastSend>=config.heartbeatInterval then
        lastSend=clock(); local task=s.currentTask
        local err=task.error and tostring(task.error):gsub('[%c]',' '):sub(1,512)
        send(config.controllerId,'mine_progress',{jobId=task.id,phase=task.phase or 'blocked',
          delivered=task.delivered or 0,held=self.inventory:getCount(task.item),error=err,assignedQuantity=task.quantity})
      end
      return true
    end
    function self:poseRecovered()
      if config.mining.enabled and s.currentTask and (not s.currentTask.type or s.currentTask.type=='MINE') and s.currentTask.phase=='blocked'
        and s.currentTask.error=='trusted position and heading required' and U.heading(s.position.heading) then
        local ok,err=miner():resume()
        if ok then s.status=s.currentTask.phase else app:report('WARN',err) end
      end
    end
    function self:step()
      if not config.mining.enabled or not s.currentTask or s.currentTask.phase=='completed' then return true end
      if not Materials.accepts(config.mining.resources,s.currentTask.item)
        or s.currentTask.miningResources~=nil and not Materials.sameResources(s.currentTask.miningResources,config.mining.resources) then
        if s.currentTask.phase~='blocked' then s.currentTask.resumePhase=s.currentTask.phase end
        s.currentTask.phase='blocked'; s.currentTask.error='Assigned mining resources differ from local config; restore original resources'; save(); return true
      end
      if s.currentTask.miningArea then
        for _,edge in ipairs({'min','max'}) do for _,axis in ipairs({'x','y','z'}) do
          if s.currentTask.miningArea[edge][axis]~=config.mining.bounds[edge][axis] then
            s.currentTask.phase='blocked'; s.currentTask.error='Assigned mining area differs from local config; restore original bounds'; save(); return true
          end
        end end
      end
      local m=miner()
      if s.currentTask.phase=='blocked' then return true end
      local ok,err=m:step(); s.status=s.currentTask.phase
      if not ok then app:report('WARN','Mining job '..s.currentTask.id..': '..tostring(err)) end
      save(); return true
    end
  end
  return self
end
return M
