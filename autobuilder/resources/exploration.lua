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
function M.candidates(records,c,item,start)
  local result={}; local material=assert(Materials.get(item))
  for _,sector in ipairs(M.sectors(c)) do
    local r=records[sector.id] or {}; local survey=(r.surveys or {})[item]
    if not survey or not survey.exhausted or not M.sameBox(survey.bounds,sector.bounds) then
      sector.cursor=survey and M.sameBox(survey.bounds,sector.bounds) and survey.cursor or 1
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
  for _,j in pairs(ctx.activeJobs or {}) do
    if j.workerId and not j.physicalComplete and j.status~='completed' then
      local g=j.exploration
      if not g then return nil,'territory owned by a fixed miner' end
      if M.overlaps(sector.bounds,g.bounds) then return nil,'sector owned' end
      claims[#claims+1]=g
    end
  end
  local function allowed(p)
    if not P.inside(p,envelope) or M.protected(p,ctx.protectedAreas) then return false end
    for _,g in ipairs(claims) do
      if P.inside(p,g.bounds) then return false end
      for _,r in ipairs(g.route) do if P.key(r)==P.key(p) then return false end end
    end
    return true
  end
  local start=ctx.depot
  for _,p in ipairs(ctx.exitRoute or {}) do if U.distance(start,p)~=1 then return nil,'invalid clear exit route' end; start=p end
  local entry={}
  for _,a in ipairs({'x','y','z'}) do entry[a]=math.max(sector.bounds.min[a],math.min(start[a],sector.bounds.max[a])) end
  if not allowed(start) or not allowed(entry) then return nil,'protected or owned entry' end
  local route,why=P.find(start,entry,allowed,c.mining.pathBudget)
  if not route then return nil,why end
  local distance=#route+#(ctx.exitRoute or {})
  if distance>math.min(math.floor(c.maxTravelDistance),1024) then return nil,'route exceeds travel limit' end
  if ctx.availableFuel~='unlimited' and ctx.availableFuel<distance*2+c.minimumFuelReserve+c.mining.returnMargin+2 then return nil,'insufficient round-trip fuel' end
  return {version=1,depot=U.copy(ctx.depot),sectorId=sector.id,bounds=U.copy(sector.bounds),entry=entry,route=route,exitRoute=U.copy(ctx.exitRoute or {}),
    cursor=sector.cursor or 1,envelope=U.copy(envelope),protectedAreas=U.copy(ctx.protectedAreas or {})}
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
  return out
end
function M.cleanReport(r)
  local out={result=r.result,cursor=r.cursor,clearedRouteCount=r.clearedRouteCount,observations={}}
  for _,p in ipairs(r.observations) do local v=point(p); v.name=p.name; out.observations[#out.observations+1]=v end
  return out
end
return M
