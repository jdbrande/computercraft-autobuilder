local U=require('autobuilder.core.util')
local Coordination=require('autobuilder.core.workflows')
local M={}
function M.new(app,config,e,network,clock)
  if config.role=='worker' then return require('autobuilder.workers.executor').new(app,config,e,network,clock) end
  local queue=require('autobuilder.core.workflows').new(app.state,function() return app:save() end,clock,app.state.id,app.chunks,config)
  local production=require('autobuilder.core.production_service').new(app,config,e,queue)
  local fuel=require('autobuilder.core.fuel_service').new(app,config,e,queue,production,clock)
  local rescue=require('autobuilder.core.fuel_rescue_service').new(app,config,e,queue,production,network,clock)
  local recovery=require('autobuilder.core.inventory_recovery_service').new(app,config,e,queue,production,network,clock)
  local projects=require('autobuilder.blueprint.projects').new(app,config,e,queue,production)
  local cathedral=require('autobuilder.blueprint.cathedral').new(app,config,e,projects)
  local infrastructure=require('autobuilder.core.infrastructure').new(app,config,e,queue)
  local self={recovery=recovery,queue=queue,production=production,fuel=fuel,rescue=rescue,projects=projects,infrastructure=infrastructure,cathedral=cathedral}; local last=-math.huge
  local function send(owner,kind,payload) return network:send(owner,kind,payload) end
  function self:restorePose(worker)
    local p=worker.telemetry and worker.telemetry.poseRecovery
    if not p or not p.granted then return true end
    local j=queue.state.jobs[p.jobId] or (app.state.jobs or {})[p.jobId]
    if p.stage=='settled' then
      if not j or not j.poseRecovery or j.poseRecovery.status=='settled' then return true end
      return queue:finishPose(worker.id,p.jobId,p.sequence,p.origin)
    end
    if j and j.workerId==worker.id and j.poseRecovery and j.poseRecovery.status=='settled'
      and j.poseRecovery.sequence==p.sequence and U.distance(j.poseRecovery.origin,p.origin)==0 and p.stage=='settling' then return true end
    if not worker.online then return false,'waiting for recovery owner to reconnect' end
    return queue:reservePose(worker.id,p.jobId,p.sequence,p.origin,app.state.workers,true)
  end
  function self:command(line)
    local args={}; for word in line:gmatch('%S+') do args[#args+1]=word end
    if args[1]=='fleet' then
      local Scaling=require('autobuilder.core.scaling')
      if args[2]=='limit' then
        assert(#args==5,'Usage: fleet limit <role> <minimum> <maximum>')
        Scaling.setLimits(app.state,config,args[3],tonumber(args[4]),tonumber(args[5]),function() return app:save() end)
      else assert(#args==1 or #args==2 and args[2]=='status','Usage: fleet status | fleet limit <role> <minimum> <maximum>') end
      app.state.view='fleet';app.state.fleetLines=Scaling.describe(app.state,config,app.mining.storage.counts,clock())
      return true,table.concat(app.state.fleetLines,'; ')
    elseif args[1]=='fuel' then app.state.view='fuel'; return true,fuel:describe()
    elseif args[1]=='worker' and args[2]=='return' then
      assert(#args==3,'Usage: worker return <id>');return true,production.returns:request(tonumber(args[3])).id
    elseif args[1]=='worker' and args[2]=='recover' then
      assert(#args==3,'Usage: worker recover <id>');return true,recovery:request(tonumber(args[3])).id
    elseif args[1]=='recoveries' then return true,recovery:describe()
    elseif args[1]=='returns' then return true,production.returns:describe()
    elseif args[1]=='logistics' then app.state.view='logistics';return true,production.logistics:describe()
    elseif args[1]=='haul' then
      assert(#args==5,'Usage: haul <item> <count> <source-node> <destination-node>')
      local r=production.logistics:request(args[2],tonumber(args[3]),args[4],args[5]);return true,r.id
    elseif args[1]=='factory' then app.state.view='factory'; return true,production.parallel:describe()
    elseif args[1]=='production' or args[1]=='8' then app.state.view='production'; return true,'Material team: different workers gather each missing resource'
    elseif args[1]=='resource' then
      assert(#args==2,'Usage: resource <namespaced-item>')
      return true,production:describe(args[2])
    elseif args[1]=='cathedral' then return cathedral:command(args)
    elseif args[1]=='build' then return projects:command(args)
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
    local p=m.payload
    if m.type=='task_inventory_status' then return recovery:handle(sender,p) end
    if m.type=='task_fuel_status' then return rescue:handle(sender,p) end
    local j=queue.state.jobs[p.jobId] or (app.state.jobs or {})[p.jobId]
    if j and not j.workerId and m.type=='task_progress' then queue:recoverOwner(sender,p,app.state.workers) end
    if not j or j.workerId~=sender then return false,'unknown task or owner' end
    if m.type=='task_progress' then
      if p.stockReceipt then local ok,err=production:acceptReceipt(j,p.stockReceipt); if not ok then return false,err end end
      local ok,err=queue:progress(sender,p); if not ok then return false,err end
      if p.phase~='paused' and p.phase~='blocked' then j.resumeRequested=nil end
      if (j.returning or j.type=='RECOVER_CARGO') and j.workerFinished and j.status~='completed' then return true end
      if j.status=='completed' or j.workerFinished then
        j.completedAt=j.completedAt or clock()
        j.blocks=nil; app:save(); return send(sender,'task_ack',{jobId=j.id})
      end
      return true
    elseif m.type=='task_pose_reserve' then
      local granted,why=queue:reservePose(sender,j.id,p.sequence,p.origin,app.state.workers)
      send(sender,'task_pose_grant',{jobId=j.id,sequence=p.sequence,origin=U.copy(p.origin),granted=granted==true,reason=why and tostring(why):sub(1,512)})
      return granted,why
    elseif m.type=='task_pose_done' then
      local ok,why=queue:finishPose(sender,j.id,p.sequence,p.origin)
      if ok then return send(sender,'task_pose_ack',{jobId=j.id,sequence=p.sequence,origin=U.copy(p.origin)}) end
      return false,why
    elseif m.type=='task_reserve' then
      local granted,err,blocker=queue:reserve(sender,j.id,p.from,p.target,app.state.workers,p.work)
      if not granted and not p.work and blocker then
        local w=app.state.workers[tostring(blocker)];local t=w and w.telemetry
        if w and w.online and t and t.status=='idle' and not t.task and not Coordination.workerBusy(app.state,w.id)
          and (t.capabilities or {}).returnCargoV1 and t.position and t.position.known
          and U.position(t.position) and U.position(t.depot) and U.distance(t.position,p.target)==0
          and U.distance(t.position,t.depot)>0 then
          production.returns:request(w.id,'traffic:'..j.id..':'..(queue.state.returnSequence+1))
        end
      end
      send(sender,'task_grant',{jobId=j.id,target=p.target,granted=granted==true,work=p.work,reason=err and tostring(err):sub(1,512)}); return granted,err
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
  function self:preflight()
    for _,jobs in ipairs({app.state.jobs or {},queue.state.jobs}) do
      for _,j in pairs(jobs) do require('autobuilder.core.scaling').record(app.state,j,function() return app:save() end,clock()) end
    end
    local _,events=require('autobuilder.core.scaling').update(app.state,config,app.mining.storage.counts,clock(),function() return app:save() end)
    for _,event in ipairs(events) do app:report('INFO','Fleet role='..event.role..' target='..event.target..' active='..event.active..' reason='..event.reason) end
    if app.state.view=='fleet' then app.state.fleetLines=require('autobuilder.core.scaling').describe(app.state,config,app.mining.storage.counts,clock()) end
    if config.automation.enabled then fuel:tick(); rescue:tick();production:inventoryAction(function() recovery:tick() end) end
  end
  function self:tick()
    if not config.automation.enabled then return true end
    if app.state.assignmentRecovery then
      local ready=true
      for _,w in pairs(app.state.workers) do
        if not w.online then ready=false end
        if w.online and not self:restorePose(w) then ready=false end
        local pose=w.telemetry and w.telemetry.poseRecovery
        if pose and pose.stage=='ready' and w.telemetry.controllerBoot~=app.state.boot then ready=false end
        local task=w.telemetry and w.telemetry.task
        if task then
          local j=queue.state.jobs[task] or (app.state.jobs or {})[task]
          if not j or j.workerId~=w.id then ready=false end
        end
      end
      if not ready then app.state.lastError='Backup recovery: waiting for every known worker to register and reconcile task ownership'; return true end
      app.state.assignmentRecovery=nil; app:save()
    end
    if app.state.view=='forecast' then projects:forecast() end
    if app.state.view=='fuel' then fuel:describe() end
    if app.state.view=='logistics' then production.logistics:describe() end
    if app.state.view=='factory' then production.parallel:describe() end
    production:tick(); projects:tick(); infrastructure:tick(); cathedral:tick()
    production:syncClaims()
    if clock()-last<config.heartbeatInterval then return true end
    last=clock()
    for _,j in pairs(queue.state.jobs) do
      if j.workerId and j.status~='completed' and not j.workerFinished then
        if j.paused then send(j.workerId,'task_pause',{jobId=j.id})
        elseif j.status=='paused' or j.resumeRequested then send(j.workerId,'task_resume',{jobId=j.id}) end
        if j.missingItem and j.supplyId and not j.paused and (config.supply.inventory~='' or #config.supplyStations>0) and j.type~='CRAFT'
          and not (queue.state.completedSupplyBatches or {})[j.supplyId] then
          self.supply=self.supply or require('autobuilder.storage.supply').new(queue.state,config,e,function() return app:save() end)
          local n,err,needsStock
          local staged=queue.state.supply
          local pendingProduction
          local supplyKey='supply:'..j.id..':'..j.missingItem
          for _,request in pairs(queue.state.requests) do
            if request.key==supplyKey and request.status~='completed' then pendingProduction=request.id;break end
          end
          local station=require('autobuilder.storage.supply').station(config,j.workerId)
          local worker=app.state.workers[tostring(j.workerId)];local t=worker and worker.telemetry
          if station.workerId and (not t or not (t.capabilities or {}).supplyStationV1 or not U.position(t.depot)
            or U.distance(t.depot,station.position)~=0 or station.side=='front' and t.depot.heading~=station.position.heading) then
            err='registered supply station requires a matching worker depot and supplyStationV1'
          elseif pendingProduction and not (staged and staged.jobId==j.supplyId and staged.owner==j.workerId and staged.offered) then
            -- Deposits can arrive before their acquisition group returns. Spending
            -- them now reopens the same stock target and mines a replacement.
            err='waiting for supply production '..pendingProduction
          elseif not Coordination.canOfferSupply(app.state,j) then
            -- Resend a prior grant without moving shared inventory. Its worker
            -- must be able to drain staging and release the production barrier.
            if staged and staged.jobId==j.supplyId and staged.owner==j.workerId and staged.offered and not staged.intent then n=staged.amount
            else err='supply waits for the active factory operation' end
          else n,err,needsStock=self.supply:offer(j.supplyId,j.workerId,j.missingItem,math.min(config.supply.batch,j.missingCount or config.supply.batch)) end
          if n and n>0 then send(j.workerId,'task_supply',{jobId=j.id,supplyId=j.supplyId,item=j.missingItem,count=n,station=station.workerId and station or nil})
          else
            j.supplyError=err
            -- A failed initial offer can claim an empty chest before discovering
            -- a shortage. Relinquish only an observed-empty, unoffered, journal-
            -- free stage so production can obtain stock for this same batch ID.
            local unoffered=queue.state.supply
            if unoffered and not unoffered.offered and not unoffered.intent and (unoffered.staged or 0)==0 then
              local destination=(unoffered.station or require('autobuilder.storage.supply').station(config,unoffered.owner)).inventory
              local ok,items=pcall(e.peripheral.call,destination,'list')
              if ok and type(items)=='table' and not next(items) then queue.state.supply=nil; app:save() end
            end
            if needsStock then
              production:request({[j.missingItem]=math.min(config.supply.batch,j.missingCount or config.supply.batch)},'supply:'..j.id..':'..j.missingItem,{stockOnly=j.stockOnly})
            end
          end
        end
      end
    end
    local j=queue:assign(app.state.workers)
    if j then send(j.workerId,'task_assign',{job=U.copy(j)}) end
    return true
  end
  function self:step() if config.automation.enabled then
    if production:inventoryAction(function() return recovery:step() end) then return true end
    if fuel:step() then return true end
    return production:step()
  end; return true end
  return self
end
return M
