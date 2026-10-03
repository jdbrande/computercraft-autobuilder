local U=require('autobuilder.core.util')
local F=require('autobuilder.factory.factory')
local Q=require('autobuilder.core.workflows')
local M={}
function M.new(app,config,e,queue,production)
  local save=function() return app:save() end
  local capacity=require('autobuilder.storage.capacity').new(app.state,save)
  local self={capacity=capacity,cursor=0}
  local function jobsFor(r)
    local jobs={}
    for _,j in pairs(queue.state.jobs) do
      if j.privateStation and j.productionRequest==r.id and j.productionOperation==r.operation and (j.productionGeneration or 0)==(r.replans or 0) then jobs[#jobs+1]=j end
    end
    table.sort(jobs,function(a,b) return a.productionBatch<b.productionBatch end); return jobs
  end
  function self:schedule(r,op)
    local jobs=jobsFor(r); local scheduled,complete,why=0,true,nil
    for _,j in ipairs(jobs) do
      assert(j.productionBatch==scheduled,'private craft batch coverage changed')
      scheduled=scheduled+j.batches
      if j.status~='completed' then complete=false; why=why or j.error or j.stockError end
    end
    assert(scheduled<=op.batches,'private craft operation over-assigned')
    if scheduled==op.batches and complete then
      F.commit(r,save,function() r.operation=r.operation+1; r.privateCraft=nil; r.status='running'; r.error=nil end)
      return
    end
    for _,station in ipairs(config.craftingStations) do
      if scheduled==op.batches then break end
      local w=app.state.workers[tostring(station.workerId)]; local t=w and w.telemetry
      if w and w.online and t and t.status=='idle' and not t.task and t.capabilities and t.capabilities.isolatedCraftingV1
        and not Q.workerBusy(app.state,w.id) then
        local occupied=false
        for _,j in pairs(queue.state.jobs) do
          if j.privateStation and j.status~='completed' then
            for _,field in ipairs({'buffer','input','output'}) do
              for _,other in ipairs({'buffer','input','output'}) do if j.privateStation[field]==station[other] then occupied=true end end
            end
          end
        end
        if not occupied then
          local n=math.min(config.craftingBatchSize,op.batches-scheduled); local inputs={}
          for item,count in pairs(op.inputs) do inputs[item]=count/op.batches*n end
          local j=queue:submit('CRAFT',{item=op.item,batches=n,quantity=op.quantity/op.batches*n,
            preferredWorker=w.id,privateStation=U.copy(station),privateReady=false,stockInputs=inputs,
            stockOutputs={[op.item]=op.quantity/op.batches*n},productionRequest=r.id,productionOperation=r.operation,
            productionGeneration=r.replans or 0,productionBatch=scheduled},{},
            r.id..':op:'..r.operation..':craft:'..scheduled..':generation:'..(r.replans or 0))
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
    local old=capacity.state.leases[job.id]; if old then assert(old.status=='held','craft capacity already released'); return old end
    local station=job.privateStation
    for _,field in ipairs({'buffer','input','output'}) do empty(station[field]) end
    local limits={}
    for item in pairs(job.stockInputs) do
      local sources=F.sources(e,config,item); local source=assert(sources[1],'reserved craft ingredient missing: '..item)
      local detail=e.peripheral.call(source.name,'getItemDetail',source.slot)
      assert(detail and U.integer(detail.maxCount) and detail.maxCount>0,'ingredient stack limit unavailable')
      limits[item]=detail.maxCount
    end
    local sources=F.sources(e,config,job.item); local outputLimit
    if sources[1] then
      local detail=e.peripheral.call(sources[1].name,'getItemDetail',sources[1].slot)
      outputLimit=detail and detail.maxCount
    end
    local combined=U.copy(job.stockInputs); combined[job.item]=(combined[job.item] or 0)+job.quantity
    local combinedLimits=U.copy(limits); combinedLimits[job.item]=outputLimit
    local outputLimits=outputLimit and {[job.item]=outputLimit} or {}
    local why='shared output storage is not configured'
    for _,destination in ipairs(config.storageInventories) do
      local lease
      lease,why=capacity:reserve(job.id,{
        {inventory=station.buffer,items=combined,limits=combinedLimits,exclusive=true},
        {inventory=station.input,items=job.stockInputs,limits=limits,exclusive=true},
        {inventory=station.output,items=job.stockOutputs,limits=outputLimits,exclusive=true},
        {inventory=destination,items=job.stockOutputs,limits=outputLimits}},e)
      if lease then return lease end
    end
    error(why,0)
  end
  local function advance(job)
    local flow=job.factoryFlow
    if not flow then F.commit(job,save,function() job.factoryFlow={stage={},collect={}} end); flow=job.factoryFlow end
    if flow.stage.intent then return F.reconcileTransfer(flow.stage,e,save) end
    if flow.collect.intent then return F.reconcileTransfer(flow.collect,e,save) end
    local allowed,why=Q.factoryCanRun(app.state,job,true); if not allowed then error(why,0) end
    local station=job.privateStation
    if job.workerFinished then
      empty(station.input); empty(station.output)
      local inv=F.list(e,station.buffer); local delivered=flow.collect.delivered or 0
      local expected=delivered<job.quantity and {[job.item]=job.quantity-delivered} or {}
      assert(F.equal(counts(inv),expected),'private crafting output changed before collection')
      if delivered==job.quantity then
        capacity:release(job.id)
        F.commit(job,save,function() job.status='completed'; job.error=nil end)
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
    local lease=reserve(job)
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
    F.commit(job,save,function() job.privateReady=true; job.status='queued'; job.error=nil end)
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
  return self
end
return M
