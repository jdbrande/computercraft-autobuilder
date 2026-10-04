-- Wired names do not encode physical coordinates. Keep spatial registration
-- separate from immutable factory contracts and native inventory reservations.
local U=require('autobuilder.core.util')
local E=require('autobuilder.resources.exploration')
local P=require('autobuilder.core.pathfinding')
local F=require('autobuilder.factory.factory')
local M={}
local sides={left=true,right=true,front=true,back=true,top=true,bottom=true,up=true,down=true}
local function name(n) return U.shortString(n,128) and not sides[n] end
local function contains(a,b) return P.inside(b.min,a) and P.inside(b.max,a) end
function M.validNames(names)
  if type(names)~='table' or #names>3 then return false end
  local count,seen=0,{}
  for k,n in pairs(names) do
    count=count+1;if not U.integer(k) or k<1 or k>#names or not name(n) or seen[n] then return false end;seen[n]=true
  end
  return count==#names
end
function M.craftingNames(config)
  local out,seen={},{}
  if (config.capabilities or {}).crafting then for _,k in ipairs({'buffer','input','output'}) do
    local n=(config.craftingStation or {})[k]
    if type(n)=='string' and n~='' and not seen[n] then out[#out+1]=n;seen[n]=true end
  end end
  return out
end
function M.validate(map)
  assert(type(map)=='table','inventoryAreas must be an inventory-name map')
  local n=0
  for k,b in pairs(map) do
    n=n+1;assert(n<=512 and name(k) and E.box(b),'invalid inventoryAreas name, bounds or count (maximum512)')
  end
end
local function inspect(config,state)
  local areas=U.copy(config.inventoryAreas or {});local required={};local busy=false
  local function need(n) if type(n)=='string' and n~='' then required[n]=true end end
  local function at(n,p,offset)
    need(n);if not name(n) or not U.position(p) then return end
    local cell={x=p.x,y=p.y+(offset or 0),z=p.z};local box={min=cell,max=U.copy(cell)}
    assert(U.position(cell),'inventory container outside world bounds: '..n)
    if areas[n] then assert(contains(areas[n],box),'inventoryAreas conflicts with registered container '..n)
    else areas[n]=box end
  end
  local function station(s) for _,k in ipairs({'buffer','input','output'}) do need((s or {})[k]) end end
  local function logistics(c)
    for _,k in ipairs({'source','destination'}) do local n=c[k];if n then at(n.inventory,n.position) end end
    for _,k in ipairs({'pickup','drop'}) do local n=c[k];if n then at(n.inventory,n.position,-1) end end
  end
  local function returned(c)
    if c.node then at(c.node.inventory,c.node.position) end
    if c.buffer then at(c.buffer.inventory,c.buffer.position,-1) end
  end
  local function supply(s)
    if not s then return end;need(s.inventory)
    if require('autobuilder.storage.supply').validStation(s) then at(s.inventory,require('autobuilder.storage.supply').container(s)) end
  end
  local seen={}
  local function journals(t)
    if type(t)~='table' or seen[t] then return end;seen[t]=true
    local i=t.intent
    if type(i)=='table' then
      busy=true
      if i.action=='transfer' then need(i.from);need(i.to) end
      need(i.source);need(i.chest)
    end
    for _,v in pairs(t) do if type(v)=='table' then journals(v) end end
  end
  for _,names in ipairs({config.storageInventories or {},config.furnaces or {}}) do for _,n in ipairs(names) do need(n) end end
  station(config.craftingStation)
  for _,s in ipairs(config.craftingStations or {}) do station(s) end
  for _,s in ipairs((config.processors or {}).machines or {}) do need(s.inventory) end
  need((config.supply or {}).inventory)
  for _,s in ipairs(config.supplyStations or {}) do supply(s) end
  for _,s in ipairs((config.fuel or {}).stations or {}) do at(s.inventory,s.position,1) end
  for _,n in ipairs((config.logistics or {}).nodes or {}) do
    at(n.inventory,n.position);for _,b in ipairs(n.buffers or {}) do at(b.inventory,b.position,-1) end
  end
  local a=state.automation or {}
  for _,jobs in ipairs({state.jobs or {},a.jobs or {}}) do for _,j in pairs(jobs) do
    journals(j)
    if j.status~='completed' or j.production and j.production.intent then
      busy=true;need(j.furnaceLane);need(j.production and j.production.furnace);need(j.processor and j.processor.inventory)
      station(j.privateStation)
      if j.logistics then logistics(j.logistics) end
      if j.returning then returned(j.returning) end
      if j.station then at(j.station.inventory,j.station.position,1) end
    end
  end end
  if a.supply then busy=true;supply(a.supply.station);journals(a.supply) end
  for _,r in pairs(a.inventoryRecoveries or {}) do if r.status~='completed' then busy=true;returned(r);journals(r) end end
  for _,ledger in ipairs({state.inventoryLedger or {},state.capacityLedger or {}}) do
    for _,lease in pairs(ledger.leases or {}) do if lease.status=='held' then
      busy=true;for n in pairs(lease.nodes or {}) do need(n) end
    end end
  end
  for _,w in pairs(state.workers or {}) do
    local t=w.telemetry or {};if t.task then busy=true end
    for _,n in ipairs(t.craftingInventories or {}) do need(n) end
  end
  if next(a.cells or {}) then busy=true end
  M.validate(areas) -- Derived registrations must obey the same checkpoint limit.
  local missing={};for n in pairs(required) do if not areas[n] then missing[#missing+1]=n end end;table.sort(missing)
  return {areas=areas,missing=missing,error=#missing>0 and ('Register inventoryAreas for '..table.concat(missing,', ')..' on the controller; run setup factory.') or nil},busy
end
local destructive={MINE=true,BUILD=true,REPAIR=true,CLEAR=true,PREPARE_SITE=true,PREPARE_REGION=true,HARVEST=true,FARM=true}
local function changedSafe(state,area)
  for key in pairs((state.automation or {}).cells or {}) do
    local x,y,z=key:match('^(-?%d+),(-?%d+),(-?%d+)$')
    if x and P.inside({x=tonumber(x),y=tonumber(y),z=tonumber(z)},area) then return false,'reserved cell '..key end
  end
  for _,jobs in ipairs({state.jobs or {},(state.automation or {}).jobs or {}}) do for id,j in pairs(jobs) do
    if j.workerId and j.status~='completed' and not j.physicalComplete and destructive[j.type] then
      local g=j.exploration;local bounds=g and g.bounds or j.miningArea or j.bounds
      if not E.box(bounds) or E.overlaps(area,bounds) then return false,'owned work '..id end
      if g then for _,route in ipairs({g.route or {},g.exitRoute or {}}) do for _,p in ipairs(route) do
        if P.inside(p,area) then return false,'owned route '..id end
      end end end
    end
  end end
  return true
end
function M.initialize(state,config)
  local nextState,busy=inspect(config,state);local old=state.inventoryGeometry
  if old then
    M.validate(old.areas)
    for n,b in pairs(old.areas) do
      assert(not busy or F.equal(b,nextState.areas[n]),'Finish retained work before moving/removing inventoryAreas '..n)
    end
  end
  for n,b in pairs(nextState.areas) do if not old or not F.equal(old.areas[n],b) then
    local ok,why=changedSafe(state,b);assert(ok,'Cannot change inventoryAreas '..n..' across '..tostring(why)..'; settle its ownership first')
  end end
  state.inventoryGeometry=nextState
  return nextState
end
function M.missing(config,state) return inspect(config,state or {}).missing end
function M.ready(state,config,job)
  if not destructive[job.type] or job.type=='PREPARE_REGION' and job.siteWork and job.siteWork.stage=='verify' then return true end
  local current=inspect(config or {},state)
  if current.error then return false,current.error end
  if state.inventoryGeometry and not F.equal(current.areas,state.inventoryGeometry.areas) then return false,'Inventory geometry changed; restart controller to validate and checkpoint inventoryAreas before excavation' end
  return true
end
function M.blocker(state,config,target)
  local current=inspect(config,state)
  for _,map in ipairs({(state.inventoryGeometry or {}).areas or {},current.areas}) do
    local names={};for n in pairs(map) do names[#names+1]=n end;table.sort(names)
    for _,n in ipairs(names) do if P.inside(target,map[n]) then return n end end
  end
end
function M.areas(state,config)
  local current=inspect(config,state);local out={}
  for _,map in ipairs({(state.inventoryGeometry or {}).areas or {},current.areas}) do for _,b in pairs(map) do out[#out+1]=U.copy(b) end end
  return out
end
return M
