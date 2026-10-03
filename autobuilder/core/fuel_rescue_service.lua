local U=require('autobuilder.core.util')
local Q=require('autobuilder.core.workflows')
local F=require('autobuilder.factory.factory')
local Courier=require('autobuilder.workers.fuel_courier')
local M={}
local ranks={frozen=1,consuming=2,consumed=3,released=4}
function M.new(app,config,e,queue,production,network,clock)
  app.state.fuel=app.state.fuel or {stations={}}
  app.state.fuel.errors=app.state.fuel.errors or {}
  local self={}; local save=function() return app:save() end
  local function send(j,kind,p) p.jobId=j.id; return network:send(j.targetWorker,kind,p) end
  local function stationOwned(station)
    for _,j in pairs(queue.state.jobs) do
      if j.station and j.station.id==station.id and (j.type=='RESCUE' and not j.rescueSettled
        or j.type=='REFUEL' and j.status~='completed' or j.type=='FUEL_STATION' and j.status~='completed') then return true end
    end
    return false
  end
  local function choose(target)
    local t=target.telemetry; local destination={x=t.position.x,y=t.position.y+1,z=t.position.z}
    for _,station in ipairs(config.fuel.stations) do
      local w=app.state.workers[tostring(station.workerId)]; local ct=w and w.telemetry
      if w and w.id~=target.id and w.online and ct and ct.status=='idle' and not ct.task
        and ct.capabilities and ct.capabilities.courier and ct.capabilities.fuelV1
        and ct.position and ct.position.known and U.position(ct.depot) and U.distance(ct.depot,station.position)==0
        and not Q.workerBusy(app.state,w.id) and not stationOwned(station) then
        local budget=Courier.budget(ct.position,station.position,destination,ct.depot,config.minimumFuelReserve or 100)
        if ct.fuel=='unlimited' or type(ct.fuel)=='number' and ct.fuel>=budget then
          local item=station.item or config.fuel.item
          local inv=F.list(e,station.inventory); local count,max=0,64
          for slot,stack in pairs(inv) do
            assert(stack.name==item and not stack.nbt,'rescue station contains foreign items')
            local detail=e.peripheral.call(station.inventory,'getItemDetail',slot)
            assert(detail and U.integer(detail.maxCount) and detail.maxCount>0,'rescue fuel capacity unavailable')
            count=count+stack.count; max=math.min(max,detail.maxCount)
          end
          local targetFuel=math.max(config.fuel.target,t.fuelRequired or 0)
          if t.fuelLimit then targetFuel=math.min(targetFuel,t.fuelLimit) end
          local quantity=math.min(count,max,64,math.ceil(math.max(0,targetFuel-t.fuel)/config.fuel.values[item]))
          if quantity>0 then
            return {targetWorker=target.id,preferredWorker=w.id,item=item,quantity=quantity,fuelTarget=targetFuel,
              station=U.copy(station),source=U.copy(station.position),home=U.copy(ct.depot),destination=destination,
              recipient={x=t.position.x,y=t.position.y,z=t.position.z},fuelBudget=budget,rescueReady=false}
          end
        end
      end
    end
    return nil,'No ready fueled courier with reserved station stock and a safe delivery/return budget'
  end
  function self:handle(sender,p)
    local j=queue.state.jobs[p.jobId]
    if not j or j.type~='RESCUE' or j.targetWorker~=sender then return false,'rescue recipient mismatch' end
    if not U.position(p.position) or U.distance(p.position,j.recipient)~=0 then return false,'rescue recipient pose changed' end
    if not ranks[p.phase] then j.rescueError=p.error or 'recipient cannot freeze'; save(); return true end
    if p.phase~='frozen' and p.quantity~=j.quantity then return false,'recipient receipt does not match delivery contract' end
    if (ranks[j.receiverPhase] or 0)>ranks[p.phase] then return true end
    if p.phase=='frozen' and (not U.integer(p.capacity) or p.capacity<1) then return false,'no rescue receiving capacity' end
    F.commit(j,save,function()
      if p.phase=='frozen' and not j.workerId then j.quantity=math.min(j.quantity,p.capacity) end
      j.receiverPhase=p.phase; j.receiverFuel=p.fuel; j.rescueError=p.error
    end)
    return true
  end
  local function advance(j)
    if j.rescueSettled then return end
    if not j.freezeContract then
      F.commit(j,save,function() j.freezeContract={jobId=j.id,item=j.item,quantity=j.quantity,position=U.copy(j.recipient),fuelTarget=j.fuelTarget} end)
    end
    if not j.receiverPhase then send(j,'task_fuel_freeze',U.copy(j.freezeContract))
    elseif j.receiverPhase=='released' then
      if j.status=='completed' then F.commit(j,save,function()
        local w=app.state.workers[tostring(j.targetWorker)]
        j.rescueSettled=true; j.settledBoot=w and w.boot; j.settledSequence=w and w.sequence or 0
      end)
      else j.rescueError='recipient already released; waiting for original courier completion'; save() end
    elseif j.receiverPhase=='consumed' then
      if j.status=='completed' then send(j,'task_fuel_release',{}) end
    elseif (j.fuelDelivered or 0)==j.quantity then send(j,'task_fuel_consume',{quantity=j.quantity})
    elseif not j.rescueReady then F.commit(j,save,function() j.rescueReady=true end) end
  end
  function self:tick()
    if not config.fuel.enabled or app.state.assignmentRecovery then return end
    production:inventoryAction(function()
      local targets={}
      for _,j in pairs(queue.state.jobs) do if j.type=='RESCUE' then
        local w=app.state.workers[tostring(j.targetWorker)]
        if not j.rescueSettled then targets[j.targetWorker]=true; advance(j)
        elseif w and w.boot==j.settledBoot and (w.sequence or 0)<=(j.settledSequence or 0) then
          targets[j.targetWorker]=true -- the last idle/low-fuel telemetry predates release
        end
      end end
      local ids={}; for id in pairs(app.state.workers) do ids[#ids+1]=tonumber(id) end; table.sort(ids)
      for _,id in ipairs(ids) do
        local w=app.state.workers[tostring(id)]; local t=w.telemetry
        local idle=t and t.status=='idle' and not t.task and not Q.workerBusy(app.state,id)
        if w.online and t and t.capabilities and t.capabilities.fuelV1 and t.position and t.position.known
          and type(t.fuel)=='number' and (idle and t.fuel<config.fuel.low or t.fuelRequired and t.fuel<t.fuelRequired)
          and not targets[id] then
          local ok,payload,why=pcall(choose,w)
          if ok and payload then
            local j=queue:submit('RESCUE',payload,{}); advance(j); targets[id]=true; app.state.fuel.errors[tostring(id)]=nil
          else app.state.fuel.errors[tostring(id)]=tostring(ok and why or payload); save() end
        end
      end
    end)
  end
  return self
end
return M
