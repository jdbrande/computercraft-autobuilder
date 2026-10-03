local U=require('autobuilder.core.util')
local Reports=require('autobuilder.core.reports')
local M={}
local function transportReceipt(t)
  if t.logistics then return {sequence=t.transportSequence or 0,pickedUp=t.pickedUp or 0,delivered=t.delivered or 0} end
end
local construction={BUILD=true,VERIFY=true,REPAIR=true,CLEAR=true}
local modules={RESCUE='autobuilder.workers.fuel_courier',BUILD='autobuilder.build.builder',VERIFY='autobuilder.build.verification',REPAIR='autobuilder.build.repair',CLEAR='autobuilder.build.repair',PREPARE_SITE='autobuilder.build.site',
  CRAFT='autobuilder.factory.crafting',TRANSPORT='autobuilder.workers.courier',HARVEST='autobuilder.resources.logger',FARM='autobuilder.resources.farmer'}
function M.new(app,config,e,network,clock)
  local s=app.state; s.completedTasks=s.completedTasks or {}; s.pendingSupplyAcks=s.pendingSupplyAcks or {}; local self={}; local lastSend=-math.huge
  local function save() return app:save() end
  local function send(kind,payload) return network:send(config.controllerId,kind,payload) end
  local function generic() return s.currentTask and s.currentTask.type and s.currentTask.type~='MINE' end
  local function constructionFuel(task,origin)
    local home=config.depot; local pose=origin or app.navigation.pose
    if not construction[task.type] or not U.position(home) or not U.position(pose) then return nil end
    local height=math.max(pose.y,home.y+2,task.clearanceY or -math.huge)
    for _,block in ipairs(task.blocks or {}) do height=math.max(height,block.y+2) end
    local required=0; local limit=config.maxTravelDistance or 1024
    for index=task.index or 1,#(task.blocks or {}) do
      local plan=require('autobuilder.build.placement').plan(task.blocks[index])
      local stand=plan and plan.stand or task.blocks[index]
      local outward=math.abs(pose.x-stand.x)+math.abs(pose.z-stand.z)
      local returning=math.abs(home.x-stand.x)+math.abs(home.z-stand.z)
      local leg=math.max(outward,returning,height-pose.y,height-home.y,height-stand.y)
      if leg>limit then return nil,'Construction route needs '..leg..' blocks; maxTravelDistance is '..limit..'. Increase the configured travel limit.' end
      -- Include both overhead ascents, the work stand and the depot descent.
      -- Eight extra moves cover the builder's bounded side-approach offsets.
      local fallback=stand.y<task.blocks[index].y and 2*(height-stand.y) or 0
      required=math.max(required,outward+returning+(height-pose.y)+(height-home.y)+2*(height-stand.y)+fallback+8+config.minimumFuelReserve)
    end
    return required
  end
  local function refuelInPlace(target)
    local item=e.turtle.getItemDetail(15)
    if item and (item.nbt or not require('autobuilder.resources.fuel').allowed(item.name,config)) then
      return false,'Empty slot 15: it contains a foreign or NBT-tagged item; reserve it for fuel.'
    end
    local selected=e.turtle.getSelectedSlot and e.turtle.getSelectedSlot()
    local ok,err=require('autobuilder.storage.inventory').new(e.turtle,config):refuel(target,false)
    if selected then e.turtle.select(selected) end
    return ok,err
  end
  local function engine()
    local t=s.currentTask
    if not self.engine or self.engine.task~=t then
      local module=modules[t.type]; assert(module,'No worker executor for '..tostring(t.type))
      if t.type=='CRAFT' then
        local craftConfig=config
        if t.privateStation then
          assert(require('autobuilder.factory.stations').matches(t.privateStation,config,s.id),'private crafting station does not match worker configuration')
          craftConfig=U.copy(config); craftConfig.storageInventories={t.privateStation.buffer}
          craftConfig.turtleFuelReserveItems={} -- the controller already protected fuel in shared stock
        end
        self.engine=require(module).new(t,e,craftConfig,save)
      else self.engine=require(module).new(t,e,config,app.navigation,save) end
    end
    return self.engine
  end
  local function resumeTask()
    local t=s.currentTask
    if t.type=='REFUEL' or t.type=='RETURN_HOME' or t.type=='CRAFT' then t.phase='work'; t.error=nil; t.blockedCategory=nil; return true end
    return engine():resume()
  end
  function self:resumeFuelTask()
    -- Remote delivery satisfied the fuel recovery; do not keep executing the
    -- old depot detour and demand a second top-up after travelling home.
    s.currentTask.fuelRecovery=nil
    return resumeTask()
  end
  function self:poseRecovered()
    local t=s.currentTask;local p=s.position
    if generic() and t.poseBlocked and not t.paused and config.automation.enabled
      and p.known and U.heading(p.heading) and not p.pending and not p.uncertain then
      if t.phase=='blocked' then
        local ok,why=resumeTask();if not ok then return false,why end
      end
      t.poseBlocked=nil;s.status=t.phase;return save()
    end
    return true
  end
  local function recoverSupplyReceipt()
    local t=s.currentTask
    if t and t.lastSupply and t.supplyReceiptId and not t.supplyRequest then
      s.pendingSupplyAcks[t.supplyReceiptId]=t.id; t.supplyReceiptId=nil
      t.missingItem=nil; t.missingCount=nil; save()
      if t.phase=='blocked' then resumeTask(); save() end
    end
  end
  app.navigation.guard=function(from,target)
    if s.poseRecovery then return app.poseRecovery:guard(from,target) end
    if not s.currentTask or not config.automation.enabled then return true end
    local r=s.motionReservation; local id=s.currentTask.id
    if r and r.jobId==id and r.granted and U.distance(r.target,target)==0 then return true end
    s.motionReservation={jobId=id,from={x=from.x,y=from.y,z=from.z},target={x=target.x,y=target.y,z=target.z},granted=false}; save()
    send('task_reserve',s.motionReservation)
    return false,'movement reservation pending'
  end
  app.navigation.afterMove=function()
    if s.poseRecovery then return end
    if not s.currentTask then return end
    local r=s.motionReservation
    if r then send('task_position',{jobId=r.jobId,from=r.from,target=r.target}); s.motionReservation=nil; save() end
  end
  function self:handle(sender,m)
    if sender~=config.controllerId or not config.automation.enabled then return false,'automation controller mismatch or disabled' end
    local previous=s.lastTaskControl
    if previous and (m.boot<previous.boot or (m.boot==previous.boot and m.sequence<=previous.sequence)) then return false,'stale task control' end
    s.lastTaskControl={boot=m.boot,sequence=m.sequence}; save()
    local p=m.payload; local t=s.currentTask
    if m.type=='task_pose_grant' or m.type=='task_pose_ack' then return app.poseRecovery:handle(m.type,p) end
    if m.type=='task_fuel_freeze' or m.type=='task_fuel_consume' or m.type=='task_fuel_release' then
      local recovery=app.fuelRecovery; if not recovery then return false,'fuel recovery unavailable' end
      local method=({task_fuel_freeze='freeze',task_fuel_consume='consume',task_fuel_release='release'})[m.type]
      local ok,why=recovery[method](recovery,p)
      local status=recovery:status(p.jobId) or {jobId=p.jobId,phase='blocked',position=U.copy(s.position),
        quantity=0,capacity=0,fuel=e.turtle.getFuelLevel(),error=tostring(why):sub(1,512)}
      if status.error then status.error=tostring(status.error):sub(1,512) end
      send('task_fuel_status',status); return ok,why
    end
    if m.type=='task_supply_ack' then
      if s.pendingSupplyAcks[p.supplyId]~=p.jobId then return false,'supply receipt job mismatch' end
      s.pendingSupplyAcks[p.supplyId]=nil; save(); return true
    end
    if m.type=='task_assign' then
      local j=p.job; local done=s.completedTasks[j.id]
      if done then return send('task_progress',{jobId=j.id,phase='completed',progress=done.progress or 0,report=done.report,transportReceipt=done.transportReceipt}) end
      if require('autobuilder.core.receipts').archived(s,'completedTasks',j.id) then return false,'Old acknowledged task was archived; restore the matching controller checkpoint' end
      local covered,why=require('autobuilder.core.chunks').workerAccept(config,s,j);if not covered then return false,why end
      if t and (t.logistics or j.logistics) then
        for _,field in ipairs({'logistics','source','destination','item','quantity','stockInputs','stockOutputs'}) do
          if not require('autobuilder.factory.factory').equal(t[field],j[field]) then return false,'changed managed transport assignment' end
        end
      end
      if t then return t.id==j.id,'worker already has a task' end
      if j.logistics and (not config.capabilities.logisticsV1 or not require('autobuilder.storage.nodes').validContract(j)) then return false,'invalid managed transport assignment' end
      local cap=({RESCUE='courier',CRAFT='crafting',BUILD='building',VERIFY='building',REPAIR='building',CLEAR='building',PREPARE_SITE='sitePreparation',HARVEST='logging',FARM='farming',TRANSPORT='courier'})[j.type]
      if cap and not config.capabilities[cap] then return false,'worker lacks '..cap end
      if j.privateStation and not require('autobuilder.factory.stations').matches(j.privateStation,config,s.id) then return false,'private crafting station does not match worker configuration' end
      s.currentTask=U.copy(j); s.currentTask.phase='setup'; s.status='setup'; self.engine=nil; save(); return true
    end
    if not t or t.id~=p.jobId then return false,'task ID mismatch' end
    if m.type=='task_ack' and t.phase=='completed' then
      require('autobuilder.core.receipts').record(s,'completedTasks',t.id,{progress=tonumber(t.progress) or t.delivered or 0,report=Reports.compact(t.report),transportReceipt=transportReceipt(t)})
      s.currentTask=nil; self.engine=nil; s.status='idle'; save(); return true
    elseif m.type=='task_pause' then t.paused=true; save(); return true
    elseif m.type=='task_resume' then
      t.paused=false
      if t.phase=='blocked' then
        resumeTask()
      end
      save(); return true
    elseif m.type=='task_grant' then
      local r=s.motionReservation
      if r and r.jobId==p.jobId and U.distance(r.target,p.target)==0 then r.granted=p.granted; save(); return true end
    elseif m.type=='task_supply' and t.supplyRequest and t.supplyRequest.item==p.item and t.supplyRequest.id==p.supplyId then
      t.supplyRequest.granted=true; t.supplyRequest.amount=p.count; save(); return true
    end
    return false,'unexpected task response'
  end
  function self:tick()
    if clock()-lastSend<config.heartbeatInterval then return true end
    recoverSupplyReceipt()
    if app.fuelRecovery and app.fuelRecovery:active() then
      local status=app.fuelRecovery:status(); if status.error then status.error=tostring(status.error):sub(1,512) end
      send('task_fuel_status',status)
    end
    for supplyId,jobId in pairs(s.pendingSupplyAcks) do send('task_supply_done',{jobId=jobId,supplyId=supplyId}) end
    if s.motionReservation and not s.motionReservation.granted then send('task_reserve',s.motionReservation) end
    if not generic() then lastSend=clock(); return true end
    lastSend=clock(); local t=s.currentTask; local phase=t.paused and 'paused' or t.phase
    if not ({setup=true,work=true,waiting=true,blocked=true,completed=true,paused=true,supply=true})[phase] then phase='running' end
    local err=t.error and tostring(t.error):gsub('[%c]',' '):sub(1,512)
    local stockReceipt
    if t.type=='CRAFT' and t.production and t.production.stockSequence then
      stockReceipt={sequence=t.production.stockSequence,withdrawn=U.copy(t.production.withdrawn or {}),delivered={[t.item]=t.production.delivered or 0}}
    end
    send('task_progress',{transportReceipt=transportReceipt(t),fuelDelivered=t.type=='RESCUE' and t.fuelDelivered or nil,stockReceipt=stockReceipt,jobId=t.id,phase=phase,progress=tonumber(t.progress) or t.delivered or 0,error=err,
      missingItem=t.supplyRequest and t.supplyRequest.item or t.missingItem,
      missingCount=t.supplyRequest and t.supplyRequest.count or t.missingCount,supplyId=t.supplyRequest and t.supplyRequest.id,report=Reports.compact(t.report)})
    return true
  end
  function self:step()
    if not generic() then return true end
    recoverSupplyReceipt()
    local t=s.currentTask
    if t.paused or t.phase=='completed' then return true end
    local required,rangeError=constructionFuel(t)
    if rangeError then
      t.resumePhase=t.phase~='blocked' and t.phase or t.resumePhase
      t.phase='blocked'; t.blockedCategory='inaccessible'; t.error=rangeError; save(); return true
    end
    if t.supplyRequest then
      local supplyId=t.supplyRequest.id
      if t.supplyReceiptId~=supplyId then t.supplyReceiptId=supplyId; save() end
      local resupply=require('autobuilder.workers.resupply').new(t,e,config,app.navigation,save)
      local done,err=resupply:step()
      if done then
        s.pendingSupplyAcks[supplyId]=t.id; t.supplyReceiptId=nil; t.missingItem=nil; t.missingCount=nil; resumeTask(); s.status=t.phase; save()
      elseif err and not tostring(err):find('movement reservation pending',1,true) then t.error=err; save() end
      return true
    end
    -- Budget before beginning a route. Reservation yields during its descent
    -- must not charge a second ascent and send an adequately fuelled turtle home.
    if required and not t.moveRoute and not t.supportCheck and not t.pairCheck and not t.intent
      and not (t.resupply and t.resupply.intent) and not t.fuelRecovery and not t.supplyRequest then
      local fuel=e.turtle.getFuelLevel()
      if fuel~='unlimited' and fuel<required then
        local ok,err=refuelInPlace(math.max(config.mining.fuelTarget,required))
        if not ok then
          t.resumePhase=t.phase~='blocked' and t.phase or t.resumePhase
          t.requiredFuel=required; t.phase='blocked'; t.blockedCategory='fuel'; t.error='Insufficient construction fuel: '..tostring(err); save()
        end
      end
    end
    if t.fuelRecovery or t.phase=='blocked' and (t.blockedCategory=='fuel' or tostring(t.error):find('insufficient fuel',1,true)) then
      if t.type=='PREPARE_SITE' then
        -- Its access corridor may still be solid. Refuel in place: a depot
        -- detour would abandon the durable adjacent excavation route.
        local target=math.max(config.mining.fuelTarget,#t.sitePlan.points-(t.index or 1)+1+config.minimumFuelReserve)
        local selected=e.turtle.getSelectedSlot and e.turtle.getSelectedSlot()
        local ok,err=require('autobuilder.storage.inventory').new(e.turtle,config):refuel(target,false)
        if selected then e.turtle.select(selected) end
        if ok then t.fuelRecovery=nil; resumeTask()
        else t.error='Put coal/charcoal or coal blocks in slot 15; waiting for fuel. '..tostring(err) end
        save(); return true
      end
      if construction[t.type] and required then
        local ok,err=refuelInPlace(math.max(config.mining.fuelTarget,required))
        if ok then t.fuelRecovery=nil; resumeTask(); save(); return true end
        if tostring(err):find('Empty slot 15',1,true) then t.error=err; save(); return true end
      end
      t.fuelRecovery=t.fuelRecovery or {}; save()
      local ok,err=require('autobuilder.workers.resupply').travel(t.fuelRecovery,t,app.navigation,config.depot,save,e.turtle,config)
      if ok then
        local depotRequired=constructionFuel(t,config.depot) or 0
        local target=math.max(config.mining.fuelTarget,depotRequired)
        if construction[t.type] then
          -- Builders must keep the overhead return corridor clear. Obtain fuel
          -- from the same journaled supply chest used for building materials.
          ok,err=refuelInPlace(target)
          if not ok and config.supply.inventory~='' then
            local held=e.turtle.getItemDetail(15)
            if not held then
              t.supplySequence=(t.supplySequence or 0)+1
              t.supplyRequest={id=t.id..':supply:'..t.supplySequence,item='minecraft:coal',
                count=math.min(64,math.max(1,math.ceil((target-e.turtle.getFuelLevel())/80))),fuel=true,granted=false}
              t.lastSupply=nil; save(); return true
            end
          end
          if not ok then err='Put coal/charcoal or coal blocks in slot 15. '..tostring(err) end
        else ok,err=require('autobuilder.storage.inventory').new(e.turtle,config):refuel(target,true) end
      end
      if ok then t.fuelRecovery=nil; resumeTask(); save()
      elseif err then t.error=err; save() end
      return true
    end
    if t.phase=='blocked' then
      if t.type=='RESCUE' and t.cargo and t.cargo.intent then
        engine():step(); s.status=t.phase; save(); return true
      end
      if t.error and tostring(t.error):find('movement reservation pending',1,true) and s.motionReservation and s.motionReservation.granted then resumeTask()
      elseif t.logisticsRetryable and clock()-(t.lastLogisticsRetry or 0)>=config.heartbeatInterval then
        t.lastLogisticsRetry=clock();resumeTask();save()
      elseif t.blockedCategory=='immature' and clock()-(t.lastFarmRetry or 0)>=config.farmRetrySeconds then
        t.lastFarmRetry=clock(); engine():resume(); save()
      elseif t.missingItem and config.supply.inventory~='' and t.type~='CRAFT' then
        t.supplySequence=(t.supplySequence or 0)+1
        local needed=t.missingCount or 1
        if t.blocks then
          needed=0
          for index=t.index or 1,#t.blocks do
            local b=t.blocks[index]
            if require('autobuilder.build.blockstates').item(b)==t.missingItem and not (b.state.half=='upper' and b.name:match('_door$')) then needed=needed+1 end
          end
          needed=math.max(needed,t.missingCount or 1)
        end
        t.supplyRequest={id=t.id..':supply:'..t.supplySequence,item=t.missingItem,count=math.min(config.supply.batch,needed),granted=false}; t.lastSupply=nil; save(); return true
      else return true end
    end
    if t.type=='REFUEL' or t.type=='RETURN_HOME' then
      if t.managedFuel then
        assert(config.fuel.enabled and t.station and U.distance(t.station.position,config.depot)==0,'managed fuel station does not match depot')
      end
      t.homeRoute=t.homeRoute or {}
      local routes=require('autobuilder.workers.resupply')
      local travel=t.type=='REFUEL' and routes.stationTravel or routes.travel
      local ok,err=travel(t.homeRoute,t,app.navigation,config.depot,save,e.turtle,config)
      if ok and t.type=='REFUEL' then ok,err=require('autobuilder.storage.inventory').new(e.turtle,config):refuel(t.fuelTarget or config.mining.fuelTarget,true,t.managedFuel) end
      t.phase=ok and 'completed' or 'blocked'; t.error=err; t.progress=ok and 1 or 0; save(); return true
    end
    local result,err=engine():step()
    if t.type=='CRAFT' then
      t.phase=result=='complete' and 'completed' or result=='blocked' and 'blocked' or result=='waiting' and 'waiting' or 'work'
      if result=='complete' then t.progress=t.quantity end
      t.error=err
    end
    s.status=t.phase; save(); return true
  end
  return self
end
return M
