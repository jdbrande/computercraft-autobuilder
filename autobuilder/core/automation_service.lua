local U=require('autobuilder.core.util')
local Coordination=require('autobuilder.core.workflows')
local M={}
function M.new(app,config,e,network,clock)
  if config.role=='worker' then return require('autobuilder.workers.executor').new(app,config,e,network,clock) end
  local queue=require('autobuilder.core.workflows').new(app.state,function() return app:save() end,clock,app.state.id)
  local production=require('autobuilder.core.production_service').new(app,config,e,queue)
  local projects=require('autobuilder.blueprint.projects').new(app,config,e,queue,production)
  local infrastructure=require('autobuilder.core.infrastructure').new(app,config,e,queue)
  local self={queue=queue,production=production,projects=projects,infrastructure=infrastructure}; local last=-math.huge
  local function send(owner,kind,payload) return network:send(owner,kind,payload) end
  function self:command(line)
    local args={}; for word in line:gmatch('%S+') do args[#args+1]=word end
    if args[1]=='build' then return projects:command(args)
    elseif args[1]=='request' then
      assert(#args==3,'Usage: request minecraft:stone_bricks 1000')
      assert(U.integer(tonumber(args[3])) and tonumber(args[3])>0,'Request quantity must be a positive integer')
      local r=production:request({[args[2]]=tonumber(args[3])},'request:'..args[2]); app.state.view='project'; return true,r.id
    elseif args[1]=='transport' then
      assert(#args==5,'Usage: transport <item> <count> <source-location> <destination-location>')
      local a,b=config.locations[args[4]],config.locations[args[5]]; assert(a and b,'Named source and destination required')
      local n=tonumber(args[3]); assert(U.integer(n) and n>0 and n<=1000000,'Invalid quantity')
      local j=queue:submit('TRANSPORT',{item=args[2],quantity=n,source=U.copy(a),destination=U.copy(b)},{})
      return true,j.id
    elseif args[1]=='expand' then
      app.state.view='project'; return infrastructure:request()
    elseif (args[1]=='resume' or args[1]=='pause') and queue.state.jobs[args[2]] then
      local j=queue.state.jobs[args[2]]; j.paused=args[1]=='pause'
      if j.workerId then send(j.workerId,j.paused and 'task_pause' or 'task_resume',{jobId=j.id})
      elseif not j.paused and j.type=='SMELT' then
        -- Hardware resumes only through the coordinated action loop.
        j.status='running'; j.error=nil
      end
      app:save(); return true,args[1]..' '..j.id
    elseif args[1]=='errors' then app.state.view='project'; return true,'Project and production errors'
    end
    return nil
  end
  function self:handle(sender,m)
    local worker=app.state.workers[tostring(sender)]
    if not worker or not worker.online or worker.boot~=m.boot then return false,'task message needs current worker registration' end
    if m.sequence<=math.max(worker.sequence or 0,worker.taskSequence or 0) then return false,'stale task packet' end
    worker.taskSequence=m.sequence
    local p=m.payload; local j=queue.state.jobs[p.jobId] or (app.state.jobs or {})[p.jobId]
    if j and not j.workerId and m.type=='task_progress' then queue:recoverOwner(sender,p,app.state.workers) end
    if not j or j.workerId~=sender then return false,'unknown task or owner' end
    if m.type=='task_progress' then
      local ok,err=queue:progress(sender,p); if not ok then return false,err end
      if p.phase~='paused' and p.phase~='blocked' then j.resumeRequested=nil end
      if j.status=='completed' then
        j.blocks=nil; app:save(); return send(sender,'task_ack',{jobId=j.id})
      end
      return true
    elseif m.type=='task_reserve' then
      local granted,err=queue:reserve(sender,j.id,p.from,p.target,app.state.workers)
      send(sender,'task_grant',{jobId=j.id,target=p.target,granted=granted==true}); return granted,err
    elseif m.type=='task_position' then return queue:position(sender,j.id,p.from,p.target)
    elseif m.type=='task_supply_done' then
      self.supply=self.supply or require('autobuilder.storage.supply').new(queue.state,config,e,function() return app:save() end)
      local owned=queue.state.supply
      if not owned or owned.jobId~=p.supplyId then return send(sender,'task_supply_ack',{jobId=j.id,supplyId=p.supplyId}) end
      if owned.owner~=sender then return false,'supply receipt owner mismatch' end
      local ok,err=self.supply:release(p.supplyId)
      if ok then return send(sender,'task_supply_ack',{jobId=j.id,supplyId=p.supplyId}) end
      return false,err
    end
    return false,'unexpected worker task packet'
  end
  function self:tick()
    if not config.automation.enabled then return true end
    if app.state.assignmentRecovery then
      local ready=true
      for _,w in pairs(app.state.workers) do
        if not w.online then ready=false end
        local task=w.telemetry and w.telemetry.task
        if task then
          local j=queue.state.jobs[task] or (app.state.jobs or {})[task]
          if not j or j.workerId~=w.id then ready=false end
        end
      end
      if not ready then app.state.lastError='Backup recovery: waiting for every known worker to register and reconcile task ownership'; return true end
      app.state.assignmentRecovery=nil; app:save()
    end
    production:tick(); projects:tick(); infrastructure:tick()
    if clock()-last<config.heartbeatInterval then return true end
    last=clock()
    for _,j in pairs(queue.state.jobs) do
      if j.workerId and j.status~='completed' then
        if j.paused then send(j.workerId,'task_pause',{jobId=j.id})
        elseif j.status=='paused' or j.resumeRequested then send(j.workerId,'task_resume',{jobId=j.id}) end
        if j.missingItem and j.supplyId and not j.paused and config.supply.inventory~='' and j.type~='CRAFT' then
          self.supply=self.supply or require('autobuilder.storage.supply').new(queue.state,config,e,function() return app:save() end)
          local n,err
          local staged=queue.state.supply
          if not Coordination.canOfferSupply(app.state,j) then
            -- Resend a prior grant without moving shared inventory. Its worker
            -- must be able to drain staging and release the production barrier.
            if staged and staged.jobId==j.supplyId and staged.owner==j.workerId and staged.offered and not staged.intent then n=staged.amount
            else err='supply waits for the active factory operation' end
          else n,err=self.supply:offer(j.supplyId,j.workerId,j.missingItem,math.min(config.supply.batch,j.missingCount or config.supply.batch)) end
          if n and n>0 then send(j.workerId,'task_supply',{jobId=j.id,supplyId=j.supplyId,item=j.missingItem,count=n})
          else
            j.supplyError=err
            -- A failed initial offer can claim an empty chest before discovering
            -- a shortage. Relinquish only an observed-empty, unoffered, journal-
            -- free stage so production can obtain stock for this same batch ID.
            local unoffered=queue.state.supply
            if unoffered and not unoffered.offered and not unoffered.intent and (unoffered.staged or 0)==0 then
              local ok,items=pcall(e.peripheral.call,config.supply.inventory,'list')
              if ok and type(items)=='table' and not next(items) then queue.state.supply=nil; app:save() end
            end
            production:request({[j.missingItem]=math.min(config.supply.batch,j.missingCount or config.supply.batch)},'supply:'..j.id..':'..j.missingItem)
          end
        end
      end
    end
    local j=queue:assign(app.state.workers)
    if j then send(j.workerId,'task_assign',{job=U.copy(j)}) end
    return true
  end
  function self:step() if config.automation.enabled then return production:step() end; return true end
  return self
end
return M
