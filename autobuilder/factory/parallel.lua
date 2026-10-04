local U=require('autobuilder.core.util')
local F=require('autobuilder.factory.factory')
local Q=require('autobuilder.core.workflows')
local M={}
function M.new(app,config,e,queue,production)
  local save=function() return app:save() end
  local capacity=require('autobuilder.storage.capacity').new(app.state,save)
  local self={capacity=capacity,cursor=0}
  local function now() return e.os and e.os.epoch and e.os.epoch('utc')/1000 or 0 end
  local function jobsFor(r)
    local jobs={}
    for _,j in pairs(queue.state.jobs) do
      if j.privateStation and not j.cancelled and j.productionRequest==r.id and j.productionOperation==r.operation and (j.productionGeneration or 0)==(r.replans or 0) then jobs[#jobs+1]=j end
    end
    table.sort(jobs,function(a,b) return a.productionBatch<b.productionBatch end); return jobs
  end
  local function claimed(j)
    return j.workerId or j.privateReady or capacity.state.leases[j.id] or production.ledger.state.leases[j.id]
      or j.factoryFlow and (j.factoryFlow.stage.intent or j.factoryFlow.collect.intent)
  end
  local function coverage(r,op)
    local offset,limit=0,op.batches
    for _,j in ipairs(jobsFor(r)) do if claimed(j) then
      if j.productionBatch>offset then limit=j.productionBatch;break end
      offset=j.productionBatch+j.batches
    end end
    return offset,limit
  end
  function self:owns(r) return #jobsFor(r)>0 end
  function self:schedule(r,op)
    if not r.privateCraft then F.commit(r,save,function() r.privateCraft=true end) end
    local jobs=jobsFor(r); local scheduled,complete,why=0,true,nil
    local last=0
    for _,j in ipairs(jobs) do
      if j.status~='completed' then why=why or j.error or j.stockError end
      if claimed(j) then
      assert(j.productionBatch>=last,'private craft batches overlap')
      last=j.productionBatch+j.batches;assert(last<=op.batches,'private craft batch exceeds operation')
      scheduled=scheduled+j.batches
      if j.status~='completed' then complete=false; why=why or j.error or j.stockError end
    end end
    assert(scheduled<=op.batches,'private craft operation over-assigned')
    if scheduled==op.batches and complete then
      for _,j in ipairs(jobs) do if not claimed(j) then F.commit(j,save,function() j.cancelled=true;j.status='completed';j.error=nil end) end end
      F.commit(r,save,function() r.operation=r.operation+1; r.privateCraft=nil; r.status='running'; r.error=nil end)
      return
    end
    for _,station in ipairs(config.craftingStations) do
      if scheduled>=op.batches then break end
      local w=app.state.workers[tostring(station.workerId)]; local t=w and w.telemetry
      if w and w.online and t and t.status=='idle' and not t.task and t.capabilities and t.capabilities.isolatedCraftingV1
        and require('autobuilder.workers.health').eligible(t,{type='CRAFT'}) and not Q.workerBusy(app.state,w.id) then
        local occupied=false
        for _,j in pairs(queue.state.jobs) do
          if j.privateStation and j.status~='completed' then
            for _,field in ipairs({'buffer','input','output'}) do
              for _,other in ipairs({'buffer','input','output'}) do if j.privateStation[field]==station[other] then occupied=true end end
            end
          end
        end
        if not occupied then
          local offset,limit=coverage(r,op)
          local n=math.min(config.craftingBatchSize,limit-offset); local inputs={}
          for item,count in pairs(op.inputs) do inputs[item]=count/op.batches*n end
          local j=queue:submit('CRAFT',{item=op.item,batches=n,quantity=op.quantity/op.batches*n,
            preferredWorker=w.id,privateStation=U.copy(station),privateReady=false,stockInputs=inputs,
            stockOutputs={[op.item]=op.quantity/op.batches*n},productionRequest=r.id,productionOperation=r.operation,
            productionGeneration=r.replans or 0,productionBatch=offset},{},
            r.id..':op:'..r.operation..':craft:'..offset..':attempt:'..(queue.state.sequence+1))
          scheduled=scheduled+j.batches; complete=false
        end
      end
    end
    r.privateCraft=true; r.status=why and 'blocked' or 'running'
    r.error=why or (scheduled<op.batches and 'waiting for an idle private Crafty station' or nil); assert(save())
  end
  local function counts(inv)
    local out={}
    for _,item in pairs(inv) do assert(not item.nbt,'private crafting inventory contains NBT items'); out[item.name]=(out[item.name] or 0)+item.count end
    return out
  end
  local function empty(name) assert(not next(F.list(e,name)),'private crafting inventory must be empty: '..name) end
  local function reserve(job)
    local old=capacity.state.leases[job.id];if old then assert(old.status=='held','craft capacity already released');return old end
    local stock=production.ledger.state.leases[job.id]
    -- Retire only never-started legacy production claims. Their closed IDs and
    -- immutable quantities remain auditable; the scheduler fills the interval.
    if stock and job.productionRequest and not job.workerId and not job.privateReady then
      local f=job.factoryFlow
      assert(not f or not (f.stage.intent or f.collect.intent or next(f.stage.withdrawn or {}) or f.stage.stockSequence or f.collect.stockSequence),'legacy craft journal still owned')
      local before=U.copy(job)
      local ok,why=pcall(function()
        require('autobuilder.storage.ledger').new(app.state,function() return true end):cancel(job.id)
        job.cancelled=true;job.status='completed';job.error='unstarted legacy batch replanned for capacity';assert(save())
      end)
      if not ok then
        production.ledger.state.leases[job.id]=stock
        for k in pairs(job) do job[k]=nil end;for k,v in pairs(before) do job[k]=v end;error(why,0)
      end
      return nil,'retired'
    end
    local function eligible()
      assert(not job.paused and job.status~='completed','craft preference paused or retired during observation')
      local worker=app.state.workers[tostring(job.preferredWorker)];local t=worker and worker.telemetry
      assert(worker and worker.online and t and t.status=='idle' and not t.task
        and t.capabilities and t.capabilities.isolatedCraftingV1
        and not Q.workerBusy(app.state,job.preferredWorker,job.id),'waiting for available preferred Crafty worker')
      local healthy,healthError=require('autobuilder.workers.health').eligible(t,job);assert(healthy,healthError)
      local allowed,why=Q.factoryCanRun(app.state,job,true);assert(allowed,why)
      allowed,why=require('autobuilder.core.scaling').canAssign(app.state,config,job,worker,app.mining.storage.counts,now());assert(allowed,why)
    end
    eligible()
    local observed=require('autobuilder.storage.capacity').observe(e)
    local station=job.privateStation
    for _,field in ipairs({'buffer','input','output'}) do
      assert(not next(F.list(observed,station[field])),'private crafting inventory must be empty: '..station[field])
    end
    local limits={}
    for item in pairs(job.stockInputs) do
      local sources=F.sources(observed,config,item);local source=assert(sources[1],'reserved craft ingredient missing: '..item)
      local detail=observed.peripheral.call(source.name,'getItemDetail',source.slot)
      assert(detail and U.integer(detail.maxCount) and detail.maxCount>0,'ingredient stack limit unavailable')
      limits[item]=detail.maxCount
    end
    local sources=F.sources(observed,config,job.item);local outputLimit
    if sources[1] then local detail=observed.peripheral.call(sources[1].name,'getItemDetail',sources[1].slot);outputLimit=detail and detail.maxCount end
    assert(app.mining:refresh())
    local max=job.batches;local offset=job.productionBatch
    if job.productionRequest and not stock then
      max=math.min(max,config.craftingBatchSize)
      local r=assert(queue.state.requests[job.productionRequest],'craft request missing')
      local op=assert(r.plan.operations[job.productionOperation],'craft operation missing')
      local limit;offset,limit=coverage(r,op);max=math.min(max,limit-offset)
      if max==0 then F.commit(job,save,function() job.cancelled=true;job.status='completed';job.error=nil end);return nil,'retired' end
    end
    if not stock then for item,count in pairs(job.stockInputs) do
      local available=production.ledger:view(item,app.mining.storage.counts).available-(config.turtleFuelReserveItems[item] or 0)
      max=math.min(max,math.floor(math.max(0,available)/(count/job.batches)))
    end end
    assert(max>0,'insufficient unreserved craft ingredients')
    local function trial(n)
      local inputs={};for item,count in pairs(job.stockInputs) do inputs[item]=count/job.batches*n end
      local quantity=job.quantity/job.batches*n;local outputs={[job.item]=quantity}
      local combined=U.copy(inputs);combined[job.item]=(combined[job.item] or 0)+quantity
      local combinedLimits=U.copy(limits);combinedLimits[job.item]=outputLimit
      local outputLimits=outputLimit and {[job.item]=outputLimit} or {}
      local why='shared output storage is not configured'
      for _,destination in ipairs(config.storageInventories) do
        local ok,lease,reason=pcall(capacity.preview,capacity,job.id,{
          {inventory=station.buffer,items=combined,limits=combinedLimits,exclusive=true},
          {inventory=station.input,items=inputs,limits=limits,exclusive=true},
          {inventory=station.output,items=outputs,limits=outputLimits,exclusive=true},
          {inventory=destination,items=outputs,limits=outputLimits}},observed)
        if ok and lease then return lease,inputs,outputs,quantity end
        why=ok and reason or lease
      end
      return nil,why
    end
    local n=max;local lease,inputs,outputs,quantity=trial(n)
    if job.productionRequest and not stock then
      -- At most64 recipe batches. Reuse native observations while shrinking;
      -- counts and slots are still exclusively observed under inventoryAction.
      while not lease and n>1 do n=n-1;lease,inputs,outputs,quantity=trial(n) end
    else assert(n==job.batches,'insufficient unreserved craft ingredients') end
    assert(lease,inputs)
    eligible() -- Peripheral observations yield; ownership and pause may have changed.
    local before=U.copy(job)
    local ok,why=pcall(function()
      capacity.state.leases[job.id]=lease
      job.productionBatch=offset;job.batches=n;job.quantity=quantity;job.stockInputs=inputs;job.stockOutputs=outputs
      assert(require('autobuilder.storage.ledger').new(app.state,function() return true end):reserve(
        job.id,inputs,outputs,app.mining.storage.counts,{protected=config.turtleFuelReserveItems}))
      job.factoryFlow={stage={},collect={}};assert(save())
    end)
    if not ok then
      capacity.state.leases[job.id]=nil;production.ledger.state.leases[job.id]=stock
      for k in pairs(job) do job[k]=nil end;for k,v in pairs(before) do job[k]=v end;error(why,0)
    end
    return lease
  end
  local function advance(job)
    local flow=job.factoryFlow
    if flow and flow.stage.intent then return F.reconcileTransfer(flow.stage,e,save) end
    if flow and flow.collect.intent then return F.reconcileTransfer(flow.collect,e,save) end
    local allowed,why=Q.factoryCanRun(app.state,job,true); if not allowed then error(why,0) end
    local station=job.privateStation
    if job.workerFinished then
      empty(station.input); empty(station.output)
      local inv=F.list(e,station.buffer); local delivered=flow.collect.delivered or 0
      local expected=delivered<job.quantity and {[job.item]=job.quantity-delivered} or {}
      assert(F.equal(counts(inv),expected),'private crafting output changed before collection')
      if delivered==job.quantity then
        capacity:release(job.id)
        F.commit(job,save,function() job.status='completed'; job.error=nil; job.factoryCompletedAt=now() end)
        return 'complete'
      end
      local lease=assert(capacity.state.leases[job.id],'missing craft capacity claim')
      assert(lease.status=='held','craft output capacity already released')
      local destination=lease.contract[#lease.contract].inventory
      local offset=delivered; local allocation
      for _,a in ipairs(lease.nodes[destination].allocations) do
        if offset<a.count then allocation=a; break end; offset=offset-a.count
      end
      assert(allocation,'craft output exceeds reserved capacity')
      local sources=F.sources(e,{storageInventories={station.buffer}},job.item); local source=assert(sources[1])
      local detail=e.peripheral.call(station.buffer,'getItemDetail',source.slot)
      local to=F.list(e,destination)[allocation.slot]
      assert(not to or to.name==job.item and not to.nbt,'reserved output slot was contaminated')
      local limit=e.peripheral.call(destination,'getItemLimit',allocation.slot)
      assert(U.integer(limit) and limit>=0 and detail and U.integer(detail.maxCount) and detail.maxCount>0,'invalid output capacity')
      local room=math.min(limit,detail.maxCount)-(to and to.count or 0)
      assert(room>0,'reserved output slot is full')
      return F.transfer(flow.collect,e,save,station.buffer,source.slot,destination,allocation.slot,job.item,
        math.min(allocation.count-offset,source.count,room),station.buffer,-1,'delivered')
    end
    local lease=reserve(job);if not lease then return 'retired' end;flow=job.factoryFlow
    empty(station.input); empty(station.output)
    local inv=F.list(e,station.buffer)
    assert(F.equal(counts(inv),flow.stage.withdrawn or {}),'private crafting input changed during staging')
    local items={}; for item in pairs(job.stockInputs) do items[#items+1]=item end; table.sort(items)
    for _,item in ipairs(items) do
      local left=job.stockInputs[item]-((flow.stage.withdrawn or {})[item] or 0)
      if left>0 then
        local sources=F.sources(e,config,item); local source=assert(sources[1],'reserved craft input is unavailable: '..item)
        local detail=e.peripheral.call(source.name,'getItemDetail',source.slot)
        assert(detail and U.integer(detail.maxCount) and detail.maxCount>0,'ingredient stack limit unavailable')
        for _,a in ipairs(lease.nodes[station.buffer].allocations) do if a.item==item then
          local stack=inv[a.slot]; local room=math.min(a.count,detail.maxCount)-(stack and stack.count or 0)
          if room>0 then return F.transfer(flow.stage,e,save,source.name,source.slot,station.buffer,a.slot,item,
            math.min(left,source.count,room),station.buffer,1,nil,nil,true) end
        end end
        error('reserved private input capacity is full',0)
      end
    end
    F.commit(job,save,function() job.privateReady=true; job.status='queued'; job.error=nil; job.factoryStartedAt=now() end)
    return 'ready'
  end
  function self:step()
    local jobs={}
    for _,j in pairs(queue.state.jobs) do
      local f=j.factoryFlow
      if j.privateStation and j.status~='completed' and (not j.paused or f and (f.stage.intent or f.collect.intent))
        and (not j.privateReady or j.workerFinished) then jobs[#jobs+1]=j end
    end
    if #jobs==0 then return false end
    table.sort(jobs,function(a,b) return a.id<b.id end)
    for _=1,#jobs do
      self.cursor=self.cursor%#jobs+1; local job=jobs[self.cursor]
      local flow=job.factoryFlow
      local pending=flow and (flow.stage.intent or flow.collect.intent)
      local allowed,reason=Q.factoryCanRun(app.state,job,true)
      if pending or allowed then
        local status,why=F.protect(function() return advance(job) end)
        if status=='blocked' then job.error=why; job.status='blocked'; assert(save()) end
        production:syncClaims(false)
        flow=job.factoryFlow
        return status~='blocked' or flow and (flow.stage.intent or flow.collect.intent)~=nil
      elseif job.error~=reason then job.error=reason; assert(save()) end
    end
    -- A waiting private batch must not starve the existing shared owner whose
    -- completion will make that batch eligible.
    return false
  end
  function self:describe()
    local active,queued,delivered=0,0,0
    local rows={}
    for _,j in pairs(queue.state.jobs) do if j.privateStation then
      local id=j.privateStation.id; local row=rows[id] or {delivered=0,measured=0,seconds=0}; rows[id]=row
      local n=j.factoryFlow and j.factoryFlow.collect.delivered or 0; delivered=delivered+n
      row.delivered=row.delivered+n
      if j.status~='completed' then
        row.job=j
        if j.workerId then active=active+1 else queued=queued+1 end
      elseif j.factoryStartedAt and j.factoryCompletedAt and j.factoryCompletedAt>j.factoryStartedAt then
        row.measured=row.measured+n; row.seconds=row.seconds+j.factoryCompletedAt-j.factoryStartedAt
      end
    end end
    local lines={'FACTORY stations='..#config.craftingStations..' active='..active..' queued='..queued..' delivered='..delivered}
    for _,station in ipairs(config.craftingStations) do
      local row=rows[station.id] or {}; local j=row.job
      local rate=(row.seconds or 0)>0 and string.format('%.2f/s',row.measured/row.seconds) or 'unmeasured'
      lines[#lines+1]=station.id..' worker='..station.workerId..' '..(j and j.status or 'idle')..' collected='..(row.delivered or 0)..' rate='..rate
      if j then
        local reason=j.error or j.stockError or (not j.privateReady and 'reserving/staging inputs' or j.workerFinished and 'collecting output' or 'crafting private batch')
        lines[#lines+1]=j.id..' '..j.item..' '..(j.factoryFlow and j.factoryFlow.collect.delivered or 0)..'/'..j.quantity..' '..reason
      end
    end
    app.state.factoryLines=lines; return table.concat(lines,'; ')
  end
  return self
end
return M
