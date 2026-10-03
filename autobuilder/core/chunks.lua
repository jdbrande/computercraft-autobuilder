local U=require('autobuilder.core.util')
local Equal=require('autobuilder.factory.factory').equal
local M={MAX_CHUNKS=1024}
local function coordinate(n) return U.integer(n) and math.abs(n)<=1875000 end
function M.validArea(a)
  return type(a)=='table' and coordinate(a.minX) and coordinate(a.maxX) and coordinate(a.minZ) and coordinate(a.maxZ)
    and a.minX<=a.maxX and a.minZ<=a.maxZ
end
function M.validGrant(a)
  return M.validArea(a) and (a.maxX-a.minX+1)*(a.maxZ-a.minZ+1)<=M.MAX_CHUNKS
end
function M.cleanArea(a) return a and {minX=a.minX,maxX=a.maxX,minZ=a.minZ,maxZ=a.maxZ} end
function M.contains(a,p)
  if not M.validArea(a) or not U.position(p) then return false end
  local x,z=math.floor(p.x/16),math.floor(p.z/16)
  return x>=a.minX and x<=a.maxX and z>=a.minZ and z<=a.maxZ
end
function M.validate(config)
  local c=config.chunkLoading
  assert(type(c)=='table' and type(c.enabled)=='boolean' and type(c.anchor)=='boolean','invalid chunk loading policy')
  assert(type(c.areas)=='table' and #c.areas<=64,'invalid assured chunk areas')
  local n=0
  for i,a in pairs(c.areas) do
    n=n+1;assert(U.integer(i) and i>=1 and i<=#c.areas and M.validArea(a),'invalid assured chunk rectangle')
  end
  assert(n==#c.areas,'sparse assured chunk areas')
  if c.anchor then
    assert(c.enabled and config.role=='worker' and not config.mining.enabled,'chunk anchor must be a stationary worker')
    for _,role in ipairs({'building','crafting','courier','logging','farming'}) do assert(not config.automation[role],'chunk anchor cannot perform '..role) end
  end
end
function M.validAnchor(a)
  return type(a)=='table' and a.provider=='advanced_peripherals_chunky' and coordinate(a.x) and coordinate(a.z)
end
function M.probe(e,state,config)
  local c=config.chunkLoading;local p=state.position
  if not c or not c.enabled or not c.anchor or not p or not p.known or not U.position(p) or p.pending or p.uncertain or state.currentTask then return end
  for _,side in ipairs({'left','right'}) do
    local ok,kind=pcall(function() return e.peripheral.getType(side) end)
    if ok and kind=='chunky' then return {provider='advanced_peripherals_chunky',x=math.floor(p.x/16),z=math.floor(p.z/16)} end
  end
end
function M.area(job,t)
  if not t or not t.position or not t.position.known or not U.position(t.position) then return nil,'MISSION_BLOCKED_UNLOADED_AREA: worker pose unknown' end
  if job.type=='MINE' and not job.exploration and not job.miningArea then return nil,'MISSION_BLOCKED_UNLOADED_AREA: mining bounds unknown' end
  local loX,hiX,loZ,hiZ=math.huge,-math.huge,math.huge,-math.huge
  local count,seen=0,{}
  local function visit(v,depth)
    count=count+1;assert(count<=20000 and depth<=16,'mission geometry limit exceeded')
    if type(v)~='table' then return end
    assert(not seen[v],'cyclic mission geometry');seen[v]=true
    if U.position(v) then
      loX=math.min(loX,v.x);hiX=math.max(hiX,v.x);loZ=math.min(loZ,v.z);hiZ=math.max(hiZ,v.z)
    else for _,child in pairs(v) do visit(child,depth+1) end end
    seen[v]=nil
  end
  -- Include all declared coordinates, including route waypoints and farm sites.
  -- The two-block margin covers the existing bounded builder/supply approaches.
  visit(job,0);visit(t.position,0);if t.depot then visit(t.depot,0) end
  local a={minX=math.floor((loX-2)/16),maxX=math.floor((hiX+2)/16),minZ=math.floor((loZ-2)/16),maxZ=math.floor((hiZ+2)/16)}
  if not M.validArea(a) or (a.maxX-a.minX+1)*(a.maxZ-a.minZ+1)>M.MAX_CHUNKS then return nil,'MISSION_BLOCKED_UNLOADED_AREA: mission chunk limit exceeded' end
  return a
end
function M.holdsAnchor(state,id)
  for _,lease in pairs((state.chunkLedger or {}).leases or {}) do
    if lease.status=='held' then for _,provider in pairs(lease.providers) do if provider.workerId==id then return true end end end
  end
  return false
end
local function assured(config,area)
  for x=area.minX,area.maxX do for z=area.minZ,area.maxZ do
    local found=false
    for _,a in ipairs(config.chunkLoading.areas) do if x>=a.minX and x<=a.maxX and z>=a.minZ and z<=a.maxZ then found=true;break end end
    if not found then return false end
  end end
  return true
end
function M.workerAccept(config,state,job)
  local c=config.chunkLoading
  local old=state.currentTask
  if old and not Equal(old.loadedArea,job.loadedArea) then return false,'changed loaded mission grant' end
  if (not c or not c.enabled) and not job.loadedArea then return true end
  if c and c.anchor then return false,'MISSION_BLOCKED_UNLOADED_AREA: stationary chunk anchor' end
  if old then return old.id==job.id,'worker already has a task' end
  local geometry=job
  if job.type=='MINE' and not job.exploration and not job.miningArea then geometry=U.copy(job);geometry.miningArea=config.mining.bounds end
  local a,why=M.area(geometry,{position=state.position,depot=config.depot});if not a then return false,why end
  -- Legacy saved assignments can continue only with explicit local assurances.
  if not job.loadedArea and assured(config,a) then return true end
  if not M.validGrant(job.loadedArea) then return false,'MISSION_BLOCKED_UNLOADED_AREA: assignment needs loaded envelope' end
  local g=job.loadedArea
  if a.minX<g.minX or a.maxX>g.maxX or a.minZ<g.minZ or a.maxZ>g.maxZ then return false,'MISSION_BLOCKED_UNLOADED_AREA: assignment omits route or depot' end
  return true
end
function M.guard(config,state,from,target)
  local c=config.chunkLoading
  local job=state.currentTask
  if (not c or not c.enabled) and not (job and job.loadedArea) then return true end
  if c and c.anchor then return false,'MISSION_BLOCKED_UNLOADED_AREA: stationary chunk anchor' end
  local function covered(p)
    if job and job.loadedArea then return M.validGrant(job.loadedArea) and M.contains(job.loadedArea,p) end
    for _,a in ipairs(c.areas) do if M.contains(a,p) then return true end end
    return false
  end
  if covered(from) and covered(target) then return true end
  return false,'MISSION_BLOCKED_UNLOADED_AREA: chunk '..math.floor(target.x/16)..','..math.floor(target.z/16)
end
function M.new(state,config,save)
  state.chunkLedger=state.chunkLedger or {leases={}};local s=state.chunkLedger
  local self={state=s}
  local function persist(change,rollback)
    change();local called,ok,why=pcall(save)
    if not called or not ok then rollback();error('chunk checkpoint failed: '..tostring(called and why or ok),0) end
  end
  local function provider(x,z)
    for _,area in ipairs(config.chunkLoading.areas) do
      if x>=area.minX and x<=area.maxX and z>=area.minZ and z<=area.maxZ then return {kind='assured'} end
    end
    local id
    for _,w in pairs(state.workers or {}) do
      local t=w.telemetry;local a=t and t.chunkAnchor;local p=t and t.position
      if w.online and M.validAnchor(a) and a.x==x and a.z==z and t.status=='idle' and not t.task
        and p and p.known and U.position(p) and math.floor(p.x/16)==x and math.floor(p.z/16)==z then
        if not id or w.id<id then id=w.id end
      end
    end
    if id then return {kind='anchor',workerId=id} end
  end
  function self:reserve(job,worker,assign)
    if not config.chunkLoading.enabled then return {status='disabled'} end
    assert(U.shortString(job.id,160),'invalid loaded mission ID')
    local old=s.leases[job.id];local t=worker.telemetry
    if old then
      assert(old.workerId==worker.id and Equal(job.loadedArea,old.area),'changed loaded mission grant')
      assert(Equal(M.area(job,old.origin),old.area),'changed loaded mission geometry')
      if old.status~='held' then return nil,'loaded mission claim already released' end
      return U.copy(old)
    end
    if not worker.online or not t or not t.capabilities or not t.capabilities.chunkCoverageV1 then return nil,'MISSION_BLOCKED_UNLOADED_AREA: worker needs coverage protocol' end
    if t.chunkAnchor or M.holdsAnchor(state,worker.id) then return nil,'MISSION_BLOCKED_UNLOADED_AREA: worker owns stationary chunk coverage' end
    local area,why=M.area(job,t);if not area then return nil,why end
    local providers={}
    for x=area.minX,area.maxX do for z=area.minZ,area.maxZ do
      local p=provider(x,z);if not p then return nil,'MISSION_BLOCKED_UNLOADED_AREA: chunk '..x..','..z end
      providers[x..','..z]=p
    end end
    assert(not job.loadedArea or Equal(job.loadedArea,area),'changed loaded mission envelope')
    local lease={status='held',workerId=worker.id,area=area,providers=providers,origin={position=U.copy(t.position),depot=U.copy(t.depot)}}
    local before,owner,status=job.loadedArea,job.workerId,job.status
    persist(function()
      s.leases[job.id]=lease;job.loadedArea=U.copy(area)
      if assign then job.workerId=worker.id;job.status='assigned' end
    end,function() s.leases[job.id]=nil;job.loadedArea=before;job.workerId=owner;job.status=status end)
    return U.copy(lease)
  end
  function self:allows(job,from,target)
    if not config.chunkLoading.enabled then return true end
    local lease=s.leases[job.id]
    if not lease then
      -- Upgraded/backup jobs keep physical ownership. Only explicit assurances
      -- can establish a missing historical coverage contract, never a heartbeat.
      local w=(state.workers or {})[tostring(job.workerId)]
      local a=w and M.area(job,w.telemetry)
      if a and assured(config,a) then lease=self:reserve(job,w) end
    end
    if lease and lease.status=='held' and lease.workerId==job.workerId and Equal(lease.area,job.loadedArea)
      and M.contains(lease.area,from) and M.contains(lease.area,target) then return true end
    return false,'MISSION_BLOCKED_UNLOADED_AREA: movement outside held coverage'
  end
  function self:reconcile()
    for id,lease in pairs(s.leases) do
      local j=(state.jobs or {})[id] or ((state.automation or {}).jobs or {})[id]
      if lease.status=='held' and j and (j.physicalComplete or j.status=='completed') then self:release(id) end
    end
  end
  function self:describe()
    local c=config.chunkLoading;local lines={'Chunk coverage '..(c.enabled and 'enforced' or 'DISABLED (legacy opt out)')}
    lines[#lines+1]='Assured rectangles: '..#c.areas
    for _,a in ipairs(c.areas) do lines[#lines+1]=a.minX..','..a.minZ..' to '..a.maxX..','..a.maxZ end
    local details={}
    for _,w in pairs(state.workers or {}) do
      local a=w.telemetry and w.telemetry.chunkAnchor
      if a then details[#details+1]='Anchor '..w.id..' chunk '..a.x..','..a.z..(w.online and ' online' or ' offline') end
    end
    if c.anchor then
      local a=state.telemetry and state.telemetry.chunkAnchor
      details[#details+1]=a and ('Local anchor chunk '..a.x..','..a.z) or 'Local anchor unavailable: check chunky hardware and settled pose'
    end
    for id,lease in pairs(s.leases) do if lease.status=='held' then
      local missing={}
      for key,p in pairs(lease.providers) do if p.kind=='anchor' then
        local w=(state.workers or {})[tostring(p.workerId)];local a=w and w.telemetry and w.telemetry.chunkAnchor
        if not w or not w.online or not a or a.x..','..a.z~=key then missing[#missing+1]=p.workerId..'@'..key end
      end end
      table.sort(missing)
      details[#details+1]=id..' held for '..lease.workerId..(#missing>0 and ('; offline/lost providers '..table.concat(missing,' ')) or '')
    end end
    for _,jobs in ipairs({state.jobs or {},(state.automation or {}).jobs or {}}) do
      for id,j in pairs(jobs) do if j.coverageError then details[#details+1]=id..' '..j.coverageError end end
    end
    table.sort(details);for _,line in ipairs(details) do lines[#lines+1]=line end
    state.chunksLines=lines;return table.concat(lines,'\n')
  end
  function self:release(id)
    local old=s.leases[id];if not old or old.status=='released' then return true end
    local lease=U.copy(old);lease.status='released'
    persist(function() s.leases[id]=lease end,function() s.leases[id]=old end);return true
  end
  return self
end
return M
