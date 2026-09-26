local U=require('autobuilder.core.util')
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
    function self:tick()
      if #config.storageInventories>0 and clock()-lastStorage>=config.checkpointInterval then self:refresh() end
      if not self.storage.valid then return true end
      if s.assignmentRecovery then return true end
      if clock()-lastSend<config.heartbeatInterval then return true end
      local job=self.jobs:assign(s.workers,self.storage.counts)
      if job then
        lastSend=clock()
        send(job.workerId,'mine_assign',{jobId=job.id,item=job.item,quantity=job.quantity,miningArea=job.miningArea})
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
        if s.completedMining[p.jobId] then
          return send(sender,'mine_progress',{jobId=p.jobId,phase='completed',delivered=s.completedMining[p.jobId],held=0})
        end
        if s.currentTask then
          if s.currentTask.id==p.jobId and s.currentTask.item==p.item and s.currentTask.quantity==p.quantity then return true end
          return false,'worker already owns a different task'
        end
        s.currentTask={id=p.jobId,type='MINE',item=p.item,quantity=p.quantity,phase='setup',delivered=0,miningArea=U.copy(p.miningArea)}
        s.status='setup'; save(); return true
      elseif m.type=='mine_ack' then
        if s.currentTask and s.currentTask.id==p.jobId and s.currentTask.phase=='completed' then
          s.completedMining[p.jobId]=s.currentTask.delivered; s.currentTask=nil; self.miner=nil; s.status='idle'; save(); return true
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
