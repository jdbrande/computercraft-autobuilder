local U=require('autobuilder.core.util')
local F=require('autobuilder.factory.factory')
local Q=require('autobuilder.core.workflows')
local M={}
function M.new(app,config,e,queue,production,clock)
  app.state.fuel=app.state.fuel or {stations={}}
  local stations=app.state.fuel.stations
  local self={}; local save=function() return app:save() end
  local function active(id) local j=id and queue.state.jobs[id]; return j and j.status~='completed' and j end
  local function inspect(station,item)
    local inv=F.list(e,station.inventory)
    for _,stack in pairs(inv) do assert(stack.name==item and not stack.nbt,'fuel station contains foreign items') end
    return inv,F.count(inv,item)
  end
  local function stationTick(station)
    for _,j in pairs(queue.state.jobs) do
      if j.type=='RESCUE' and not j.rescueSettled and j.station.id==station.id then return end
    end
    local row=stations[station.id]
    if not row then row={}; stations[station.id]=row; assert(save()) end
    local refuel=active(row.refuel)
    -- An assigned consumer owns this chest until its durable completion receipt,
    -- including while offline. Never reconcile a fill against a moving endpoint.
    if refuel and refuel.workerId then return end
    local worker=app.state.workers[tostring(station.workerId)]; local t=worker and worker.telemetry
    if not refuel and t and type(t.fuel)=='number' and row.goal and t.fuel>=row.goal then row.goal=nil; assert(save()) end
    if not refuel and worker and worker.online and t and t.status=='idle' and not t.task
      and t.capabilities and t.capabilities.fuelV1 and type(t.fuel)=='number' and t.fuel<(row.goal or config.fuel.low)
      and not Q.workerBusy(app.state,worker.id) then
      assert(t.position and t.position.known and U.position(t.depot),'fuel worker needs a known position and depot')
      assert(U.distance(t.depot,station.position)==0,'fuel station does not match worker depot')
      local distance=U.distance(t.position,station.position)
      -- The normal station route ascends two blocks, may step sideways out
      -- from under a chest, and retains navigation's return reserve throughout.
      local required=distance==0 and 0 or distance+8+(config.minimumFuelReserve or 100)
      assert(required<=t.fuel,'worker needs remote fuel rescue')
      refuel=queue:submit('REFUEL',{managedFuel=true,fuelReady=false,preferredWorker=worker.id,
        fuelTarget=config.fuel.target,station=U.copy(station)}, {}, 'fuel-worker:'..station.id..':'..tostring(row.refuel or 'first'))
      row.refuel=refuel.id; row.goal=config.fuel.target; assert(save())
    end
    if active(row.fill) then return end
    local item=station.item or config.fuel.item
    local _,count=inspect(station,item)
    local target=station.targetItems or 16
    row.stock=count; row.item=item; row.target=target; row.observedAt=clock()
    if count<target then
      local n=target-count
      local job=queue:submit('FUEL_STATION',{station=U.copy(station),item=item,quantity=n,
        stockInputs={[item]=n},stockOutputs={[item]=n}}, {}, 'fuel-fill:'..station.id..':'..tostring(row.fill or 'first'))
      row.fill=job.id; assert(save())
      local _,available=F.sources(e,config,item)
      if available<n then
        production:request({[item]=n},'fuel-stock:'..station.id)
        error('Fuel shortage: acquiring '..item..'; a fueled producer or bootstrap fuel is required',0)
      end
    elseif refuel and not refuel.fuelReady then
      F.commit(refuel,save,function() refuel.fuelReady=true end)
    end
    row.error=nil
  end
  function self:tick()
    if not config.fuel.enabled or app.state.assignmentRecovery then return end
    production:inventoryAction(function()
      for _,station in ipairs(config.fuel.stations) do
        local ok,why=pcall(stationTick,station)
        local row=stations[station.id]
        if row and not ok then row.error=tostring(why); save() end
      end
    end)
  end
  local function execute(job)
    job.production=job.production or {}
    local p=job.production
    if p.intent then return F.reconcileTransfer(p,e,save) end
    if (p.delivered or 0)>=job.quantity then return 'complete' end
    local lease=production.ledger.state.leases[job.id]
    assert(lease and lease.status=='held',job.stockError or 'waiting for durable fuel reservation')
    local inv=inspect(job.station,job.item)
    local sources=F.sources(e,config,job.item); local source=assert(sources[1],'reserved fuel source is empty')
    local detail=e.peripheral.call(source.name,'getItemDetail',source.slot)
    local max=assert(detail and detail.maxCount,'source fuel stack limit unavailable')
    local size=e.peripheral.call(job.station.inventory,'size')
    assert(U.integer(size) and size>0 and size<=4096,'invalid fuel station capacity')
    local slot,room
    for i=1,size do
      local limit=e.peripheral.call(job.station.inventory,'getItemLimit',i)
      assert(U.integer(limit) and limit>=0,'invalid station slot limit')
      local free=math.min(max,limit)-(inv[i] and inv[i].count or 0)
      if free>0 then slot=i; room=free; break end
    end
    assert(slot,'fuel station has no capacity')
    F.commit(job,save,function() job.status='running' end)
    return F.transfer(p,e,save,source.name,source.slot,job.station.inventory,slot,job.item,
      math.min(source.count,room,job.quantity-(p.delivered or 0)),job.station.inventory,1,'delivered',nil,true)
  end
  function self:describe()
    local lines={'FUEL '..(config.fuel.enabled and 'automatic' or 'disabled')..' low='..config.fuel.low..' target='..config.fuel.target}
    for _,station in ipairs(config.fuel.stations) do
      local row=stations[station.id] or {}
      lines[#lines+1]=station.id..' worker='..station.workerId..' stock='..tostring(row.stock or 'unknown')..'/'..(station.targetItems or 16)
        ..' fill='..tostring(row.fill or '-')..' refuel='..tostring(row.refuel or '-')
      local fill=row.fill and queue.state.jobs[row.fill]
      local why=row.error or fill and (fill.error or fill.stockError)
      if why then lines[#lines+1]=station.id..': '..why end
    end
    local ids={}; for id in pairs(app.state.workers) do ids[#ids+1]=id end; table.sort(ids)
    for _,id in ipairs(ids) do
      local w=app.state.workers[id]; local t=w.telemetry or {}
      lines[#lines+1]='Worker '..id..' fuel='..tostring(t.fuel or 'unknown')..' required='..tostring(t.fuelRequired or config.fuel.low)
        ..' '..(w.online and 'online' or 'offline')
      local why=(app.state.fuel.errors or {})[id]; if why then lines[#lines+1]=why end
    end
    local jobs={}; for _,j in pairs(queue.state.jobs) do if j.type=='RESCUE' and not j.rescueSettled then jobs[#jobs+1]=j end end
    table.sort(jobs,function(a,b) return a.id<b.id end)
    for _,j in ipairs(jobs) do
      lines[#lines+1]=j.id..' courier='..tostring(j.workerId or j.preferredWorker)..' recipient='..j.targetWorker
        ..' delivered='..(j.fuelDelivered or 0)..'/'..j.quantity..' budget='..j.fuelBudget..' '..j.status
      lines[#lines+1]='Recipient '..tostring(j.receiverPhase or 'waiting for freeze')..' '..tostring(j.rescueError or j.error or '')
    end
    app.state.fuelLines=lines
    return table.concat(lines,'; ')
  end
  function self:step()
    if not config.fuel.enabled or app.state.assignmentRecovery then return false end
    return production:inventoryAction(function()
      if Q.factoryActive(app.state) or queue.state.supply then return false end
      local jobs={}
      for _,j in pairs(queue.state.jobs) do if j.type=='FUEL_STATION' and j.status~='completed' then jobs[#jobs+1]=j end end
      table.sort(jobs,function(a,b) return a.id<b.id end)
      for _,j in ipairs(jobs) do
        local lease=production.ledger.state.leases[j.id]
        if j.production and j.production.intent or not j.paused and lease and lease.status=='held' then
          local status,err=F.protect(function() return execute(j) end)
          j.status=status=='complete' and 'completed' or status=='blocked' and 'blocked' or 'running'; j.error=err
          assert(save()); production:syncClaims(false); return true
        end
      end
      return false
    end)
  end
  return self
end
return M
