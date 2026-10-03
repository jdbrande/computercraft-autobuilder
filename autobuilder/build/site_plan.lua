local U=require('autobuilder.core.util')
local S=require('autobuilder.blueprint.schematic')
local T=require('autobuilder.blueprint.transforms')
local C=require('autobuilder.build.blockstates')
local Cooperate=require('autobuilder.core.cooperate')
local M={VERSION=1}
local function integer(value,low,high,why)
  assert(U.integer(value) and value>=low and value<=high,why);return value
end
local function fields(value,allowed,why)
  assert(type(value)=='table',why)
  for key in pairs(value) do assert(allowed[key],why..': '..tostring(key)) end
end
function M.new(source,transform,sourceHash,options)
  local valid,why=S.validate(source);assert(valid,why)
  assert(type(sourceHash)=='string' and #sourceHash==64 and sourceHash:match('^[a-f0-9]+$'),'site source hash required')
  assert(type(transform)=='table' and U.position(transform.origin),'site origin required')
  T.state({},transform.rotation,transform.mirrorX,transform.mirrorZ)
  options=options or {};fields(options,{margin=true,regionSize=true,minY=true,maxY=true},'invalid site option')
  local margin=integer(options.margin or 1,0,8,'site margin must be 0..8')
  local regionSize=integer(options.regionSize or 8,1,8,'site region size must be 1..8')
  local minY=integer(options.minY or -64,-30000000,30000000,'invalid site dimension minimum')
  local maxY=integer(options.maxY or 319,minY,math.min(30000000,minY+4095),'invalid site dimension maximum')
  local origin=U.copy(transform.origin);local size=U.copy(source.size)
  local rotation=transform.rotation or 0;local mx,mz=transform.mirrorX==true,transform.mirrorZ==true
  local width,depth=size.x,size.z;if rotation%180~=0 then width,depth=depth,width end
  local bounds={min={x=origin.x-margin,y=minY,z=origin.z-margin},max={x=origin.x+width-1+margin,y=origin.y+size.y+1,z=origin.z+depth-1+margin}}
  -- Keep run endpoints, not an expanded cell/region array. Random cell lookup is
  -- logarithmic in the existing run count; only requested column batches allocate.
  local ends,palette={},{};local total=0;local hasStructure=false
  for i,run in ipairs(source.runs) do
    total=total+run.count;ends[i]={last=total,id=run.id};hasStructure=hasStructure or not C.isAir(source.palette[run.id].name);Cooperate.every(i)
  end
  assert(U.position(bounds.min) and U.position(bounds.max) and origin.y-(hasStructure and 1 or 0)>=minY and bounds.max.y<=maxY,'site exceeds dimension or world bounds')
  for i,entry in ipairs(source.palette) do palette[i]={name=entry.name,state=T.state(entry.state,rotation,mx,mz)};Cooperate.every(i) end
  local nx,nz=width+margin*2,depth+margin*2
  local rx,rz=math.ceil(nx/regionSize),math.ceil(nz/regionSize)
  local self={version=M.VERSION,sourceHash=sourceHash,bounds=U.copy(bounds),maxY=maxY,regionCount=rx*rz,columnCount=nx*nz}
  function self:wanted(p)
    assert(U.position(p),'invalid site lookup coordinate')
    local x,y,z=p.x-origin.x,p.y-origin.y,p.z-origin.z
    if x<0 or x>=width or z<0 or z>=depth or y<0 or y>=size.y then return nil end
    local w,d=width,depth
    for _=1,rotation/90 do x,z,w,d=z,w-1-x,d,w end
    if mx then x=size.x-1-x end;if mz then z=size.z-1-z end
    local index=y*size.x*size.z+z*size.x+x+1
    local low,high=1,#ends
    while low<high do local mid=math.floor((low+high)/2);if ends[mid].last<index then low=mid+1 else high=mid end end
    local entry=palette[ends[low].id]
    return {x=p.x,y=p.y,z=p.z,name=entry.name,state=U.copy(entry.state)}
  end
  local overrides={};local site=source.metadata.site
  if site~=nil then
    fields(site,{foundation=true},'invalid site metadata')
    if site.foundation~=nil then
      fields(site.foundation,{columns=true},'invalid site foundation')
      local columns=site.foundation.columns or {};local count=0
      assert(type(columns)=='table','invalid foundation columns')
      for key in pairs(columns) do integer(key,1,size.x*size.z,'invalid foundation column index');count=count+1 end
      for i=1,count do
        local c=columns[i];fields(c,{x=true,y=true,z=true},'invalid foundation column')
        integer(c.x,0,size.x-1,'foundation x outside footprint');integer(c.z,0,size.z-1,'foundation z outside footprint')
        integer(c.y,minY-origin.y,size.y-1,'foundation elevation outside dimension or schematic')
        local p=T.position(c,size,rotation,mx,mz);p.x=p.x+origin.x;p.y=p.y+origin.y;p.z=p.z+origin.z
        local key=p.x..','..p.z;assert(not overrides[key],'duplicate foundation column')
        if c.y>=0 then
          local wanted=self:wanted(p)
          assert(wanted and C.family(wanted.name)=='cube' and C.classify(wanted.name,wanted.state)=='SUPPORTED','foundation must preserve an explicit stable schematic block; cannot fill required air')
        end
        overrides[key]=p.y
      end
    end
  end
  local identity={tostring(M.VERSION),sourceHash,origin.x,origin.y,origin.z,size.x,size.y,size.z,rotation,tostring(mx),tostring(mz),margin,regionSize,minY,maxY}
  local keys={};for key in pairs(overrides) do keys[#keys+1]=key end;table.sort(keys)
  for _,key in ipairs(keys) do identity[#identity+1]=key..'='..overrides[key] end
  local planId=require('autobuilder.install.sha256').digest(table.concat(identity,'|'));self.identity=planId
  if not hasStructure and not next(overrides) then bounds.min.y=origin.y;self.bounds.min.y=origin.y end
  function self:region(index)
    integer(index,1,rx*rz,'invalid site region index')
    local x=(index-1)%rx;local z=math.floor((index-1)/rx)
    local lo={x=bounds.min.x+x*regionSize,y=bounds.min.y,z=bounds.min.z+z*regionSize}
    local hi={x=math.min(lo.x+regionSize-1,bounds.max.x),y=bounds.max.y,z=math.min(lo.z+regionSize-1,bounds.max.z)}
    return {id=index,identity=planId,bounds={min=lo,max=hi},columns=(hi.x-lo.x+1)*(hi.z-lo.z+1)}
  end
  function self:columns(regionIndex,first,limit)
    local r=self:region(regionIndex);integer(first,1,r.columns,'invalid site column cursor');integer(limit,1,64,'site column batch must be 1..64')
    local columns={};local w=r.bounds.max.x-r.bounds.min.x+1;local last=math.min(r.columns,first+limit-1)
    for index=first,last do
      local x=r.bounds.min.x+(index-1)%w;local z=r.bounds.min.z+math.floor((index-1)/w)
      local inside=x>=origin.x and x<origin.x+width and z>=origin.z and z<origin.z+depth
      local foundation=inside and (overrides[x..','..z] or hasStructure and origin.y-1) or nil
      columns[#columns+1]={x=x,z=z,foundationY=foundation,clearanceY=bounds.max.y,minY=foundation and minY or origin.y}
    end
    return columns,last<r.columns and last+1 or nil
  end
  function self:survey(regionIndex,first,limit)
    local columns,nextCursor=self:columns(regionIndex,first,limit)
    return {type='SURVEY_SITE',clearanceY=bounds.max.y,bounds=self:region(regionIndex).bounds,
      siteSurvey={identity=planId,region=regionIndex,columns=columns}},nextCursor
  end
  function self:access(regionIndex,target,clearanceY)
    local P=require('autobuilder.core.pathfinding');local r=self:region(regionIndex)
    if not U.position(target) or not P.inside(target,r.bounds) or self:wanted(target)
      or not U.integer(clearanceY) or clearanceY<bounds.max.y or clearanceY>maxY
      or clearanceY-target.y>128 then return nil,'no bounded generic foundation access' end
    local columns=self:columns(regionIndex,1,64);local foundation=false
    for _,c in ipairs(columns) do if c.x==target.x and c.z==target.z and c.foundationY==target.y then foundation=true end end
    if not foundation then return nil,'access target is not a generic foundation' end
    local function removable(p)
      if p.y~=target.y or not P.inside(p,r.bounds) or U.distance(p,target)==0 then return false end
      local wanted=self:wanted(p);return not wanted or C.isAir(wanted.name)
    end
    table.sort(columns,function(a,b)
      local da,db=math.abs(a.x-target.x)+math.abs(a.z-target.z),math.abs(b.x-target.x)+math.abs(b.z-target.z)
      return da<db or da==db and (a.x<b.x or a.x==b.x and a.z<b.z)
    end)
    for _,c in ipairs(columns) do
      local shaft={x=c.x,y=target.y,z=c.z};local clear=removable(shaft)
      if clear then for y=target.y+1,clearanceY-1 do
        local wanted=self:wanted({x=c.x,y=y,z=c.z})
        if wanted and not C.isAir(wanted.name) then clear=false;break end
      end end
      if clear then for _,stand in ipairs(P.neighbors(target)) do if removable(stand) then
        local path=P.find(shaft,stand,removable,64)
        if path and clearanceY-target.y+#path<=128 then
          local cells={};for y=clearanceY-1,target.y,-1 do cells[#cells+1]={x=c.x,y=y,z=c.z} end
          for _,cell in ipairs(path) do cells[#cells+1]=cell end
          return {entry={x=c.x,y=clearanceY,z=c.z},cells=cells,stand=U.copy(stand),target=U.copy(target)}
        end
      end end end
    end
    return nil,'retained schematic leaves no access shaft within the owned region'
  end
  function self:requiredRegions(blocks)
    assert(type(blocks)=='table' and #blocks>0 and #blocks<=512,'bounded structural region required')
    local x0,x1,z0,z1=math.huge,-math.huge,math.huge,-math.huge
    for _,b in ipairs(blocks) do
      assert(U.position(b) and b.x>=origin.x and b.x<origin.x+width and b.z>=origin.z and b.z<origin.z+depth,'structural region outside site footprint')
      x0=math.min(x0,b.x);x1=math.max(x1,b.x);z0=math.min(z0,b.z);z1=math.max(z1,b.z)
    end
    x0=math.floor((math.max(bounds.min.x,x0-1)-bounds.min.x)/regionSize);x1=math.floor((math.min(bounds.max.x,x1+1)-bounds.min.x)/regionSize)
    z0=math.floor((math.max(bounds.min.z,z0-1)-bounds.min.z)/regionSize);z1=math.floor((math.min(bounds.max.z,z1+1)-bounds.min.z)/regionSize)
    assert((x1-x0+1)*(z1-z0+1)<=128,'too many preparation dependencies for one structural region')
    local out={};for z=z0,z1 do for x=x0,x1 do out[#out+1]=z*rx+x+1 end end;return out
  end
  function self:work(regionIndex,evidence,stage,cursor,limit,fill)
    local verify=stage=='verify_clear' or stage=='verify_fill'
    local sealing=stage=='seal'
    local clearing=stage=='clear' or stage=='verify_clear' or sealing
    assert(clearing or stage=='fill' or stage=='verify_fill','invalid preparation stage')
    integer(cursor,1,262145,'invalid preparation cursor');integer(limit,1,512,'preparation batch must be 1..512')
    assert(type(evidence)=='table' and evidence.identity==planId and evidence.region==regionIndex
      and U.integer(evidence.clearanceY) and evidence.clearanceY>=bounds.max.y and evidence.clearanceY<=maxY,'site evidence differs from geometry')
    local survey=self:survey(regionIndex,1,64);survey.clearanceY=evidence.clearanceY;survey.bounds.max.y=evidence.clearanceY
    for _,c in ipairs(survey.siteSurvey.columns) do c.clearanceY=evidence.clearanceY end
    assert(require('autobuilder.build.site_survey').validReport(survey,evidence.report,true),'invalid preparation survey evidence')
    if not clearing or sealing then assert(C.family(fill)=='cube' and C.classify(fill,{})=='SUPPORTED','fill must be a supported stable cube') end
    local ranges={};local total=0
    for i,c in ipairs(survey.siteSurvey.columns) do
      local observed=evidence.report.observations[i]
      assert(observed.status~='blocked','site column remains inaccessible: '..c.x..','..observed.y..','..c.z)
      local low,high
      if clearing then low=math.min(origin.y,c.foundationY and c.foundationY+1 or origin.y);high=evidence.clearanceY-1
      elseif c.foundationY then
        high=c.foundationY
        local solid=observed.status=='surface' and require('autobuilder.build.site_work').support(observed.name)
        low=math.min(high,observed.y+(solid and 1 or 0))
      end
      if low and low<=high then
        ranges[#ranges+1]={column=c,first=total+1,last=total+high-low+1,low=low,high=high}
        total=total+high-low+1
      end
    end
    assert(cursor<=total+1,'preparation cursor exceeds work')
    local blocks={};local position=cursor
    for _,r in ipairs(ranges) do if position<=r.last then
      position=math.max(position,r.first)
      while position<=r.last and #blocks<limit do
        local y=clearing and r.high-(position-r.first) or r.low+(position-r.first)
        local p={x=r.column.x,y=y,z=r.column.z};local wanted=self:wanted(p)
        if sealing then
          p.name=fill;p.state={};blocks[#blocks+1]=p
        elseif clearing then
          p.name='minecraft:air';p.state={}
          if wanted and not C.isAir(wanted.name) then p.retain={name=wanted.name,state=wanted.state} end
          blocks[#blocks+1]=p
        elseif not wanted or y==r.column.foundationY then
          p.name=wanted and wanted.name or fill;p.state=wanted and wanted.state or {};p.support=not wanted or nil
          blocks[#blocks+1]=p
        end
        position=position+1;Cooperate.every(position)
      end
      if #blocks==limit then break end
    end end
    if #blocks==0 then return nil,nil,total end
    local payload={type='PREPARE_REGION',blocks=blocks,bounds=survey.bounds,clearanceY=evidence.clearanceY,
      siteWork={identity=planId,region=regionIndex,stage=verify and 'verify' or sealing and 'seal' or clearing and 'clear' or 'fill'}}
    return payload,position<=total and position or nil,total
  end
  return self
end
return M
