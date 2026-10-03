local U=require('autobuilder.core.util')
local F=require('autobuilder.factory.factory')
local Q=require('autobuilder.core.workflows')
local Nodes=require('autobuilder.storage.nodes')
local M={}
function M.new(app,config,e,queue,production)
  local s=queue.state;s.hauls=s.hauls or {};s.haulSequence=s.haulSequence or 0
  local save=function() return app:save() end
  local capacity=require('autobuilder.storage.capacity').new(app.state,save)
  s.logisticsProduction=s.logisticsProduction or {};s.logisticsStatus=s.logisticsStatus or {}
  local self={capacity=capacity,cursor=0}
  local function jobs(r)
    local out={};for _,j in pairs(s.jobs) do if j.haulRequest==r.id then out[#out+1]=j end end
    table.sort(out,function(a,b) return a.id<b.id end);return out
  end
  function self:request(item,n,from,to,key)
    assert(U.shortString(item,128) and U.integer(n) and n>=1 and n<=1000000,'invalid haul item/count')
    assert(from~=to and Nodes.get(config,from) and Nodes.get(config,to),'distinct registered logistics nodes required')
    for _,r in pairs(s.hauls) do if key and r.key==key then
      assert(r.item==item and r.quantity==n and r.source==from and r.destination==to,'changed haul request');return r
    end end
    local r
    F.commit(s,save,function()
      s.haulSequence=s.haulSequence+1
      r={id='haul:'..s.haulSequence,item=item,quantity=n,source=from,destination=to,key=key,status='queued'}
      s.hauls[r.id]=r
    end)
    return r
  end
  local function canRun()
    if Q.factoryActive(app.state) then return false,'waiting for active factory operation' end
    for _,j in pairs(app.state.jobs or {}) do
      if j.workerId and not j.physicalComplete and j.status~='completed' then return false,'waiting for mining delivery '..j.id end
    end
    for _,j in pairs(s.jobs) do
      if not j.logistics and j.status~='completed' and (j.type=='FUEL_STATION' and j.production
        or j.workerId and (j.type=='TRANSPORT' or j.type=='REFUEL' or j.type=='HARVEST' or j.type=='FARM')) then
        return false,'waiting for shared inventory owner '..j.id
      end
    end
    if s.supply then return false,'waiting for builder supply collection' end
    return true
  end
  local function availableBuffer(node,position)
    local ordered=U.copy(node.buffers)
    table.sort(ordered,function(a,b)
      local da,db=U.distance(a.position,position),U.distance(b.position,position)
      return da<db or da==db and a.inventory<b.inventory
    end)
    local unavailable
    for _,b in ipairs(ordered) do
      local busy=false
      for _,j in pairs(s.jobs) do if j.logistics and j.status~='completed' then
        if j.logistics.pickup.inventory==b.inventory or j.logistics.drop.inventory==b.inventory then busy=true end
      end end
      if not busy then
        local ok,inventory=pcall(F.list,e,b.inventory)
        if ok and not next(inventory) then return b end
        if not ok then unavailable=b.inventory..': '..tostring(inventory) end
      end
    end
    return nil,unavailable
  end
  local function idleWorker()
    local ids={}
    for _,w in pairs(app.state.workers or {}) do
      local t=w.telemetry
      if w.online and t and t.status=='idle' and not t.task and t.position and t.position.known and U.position(t.position) and t.capabilities and t.capabilities.logisticsV1
        and t.capabilities.courier and not Q.workerBusy(app.state,w.id) then ids[#ids+1]=w.id end
    end
    table.sort(ids);return ids[1]
  end
  local function sourceCount(node,item,except)
    local _,total=F.sources(e,{storageInventories={node.inventory}},item)
    for _,j in pairs(s.jobs) do
      local lease=production.ledger.state.leases[j.id]
      if j.id~=except and j.logistics and j.item==item and j.logistics.source.inventory==node.inventory and lease and lease.status=='held' then
        total=total-(j.quantity-(lease.withdrawn[item] or 0))
      end
    end
    return math.max(0,total)
  end
  local function schedule(r)
    local allocated,delivered=0,0
    for _,j in ipairs(jobs(r)) do allocated=allocated+j.quantity;if j.status=='completed' then delivered=delivered+j.quantity end end
    r.delivered=delivered
    if delivered==r.quantity then r.status='completed';r.error=nil;assert(save());return false end
    if allocated>=r.quantity then return false end
    local allowed,why=canRun();if not allowed then r.error=why;assert(save());return false end
    local owner=idleWorker();if not owner then r.error='waiting for an idle logisticsV1 courier';assert(save());return false end
    local from,to=Nodes.get(config,r.source),Nodes.get(config,r.destination)
    local pickup,pickupError=availableBuffer(from,app.state.workers[tostring(owner)].telemetry.position)
    local drop,dropError
    if pickup then drop,dropError=availableBuffer(to,pickup.position) end
    if not pickup or not drop then r.error=pickupError or dropError or 'waiting for empty private logistics buffers';assert(save());return false end
    local n=math.min(config.logistics.batchSize,r.quantity-allocated,sourceCount(from,r.item))
    if n==0 then r.error='source stock missing: '..r.source..' '..r.item;assert(save());return false end
    queue:submit('TRANSPORT',{item=r.item,quantity=n,preferredWorker=owner,haulRequest=r.id,logisticsReady=false,
      source=U.copy(pickup.position),destination=U.copy(drop.position),
      logistics={source=Nodes.identity(from),destination=Nodes.identity(to),pickup=U.copy(pickup),drop=U.copy(drop)}},{},r.id..':'..allocated)
    r.status='running';r.error=nil;assert(save());return true
  end
  -- Reserve both ledgers and the batch contract in one checkpoint. All native
  -- observations occur under production's inventory lock, before any transfer.
  local function reserve(job)
    local old=capacity.state.leases[job.id];if old then assert(old.status=='held','logistics capacity released');return old end
    local worker=app.state.workers[tostring(job.preferredWorker)]
    local telemetry=worker and worker.telemetry
    assert(worker and worker.online and telemetry and telemetry.status=='idle' and not telemetry.task
      and not Q.workerBusy(app.state,job.preferredWorker,job.id),'waiting for available preferred courier')
    local c=job.logistics
    assert(not next(F.list(e,c.pickup.inventory)) and not next(F.list(e,c.drop.inventory)),'logistics buffers must be empty')
    local sources=F.sources(e,{storageInventories={c.source.inventory}},job.item)
    local first=assert(sources[1],'source stock missing: '..c.source.id)
    local detail=e.peripheral.call(first.name,'getItemDetail',first.slot)
    assert(detail and U.integer(detail.maxCount) and detail.maxCount>0,'source item stack limit unavailable')
    assert(app.mining:refresh())
    local available=production.ledger:view(job.item,app.mining.storage.counts).available-(config.turtleFuelReserveItems[job.item] or 0)
    local n=math.min(job.quantity,detail.maxCount,sourceCount(c.source,job.item,job.id),available)
    assert(n>0,'insufficient unreserved source stock')
    local capacityDraft=require('autobuilder.storage.capacity').new(app.state,function() return true end)
    local stockDraft=require('autobuilder.storage.ledger').new(app.state,function() return true end)
    local before=U.copy(job)
    local ok,lease=pcall(function()
      local claim,why
      -- At most64 finite item counts; reduce to actual destination capacity.
      while n>0 do
        local items={[job.item]=n};local limits={[job.item]=detail.maxCount}
        claim,why=capacityDraft:reserve(job.id,{
          {inventory=c.pickup.inventory,items=items,limits=limits,exclusive=true},
          {inventory=c.drop.inventory,items=items,limits=limits,exclusive=true},
          {inventory=c.destination.inventory,items=items,limits=limits}},e)
        if claim then break end;n=n-1
      end
      assert(claim,why)
      job.quantity=n;job.stockInputs={[job.item]=n};job.stockOutputs={[job.item]=n}
      assert(stockDraft:reserve(job.id,job.stockInputs,job.stockOutputs,app.mining.storage.counts,{protected=config.turtleFuelReserveItems}))
      job.logisticsFlow={stage={},collect={}}
      assert(save());return claim
    end)
    if not ok then
      capacity.state.leases[job.id]=nil;production.ledger.state.leases[job.id]=nil
      for k in pairs(job) do job[k]=nil end;for k,v in pairs(before) do job[k]=v end
      error(lease,0)
    end
    return lease
  end
  local function exact(inv,item,n)
    local total=0
    for _,v in pairs(inv) do assert(v.name==item and not v.nbt,'logistics buffer contains foreign cargo');total=total+v.count end
    assert(total==n,'logistics buffer count changed outside its owner')
  end
  local function transfer(job,flow,from,to,allocations,offset,withdrawal)
    local sources=F.sources(e,{storageInventories={from}},job.item);local source=assert(sources[1],'reserved cargo unavailable')
    local remaining=offset
    for _,a in ipairs(allocations) do
      if remaining<a.count then
        local inv=F.list(e,to);local v=inv[a.slot]
        assert(not v or v.name==job.item and not v.nbt,'reserved destination slot contaminated')
        local detail=e.peripheral.call(from,'getItemDetail',source.slot)
        local limit=e.peripheral.call(to,'getItemLimit',a.slot)
        local room=math.min(limit,assert(detail.maxCount))-(v and v.count or 0)
        assert(room>0,'reserved destination slot full')
        return F.transfer(flow,e,save,from,source.slot,to,a.slot,job.item,
          math.min(a.count-remaining,source.count,room),withdrawal and to or from,withdrawal and 1 or -1,
          not withdrawal and 'delivered' or nil,nil,withdrawal)
      end
      remaining=remaining-a.count
    end
    error('logistics transfer exceeds reserved capacity',0)
  end
  local function advance(job)
    local flow=job.logisticsFlow
    if flow and flow.stage.intent then return F.reconcileTransfer(flow.stage,e,save) end
    if flow and flow.collect.intent then return F.reconcileTransfer(flow.collect,e,save) end
    local allowed,why=canRun();assert(allowed,why)
    local c=job.logistics
    if job.workerFinished then
      assert(not next(F.list(e,c.pickup.inventory)),'pickup buffer not empty after completion')
      local delivered=flow.collect.delivered or 0
      exact(F.list(e,c.drop.inventory),job.item,job.quantity-delivered)
      if delivered==job.quantity then
        capacity:release(job.id)
        F.commit(job,save,function() job.status='completed';job.error=nil end);return 'complete'
      end
      local lease=assert(capacity.state.leases[job.id]);assert(lease.status=='held')
      return transfer(job,flow.collect,c.drop.inventory,c.destination.inventory,lease.nodes[c.destination.inventory].allocations,delivered,false)
    end
    local lease=reserve(job);flow=job.logisticsFlow
    assert(not next(F.list(e,c.drop.inventory)),'drop buffer changed during staging')
    local staged=(flow.stage.withdrawn or {})[job.item] or 0
    exact(F.list(e,c.pickup.inventory),job.item,staged)
    if staged<job.quantity then
      return transfer(job,flow.stage,c.source.inventory,c.pickup.inventory,lease.nodes[c.pickup.inventory].allocations,staged,true)
    end
    F.commit(job,save,function() job.logisticsReady=true;job.status='queued';job.error=nil end);return 'ready'
  end
  local function outstanding(node,item,inbound)
    local n=0
    for _,r in pairs(s.hauls) do
      if r.status~='completed' and r.item==item and (inbound and r.destination or r.source)==node.id then
        local moved=0
        for _,j in ipairs(jobs(r)) do
          local f=j.logisticsFlow
          if f then moved=moved+(inbound and (f.collect.delivered or 0) or (f.stage.withdrawn or {})[item] or 0) end
        end
        n=n+r.quantity-moved
      end
    end
    return n
  end
  local function restock()
    local nodes=U.copy(config.logistics.nodes);table.sort(nodes,function(a,b) return a.id<b.id end)
    for _,node in ipairs(nodes) do
      local items={};for item in pairs(node.targets or {}) do items[#items+1]=item end;table.sort(items)
      for _,item in ipairs(items) do
        local _,physical=F.sources(e,{storageInventories={node.inventory}},item)
        local need=node.targets[item]-physical-outstanding(node,item,true)
        local key=node.id..':'..item
        s.logisticsStatus[key]=nil
        if need>0 then
          local request=s.logisticsProduction[item] and s.requests[s.logisticsProduction[item]]
          if request and request.status~='completed' then
            s.logisticsStatus[key]='waiting for production '..request.id..': '..(request.error or request.status)
          else
            assert(app.mining:refresh())
            local stockView=production.ledger:view(item,app.mining.storage.counts)
            local available=math.max(0,stockView.available-(config.turtleFuelReserveItems[item] or 0))
            local candidates={}
            for _,source in ipairs(nodes) do if source.id~=node.id then
              local _,stock=F.sources(e,{storageInventories={source.inventory}},item)
              local free=math.min(available,stock-((source.targets or {})[item] or 0)-outstanding(source,item,false))
              if free>0 then candidates[#candidates+1]={node=source,count=free,distance=U.distance(source.position,node.position)} end
            end end
            table.sort(candidates,function(a,b) return a.distance<b.distance or a.distance==b.distance and a.node.id<b.node.id end)
            if candidates[1] then
              local source=candidates[1]
              self:request(item,math.min(need,source.count),source.node.id,node.id,'restock:'..key..':'..(s.haulSequence+1))
              return true
            end
            local transit=stockView.reserved>0 or stockView.transit>0 or stockView.expected>0
            for _,r in pairs(s.hauls) do if r.item==item and r.status~='completed' then transit=true end end
            if transit then s.logisticsStatus[key]='waiting for owned cargo to settle before forecasting shortage'
            else
              local registered={};for _,source in ipairs(nodes) do registered[source.inventory]=true end
              local missing
              for _,inventory in ipairs(config.storageInventories) do if not registered[inventory] then missing=inventory;break end end
              if missing then s.logisticsStatus[key]='register logistics node for factory output inventory '..missing
              else
                local target=(app.mining.storage.counts[item] or 0)+need
                assert(target<=1000000,'logistics production target exceeds finite request limit')
                local r=production:request({[item]=target},'logistics-stock:'..item)
                s.logisticsProduction[item]=r.id;s.logisticsStatus[key]='acquiring '..need..' '..item..' through '..r.id
                assert(save());return true
              end
            end
          end
        end
      end
    end
    return false
  end
  function self:tick()
    for _,r in pairs(s.hauls) do if r.status~='completed' then
      local delivered=0;for _,j in ipairs(jobs(r)) do if j.status=='completed' then delivered=delivered+j.quantity end end
      if delivered==r.quantity then r.status='completed';r.error=nil;r.delivered=delivered;assert(save()) end
    end end
  end
  function self:step()
    self:tick()
    local pending={}
    for _,j in pairs(s.jobs) do if j.logistics and j.status~='completed' then
      local f=j.logisticsFlow
      if f and (f.stage.intent or f.collect.intent) then pending={j};break end
      if not j.paused and (not j.logisticsReady or j.workerFinished) then pending[#pending+1]=j end
    end end
    table.sort(pending,function(a,b) return a.id<b.id end)
    for _=1,#pending do
      self.cursor=self.cursor%#pending+1;local j=pending[self.cursor]
      local status,why=F.protect(function() return advance(j) end)
      if status=='blocked' then j.status='blocked';j.error=why;assert(save()) end
      production:syncClaims(false)
      local flow=j.logisticsFlow
      if status~='blocked' or flow and (flow.stage.intent or flow.collect.intent) then return true end
    end
    local requests={};for _,r in pairs(s.hauls) do if r.status~='completed' then requests[#requests+1]=r end end
    table.sort(requests,function(a,b) return a.id<b.id end)
    for _,r in ipairs(requests) do
      local ok,result=pcall(schedule,r)
      if not ok then r.error=tostring(result);assert(save()) elseif result then return true end
    end
    local ok,result=pcall(restock)
    if not ok then s.logisticsError=tostring(result);assert(save())
    else s.logisticsError=nil;if result then return true end end
    return false
  end
  function self:describe()
    local lines={'LOGISTICS nodes='..#config.logistics.nodes}
    if s.logisticsError then lines[#lines+1]=s.logisticsError end
    for key,why in pairs(s.logisticsStatus) do lines[#lines+1]=key..' '..why end
    for _,r in pairs(s.hauls) do lines[#lines+1]=r.id..' '..r.status..' '..r.item..' '..(r.delivered or 0)..'/'..r.quantity..' '..(r.error or '') end
    for _,j in pairs(s.jobs) do if j.logistics and j.status~='completed' then
      lines[#lines+1]=j.id..' worker='..tostring(j.workerId or j.preferredWorker)..' '..j.status..' '..(j.error or j.coverageError or '')
    end end
    app.state.logisticsLines=lines;return table.concat(lines,'; ')
  end
  return self
end
return M
