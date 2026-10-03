local U=require('autobuilder.core.util')
local Q=require('autobuilder.core.workflows')
local M={roles={'mining','hauling','crafting','clearing','building'}}
local roles={MINE='mining',HARVEST='mining',FARM='mining',TRANSPORT='hauling',CRAFT='crafting',
  SURVEY_SITE='clearing',PREPARE_SITE='clearing',PREPARE_REGION='clearing',CLEAR='clearing',BUILD='building',VERIFY='building',REPAIR='building'}
local capabilities={mining={'mining','logging','farming'},hauling={'courier'},crafting={'crafting'},
  clearing={'siteWorkV1','siteSurveyV1','sitePreparation'},building={'building'}}
local secondsPerUnit={mining=8,hauling=4,crafting=1,clearing=2,building=3}
M.defaults={roles={}}
for _,role in ipairs(M.roles) do M.defaults.roles[role]={min=0,max=128} end
function M.validate(c)
  assert(type(c)=='table' and type(c.roles)=='table','invalid scaling configuration')
  for _,role in ipairs(M.roles) do
    local r=c.roles[role]
    assert(type(r)=='table' and U.integer(r.min) and U.integer(r.max) and r.min>=0 and r.min<=r.max and r.max<=128,'invalid scaling limits for '..role)
  end
  return true
end
function M.limits(state,c,role)
  local base=(c or {}).scaling or M.defaults;local fleet=state.fleet
  if fleet and fleet.limits and require('autobuilder.factory.factory').equal(fleet.config,base) then return fleet.limits[role] end
  return base.roles[role]
end
local function commit(state,fleet,save)
  local previous=state.fleet;state.fleet=fleet
  local ok,result,why=pcall(save)
  if not ok or not result then state.fleet=previous;error(ok and why or result,0) end
end
function M.setLimits(state,c,role,min,max,save)
  assert(M.defaults.roles[role],'Unknown fleet role')
  local limits={};for _,name in ipairs(M.roles) do limits[name]=U.copy(M.limits(state,c,name)) end
  limits[role]={min=min,max=max};M.validate({roles=limits})
  local fleet=U.copy(state.fleet or {metrics={}});fleet.config=U.copy(c.scaling or M.defaults);fleet.limits=limits
  commit(state,fleet,save)
end
function M.role(j) return j and roles[j.type or (j.item and 'MINE')] end
local function capable(w,role)
  local caps=w.telemetry and w.telemetry.capabilities or {}
  for _,cap in ipairs(capabilities[role]) do if caps[cap] then return true end end
  return false
end
local function idle(state,c,w,role)
  local t=w.telemetry
  return w.online and t and t.status=='idle' and not t.task and not Q.workerBusy(state,w.id)
    and (role=='crafting' or t.fuel==nil or t.fuel=='unlimited' or U.finite(t.fuel) and t.fuel>=math.max(1,c.minimumFuelReserve or 0))
end
local function owner(j)
  if j.status=='completed' or j.physicalComplete then return nil end
  return j.workerId or (j.privateStation and j.factoryFlow or j.logistics and j.logisticsFlow) and j.preferredWorker
end
local function units(j)
  if j.type=='MINE' or not j.type then return math.max(0,(j.quantity or 0)-(j.progress and j.progress.delivered or 0)) end
  if j.siteSurvey then return math.max(0,math.max(1,#(j.siteSurvey.columns or {}))-(j.progress or 0)) end
  if j.blocks then return math.max(0,#j.blocks-(j.progress or 0)) end
  return math.max(0,(j.quantity or j.batches or 1)-(j.delivered or type(j.progress)=='number' and j.progress or 0))
end
local function ready(state,j)
  if j.paused or j.status=='completed' then return false end
  for _,id in ipairs(j.dependencies or {}) do
    local dep=(state.automation or {}).jobs and state.automation.jobs[id] or (state.jobs or {})[id]
    if not dep or dep.status~='completed' then return false end
  end
  return true
end
function M.snapshot(state,c,counts,now,workers)
  if workers and workers~=state.workers then state=setmetatable({workers=workers},{__index=state}) end
  c=c or {};counts=counts or {};local view,owned,projectUnits={},{},{}
  for _,role in ipairs(M.roles) do
    view[role]={active=0,idle=0,queue=0,ready=0,remaining=0,desired=0,rate=1/secondsPerUnit[role]};owned[role]={};projectUnits[role]={}
    local metric=state.fleet and state.fleet.metrics and state.fleet.metrics[role]
    if metric and #(metric.samples or {})>0 then
      local n,t=0,0;for _,sample in ipairs(metric.samples) do n=n+sample.units;t=t+sample.seconds end
      view[role].rate=n/math.max(1,t);view[role].measured=true
    end
  end
  local function add(j,mining)
    local role=M.role(j);if not role or j.status=='completed' or j.physicalComplete then return end
    local r=view[role];local id=owner(j)
    if id then owned[role][id]=true else r.queue=r.queue+1;if ready(state,j) then r.ready=r.ready+1 end end
    if not (mining and j.exploration) then r.remaining=r.remaining+units(j) end
    if j.project then projectUnits[role][j.project]=(projectUnits[role][j.project] or 0)+units(j) end
    if role=='hauling' and U.position(j.source) and U.position(j.destination) then
      r.travel=(r.travel or 0)+2*U.distance(j.source,j.destination)*units(j)/math.max(1,j.quantity or 1)
    end
    if j.error or j.stockError or j.coverageError or j.preparationError then r.bottleneck=r.bottleneck or j.stockError or j.coverageError or j.preparationError or j.error end
  end
  for _,j in pairs(state.jobs or {}) do add(j,true) end
  for _,j in pairs((state.automation or {}).jobs or {}) do add(j,false) end
  for name,p in pairs((state.automation or {}).projects or {}) do if not p.paused then
    local structural=({building=true,verifying=true,repairing=true,clearing=true})[p.phase]
    if structural then
      local role=p.phase=='clearing' and 'clearing' or 'building'
      view[role].remaining=view[role].remaining+math.max(0,(p.total or 0)-(p.completed or 0)-(projectUnits[role][name] or 0))
    end
    local site=p.site;local estimate=0
    if site and site.status=='surveying' then estimate=math.max(0,(site.columnCount or p.total or 0)-(p.completed or 0))
    elseif site and site.work and site.work.status~='completed' then
      estimate=math.ceil((site.estimatedCells or 0)*math.max(0,(site.regionCount or 0)-(site.work.completed or 0))/math.max(1,site.regionCount or 0))
    end
    view.clearing.remaining=view.clearing.remaining+math.max(0,estimate-(projectUnits.clearing[name] or 0))
  end end
  local exploration=(state.exploration or {})
  for _,g in pairs(exploration.groups or {}) do if g.status~='completed' and not g.paused and not exploration.paused then
    local demand=math.max(0,g.target-(counts[g.item] or 0));local r=view.mining
    r.remaining=r.remaining+demand
    if demand>0 then r.queue=r.queue+1;r.ready=r.ready+demand;r.bottleneck=r.bottleneck or g.error end
  end end
  for _,role in ipairs(M.roles) do
    local r=view[role];for _ in pairs(owned[role]) do r.active=r.active+1 end
    local distance,n=0,0
    for _,w in pairs(state.workers or {}) do if capable(w,role) and idle(state,c,w,role) then
      r.idle=r.idle+1
      local t=w.telemetry;local home=t.explorationHome
      local origin=home and home.depot or t.depot;local route=home and home.exitRoute or {}
      if U.position(origin) and U.position(route[#route] or t.position) then
        distance=distance+math.max(#route,U.distance(origin,route[#route] or t.position));n=n+1
      end
    end end
    local limits=M.limits(state,c,role)
    local cost=1/math.max(1/120,r.rate)
    if not r.measured and r.travel then cost=cost+r.travel/math.max(1,r.remaining) end
    if role=='mining' and not r.measured and n>0 then cost=cost+2*distance/n/math.max(1,math.min(64,r.remaining)) end
    -- ponytail: a shared two-minute planning window, not an optimizer. Measured
    -- delivery costs replace bootstrap rates; durable task gates remain final.
    local useful=math.min(r.active+r.idle,r.active+r.ready,math.ceil(r.remaining*cost/120))
    if r.remaining>0 then r.desired=math.min(limits.max,math.max(math.min(limits.min,r.active+r.idle,r.active+r.ready),useful)) end
    r.estimatedSeconds=r.remaining*cost/math.max(1,r.desired)
    r.saturated=r.remaining>0 and r.desired>=r.active+r.idle
    if r.remaining>0 and limits.max==0 then r.bottleneck=r.bottleneck or 'Role maximum is zero' end
    if r.remaining>0 and r.active+r.idle==0 then r.bottleneck=r.bottleneck or 'No idle capable fueled worker' end
  end
  return view
end
local rank={mining=1,hauling=2,crafting=3,clearing=4,building=5}
function M.priority(view,j)
  local role=M.role(j)
  if not role or j.siteAccess then return 10 end
  local r=view[role]
  return math.max(0,r.desired-r.active)/math.max(1,r.desired)+(6-rank[role])/1000
end
local function competing(state,c,role,w,counts)
  local function matches(j)
    if M.role(j)~=role or owner(j) or j.status~='queued' or not ready(state,j) or j.preparationError or j.coverageError
      or j.preferredWorker and j.preferredWorker~=w.id or j.requiredCapability and not (w.telemetry.capabilities or {})[j.requiredCapability] then return false end
    if not Q.canDispatch(state,j) then return false end
    if not require('autobuilder.core.protection').canOwn(state,j,w.id) then return false end
    return true
  end
  for _,j in pairs((state.automation or {}).jobs or {}) do if matches(j) then return true end end
  if role=='mining' and not Q.factoryPending(state) then
    local caps=w.telemetry.capabilities or {}
    for _,j in pairs(state.jobs or {}) do
      if matches(j) and caps.mining and require('autobuilder.resources.materials').accepts(w.telemetry.miningResources,j.item) then return true end
    end
    if caps.explorationV1 and require('autobuilder.resources.exploration').home(w.telemetry.explorationHome) and not (state.exploration or {}).paused then
      for _,g in pairs((state.exploration or {}).groups or {}) do
        if g.status=='running' and not g.paused and g.target>((counts or {})[g.item] or 0)
          and require('autobuilder.resources.materials').accepts(w.telemetry.miningResources,g.item) then return true end
      end
    end
  end
  return false
end
function M.canAssign(state,c,j,w,counts,now,workers)
  if workers and workers~=state.workers then state=setmetatable({workers=workers},{__index=state}) end
  local role=M.role(j)
  if not role or j.siteAccess or owner(j)==w.id then return true end
  if not idle(state,c or {},w,role) then return false,'worker is no longer idle or lacks fuel' end
  if not capable(w,role) or j.requiredCapability and not (w.telemetry.capabilities or {})[j.requiredCapability] then return false,'worker capability changed before assignment' end
  local view=M.snapshot(state,c,counts,now);local r=view[role]
  if r.active>=r.desired then return false,role..' allocation '..r.active..'/'..r.desired end
  local priority=M.priority(view,j)
  for _,other in ipairs(M.roles) do
    if other~=role and capable(w,other) and view[other].active<view[other].desired
      and M.priority(view,{type=({mining='MINE',hauling='TRANSPORT',crafting='CRAFT',clearing='PREPARE_REGION',building='BUILD'})[other]})>priority
      and competing(state,c,other,w,counts) then return false,'idle worker needed for '..other..' bottleneck' end
  end
  return true
end
function M.preference(state,c,j,w)
  local n=0;for _,role in ipairs(M.roles) do if capable(w,role) then n=n+1 end end
  return n
end
function M.window(state,c,role)
  local n=0
  for _,w in pairs(state.workers or {}) do if w.online and capable(w,role) then n=n+1 end end
  -- Neighboring regions retain a one-cell safety gap. Expose alternate regions
  -- so a queue sized to the fleet does not halve useful physical concurrency.
  return math.max(4,math.min(64,2*math.min(M.limits(state,c,role).max,n)))
end
function M.update(state,c,counts,now,save)
  local view=M.snapshot(state,c,counts,now);local fleet=U.copy(state.fleet or {metrics={}})
  local previous=fleet.status or {};local events={};fleet.decisions=fleet.decisions or {}
  for _,role in ipairs(M.roles) do
    local r,old=view[role],previous[role]
    if (not old and r.desired>0) or old and (old.desired~=r.desired or old.bottleneck~=r.bottleneck) then
      local event={at=now,role=role,from=old and old.desired or 0,target=r.desired,active=r.active,idle=r.idle,
        remaining=r.remaining,reason=r.bottleneck or (r.remaining==0 and 'work drained' or 'ready workload and delivery rate')}
      events[#events+1]=event;fleet.decisions[#fleet.decisions+1]=event
      if #fleet.decisions>32 then table.remove(fleet.decisions,1) end
    end
  end
  fleet.status=view
  if #events>0 then commit(state,fleet,save) else state.fleet=fleet end
  return view,events
end
function M.describe(state,c,counts,now)
  local view=M.snapshot(state,c,counts,now);local lines={'FLEET ALLOCATION'}
  for _,role in ipairs(M.roles) do
    local r=view[role];local limits=M.limits(state,c,role)
    lines[#lines+1]=role..' target='..r.desired..' active='..r.active..' idle='..r.idle..' limits='..limits.min..'..'..limits.max
    lines[#lines+1]='queue='..r.queue..' remaining='..r.remaining..' rate='..(r.measured and '' or '~')..string.format('%.3f/s',r.rate)..' estimate='..math.ceil(r.estimatedSeconds)..'s'
    if r.bottleneck then lines[#lines+1]=r.bottleneck end
  end
  lines[#lines+1]='fleet limit <role> <minimum> <maximum>'
  return lines
end
function M.record(state,j,save,now)
  local role=M.role(j);local startedAt=j.factoryStartedAt or j.assignedAt
  local completedAt=j.physicalCompletedAt or j.factoryCompletedAt or (j.privateStation or j.logistics) and now or j.completedAt
  if not role or j.scalingSampled or not j.workerId or not (j.status=='completed' or j.physicalComplete)
    or not U.finite(startedAt) or not U.finite(completedAt) or completedAt<startedAt then return false end
  local amount
  if role=='mining' and (j.type=='MINE' or not j.type) then amount=j.progress and j.progress.delivered or 0
  elseif role=='hauling' then amount=j.delivered or j.transportReceipt and j.transportReceipt.delivered or 0
  elseif role=='crafting' then amount=j.factoryFlow and j.factoryFlow.collect and j.factoryFlow.collect.delivered or j.delivered or j.production and j.production.delivered or 0
  else amount=type(j.progress)=='number' and j.progress or 0 end
  local previous=state.fleet;local fleet=U.copy(previous or {metrics={}});fleet.metrics=fleet.metrics or {}
  local r=fleet.metrics[role] or {units=0,seconds=0,count=0,samples={}};fleet.metrics[role]=r
  local duration=math.max(1,completedAt-startedAt)
  r.units=r.units+amount;r.seconds=r.seconds+duration;r.count=r.count+1
  r.samples[#r.samples+1]={units=amount,seconds=duration};if #r.samples>32 then table.remove(r.samples,1) end
  state.fleet=fleet;j.scalingSampled=true
  local ok,result,why=pcall(save)
  if not ok or not result then state.fleet=previous;j.scalingSampled=nil;error(ok and why or result,0) end
  return true
end
return M
