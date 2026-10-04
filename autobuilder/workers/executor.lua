local U=require('autobuilder.core.util')
local Reports=require('autobuilder.core.reports')
local M={}
local function transportReceipt(t)
  if t.logistics then return {sequence=t.transportSequence or 0,pickedUp=t.pickedUp or 0,delivered=t.delivered or 0} end
end
local function homeReceipt(t)
  if t.returning then return {sequence=t.homeCargo and t.homeCargo.sequence or 0,deposited=U.copy(t.homeCargo and t.homeCargo.deposited or {})} end
end
local construction={BUILD=true,VERIFY=true,REPAIR=true,CLEAR=true,SURVEY_SITE=true,PREPARE_REGION=true}
local modules={RECOVER_CARGO='autobuilder.workers.inventory_courier',RETURN_HOME='autobuilder.workers.home',RESCUE='autobuilder.workers.fuel_courier',BUILD='autobuilder.build.builder',VERIFY='autobuilder.build.verification',REPAIR='autobuilder.build.repair',CLEAR='autobuilder.build.repair',PREPARE_SITE='autobuilder.build.site',SURVEY_SITE='autobuilder.build.site_survey',
  PREPARE_REGION='autobuilder.build.site_work',
  CRAFT='autobuilder.factory.crafting',TRANSPORT='autobuilder.workers.courier',HARVEST='autobuilder.resources.logger',FARM='autobuilder.resources.farmer'}
function M.new(app,config,e,network,clock)
  local s=app.state; s.completedTasks=s.completedTasks or {}; s.pendingSupplyAcks=s.pendingSupplyAcks or {}; local self={}; local lastSend=-math.huge
  local function save() return app:save() end
  local function send(kind,payload) return network:send(config.controllerId,kind,payload) end
  local function generic() return s.currentTask and s.currentTask.type and s.currentTask.type~='MINE' end
  local function miningEnabled()
    local t=s.currentTask
    return t and (not t.type or t.type=='MINE') and (config.mining.enabled or t.exploration)
  end
  local function constructionFuel(task,origin)
    if not construction[task.type] then return nil end
    local b,why=require('autobuilder.resources.fuel_budget').construction(config,task,origin or app.navigation.pose,e.turtle.getFuelLevel())
    return b and b.required,why
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
    if s.inventoryRecovery then return true end
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
  local function reserve(from,target,work)
    local enabled=config.automation.enabled or miningEnabled()
    if work and (s.poseRecovery or not s.currentTask or not enabled) then return false,'mutation requires active enabled task ownership' end
    if s.poseRecovery then return app.poseRecovery:guard(from,target) end
    if not s.currentTask or not enabled then return true end
    local r=s.motionReservation; local id=s.currentTask.id
    if r and r.jobId==id and (r.work==true)==(work==true) and U.distance(r.target,target)==0 then
      if r.granted then return true end
      return false,'movement reservation pending'..(r.reason and ': '..r.reason or ''),r.reason~=nil
    end
    s.motionReservation={jobId=id,from={x=from.x,y=from.y,z=from.z},target={x=target.x,y=target.y,z=target.z},work=work,granted=false}; save()
    send('task_reserve',s.motionReservation)
    return false,'movement reservation pending'
  end
  app.navigation.guard=function(from,target) return reserve(from,target) end
  app.navigation.trafficObstacle=function()
    local r=s.motionReservation
    if r and not r.work and not r.granted and s.currentTask and r.jobId==s.currentTask.id and r.reason
      and (r.reason=='worker occupies destination' or r.reason:find('position reserved by worker ',1,true)==1
        or r.reason:find('active preparation region owned by ',1,true)==1) then return U.copy(r.target) end
  end
  app.navigation.workGuard=function(target) return reserve(app.navigation.pose,target,true) end
  app.navigation.workDone=function()
    if s.motionReservation and s.motionReservation.work then s.motionReservation=nil;return save() end
  end
  app.navigation.afterMove=function()
    if s.poseRecovery then return end
    if not s.currentTask then return end
    local r=s.motionReservation
    if r then send('task_position',{jobId=r.jobId,from=r.from,target=r.target}); s.motionReservation=nil; save() end
  end
  function self:handle(sender,m)
    local inventoryControl=m.type=='task_inventory_freeze' or m.type=='task_inventory_grant' or m.type=='task_inventory_ack'
    local miningControl=(m.type=='task_pose_grant' or m.type=='task_pose_ack' or m.type=='task_grant') and miningEnabled()
    if sender~=config.controllerId or not config.automation.enabled and not miningControl and not inventoryControl then return false,'automation controller mismatch or disabled' end
    if m.boot<(s.controllerBoot or 0) then return false,'stale controller generation' end
    local previous=s.lastTaskControl
    if previous and (m.boot<previous.boot or (m.boot==previous.boot and m.sequence<=previous.sequence)) then return false,'stale task control' end
    s.lastTaskControl={boot=m.boot,sequence=m.sequence}; save()
    local p=m.payload; local t=s.currentTask
    if inventoryControl then
      local recovery=app.inventoryDonor;if not recovery then return false,'inventory recovery unavailable' end
      local method=({task_inventory_freeze='freeze',task_inventory_grant='grant',task_inventory_ack='ack'})[m.type]
      local ok,why=recovery[method](recovery,p);local status=recovery:status()
      if not status and m.type=='task_inventory_freeze' then
        status={jobId=p.jobId,position=U.copy(p.position),originalTask=p.originalTask,phase='blocked',sequence=0,moved=0,inventory={},error=tostring(why):sub(1,512)}
      end
      if status then
        if status.error then status.error=tostring(status.error):sub(1,512) end
        send('task_inventory_status',status)
      end
      return ok,why
    end
    if s.inventoryRecovery then return false,'worker quarantined for inventory recovery' end
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
      if done then return send('task_progress',{jobId=j.id,phase='completed',progress=done.progress or 0,report=done.report,transportReceipt=done.transportReceipt,homeReceipt=done.homeReceipt,recoveryReceipt=done.recoveryReceipt,siteReport=done.siteReport}) end
      if require('autobuilder.core.receipts').archived(s,'completedTasks',j.id) then return false,'Old acknowledged task was archived; restore the matching controller checkpoint' end
      local covered,why=require('autobuilder.core.chunks').workerAccept(config,s,j);if not covered then return false,why end
      if t and (t.siteSurvey or j.siteSurvey) then
        for _,field in ipairs({'siteSurvey','bounds','clearanceY'}) do
          if not require('autobuilder.factory.factory').equal(t[field],j[field]) then return false,'changed site survey assignment' end
        end
      end
      if t and (t.siteWork or j.siteWork) then
        for _,field in ipairs({'siteWork','siteAccess','blocks','bounds','clearanceY'}) do
          if not require('autobuilder.factory.factory').equal(t[field],j[field]) then return false,'changed region preparation assignment' end
        end
      end
      if t and (t.type=='RECOVER_CARGO' or j.type=='RECOVER_CARGO') then
        for _,field in ipairs({'type','source','home','targetWorker','item','nbt','quantity','recoveryId','recoverySequence'}) do
          if not require('autobuilder.factory.factory').equal(t[field],j[field]) then return false,'changed inventory recovery assignment' end
        end
      end
      if t and (t.returning or j.returning) then
        for _,field in ipairs({'returning','home','stockInputs','stockOutputs'}) do
          if not require('autobuilder.factory.factory').equal(t[field],j[field]) then return false,'changed home return assignment' end
        end
      end
      if j.returnManaged and (j.workerId~=s.id or j.preferredWorker~=s.id or not U.position(j.home)
        or not U.position(config.depot) or U.distance(j.home,config.depot)~=0) then return false,'home assignment differs from worker depot or identity' end
      if t and (t.logistics or j.logistics) then
        for _,field in ipairs({'logistics','source','destination','item','quantity','stockInputs','stockOutputs'}) do
          if not require('autobuilder.factory.factory').equal(t[field],j[field]) then return false,'changed managed transport assignment' end
        end
      end
      if t then return t.id==j.id,'worker already has a task' end
      if j.type=='RECOVER_CARGO' and not config.capabilities.courier then return false,'recovery requires courier capability' end
      if j.logistics and (not config.capabilities.logisticsV1 or not require('autobuilder.storage.nodes').validContract(j)) then return false,'invalid managed transport assignment' end
      local cap=({RECOVER_CARGO='inventoryRecoveryV1',RESCUE='courier',CRAFT='crafting',BUILD='building',VERIFY='building',REPAIR='building',CLEAR='building',PREPARE_SITE='sitePreparation',SURVEY_SITE='siteSurveyV1',PREPARE_REGION='siteWorkV1',HARVEST='logging',FARM='farming',TRANSPORT='courier'})[j.type]
      if j.siteAccess then cap='siteAccessV1' end
      if require('autobuilder.build.blockstates').requiresModern(j.blocks,j.siteSurvey) and not config.capabilities.placementV1 then return false,'worker lacks placementV1' end
      if require('autobuilder.build.blockstates').requiresMetadata(j.blocks) and not config.capabilities.metadataV1 then return false,'worker lacks metadataV1' end
      if cap and not config.capabilities[cap] then return false,'worker lacks '..cap end
      if j.privateStation and not require('autobuilder.factory.stations').matches(j.privateStation,config,s.id) then return false,'private crafting station does not match worker configuration' end
      s.currentTask=U.copy(j); s.currentTask.phase='setup';
      if j.siteSurvey then s.currentTask.siteReport={identity=j.siteSurvey.identity,region=j.siteSurvey.region,observations={}} end
      s.status='setup'; self.engine=nil; save(); return true
    end
    if not t or t.id~=p.jobId then return false,'task ID mismatch' end
    if m.type=='task_inventory_received' and t.type=='RECOVER_CARGO' then return engine():received(p) end
    if m.type=='task_ack' and t.phase=='completed' then
      require('autobuilder.core.receipts').record(s,'completedTasks',t.id,{progress=tonumber(t.progress) or t.delivered or 0,report=Reports.compact(t.report,t.type),transportReceipt=transportReceipt(t),homeReceipt=homeReceipt(t),recoveryReceipt=require('autobuilder.workers.inventory_courier').receipt(t),siteReport=U.copy(t.siteReport)})
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
      if r and r.jobId==p.jobId and (r.work==true)==(p.work==true) and U.distance(r.target,p.target)==0 then r.granted=p.granted;r.reason=p.reason;save();return true end
    elseif m.type=='task_supply' and t.supplyRequest and t.supplyRequest.item==p.item and t.supplyRequest.id==p.supplyId then
      if p.station and not require('autobuilder.storage.supply').matchesWorker(p.station,config,s.id) then return false,'supply station differs from worker configuration' end
      if t.supplyRequest.station and not require('autobuilder.factory.factory').equal(t.supplyRequest.station,p.station) then return false,'supply station changed during grant' end
      t.supplyRequest.station=U.copy(p.station)
      t.supplyRequest.granted=true; t.supplyRequest.amount=p.count; save(); return true
    end
    return false,'unexpected task response'
  end
  function self:tick()
    if clock()-lastSend<config.heartbeatInterval then return true end
    if app.inventoryDonor and app.inventoryDonor:active() then
      local status=app.inventoryDonor:status();if status.error then status.error=tostring(status.error):sub(1,512) end
      send('task_inventory_status',status);lastSend=clock();return true
    end
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
    send('task_progress',{recoveryReceipt=require('autobuilder.workers.inventory_courier').receipt(t),siteReport=U.copy(t.siteReport),homeReceipt=homeReceipt(t),transportReceipt=transportReceipt(t),fuelDelivered=t.type=='RESCUE' and t.fuelDelivered or nil,stockReceipt=stockReceipt,jobId=t.id,phase=phase,progress=tonumber(t.progress) or t.delivered or 0,error=err,
      missingItem=t.supplyRequest and t.supplyRequest.item or t.missingItem,
      missingCount=t.supplyRequest and t.supplyRequest.count or t.missingCount,supplyId=t.supplyRequest and t.supplyRequest.id,report=Reports.compact(t.report,t.type)})
    return true
  end
  function self:step()
    if s.inventoryRecovery then return true end
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
    -- Budget before beginning a route. Reservation yields during descent or at
    -- the mutation stand must not charge a second ascent after arrival.
    local mutation=s.motionReservation
    local atMutation=mutation and mutation.work and mutation.jobId==t.id and U.distance(mutation.from,app.navigation.pose)==0
    if required and not t.surveyRoute and not t.surveyScanning and not t.moveRoute and not t.supportCheck and not t.pairCheck and not t.intent
      and not atMutation and not (t.resupply and t.resupply.intent) and not t.fuelRecovery and not t.supplyRequest then
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
      if t.returning and t.homeCargo and t.homeCargo.intent then
        engine():step();s.status=t.phase;save();return true
      end
      if t.type=='RESCUE' and t.cargo and t.cargo.intent then
        engine():step(); s.status=t.phase; save(); return true
      end
      if t.type=='RECOVER_CARGO' and t.recoveryCargo and t.recoveryCargo.intent then
        engine():step(); s.status=t.phase; save(); return true
      end
      if t.error and tostring(t.error):find('movement reservation pending',1,true) and s.motionReservation
        and (s.motionReservation.granted or app.navigation.trafficObstacle() or t.siteWork and s.motionReservation.work and s.motionReservation.reason) then resumeTask()
      elseif (t.logisticsRetryable or t.homeRetryable) and clock()-(t.lastLogisticsRetry or 0)>=config.heartbeatInterval then
        t.lastLogisticsRetry=clock();resumeTask();save()
      elseif t.blockedCategory=='immature' and clock()-(t.lastFarmRetry or 0)>=config.farmRetrySeconds then
        t.lastFarmRetry=clock(); engine():resume(); save()
      elseif t.missingItem and config.supply.inventory~='' and t.type~='CRAFT' then
        t.supplySequence=(t.supplySequence or 0)+1
        local needed=t.missingCount or 1
        -- Preparation may retain suitable ground in every remaining cell. Only
        -- the inspected shortage is proven; speculative supply can strand its
        -- acquisition after the worker skips those already-correct supports.
        if t.blocks and t.type~='PREPARE_REGION' then
          needed=0
          for index=t.index or 1,#t.blocks do
            local b=t.blocks[index]
            if Reports.materialItem(b)==t.missingItem then needed=needed+1 end
          end
          needed=math.max(needed,t.missingCount or 1)
        end
        t.supplyRequest={id=t.id..':supply:'..t.supplySequence,item=t.missingItem,count=math.min(config.supply.batch,needed),granted=false}; t.lastSupply=nil; save(); return true
      else return true end
    end
    if not atMutation then
      local upcoming=require('autobuilder.resources.material_forecast').upcoming(t,e.turtle,config)
      if upcoming then
        t.supplySequence=(t.supplySequence or 0)+1
        t.supplyRequest={id=t.id..':supply:'..t.supplySequence,item=upcoming.item,count=upcoming.count,granted=false}
        t.lastSupply=nil;save();return true
      end
    end
    if t.type=='REFUEL' or t.type=='RETURN_HOME' and not t.returning then
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
