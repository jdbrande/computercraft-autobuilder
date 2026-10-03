local U=require('autobuilder.core.util')
local M={}
M.types={RESCUE=true,FUEL_STATION=true,CRAFT=true,SMELT=true,BUILD=true,VERIFY=true,REPAIR=true,CLEAR=true,PREPARE_SITE=true,SURVEY_SITE=true,PREPARE_REGION=true,TRANSPORT=true,HARVEST=true,FARM=true,REFUEL=true,RETURN_HOME=true}
local phases={setup=true,work=true,running=true,waiting=true,blocked=true,completed=true,paused=true,supply=true}
local function bounded(value,depth,seen,budget)
  budget.n=budget.n+1; if budget.n>20000 or depth>12 then return false end
  if type(value)=='string' then budget.bytes=budget.bytes+#value; return #value<=512 and budget.bytes<=60000 end
  if type(value)=='number' then return U.finite(value) end
  if type(value)=='boolean' or value==nil then return true end
  if type(value)~='table' or seen[value] then return false end
  seen[value]=true
  for k,v in pairs(value) do
    if (type(k)~='string' and type(k)~='number') or not bounded(k,depth+1,seen,budget) or not bounded(v,depth+1,seen,budget) then return false end
  end
  seen[value]=nil; return true
end
local function quantities(map)
  if type(map)~='table' then return false end
  local size=0
  for item,n in pairs(map) do
    size=size+1
    if size>64 or not U.shortString(item,128) or not U.integer(n) or n<0 or n>100000000 then return false end
  end
  return true
end
function M.validPoseReport(p)
  return type(p)=='table' and U.shortString(p.jobId,100) and U.integer(p.sequence) and p.sequence>=1
    and p.sequence<=9007199254740991 and U.position(p.origin) and type(p.granted)=='boolean'
    and ({ready=true,probe=true,['return']=true,settling=true,settled=true})[p.stage]==true
end
function M.poseReport(p)
  if not p then return nil end
  return {jobId=p.jobId,sequence=p.sequence,origin={x=p.origin.x,y=p.origin.y,z=p.origin.z},stage=p.stage,granted=p.granted==true}
end
function M.validate(kind,p)
  if type(p)~='table' or not bounded(p,0,{}, {n=0,bytes=0}) then return false,'oversized or malformed task payload' end
  if kind=='task_assign' then
    local j=p.job
    if type(j)~='table' or not U.shortString(j.id,100) or not M.types[j.type] then return false,'invalid task assignment' end
    if j.requiresSite~=nil and (type(j.requiresSite)~='boolean' or not ({BUILD=true,REPAIR=true,CLEAR=true,VERIFY=true})[j.type]
      or not U.shortString(j.project,64) or not j.project:match('^[%w_-]+$') or not U.integer(j.projectRun) or j.projectRun<0) then
      return false,'invalid preparation gate'
    end
    if j.loadedArea~=nil and not require('autobuilder.core.chunks').validGrant(j.loadedArea) then return false,'invalid loaded mission envelope' end
    if j.returnManaged~=nil and (type(j.returnManaged)~='boolean' or j.type~='RETURN_HOME' or not U.position(j.home)) then return false,'invalid managed home assignment' end
    if j.returning~=nil and not require('autobuilder.storage.returns').validContract(j) then return false,'invalid home cargo contract' end
    if j.logistics~=nil and not require('autobuilder.storage.nodes').validContract(j) then return false,'invalid managed logistics contract' end
    if j.privateStation and (j.type~='CRAFT' or not require('autobuilder.factory.stations').valid(j.privateStation)
      or j.workerId~=j.privateStation.workerId or j.preferredWorker~=j.workerId) then return false,'invalid private crafting station' end
    if j.type=='RESCUE' and (not U.position(j.source) or not U.position(j.destination) or not U.position(j.home)
      or not U.integer(j.targetWorker) or j.targetWorker<0 or not U.integer(j.quantity) or j.quantity<1 or j.quantity>64) then return false,'invalid rescue assignment' end
    if j.managedFuel and (j.type~='REFUEL' or type(j.station)~='table' or not U.position(j.station.position)
      or not U.integer(j.fuelTarget) or j.fuelTarget<1 or j.fuelTarget>100000000) then return false,'invalid managed fuel assignment' end
    if j.type=='FUEL_STATION' then return false,'controller-only task' end
    if j.siteWork~=nil and j.type~='PREPARE_REGION' or j.siteSurvey~=nil and j.type~='SURVEY_SITE' then return false,'site metadata requires its matching task type' end
    if j.type=='SURVEY_SITE' and not require('autobuilder.build.site_survey').validContract(j) then return false,'invalid site survey assignment' end
    if j.type=='PREPARE_REGION' and not require('autobuilder.build.site_work').validContract(j) then return false,'invalid region preparation assignment' end
    if j.type=='PREPARE_SITE' then
      local plan=j.sitePlan
      if type(plan)~='table' or not U.position(plan.start) or not U.heading(plan.start.heading)
        or type(plan.points)~='table' or #plan.points<1 or #plan.points>512 then return false,'invalid automatic site plan' end
      for _,p in ipairs(plan.points) do if not U.position(p) then return false,'invalid site waypoint' end end
    end
    if j.blocks then
      if type(j.blocks)~='table' or #j.blocks>512 or #j.blocks<1 then return false,'invalid block batch' end
      for _,b in ipairs(j.blocks) do
        if not U.position(b) or not U.shortString(b.name,128) or type(b.state)~='table' then return false,'invalid block record' end
        for k,v in pairs(b.state) do if type(k)~='string' or type(v)~='string' then return false,'invalid block state' end end
      end
    end
    if (j.stockInputs or j.stockOutputs) and (not quantities(j.stockInputs) or not quantities(j.stockOutputs)) then return false,'invalid stock contract' end
    if j.item and not U.shortString(j.item,128) then return false,'invalid task item' end
    if j.quantity and (not U.integer(j.quantity) or j.quantity<1 or j.quantity>1000000) then return false,'invalid task quantity' end
    if j.batches and (not U.integer(j.batches) or j.batches<1 or j.batches>1000000) then return false,'invalid task batches' end
  else
    if not U.shortString(p.jobId,100) then return false,'invalid task ID' end
    if p.supplyId and not U.shortString(p.supplyId,160) then return false,'invalid supply identity' end
    if kind=='task_supply' or kind=='task_supply_done' or kind=='task_supply_ack' then
      if not U.shortString(p.supplyId,160) or p.supplyId:sub(1,#p.jobId+8)~=p.jobId..':supply:' or not p.supplyId:sub(#p.jobId+9):match('^%d+$') then return false,'supply batch identity required' end
      if p.station~=nil and (kind~='task_supply' or not require('autobuilder.storage.supply').validStation(p.station)) then return false,'invalid supply station grant' end
    end
    if kind=='task_fuel_freeze' then
      if not U.position(p.position) or not U.shortString(p.item,128) or not U.integer(p.quantity) or p.quantity<1 or p.quantity>64
        or not U.integer(p.fuelTarget) or p.fuelTarget<1 or p.fuelTarget>100000000 then return false,'invalid rescue freeze' end
    elseif kind=='task_fuel_consume' then
      if not U.integer(p.quantity) or p.quantity<1 or p.quantity>64 then return false,'invalid rescue consumption' end
    elseif kind=='task_fuel_status' then
      if not ({frozen=true,consuming=true,consumed=true,released=true,blocked=true})[p.phase] or not U.position(p.position)
        or not U.integer(p.quantity) or p.quantity<0 or p.quantity>64 or not U.integer(p.capacity) or p.capacity<0 or p.capacity>64
        or p.fuel~='unlimited' and (not U.finite(p.fuel) or p.fuel<0)
        or p.error and not U.shortString(p.error,512) then return false,'invalid rescue status' end
    elseif kind=='task_fuel_release' then
      -- Identity-only release; the worker verifies its durable consumed receipt.
    elseif kind=='task_progress' then
      if p.siteReport~=nil and not require('autobuilder.build.site_survey').validSummary(p.siteReport) then return false,'invalid site survey report' end
      if p.homeReceipt~=nil and not require('autobuilder.storage.returns').validReceipt(p.homeReceipt) then return false,'invalid home deposit receipt' end
      local tr=p.transportReceipt
      if tr and (type(tr)~='table' or not U.integer(tr.sequence) or tr.sequence<0 or tr.sequence>9007199254740991
        or not U.integer(tr.pickedUp) or tr.pickedUp<0 or tr.pickedUp>64
        or not U.integer(tr.delivered) or tr.delivered<0 or tr.delivered>tr.pickedUp) then return false,'invalid transport receipt' end
      if p.fuelDelivered~=nil and (not U.integer(p.fuelDelivered) or p.fuelDelivered<0 or p.fuelDelivered>64) then return false,'invalid rescue delivery quantity' end
      local r=p.stockReceipt
      if r and (type(r)~='table' or not U.integer(r.sequence) or r.sequence<1 or r.sequence>9007199254740991
        or not quantities(r.withdrawn) or not quantities(r.delivered)) then return false,'invalid stock receipt' end
      if not phases[p.phase] or not U.integer(p.progress or 0) or (p.progress or 0)<0 then return false,'invalid task progress' end
      if p.error and not U.shortString(p.error,512) then return false,'invalid task error' end
      if p.missingItem and not U.shortString(p.missingItem,128) then return false,'invalid missing item' end
      if p.missingCount and (not U.integer(p.missingCount) or p.missingCount<1 or p.missingCount>1000000) then return false,'invalid missing count' end
    elseif kind=='task_pose_reserve' or kind=='task_pose_grant' or kind=='task_pose_done' or kind=='task_pose_ack' then
      if not U.integer(p.sequence) or p.sequence<1 or p.sequence>9007199254740991 or not U.position(p.origin)
        or p.reason~=nil and not U.shortString(p.reason,512)
        or kind=='task_pose_grant' and type(p.granted)~='boolean' then return false,'invalid pose recovery contract' end
    elseif kind=='task_reserve' or kind=='task_position' then
      if p.work~=nil and (kind~='task_reserve' or type(p.work)~='boolean') then return false,'invalid mutation reservation' end
      if not U.position(p.from) or not U.position(p.target) then return false,'invalid movement reservation' end
    elseif kind=='task_grant' then
      if p.work~=nil and type(p.work)~='boolean' or p.reason~=nil and not U.shortString(p.reason,512) then return false,'invalid mutation grant' end
      if not U.position(p.target) or type(p.granted)~='boolean' then return false,'invalid movement grant' end
    elseif kind=='task_supply' then
      if not U.shortString(p.item,128) or not U.integer(p.count) or p.count<1 or p.count>64 then return false,'invalid supply grant' end
    elseif kind~='task_ack' and kind~='task_resume' and kind~='task_pause' and kind~='task_supply_done' and kind~='task_supply_ack' then return false,'unknown task message' end
  end
  return true
end
function M.clean(_,p) return U.copy(p) end
return M
