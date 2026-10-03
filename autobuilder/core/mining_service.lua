local U=require('autobuilder.core.util')
local Materials=require('autobuilder.resources.materials')
local E=require('autobuilder.resources.exploration')
local function same(a,b)
  if type(a)~=type(b) then return false end
  if type(a)~='table' then return a==b end
  for k,v in pairs(a) do if not same(v,b[k]) then return false end end
  for k in pairs(b) do if a[k]==nil then return false end end
  return true
end
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
    self.jobs=require('autobuilder.core.jobs').new(s,save,clock,s.id,config,app.chunks)
    if (config.exploration or {}).enabled then
      local gridChanged=s.exploration.gridBase and not same(s.exploration.gridBase,config.exploration.base)
      local settingsChanged=s.exploration.settingsRevision~=nil and s.exploration.settingsRevision~=(config.exploration.revision or 0)
        or s.exploration.configuredBounds and not same(s.exploration.configuredBounds,config.exploration.bounds) and not same(s.exploration.bounds,config.exploration.bounds)
      if gridChanged or settingsChanged then
        for _,j in pairs(s.jobs) do assert(j.physicalComplete or j.status=='completed','Finish exploration work before changing its base grid') end
        if gridChanged then s.exploration.sectors={} end
        s.exploration.bounds=nil; s.exploration.configuredBounds=nil
      end
      s.exploration.gridBase=U.copy(config.exploration.base)
      s.exploration.settingsRevision=config.exploration.revision or 0
      s.exploration.configuredBounds=s.exploration.configuredBounds or U.copy(config.exploration.bounds)
      if s.exploration.bounds then config.exploration.bounds=U.copy(s.exploration.bounds); assert(E.validate(config.exploration)) end
    end
    function self:refresh()
      local ok,err=self.storage:refresh(); s.storageError=err
      if ok then s.resourceCounts=U.copy(self.storage.counts) else s.resourceCounts={} end
      lastStorage=clock(); return ok,err
    end
    function self:command(line)
      local args={}; for word in line:gmatch('%S+') do args[#args+1]=word end
      if args[1]=='exploration' then
        assert((config.exploration or {}).enabled,'Run setup exploration on the controller first')
        if args[2]=='status' or args[2]==nil then s.view='exploration';s.explorationLines=nil; return true,'Exploration '..(s.exploration.paused and 'paused' or 'enabled') end
        if args[2]=='sector' or args[2]=='retry' then
          assert(#args==3,'Usage: exploration '..args[2]..' <sectorId>')
          local r=s.exploration.sectors[args[3]];if not r then return false,'unknown exploration sector' end
          if args[2]=='retry' then local ok,why=self.jobs:retrySector(args[3]);if not ok then return false,why end end
          s.explorationLines=E.describe(args[3],r);s.view='exploration';return true,table.concat(s.explorationLines,'; ')
        end
        if args[2]=='pause' or args[2]=='resume' then
          local previous=s.exploration.paused; s.exploration.paused=args[2]=='pause'
          local ok,err=save(); if not ok then s.exploration.paused=previous; return false,err end
          return true,'Exploration '..args[2]
        end
        if args[2]=='expand' then
          local radius=tonumber(args[3]); assert(#args==3 and U.integer(radius) and radius>0,'Usage: exploration expand <positive radius>')
          local chosen=U.copy(config.exploration); local b=chosen.base
          local old=chosen.bounds; chosen.bounds={min={x=b.x-radius,y=old.min.y,z=b.z-radius},max={x=b.x+radius,y=old.max.y,z=b.z+radius}}
          for _,a in ipairs({'x','z'}) do assert(chosen.bounds.min[a]<=old.min[a] and chosen.bounds.max[a]>=old.max[a],'Expansion cannot shrink existing territory') end
          local valid,why=E.validate(chosen); assert(valid,why)
          local previous=s.exploration.bounds; s.exploration.bounds=U.copy(chosen.bounds)
          local ok,err=save(); if not ok then s.exploration.bounds=previous; return false,err end
          config.exploration.bounds=chosen.bounds; s.view='exploration'; return true,'Expanded search boundary; keep the entire area loaded and within modem range'
        end
        return false,'exploration status|sector <id>|retry <id>|expand <radius>|pause|resume'
      elseif args[1]=='mine' then
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
      for _,g in pairs((s.exploration or {}).groups or {}) do
        for _,id in ipairs(g.tripIds) do
          local j=s.jobs[id]
          if j and not j.physicalComplete then referenced[id]=true end
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
        if app.chunks then app.chunks:reconcile() end
        for id in pairs(removed) do s.jobs[id]=nil end
        local ok,err=save()
        if not ok then
          for id,job in pairs(removed) do s.jobs[id]=job end
          for _,job in ipairs(stamped) do job.completedAt=nil end
          return false,err
        end
      end
      if count>0 then
        for _,g in pairs((s.exploration or {}).groups or {}) do
          local ids={}; for _,id in ipairs(g.tripIds) do if s.jobs[id] then ids[#ids+1]=id end end; g.tripIds=ids
        end
        local ok,err=save(); if not ok then return false,err end
      end
      return true,count
    end
    function self:tick()
      local retired,why=self:retireCompleted(); if not retired then return false,why end
      if #config.storageInventories>0 and clock()-lastStorage>=config.checkpointInterval then self:refresh() end
      if not self.storage.valid then return true end
      if s.assignmentRecovery then return true end
      if clock()-lastSend<config.heartbeatInterval then return true end
      if (config.exploration or {}).enabled then
        local ready=self:refresh(); if not ready then return true end
      end
      for _,j in pairs(s.jobs) do
        local g=j.exploration and s.exploration.groups[j.exploration.groupId]
        if g and not j.physicalComplete and (g.paused or s.exploration.paused or not (config.exploration or {}).enabled) then send(j.workerId,'mine_return',{jobId=j.id}) end
      end
      local job=self.jobs:assign(s.workers,self.storage.counts)
      if job then
        lastSend=clock()
        send(job.workerId,'mine_assign',{jobId=job.id,item=job.item,quantity=job.quantity,loadedArea=job.loadedArea,miningArea=job.miningArea,miningResources=job.miningResources,exploration=job.exploration,returnRequested=job.exploration and (s.exploration.paused or s.exploration.groups[job.exploration.groupId].paused or not (config.exploration or {}).enabled) or nil})
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
    if config.mining.enabled or s.currentTask and s.currentTask.exploration then
      self.inventory=require('autobuilder.storage.inventory').new(e.turtle,{reservedSlots={15,16},fuelSlot=15,fuel=config.fuel})
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
      if not config.mining.enabled and not (s.currentTask and s.currentTask.exploration) then return false,'mining disabled on worker' end
      local p=m.payload
      if m.type=='mine_assign' then
        if p.exploration then
          if not config.capabilities.explorationV1 or not E.geometry(p.exploration) then return false,'exploration capability or geometry invalid' end
          if not same(p.exploration.depot,{x=config.depot.x,y=config.depot.y,z=config.depot.z}) then return false,'assigned depot differs from worker depot' end
          if not same(p.exploration.exitRoute,config.mining.exitRoute) then return false,'assigned clear exit differs from worker config' end
        end
        if not Materials.accepts(config.mining.resources,p.item) then return false,'assigned item is outside configured mining resources' end
        if p.miningResources~=nil and not Materials.sameResources(p.miningResources,config.mining.resources) then return false,'assigned mining resources differ from local config' end
        if s.completedMining[p.jobId] then
          local r=s.completedMining[p.jobId]
          return send(sender,'mine_progress',{jobId=p.jobId,phase='completed',delivered=type(r)=='table' and r.delivered or r,held=0,exploration=type(r)=='table' and r.exploration or nil})
        end
        if require('autobuilder.core.receipts').archived(s,'completedMining',p.jobId) then return false,'Old acknowledged mine was archived; restore the matching controller checkpoint' end
        local covered,why=require('autobuilder.core.chunks').workerAccept(config,s,{id=p.jobId,type='MINE',miningArea=p.miningArea,exploration=p.exploration,loadedArea=p.loadedArea})
        if not covered then return false,why end
        if s.currentTask then
          if s.currentTask.id==p.jobId and s.currentTask.item==p.item and s.currentTask.quantity==p.quantity and same(s.currentTask.exploration,p.exploration) then return true end
          return false,'worker already owns a different task'
        end
        s.currentTask={loadedArea=U.copy(p.loadedArea),id=p.jobId,type='MINE',item=p.item,quantity=p.quantity,returnRequested=p.returnRequested,exploration=p.exploration and E.cleanGeometry(p.exploration),phase='setup',delivered=0,miningArea=U.copy(p.miningArea),miningResources=U.copy(p.miningResources or config.mining.resources or {})}
        s.status='setup'; local ok,err=save()
        if not ok then s.currentTask=nil; s.status='idle'; return false,err end
        return true
      elseif m.type=='mine_ack' then
        if s.currentTask and s.currentTask.id==p.jobId and s.currentTask.phase=='completed' then
          local receipt=s.currentTask.exploration and {delivered=s.currentTask.delivered,exploration=E.cleanReport(s.currentTask.explorationProgress)} or s.currentTask.delivered
          require('autobuilder.core.receipts').record(s,'completedMining',p.jobId,receipt); s.currentTask=nil; self.miner=nil; s.status='idle'; save(); return true
        end
        return false,'unexpected job acknowledgement'
      elseif m.type=='mine_return' and s.currentTask and s.currentTask.id==p.jobId and s.currentTask.exploration then return miner():requestReturn()
      elseif m.type=='mine_resume' and s.currentTask and s.currentTask.id==p.jobId then
        return miner():resume()
      end
      return false,'unexpected mining message'
    end
    function self:tick()
      if s.currentTask and (not s.currentTask.type or s.currentTask.type=='MINE') and (config.mining.enabled or s.currentTask.exploration) and clock()-lastSend>=config.heartbeatInterval then
        lastSend=clock(); local task=s.currentTask
        local err=task.error and tostring(task.error):gsub('[%c]',' '):sub(1,512)
        send(config.controllerId,'mine_progress',{jobId=task.id,phase=task.phase or 'blocked',
          delivered=task.delivered or 0,held=self.inventory:getCount(task.item),error=err,assignedQuantity=task.quantity,exploration=task.exploration and (task.explorationProgress or {cursor=task.exploration.cursor,clearedRouteCount=0,observations={}})})
      end
      return true
    end
    function self:resumeFuelTask() return miner():resume() end
    function self:poseRecovered()
      if (config.mining.enabled or s.currentTask and s.currentTask.exploration) and s.currentTask and not s.currentTask.paused
        and (not s.currentTask.type or s.currentTask.type=='MINE') and s.currentTask.phase=='blocked'
        and (s.currentTask.poseBlocked or s.currentTask.error=='trusted position and heading required')
        and s.position.known and not s.position.pending and not s.position.uncertain and U.heading(s.position.heading) then
        local ok,err=miner():resume()
        if ok then s.currentTask.poseBlocked=nil;s.status=s.currentTask.phase;save() else app:report('WARN',err) end
      end
    end
    function self:step()
      if not s.currentTask or not config.mining.enabled and not s.currentTask.exploration or s.currentTask.phase=='completed' then return true end
      if not Materials.accepts(config.mining.resources,s.currentTask.item)
        or s.currentTask.miningResources~=nil and not Materials.sameResources(s.currentTask.miningResources,config.mining.resources) then
        if s.currentTask.phase~='blocked' then s.currentTask.resumePhase=s.currentTask.phase end
        s.currentTask.phase='blocked'; s.currentTask.error='Assigned mining resources differ from local config; restore original resources'; save(); return true
      end
      if s.currentTask.miningArea and not s.currentTask.exploration then
        for _,edge in ipairs({'min','max'}) do for _,axis in ipairs({'x','y','z'}) do
          if s.currentTask.miningArea[edge][axis]~=config.mining.bounds[edge][axis] then
            s.currentTask.phase='blocked'; s.currentTask.error='Assigned mining area differs from local config; restore original bounds'; save(); return true
          end
        end end
      end
      local m=miner()
      if s.currentTask.exploration and not config.mining.enabled then m:requestReturn() end
      if s.currentTask.phase=='blocked' and s.motionReservation and s.motionReservation.granted
        and s.motionReservation.jobId==s.currentTask.id and tostring(s.currentTask.error):find('movement reservation pending',1,true) then m:resume() end
      if s.currentTask.phase=='blocked' then return true end
      local ok,err=m:step(); s.status=s.currentTask.phase
      if not ok then app:report('WARN','Mining job '..s.currentTask.id..': '..tostring(err)) end
      save(); return true
    end
  end
  return self
end
return M
