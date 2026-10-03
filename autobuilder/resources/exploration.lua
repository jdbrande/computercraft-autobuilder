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
  return {version=1,sectorId=sector.id,bounds=U.copy(sector.bounds),entry=entry,route=route,exitRoute=U.copy(ctx.exitRoute or {}),
    cursor=sector.cursor or 1,envelope=U.copy(envelope),protectedAreas=U.copy(ctx.protectedAreas or {})}
end
return M
