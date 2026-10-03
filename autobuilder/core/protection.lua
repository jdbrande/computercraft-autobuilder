local U=require('autobuilder.core.util')
local E=require('autobuilder.resources.exploration')
local P=require('autobuilder.core.pathfinding')
local M={}
function M.preparation(job)
  return job and (job.siteSurvey~=nil or job.siteWork~=nil or job.type=='PREPARE_SITE')
end
function M.canOwn(state,job,owner)
  if job.type=='FARM' or job.type=='HARVEST' then
    for id,other in pairs((state.automation or {}).jobs or {}) do
      if id~=job.id and other.workerId and other.status~='completed' and other.farm then
        -- Registered plots are bounded to64 columns and32 blocks high. Checking
        -- their end points avoids assigning two owners that would deny each
        -- other's later mutation grants. Recheck at the ownership checkpoint.
        for _,pair in ipairs({{job,other},{other,job}}) do
          for _,p in ipairs((pair[1].farm or {}).sites or {}) do
            local top={x=p.x,y=p.y+((pair[1].farm or {}).maxHeight or 8)-1,z=p.z}
            if M.farmTarget(pair[2],p) or M.farmTarget(pair[2],top) then return false,'farm overlaps active work '..id end
          end
        end
      end
    end
  end
  if not M.preparation(job) then return true end
  if not E.box(job.bounds) then return false,'preparation requires bounded territory' end
  local interior=U.copy(job.bounds)
  if job.clearanceY then interior.max.y=math.min(interior.max.y,job.clearanceY-1) end
  local function inside(p) return U.position(p) and P.inside(p,interior) end
  for _,w in pairs(state.workers or {}) do
    local p=w.telemetry and w.telemetry.position
    if w.id~=owner and p and p.known and inside(p) then return false,'preparation contains worker '..w.id end
  end
  for key,cell in pairs((state.automation or {}).cells or {}) do
    local x,y,z=key:match('^(-?%d+),(-?%d+),(-?%d+)$')
    if cell.owner~=owner and inside({x=tonumber(x),y=tonumber(y),z=tonumber(z)}) then return false,'preparation contains reserved cell '..key end
  end
  for id,other in pairs(state.jobs or {}) do
    if other.workerId and other.status~='completed' and not other.physicalComplete then
      local g=other.exploration;local bounds=g and g.bounds or other.miningArea or other.bounds
      if not bounds then return false,'active mining territory is unknown: '..id end
      if E.overlaps(interior,bounds) then return false,'preparation overlaps active mining '..id end
      if g then for _,route in ipairs({g.route or {},g.exitRoute or {}}) do
        for _,p in ipairs(route) do if inside(p) then return false,'preparation contains mining route '..id end end
      end end
    end
  end
  return true
end
function M.farmTarget(job,target)
  if not job or not ({FARM=true,HARVEST=true})[job.type] then return false end
  local farm=job.farm
  if type(farm)~='table' or type(farm.sites)~='table' or #farm.sites<1 or #farm.sites>64 then return false end
  local height=farm.maxHeight or 8
  if not U.integer(height) or height<2 or height>32 then return false end
  local tree=job.type=='HARVEST' and ({oak=true,birch=true,spruce=true})[farm.kind]
  local column=job.type=='FARM' and ({bamboo=true,cactus=true,sugar_cane=true})[farm.kind]
  if not tree and not column and not (job.type=='FARM' and farm.kind=='wheat') then return false end
  for _,p in ipairs(farm.sites) do
    if U.position(p) and target.x==p.x and target.z==p.z and target.y>=p.y+(column and 1 or 0)
      and target.y<=p.y+((tree or column) and height-1 or 0) then return true end
  end
  return false
end
function M.areas(state,config,exceptProject,skipMiningBase,purpose)
  local areas=E.protectedAreas(state,config,exceptProject,skipMiningBase,purpose)
  local home=purpose and purpose.home
  local function box(p,radius,below,above)
    if not U.position(p) then return end
    areas[#areas+1]={min={x=p.x-radius,y=p.y-below,z=p.z-radius},max={x=p.x+radius,y=p.y+above,z=p.z+radius}}
  end
  -- Depot stands need their containers and side access, even while their turtle
  -- is offline or away. A configured stand is not evidence its chest can be dug.
  box(config.depot,1,1,home and U.position(config.depot) and U.distance(home,config.depot)==0 and 0 or 2)
  for _,w in pairs(state.workers or {}) do
    local d=w.telemetry and w.telemetry.depot
    box(d,1,1,home and purpose.owner==w.id and U.position(d) and U.distance(home,d)==0 and 0 or 2)
  end
  for _,station in ipairs((config.fuel or {}).stations or {}) do box(station.position,1,0,2) end
  for _,station in ipairs(config.supplyStations or {}) do
    box(station.position,0,0,0);box(require('autobuilder.storage.supply').container(station),0,0,0)
  end
  for _,farms in ipairs({config.farms or {},config.treeFarms or {}}) do
    for _,farm in pairs(farms) do if not purpose or farm~=purpose.farm then
      for _,p in ipairs(farm.sites or {}) do box(p,1,1,(farm.maxHeight or 8)+2) end
    end end
  end
  local out,seen={},{}
  for _,area in ipairs(areas) do
    local key=P.key(area.min)..':'..P.key(area.max)
    if not seen[key] then seen[key]=true;out[#out+1]=area end
  end
  return out
end
function M.canModify(state,config,job,target)
  if not U.position(target) or not job or not job.workerId or job.status=='completed' or job.paused
    then return false,'mutation requires active owned work bounds' end
  local bounds=job.type=='MINE' and job.miningArea or job.bounds
  local owned=E.box(bounds) and P.inside(target,bounds)
  local purpose={owner=job.workerId}
  if job.type=='FARM' or job.type=='HARVEST' then
    for _,farm in ipairs(job.type=='FARM' and config.farms or config.treeFarms) do
      if require('autobuilder.factory.factory').equal(farm,job.farm) then purpose.farm=farm;break end
    end
    owned=purpose.farm and M.farmTarget(job,target)
  elseif job.type=='PREPARE_SITE' then
    local valid,plan=pcall(require('autobuilder.build.site').plan,job.sitePlan and job.sitePlan.start)
    owned=false
    if valid and require('autobuilder.factory.factory').equal(plan,job.sitePlan) then
      for _,p in ipairs(plan.points) do if U.distance(p,target)==0 then owned=true;break end end
      local worker=(state.workers or {})[tostring(job.workerId)]
      local depot=worker and worker.telemetry and worker.telemetry.depot
      if U.position(depot) and U.distance(depot,plan.start)==0 then purpose.home=depot end
    end
  end
  if job.type=='MINE' and job.exploration then
    local g=job.exploration;owned=E.box(g.bounds) and P.inside(target,g.bounds)
    for _,p in ipairs(g.route or {}) do if U.distance(p,target)==0 then owned=true end end
    for _,p in ipairs(g.exitRoute or {}) do if U.distance(p,target)==0 then owned=false end end
    if E.protected(target,g.protectedAreas) then owned=false end
  end
  if not owned then return false,'mutation requires active owned work bounds' end
  if E.protected(target,M.areas(state,config,job.project,job.type~='MINE',purpose)) then return false,'target is registered protected infrastructure or another project' end
  for _,w in pairs(state.workers or {}) do
    local at=w.telemetry and w.telemetry.position
    if w.id~=job.workerId and at and at.known and U.position(at) and U.distance(at,target)==0 then return false,'target occupied by worker '..w.id end
  end
  local cell=((state.automation or {}).cells or {})[P.key(target)]
  if cell and (cell.owner~=job.workerId or cell.jobId~=job.id) then return false,'target held by another movement or action reservation' end
  for queueIndex,jobs in ipairs({state.jobs or {},(state.automation or {}).jobs or {}}) do
    for id,other in pairs(jobs) do
      if id~=job.id and other.workerId and other.status~='completed' and not other.physicalComplete then
        local g=other.exploration
        local bounds=g and g.bounds or other.miningArea or other.bounds
        if queueIndex==1 and not bounds then return false,'active mining territory is unknown: '..id end
        if bounds and P.inside(target,bounds) or M.farmTarget(other,target) then return false,'target belongs to active work '..id end
        if g then for _,route in ipairs({g.route or {},g.exitRoute or {}}) do
          for _,p in ipairs(route) do if U.distance(target,p)==0 then return false,'target belongs to active mining route '..id end end
        end end
      end
    end
  end
  return true
end
return M
