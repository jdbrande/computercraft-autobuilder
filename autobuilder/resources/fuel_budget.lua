local U=require('autobuilder.core.util')
local Fuel=require('autobuilder.resources.fuel')
local M={}
local construction={BUILD=true,VERIFY=true,REPAIR=true,CLEAR=true,SURVEY_SITE=true,PREPARE_REGION=true}
local function result(task,current,outward,work,returning,reserve,scope)
  local b=Fuel.budget(current,outward,work,returning,reserve)
  b.taskId=task.id;b.scope=scope or 'excursion';return b
end
local function leg(a,b)
  local distance=U.distance(a,b);return distance==0 and 0 or distance+8
end
function M.construction(config,task,pose,current)
  local home=config.depot
  if not construction[task.type] or not U.position(home) or not U.position(pose) then return nil,'Construction needs a known pose and depot' end
  local height=math.max(pose.y,home.y+2,task.clearanceY or -math.huge)
  for _,block in ipairs(task.blocks or {}) do height=math.max(height,block.y+2) end
  local best=result(task,current,0,0,0,0);local limit=config.maxTravelDistance or 1024
  local targets=task.blocks or {}
  if task.siteSurvey then
    targets={};for _,column in ipairs(task.siteSurvey.columns) do targets[#targets+1]={x=column.x,y=column.minY+1,z=column.z} end
  end
  for index=task.siteSurvey and (task.progress or 0)+1 or task.index or 1,#targets do
    local plan=not task.siteSurvey and require('autobuilder.build.placement').plan(targets[index])
    if plan and task.siteAccess then plan=require('autobuilder.build.site_work').approach(task.siteAccess,targets[index],plan) end
    local stand=plan and plan.stand or targets[index]
    local outward=math.abs(pose.x-stand.x)+math.abs(pose.z-stand.z)
    local returning=math.abs(home.x-stand.x)+math.abs(home.z-stand.z)
    local longest=math.max(outward,returning,height-pose.y,height-home.y,height-stand.y)
    if longest>limit then return nil,'Construction route needs '..longest..' blocks; maxTravelDistance is '..limit..'. Increase the configured travel limit.' end
    local fallback=stand.y<targets[index].y and 2*(height-stand.y) or 0
    local access=task.siteAccess and 4*#task.siteAccess.cells or 0
    local b=result(task,current,outward+height-pose.y+height-stand.y,8+fallback+access,
      returning+height-stand.y+height-home.y,config.minimumFuelReserve or 100)
    if b.required>best.required then best=b end
  end
  return best
end
function M.mission(config,task,telemetry)
  if not task or not telemetry then return nil,'Mission and worker telemetry required' end
  local current=telemetry.fuel
  if current~='unlimited' and (not U.integer(current) or current<0 or current>100000000) then return nil,'Current fuel unavailable' end
  if task.type=='CRAFT' then return result(task,current,0,0,0,0,'stationary') end
  local pose,home=telemetry.position,telemetry.depot or config.depot
  if not pose or pose.known~=true or pose.pending or pose.uncertain or not U.position(pose) or not U.position(home) then return nil,'Trusted position and depot required for fuel budget' end
  local reserve=config.minimumFuelReserve or 100
  if construction[task.type] then
    local localConfig=setmetatable({depot=home},{__index=config})
    return M.construction(localConfig,task,pose,current)
  elseif task.type=='MINE' or not task.type and task.item then
    local g=task.exploration;local entry=g and g.entry or telemetry.miningRoute and telemetry.miningRoute.entry or (config.mining or {}).entry
    if not U.position(entry) then return nil,'Mining route geometry unavailable' end
    local outward=g and (#(g.exitRoute or {})+#(g.route or {})) or U.distance(home,entry)
    local trail=#(task.trail or {});local returning=math.max(trail,U.distance(pose,home))
    local phase=task.phase=='blocked' and task.resumePhase or task.phase
    local back=phase=='return' or task.returnReason and task.returnReason~='initial'
    if back or phase=='work' or phase=='survey' then outward=0
    elseif g then outward=math.max(0,outward-math.max(0,trail-1))
    else outward=task.outbound and math.max(0,#task.outbound-math.max(1,trail)) or U.distance(pose,entry) end
    returning=returning+outward
    reserve=reserve+((config.mining or {}).returnMargin or 8)
    if not back and phase~='work' and phase~='survey' and phase~='travel' then
      local target=telemetry.miningRoute and telemetry.miningRoute.fuelTarget or 0
      reserve=math.max(reserve,target-outward-returning-2)
    end
    return result(task,current,outward,back and 0 or 2,returning,reserve)
  elseif task.type=='TRANSPORT' or task.type=='RESCUE' then
    if not U.position(task.source) or not U.position(task.destination) then return nil,'Pickup and delivery geometry unavailable' end
    home=task.home or home
    local stage=task.cargo and task.cargo.stage or 'source'
    if stage=='home' then return result(task,current,0,0,leg(pose,home),reserve,'mission') end
    local outward=stage=='source' and leg(pose,task.source) or 0
    local work=leg(stage=='source' and task.source or pose,task.destination)
    return result(task,current,outward,work,leg(task.destination,home),reserve,task.type=='RESCUE' and 'mission' or 'excursion')
  elseif task.type=='RETURN_HOME' or task.type=='REFUEL' then
    local target=task.home or task.station and task.station.position or home
    if not U.position(target) then return nil,'Return/station geometry unavailable' end
    local distance=leg(pose,target)
    return result(task,current,0,0,distance,distance==0 and 0 or reserve,'mission')
  elseif task.type=='HARVEST' or task.type=='FARM' then
    local farm=task.farm
    if not farm or not farm.sites or #farm.sites==0 then return nil,'Managed farm geometry unavailable' end
    local height=farm.maxHeight or 8;local ceiling=farm.travelHeight or -math.huge
    for _,site in ipairs(farm.sites) do ceiling=math.max(ceiling,site.y+height+2) end
    local function route(a,b)
      if U.distance(a,b)==0 then return 0 end
      local high=math.max(ceiling,a.y,b.y)
      return high-a.y+math.abs(a.x-b.x)+math.abs(a.z-b.z)+high-b.y
    end
    local site=farm.sites[task.site or 1]
    if task.stage=='deposit' or not site then return result(task,current,0,0,route(pose,home),reserve) end
    local spec=require('autobuilder.resources.renewables').forFarm(farm,config)
    local column=task.type=='HARVEST' or spec and spec.mode=='column'
    local y=task.stage=='plant' and site.y or task.cursor or (column and site.y+height-1 or site.y)
    local stand={x=site.x,y=y+1,z=site.z}
    return result(task,current,route(pose,stand),4,route(stand,home),reserve)
  elseif task.type=='PREPARE_SITE' then
    local points=task.sitePlan and task.sitePlan.points
    if not points then return nil,'Preparation access geometry unavailable' end
    local work,last=0,pose
    for i=task.index or 1,#points do work=work+U.distance(last,points[i]);last=points[i] end
    -- Validated site plans already include their final return to the starting stand.
    return result(task,current,0,work,U.distance(last,home),reserve)
  end
  return nil,'No fuel budget for task type '..tostring(task.type)
end
function M.admit(config,task,worker)
  if not config or not config.fuel or not config.fuel.enabled or not task.id or task.workerId==worker.id
    or task.type=='RESCUE' or task.type=='REFUEL' or task.type=='RETURN_HOME' then return true end
  local b,why=M.mission(config,task,worker.telemetry)
  if not b then return false,why end
  if not b.allowed then return false,'Insufficient mission fuel: requires '..b.required..', current '..tostring(b.current) end
  return true
end
function M.forecast(state,config)
  local Q=require('autobuilder.core.workflows')
  local result={workers={},required=0,shortfall=0,current=0,unlimited=0,unknown=0,items={}}
  local jobs,ids={},{}
  for _,queue in ipairs({state.jobs or {},(state.automation or {}).jobs or {}}) do
    for _,j in pairs(queue) do if not j.physicalComplete and j.status~='completed' then jobs[#jobs+1]=j end end
  end
  for id in pairs(state.workers or {}) do ids[#ids+1]=id end
  table.sort(ids,function(a,b) return tonumber(a)<tonumber(b) end)
  table.sort(jobs,function(a,b) return (a.created or 0)<(b.created or 0) or (a.created or 0)==(b.created or 0) and a.id<b.id end)
  local function owned(j)
    return j.workerId or (j.managedFuel or j.returnManaged and j.returnReady or j.privateStation and j.factoryFlow or j.logistics and j.logisticsFlow) and j.preferredWorker
  end
  local function record(id,j,b,why)
    result.workers[id]={taskId=j.id,type=j.type or 'MINE',budget=b,error=why}
    if not b then result.unknown=result.unknown+1;return end
    result.required=result.required+b.required;result.shortfall=result.shortfall+b.shortfall
    if b.current=='unlimited' then result.unlimited=result.unlimited+1 else result.current=result.current+b.current end
    local item=(config.fuel or Fuel.defaults).item
    for _,station in ipairs((config.fuel or {}).stations or {}) do if tostring(station.workerId)==id then item=station.item or item;break end end
    local n=Fuel.items(item,b.current,b.required,config.fuel or Fuel.defaults)
    if n>0 then result.items[item]=(result.items[item] or 0)+n end
  end
  for _,j in ipairs(jobs) do
    local owner=owned(j);local id=owner and tostring(owner);local w=id and (state.workers or {})[id]
    if w and not result.workers[id] then
      local t=w.telemetry or {};local b,why
      if not w.online then why='Offline owner; last fuel is not a current observation'
      elseif t.task==j.id and t.fuelBudget and M.valid(t.fuelBudget,j.id,t.fuel) then b=M.clean(t.fuelBudget)
      else b,why=M.mission(config,j,t) end
      record(id,j,b,why)
    end
  end
  for _,j in ipairs(jobs) do
    if not owned(j) and not j.paused and j.status=='queued' then
      local ready=Q.canDispatch(state,j) and not j.preparationError
      for _,dep in ipairs(j.dependencies or {}) do
        local d=((state.automation or {}).jobs or {})[dep] or (state.jobs or {})[dep]
        if not d or d.status~='completed' then ready=false end
      end
      local cap=j.requiredCapability or (j.type=='MINE' or not j.type and j.item) and 'mining'
      if cap=='mining' and Q.factoryPending(state) then ready=false end
      local selected,best,reason
      if ready and cap then for _,id in ipairs(ids) do
        local w=state.workers[id];local t=w.telemetry
        if not result.workers[id] and w.online and t and t.status=='idle' and not t.task
          and (t.capabilities or {})[cap] and (not j.preferredWorker or j.preferredWorker==w.id)
          and (not j.privateStation or t.capabilities.isolatedCraftingV1)
          and (not j.logistics or t.capabilities.logisticsV1)
          and (not j.returnManaged or t.capabilities.returnCargoV1)
          and not Q.workerBusy(state,w.id) then
          local compatible=cap~='mining' or require('autobuilder.resources.materials').accepts(t.miningResources,j.item)
          if compatible then
            local b,why=M.mission(config,j,t)
            local fit=b and (not t.fuelLimit or b.required<=t.fuelLimit)
            local bestLimit=selected and state.workers[selected].telemetry.fuelLimit
            local bestFit=best and (not bestLimit or best.required<=bestLimit)
            if not selected or b and (not best or fit and not bestFit or fit==bestFit and (b.allowed and not best.allowed or b.allowed==best.allowed and b.required<best.required)) then
              selected,best,reason=id,b,why
            end
          end
        end
      end end
      if selected then record(selected,j,best,reason) end
    end
  end
  -- Reuse bounded exploration planning refusals; forecasting never searches for
  -- routes or creates a trip lease. A later detour may increase this lower bound.
  local groups={}
  if (config.exploration or {}).enabled and not (state.exploration or {}).paused then
    for _,g in pairs((state.exploration or {}).groups or {}) do
      if not g.paused and g.status~='completed' then groups[#groups+1]=g end
    end
  end
  table.sort(groups,function(a,b) return a.id<b.id end)
  for _,g in ipairs(groups) do
    local chosen,best
    for _,id in ipairs(ids) do
      local w=state.workers[id];local t=w.telemetry;local need=(g.fuelNeeds or {})[id]
      if need and not result.workers[id] and w.online and t and t.status=='idle' and not t.task
        and (t.capabilities or {}).explorationV1 and not Q.workerBusy(state,w.id)
        and require('autobuilder.resources.materials').accepts(t.miningResources,g.item)
        and require('autobuilder.factory.factory').equal(need.home,t.explorationHome)
        and require('autobuilder.factory.factory').equal(need.bounds,config.exploration.bounds) then
        local reserve=math.max(need.reserve,((t.miningRoute or {}).fuelTarget or 0)-2*need.outward-2)
        local b=Fuel.budget(t.fuel,need.outward,2,need.outward,reserve)
        b.taskId=g.id..':fuel';b.scope='excursion'
        if not chosen or (not t.fuelLimit or b.required<=t.fuelLimit) and (state.workers[chosen].telemetry.fuelLimit and best.required>state.workers[chosen].telemetry.fuelLimit or b.required<best.required) then chosen,best=id,b end
      end
    end
    if chosen then record(chosen,{id=best.taskId,type='MINE'},best) end
  end
  return result
end
local fields={'taskId','scope','current','outward','work','returning','reserve','required','shortfall','allowed'}
function M.valid(b,taskId,current)
  if type(b)~='table' or not U.shortString(b.taskId,128) or b.taskId~=taskId or b.current~=current
    or not ({excursion=true,mission=true,stationary=true})[b.scope] then return false end
  local ok,expected=pcall(Fuel.budget,b.current,b.outward,b.work,b.returning,b.reserve)
  if not ok then return false end
  for _,field in ipairs({'required','shortfall','allowed'}) do if b[field]~=expected[field] then return false end end
  return true
end
function M.clean(b)
  if not b then return nil end
  local clean={};for _,field in ipairs(fields) do clean[field]=b[field] end;return clean
end
return M
