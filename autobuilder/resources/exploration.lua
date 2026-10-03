local U=require('autobuilder.core.util')
local P=require('autobuilder.core.pathfinding')
local Materials=require('autobuilder.resources.materials')
local M={}
function M.box(b)
  if type(b)~='table' or not U.position(b.min) or not U.position(b.max) then return false end
  for _,a in ipairs({'x','y','z'}) do if b.min[a]>b.max[a] then return false end end
  return true
end
function M.overlaps(a,b)
  if not a or not b then return true end
  for _,k in ipairs({'x','y','z'}) do if a.max[k]<b.min[k] or b.max[k]<a.min[k] then return false end end
  return true
end
function M.sameBox(a,b)
  if not M.box(a) or not M.box(b) then return false end
  for _,edge in ipairs({'min','max'}) do for _,axis in ipairs({'x','y','z'}) do if a[edge][axis]~=b[edge][axis] then return false end end end
  return true
end
function M.validate(c)
  if type(c)~='table' or type(c.enabled)~='boolean' then return nil,'invalid exploration mode' end
  if c.revision~=nil and (not U.integer(c.revision) or c.revision<0) then return nil,'invalid exploration settings revision' end
  if not c.enabled then return true end
  if not U.position(c.base) or not M.box(c.bounds) or not M.box(c.baseProtection) then return nil,'exploration requires base, bounds and base protection' end
  if not U.integer(c.dimensionMinY) or not U.integer(c.dimensionMaxY) or c.dimensionMinY>c.dimensionMaxY
    or c.bounds.min.y<c.dimensionMinY or c.bounds.max.y>c.dimensionMaxY then return nil,'exploration exceeds dimension heights' end
  local count=1
  for _,a in ipairs({'x','y','z'}) do
    local size=a=='y' and 3 or 8
    count=count*(math.floor((c.bounds.max[a]-c.base[a])/size)-math.floor((c.bounds.min[a]-c.base[a])/size)+1)
  end
  if count>4096 then return nil,'exploration exceeds 4096 sectors' end
  return true
end
function M.sectors(c)
  assert(M.validate(c)); local out={}
  if not c.enabled then return out end
  for x=math.floor((c.bounds.min.x-c.base.x)/8),math.floor((c.bounds.max.x-c.base.x)/8) do
    for y=math.floor((c.bounds.min.y-c.base.y)/3),math.floor((c.bounds.max.y-c.base.y)/3) do
      for z=math.floor((c.bounds.min.z-c.base.z)/8),math.floor((c.bounds.max.z-c.base.z)/8) do
        local lo={x=c.base.x+x*8,y=c.base.y+y*3,z=c.base.z+z*8}; local hi={x=lo.x+7,y=lo.y+2,z=lo.z+7}
        for _,a in ipairs({'x','y','z'}) do lo[a]=math.max(lo[a],c.bounds.min[a]); hi[a]=math.min(hi[a],c.bounds.max[a]) end
        out[#out+1]={id=x..','..y..','..z,x=x,y=y,z=z,bounds={min=lo,max=hi}}
      end
    end
  end
  return out
end
function M.surveyCell(b,index)
  local nx=b.max.x-b.min.x+1; local nz=b.max.z-b.min.z+1; local i=index-1
  if i>=nx*nz*(b.max.y-b.min.y+1) then return nil end
  local y=math.floor(i/(nx*nz)); local z=math.floor(i/nx)%nz; local x=i%nx
  if z%2==1 then x=nx-1-x end
  return {x=b.min.x+x,y=b.min.y+y,z=b.min.z+z}
end
local function coverage(survey)
  local points={}
  if survey then
    for _,p in ipairs(survey.surveyed or {}) do points[P.key(p)]=p end
    for i=1,(survey.cursor or 1)-1 do local p=M.surveyCell(survey.bounds,i); if p then points[P.key(p)]=p end end
  end
  return points
end
function M.candidates(records,c,item,start)
  local result={}; local material=assert(Materials.get(item))
  for _,sector in ipairs(M.sectors(c)) do
    local r=records[sector.id] or {}; local survey=(r.surveys or {})[item]
    if not survey or not survey.exhausted or not M.sameBox(survey.bounds,sector.bounds) then
      sector.cursor=survey and M.sameBox(survey.bounds,sector.bounds) and survey.cursor or 1
      sector.surveyed={}
      local visited=coverage(survey); local keys={}; for k in pairs(visited) do keys[#keys+1]=k end; table.sort(keys)
      for _,k in ipairs(keys) do if P.inside(visited[k],sector.bounds) then sector.surveyed[#sector.surveyed+1]=U.copy(visited[k]) end end
      sector.known=false
      for _,p in ipairs(r.observations or {}) do if material.blocks[p.name] and P.inside(p,sector.bounds) then sector.known=true; break end end
      sector.distance=U.distance(start,sector.bounds.min)
      result[#result+1]=sector
    end
  end
  table.sort(result,function(a,b)
    if a.known~=b.known then return a.known end
    if a.distance~=b.distance then return a.distance<b.distance end
    local ay=math.abs(a.bounds.min.y-(material.suggestedY or start.y)); local by=math.abs(b.bounds.min.y-(material.suggestedY or start.y))
    if ay~=by then return ay<by end
    if a.x~=b.x then return a.x<b.x end; if a.y~=b.y then return a.y<b.y end; return a.z<b.z
  end)
  return result
end
function M.protected(p,boxes)
  for _,box in ipairs(boxes or {}) do if P.inside(p,box) then return true end end
  return false
end
function M.plan(sector,ctx)
  local c=ctx.config; local envelope=c.exploration.bounds; local claims={}
  if #(ctx.protectedAreas or {})>128 then return nil,'Too many protection boxes; combine nearby infrastructure in base protection' end
  for _,j in pairs(ctx.activeJobs or {}) do
    if j.workerId and not j.physicalComplete and j.status~='completed' then
      local g=j.exploration
      if not g then return nil,'territory owned by a fixed miner' end
      if M.overlaps(sector.bounds,g.bounds) then return nil,'sector owned' end
      for _,path in ipairs({g.route,g.exitRoute or {}}) do
        for _,p in ipairs(path) do if P.inside(p,sector.bounds) then return nil,'sector contains owned route' end end
      end
      claims[#claims+1]=g
    end
  end
  local function allowed(p)
    if not P.inside(p,envelope) or M.protected(p,ctx.protectedAreas) then return false end
    for _,g in ipairs(claims) do
      if P.inside(p,g.bounds) then return false end
      for _,r in ipairs(g.route) do if P.key(r)==P.key(p) then return false end end
      for _,r in ipairs(g.exitRoute or {}) do if P.key(r)==P.key(p) then return false end end
    end
    return true
  end
  local start=ctx.depot
  for _,p in ipairs(ctx.exitRoute or {}) do
    if U.distance(start,p)~=1 then return nil,'invalid clear exit route' end
    for _,g in ipairs(claims) do
      if P.inside(p,g.bounds) then return nil,'exit crosses owned sector' end
      for _,path in ipairs({g.route,g.exitRoute or {}}) do for _,r in ipairs(path) do
        if P.key(r)==P.key(p) then return nil,'exit crosses owned route' end
      end end
    end
    start=p
  end
  local entry={}
  for _,a in ipairs({'x','y','z'}) do entry[a]=math.max(sector.bounds.min[a],math.min(start[a],sector.bounds.max[a])) end
  if not P.inside(start,envelope) then return nil,'exit outside exploration envelope' end
  if not allowed(entry) then
    local nearest,distance
    for x=sector.bounds.min.x,sector.bounds.max.x do for y=sector.bounds.min.y,sector.bounds.max.y do for z=sector.bounds.min.z,sector.bounds.max.z do
      local p={x=x,y=y,z=z}; local d=U.distance(start,p)
      if allowed(p) and (not distance or d<distance) then nearest=p; distance=d end
    end end end
    if not nearest then return nil,'protected or owned entry' end
    entry=nearest
  end
  local lower=U.distance(start,entry)+#(ctx.exitRoute or {})
  local limit=math.min(math.floor(c.maxTravelDistance),1024)
  if lower>limit then return nil,'route exceeds travel limit' end
  if ctx.availableFuel~='unlimited' and ctx.availableFuel<lower*2+c.minimumFuelReserve+c.mining.returnMargin+2 then return nil,'insufficient round-trip fuel' end
  local route={}; local position=U.copy(start)
  for _,axis in ipairs({'x','y','z'}) do
    while position[axis]~=entry[axis] do
      position[axis]=position[axis]+(entry[axis]>position[axis] and 1 or -1)
      if not allowed(position) then route=nil; break end
      route[#route+1]=U.copy(position)
    end
    if not route then break end
  end
  local why
  -- ponytail: bounded detour search; a failed candidate gives the next sector a turn.
  if not route then route,why=P.find(start,entry,allowed,math.min(c.mining.pathBudget,256)) end
  if not route then return nil,why end
  local distance=#route+#(ctx.exitRoute or {})
  if distance>math.min(math.floor(c.maxTravelDistance),1024) then return nil,'route exceeds travel limit' end
  if ctx.availableFuel~='unlimited' and ctx.availableFuel<distance*2+c.minimumFuelReserve+c.mining.returnMargin+2 then return nil,'insufficient round-trip fuel' end
  return {version=1,depot=U.copy(ctx.depot),sectorId=sector.id,bounds=U.copy(sector.bounds),entry=entry,route=route,exitRoute=U.copy(ctx.exitRoute or {}),
    cursor=sector.cursor or 1,surveyed=U.copy(sector.surveyed or {}),envelope=U.copy(envelope),protectedAreas=U.copy(ctx.protectedAreas or {})}
end
function M.list(t,limit,valid)
  if type(t)~='table' then return false end
  local count=0
  for k,v in pairs(t) do
    count=count+1
    if count>limit or not U.integer(k) or k<1 or k>limit or not valid(v) then return false end
  end
  for i=1,count do if t[i]==nil then return false end end
  return true
end
function M.home(h)
  if type(h)~='table' or not U.position(h.depot) or not M.list(h.exitRoute,1024,U.position)
    or not M.list(h.protectedAreas,128,M.box) then return false end
  local p=h.depot
  for _,v in ipairs(h.exitRoute) do if U.distance(p,v)~=1 then return false end; p=v end
  return true
end
function M.geometry(g)
  if type(g)~='table' or g.version~=1 or not U.shortString(g.groupId,100) or not U.shortString(g.sectorId,100)
    or not M.home(g) or not M.box(g.bounds) or not M.box(g.envelope) or not U.position(g.entry)
    or not U.integer(g.cursor) or g.cursor<1 or g.cursor>193 or not M.list(g.route,1024,U.position) then return false end
  if not P.inside(g.bounds.min,g.envelope) or not P.inside(g.bounds.max,g.envelope) or not P.inside(g.entry,g.bounds) then return false end
  for _,a in ipairs({'x','y','z'}) do if g.bounds.max[a]-g.bounds.min[a]> (a=='y' and 2 or 7) then return false end end
  if #g.route+#g.exitRoute>1024 then return false end
  if g.surveyed~=nil and not M.list(g.surveyed,192,function(p) return U.position(p) and P.inside(p,g.bounds) end) then return false end
  local p=g.exitRoute[#g.exitRoute] or g.depot
  for _,v in ipairs(g.route) do
    if U.distance(p,v)~=1 or not P.inside(v,g.envelope) or M.protected(v,g.protectedAreas) then return false end; p=v
  end
  return P.key(p)==P.key(g.entry)
end
local results={quota=true,survey_exhausted=true,cargo=true,fuel=true,paused=true,route_blocked=true}
function M.report(r)
  return type(r)=='table' and (r.result==nil or results[r.result]==true)
    and U.integer(r.cursor) and r.cursor>=1 and r.cursor<=193
    and U.integer(r.clearedRouteCount) and r.clearedRouteCount>=0 and r.clearedRouteCount<=1024
    and M.list(r.observations,64,function(p) return U.position(p) and U.shortString(p.name,128) end)
end
local function point(p) return {x=p.x,y=p.y,z=p.z} end
local function box(b) return {min=point(b.min),max=point(b.max)} end
function M.cleanHome(h)
  local out={depot=point(h.depot),exitRoute={},protectedAreas={}}
  for _,p in ipairs(h.exitRoute) do out.exitRoute[#out.exitRoute+1]=point(p) end
  for _,b in ipairs(h.protectedAreas) do out.protectedAreas[#out.protectedAreas+1]=box(b) end
  return out
end
function M.cleanGeometry(g)
  local out=M.cleanHome(g)
  for _,k in ipairs({'version','groupId','sectorId','cursor'}) do out[k]=g[k] end
  out.bounds=box(g.bounds); out.envelope=box(g.envelope); out.entry=point(g.entry); out.route={}
  for _,p in ipairs(g.route) do out.route[#out.route+1]=point(p) end
  if g.surveyed then out.surveyed={}; for _,p in ipairs(g.surveyed) do out.surveyed[#out.surveyed+1]=point(p) end end
  return out
end
function M.cleanReport(r)
  local out={result=r.result,cursor=r.cursor,clearedRouteCount=r.clearedRouteCount,observations={}}
  for _,p in ipairs(r.observations) do local v=point(p); v.name=p.name; out.observations[#out.observations+1]=v end
  return out
end
function M.record(records,trip,report)
  if not M.report(report) then return nil,'invalid exploration progress' end
  local g=trip.exploration; local r=records[g.sectorId] or {surveys={},observations={}}; records[g.sectorId]=r
  r.surveys=r.surveys or {}; r.observations=r.observations or {}
  local visited=coverage(r.surveys[trip.item])
  for k,p in pairs(coverage({bounds=g.bounds,cursor=report.cursor,surveyed=g.surveyed})) do visited[k]=p end
  local keys={}; for k in pairs(visited) do keys[#keys+1]=k end; table.sort(keys)
  local surveyed={}; for i=1,math.min(192,#keys) do surveyed[#surveyed+1]=U.copy(visited[keys[i]]) end
  r.surveys[trip.item]={cursor=report.cursor,surveyed=surveyed,exhausted=report.result=='survey_exhausted' or report.result=='route_blocked',bounds=U.copy(g.bounds)}
  local positions={}; for _,p in ipairs(r.observations) do positions[P.key(p)]=p end
  for _,p in ipairs(report.observations) do if P.inside(p,g.bounds) then positions[P.key(p)]={x=p.x,y=p.y,z=p.z,name=p.name} end end
  local keys={}; for k in pairs(positions) do keys[#keys+1]=k end; table.sort(keys)
  r.observations={}; for i=math.max(1,#keys-63),#keys do r.observations[#r.observations+1]=positions[keys[i]] end
  return true
end
function M.protectedAreas(state,config)
  local boxes=U.copy(config.restrictedAreas or {})
  for _,p in pairs((state.automation or {}).projects or {}) do
    if p.protectedBounds then boxes[#boxes+1]=U.copy(p.protectedBounds)
    elseif config.exploration.enabled then error('exploration requires project protection migration') end
  end
  if config.depot then boxes[#boxes+1]={min={x=config.depot.x,y=config.depot.y-1,z=config.depot.z},max={x=config.depot.x,y=config.depot.y+2,z=config.depot.z}} end
  if M.box(config.exploration.baseProtection) then boxes[#boxes+1]=U.copy(config.exploration.baseProtection) end
  for _,w in pairs(state.workers or {}) do
    local h=w.telemetry and w.telemetry.explorationHome
    if h then
      for _,b in ipairs(h.protectedAreas) do boxes[#boxes+1]=U.copy(b) end
      local d=h.depot
      boxes[#boxes+1]={min={x=d.x,y=d.y-1,z=d.z},max={x=d.x,y=d.y+2,z=d.z}}
      -- A cleared exit is traversal-only. Coalesce straight runs to bound messages.
      local segment,last,axis,direction
      for _,p in ipairs(h.exitRoute) do
        local a,sign
        if last then for _,k in ipairs({'x','y','z'}) do if p[k]~=last[k] then a=k; sign=p[k]-last[k] end end end
        if segment and a==axis and sign==direction then
          for _,k in ipairs({'x','y','z'}) do segment.min[k]=math.min(segment.min[k],p[k]); segment.max[k]=math.max(segment.max[k],p[k]) end
        else
          segment={min=point(p),max=point(p)}; boxes[#boxes+1]=segment; axis=a; direction=sign
        end
        last=p
      end
    end
  end
  return boxes
end
function M.projectBounds(transform,size)
  local x,z=size.x,size.z
  if transform.rotation==90 or transform.rotation==270 then x,z=z,x end
  local o=transform.origin
  return {min={x=o.x,y=o.y,z=o.z},max={x=o.x+x-1,y=o.y+size.y+1,z=o.z+z-1}}
end
function M.conflicts(state,box)
  for _,j in pairs(state.jobs or {}) do
    if j.workerId and not j.physicalComplete and j.status~='completed' then
      local g=j.exploration
      if g then
        if M.overlaps(box,g.bounds) then return true end
        for _,p in ipairs(g.route) do if P.inside(p,box) then return true end end
        for _,p in ipairs(g.exitRoute or {}) do if P.inside(p,box) then return true end end
      end
    end
  end
  return false
end
return M
