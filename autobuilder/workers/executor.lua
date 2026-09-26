local U=require('autobuilder.core.util')
local Reports=require('autobuilder.core.reports')
local M={}
local modules={BUILD='autobuilder.build.builder',VERIFY='autobuilder.build.verification',REPAIR='autobuilder.build.repair',CLEAR='autobuilder.build.repair',
  CRAFT='autobuilder.factory.crafting',TRANSPORT='autobuilder.workers.courier',HARVEST='autobuilder.resources.logger',FARM='autobuilder.resources.farmer'}
function M.new(app,config,e,network,clock)
  local s=app.state; s.completedTasks=s.completedTasks or {}; s.pendingSupplyAcks=s.pendingSupplyAcks or {}; local self={}; local lastSend=-math.huge
  local function save() return app:save() end
  local function send(kind,payload) return network:send(config.controllerId,kind,payload) end
  local function generic() return s.currentTask and s.currentTask.type and s.currentTask.type~='MINE' end
  local function engine()
    local t=s.currentTask
    if not self.engine or self.engine.task~=t then
      local module=modules[t.type]; assert(module,'No worker executor for '..tostring(t.type))
      if t.type=='CRAFT' then self.engine=require(module).new(t,e,config,save)
      else self.engine=require(module).new(t,e,config,app.navigation,save) end
    end
    return self.engine
  end
  local function resumeTask()
    local t=s.currentTask
    if t.type=='REFUEL' or t.type=='RETURN_HOME' then t.phase='work'; t.error=nil; t.blockedCategory=nil; return true end
    return engine():resume()
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
    if not s.currentTask or not config.automation.enabled then return true end
    local r=s.motionReservation; local id=s.currentTask.id
    if r and r.jobId==id and r.granted and U.distance(r.target,target)==0 then return true end
    s.motionReservation={jobId=id,from={x=from.x,y=from.y,z=from.z},target={x=target.x,y=target.y,z=target.z},granted=false}; save()
    send('task_reserve',s.motionReservation)
    return false,'movement reservation pending'
  end
  app.navigation.afterMove=function()
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
    if m.type=='task_supply_ack' then
      if s.pendingSupplyAcks[p.supplyId]~=p.jobId then return false,'supply receipt job mismatch' end
      s.pendingSupplyAcks[p.supplyId]=nil; save(); return true
    end
    if m.type=='task_assign' then
      local j=p.job; local done=s.completedTasks[j.id]
      if done then return send('task_progress',{jobId=j.id,phase='completed',progress=done.progress or 0,report=done.report}) end
      if t then return t.id==j.id,'worker already has a task' end
      local cap=({CRAFT='crafting',BUILD='building',VERIFY='building',REPAIR='building',CLEAR='building',HARVEST='logging',FARM='farming',TRANSPORT='courier'})[j.type]
      if cap and not config.capabilities[cap] then return false,'worker lacks '..cap end
      s.currentTask=U.copy(j); s.currentTask.phase='setup'; s.status='setup'; self.engine=nil; save(); return true
    end
    if not t or t.id~=p.jobId then return false,'task ID mismatch' end
    if m.type=='task_ack' and t.phase=='completed' then
      s.completedTasks[t.id]={progress=tonumber(t.progress) or t.delivered or 0,report=Reports.compact(t.report)}
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
    for supplyId,jobId in pairs(s.pendingSupplyAcks) do send('task_supply_done',{jobId=jobId,supplyId=supplyId}) end
    if s.motionReservation and not s.motionReservation.granted then send('task_reserve',s.motionReservation) end
    if not generic() then lastSend=clock(); return true end
    lastSend=clock(); local t=s.currentTask; local phase=t.paused and 'paused' or t.phase
    if not ({setup=true,work=true,waiting=true,blocked=true,completed=true,paused=true,supply=true})[phase] then phase='running' end
    local err=t.error and tostring(t.error):gsub('[%c]',' '):sub(1,512)
    send('task_progress',{jobId=t.id,phase=phase,progress=tonumber(t.progress) or t.delivered or 0,error=err,
      missingItem=t.supplyRequest and t.supplyRequest.item or t.missingItem,
      missingCount=t.supplyRequest and t.supplyRequest.count or t.missingCount,supplyId=t.supplyRequest and t.supplyRequest.id,report=Reports.compact(t.report)})
    return true
  end
  function self:step()
    if not generic() then return true end
    recoverSupplyReceipt()
    local t=s.currentTask
    if t.paused or t.phase=='completed' then return true end
    if t.fuelRecovery or t.phase=='blocked' and (t.blockedCategory=='fuel' or tostring(t.error):find('insufficient fuel',1,true)) then
      t.fuelRecovery=t.fuelRecovery or {}; save()
      local ok,err=require('autobuilder.workers.resupply').travel(t.fuelRecovery,t,app.navigation,config.depot,save)
      if ok then ok,err=require('autobuilder.storage.inventory').new(e.turtle):refuel(config.mining.fuelTarget,true) end
      if ok then t.fuelRecovery=nil; resumeTask(); save()
      elseif err then t.error=err; save() end
      return true
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
    if t.phase=='blocked' then
      if t.error and tostring(t.error):find('movement reservation pending',1,true) and s.motionReservation and s.motionReservation.granted then resumeTask()
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
      local ok,err=app.navigation:goHome()
      if ok and t.type=='REFUEL' then ok,err=require('autobuilder.storage.inventory').new(e.turtle):refuel(config.mining.fuelTarget,true) end
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
