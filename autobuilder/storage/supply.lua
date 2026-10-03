local U=require('autobuilder.core.util')
local M={}
function M.validStation(s)
  return type(s)=='table' and U.integer(s.workerId) and s.workerId>=0 and U.shortString(s.inventory,128)
    and ({front=true,up=true,down=true})[s.side] and U.position(s.position)
    and (s.side~='front' or U.heading(s.position.heading))
end
function M.station(config,owner)
  for _,s in ipairs(config.supplyStations or {}) do if s.workerId==owner then return U.copy(s) end end
  return {inventory=(config.supply or {}).inventory,side=(config.supply or {}).side or 'front'}
end
function M.matchesWorker(s,config,id)
  return M.validStation(s) and s.workerId==id and U.position(config.depot)
    and s.inventory==(config.supply or {}).inventory and s.side==((config.supply or {}).side or 'front')
    and U.distance(s.position,config.depot)==0 and (s.side~='front' or s.position.heading==config.depot.heading)
end
function M.container(s)
  local p=U.copy(s.position)
  if s.side=='up' then p.y=p.y+1 elseif s.side=='down' then p.y=p.y-1
  else local d=({north={0,-1},east={1,0},south={0,1},west={-1,0}})[p.heading];p.x=p.x+d[1];p.z=p.z+d[2] end
  return p
end
function M.validate(config)
  local stations=config.supplyStations
  assert(type(stations)=='table' and #stations<=128,'at most128 supply stations allowed')
  local occupied,workers,cells={},{},{}
  for _,names in ipairs({config.storageInventories,config.furnaces}) do for _,name in ipairs(names) do occupied[name]=true end end
  occupied[config.supply.inventory]=true
  for _,s in ipairs(config.fuel.stations) do occupied[s.inventory]=true end
  for _,s in ipairs({config.craftingStation}) do for _,field in ipairs({'buffer','input','output'}) do occupied[s[field]]=true end end
  for _,s in ipairs(config.craftingStations) do for _,field in ipairs({'buffer','input','output'}) do occupied[s[field]]=true end end
  for _,node in ipairs(config.logistics.nodes) do
    occupied[node.inventory]=true;for _,b in ipairs(node.buffers) do occupied[b.inventory]=true end
  end
  local count=0
  for i,s in pairs(stations) do
    count=count+1;assert(U.integer(i) and i>=1 and i<=#stations and M.validStation(s),'invalid supply station')
    assert(not occupied[s.inventory] and not workers[s.workerId],'supply stations require private inventories and distinct workers')
    occupied[s.inventory]=true;workers[s.workerId]=true
    for _,p in ipairs({s.position,M.container(s)}) do
      assert(U.position(p),'supply container outside world bounds')
      local key=require('autobuilder.core.pathfinding').key(p)
      assert(not cells[key],'supply stations have overlapping stands or containers');cells[key]=true
    end
  end
  assert(count==#stations,'sparse supply station list')
end
function M.validateSaved(config,state)
  local s=state.supply
  if s then
    if s.station then assert(require('autobuilder.factory.factory').equal(s.station,M.station(config,s.owner)),'owned supply station changed')
    else assert(#(config.supplyStations or {})==0,'drain the legacy supply batch before adding worker stations') end
  end
end
function M.new(state,config,e,save)
  assert(type(state)=='table' and e and e.peripheral and type(save)=='function','supply state/peripheral/persistence required')
  M.validateSaved(config,state)
  local self={}; local fault;local needsStock
  local function stage(s) return (s.station or M.station(config,s.owner)).inventory end
  local function persist()
    local ok,v,err=pcall(save)
    if not ok or not v then fault='supply checkpoint failed: '..tostring(ok and err or v); error(fault,0) end
  end
  local function list(name)
    local inv=e.peripheral.call(name,'list'); assert(type(inv)=='table','inventory unavailable: '..tostring(name))
    for slot,i in pairs(inv) do assert(U.integer(slot) and slot>0 and type(i)=='table' and U.shortString(i.name,128) and U.integer(i.count) and i.count>0,'invalid inventory contents') end
    return inv
  end
  local function staged(s)
    local total=0
    for _,i in pairs(list(stage(s))) do assert(i.name==s.item and not i.nbt,'foreign contents in supply chest'); total=total+i.count end
    return total
  end
  local function reconcile(s)
    local i=s.intent; if not i then return end
    local observed=list(i.source)[i.slot]
    assert(not observed or observed.name==s.item and not observed.nbt,'supply source slot changed during recovery')
    local lost=i.sourceBefore-(observed and observed.count or 0)
    local total=staged(s); local gained=total-i.stageBefore
    assert(lost>=0 and lost<=i.limit and gained==lost,'ambiguous supply transfer; preserve both inventories')
    s.staged=total; s.intent=nil; persist()
  end
  local function offer(jobId,owner,item,count)
    local station=M.station(config,owner);local destination=station.inventory
    assert(type(destination)=='string' and #destination>0,'supply inventory is not configured')
    assert(U.shortString(jobId,160) and U.integer(owner) and owner>=0 and U.shortString(item,128) and U.integer(count) and count>0,'invalid supply request')
    assert(not (state.completedSupplyBatches or {})[jobId],'supply batch has already been released')
    local s=state.supply
    if s then
      assert(s.jobId==jobId and s.owner==owner and s.item==item,'supply chest is owned by another request')
      M.validateSaved(config,state)
      reconcile(s)
      local total=staged(s)
      if s.offered then assert(total<=s.amount,'foreign items added to offered supply batch'); return s.amount end
      assert(total==(s.staged or 0),'supply stage changed before grant')
    else
      assert(next(list(destination))==nil,'supply chest must be empty before ownership')
      s={jobId=jobId,owner=owner,item=item,station=station,requested=math.min(count,(config.supply or {}).batch or 64),staged=0}; state.supply=s; persist()
    end
    local sources,total,seen={},0,{}
    for _,name in ipairs(config.storageInventories or {}) do
      assert(not seen[name],'duplicate source inventory'); seen[name]=true
      if name~=destination then
        for slot,i in pairs(list(name)) do
          if i.name==item and not i.nbt then sources[#sources+1]={name=name,slot=slot,count=i.count}; total=total+i.count end
        end
      end
    end
    local available=math.max(0,total-((config.turtleFuelReserveItems or {})[item] or 0))
    for _,source in ipairs(sources) do
      local remaining=math.min(s.requested-s.staged,available)
      if remaining<=0 then break end
      local limit=math.min(remaining,source.count)
      s.intent={source=source.name,slot=source.slot,sourceBefore=source.count,stageBefore=s.staged,limit=limit}; persist()
      local before=s.staged
      e.peripheral.call(source.name,'pushItems',destination,source.slot,limit)
      reconcile(s); local moved=s.staged-before; available=available-moved
      if moved<limit then break end
    end
    needsStock=s.staged==0 and available==0
    assert(s.staged>0,'supply stock unavailable or staging chest full')
    s.offered=true; s.amount=s.staged; persist(); return s.amount
  end
  function self:offer(jobId,owner,item,count)
    if fault then return nil,fault end
    needsStock=false
    local ok,result=pcall(offer,jobId,owner,item,count)
    if not ok then return nil,tostring(result),needsStock end
    return result
  end
  function self:release(jobId)
    if fault then return false,fault end
    local ok,err=pcall(function()
      local s=state.supply; if not s then return end
      assert(s.jobId==jobId,'cannot release another job supply')
      M.validateSaved(config,state)
      reconcile(s); assert(next(list(stage(s)))==nil,'supply chest still contains staged items')
      state.completedSupplyBatches=state.completedSupplyBatches or {}
      state.completedSupplyBatches[jobId]=true
      state.supply=nil; persist()
    end)
    return ok,not ok and tostring(err) or nil
  end
  return self
end
return M
