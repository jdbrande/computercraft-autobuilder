local U=require('autobuilder.core.util')
local M={}
function M.valid(s)
  if type(s)~='table' or not U.shortString(s.id,64) or not U.integer(s.workerId) or s.workerId<0 then return false end
  local seen={}
  for _,field in ipairs({'buffer','input','output'}) do
    local name=s[field]; if not U.shortString(name,128) or seen[name] then return false end; seen[name]=true
  end
  return true
end
function M.matches(s,config,id)
  if not M.valid(s) or not config.capabilities.isolatedCraftingV1 or s.workerId~=id then return false end
  for _,field in ipairs({'buffer','input','output'}) do if s[field]~=config.craftingStation[field] then return false end end
  return true
end
function M.validate(config)
  assert(U.integer(config.craftingBatchSize) and config.craftingBatchSize>=1 and config.craftingBatchSize<=64,'craftingBatchSize must be 1..64')
  local stations=config.craftingStations
  assert(type(stations)=='table' and #stations<=128,'invalid crafting stations')
  local occupied,ids,workers={},{},{}
  for _,name in ipairs(config.storageInventories) do occupied[name]=true end
  for _,name in ipairs(config.furnaces) do occupied[name]=true end
  occupied[config.supply.inventory]=true
  for _,station in ipairs(config.fuel.stations) do occupied[station.inventory]=true end
  local function claim(station)
    for _,field in ipairs({'buffer','input','output'}) do
      local name=station[field]; assert(U.shortString(name,128) and not occupied[name],'crafting inventories must be distinct and private')
      occupied[name]=true
    end
  end
  local localStation=config.craftingStation
  assert(type(localStation.buffer)=='string','invalid crafting buffer')
  if localStation.buffer~='' then claim(localStation)
  else
    for _,field in ipairs({'input','output'}) do
      if localStation[field]~='' then occupied[localStation[field]]=true end
    end
  end
  local count=0
  for i,station in pairs(stations) do
    count=count+1; assert(U.integer(i) and i>=1 and i<=#stations and M.valid(station),'invalid crafting station')
    assert(not ids[station.id] and not workers[station.workerId],'duplicate crafting station identity')
    ids[station.id]=true; workers[station.workerId]=true; claim(station)
  end
  assert(count==#stations,'sparse crafting station array')
end
-- Configuration is not an ownership release. Validate before runtime startup can
-- observe shared stock or dispatch any consumer of a saved private inventory.
function M.validateSaved(config,state)
  local shared={}
  for _,names in ipairs({config.storageInventories,config.furnaces}) do
    for _,name in ipairs(names) do shared[name]=true end
  end
  shared[config.supply.inventory]=true
  for _,station in ipairs(config.fuel.stations) do shared[station.inventory]=true end
  for _,field in ipairs({'buffer','input','output'}) do shared[config.craftingStation[field]]=true end
  local owners={}
  for _,job in pairs((state.automation or {}).jobs or {}) do
    if job.privateStation and job.status~='completed' then
      for _,field in ipairs({'buffer','input','output'}) do owners[job.privateStation[field]]=job.privateStation end
    end
  end
  for _,lease in pairs((state.capacityLedger or {}).leases or {}) do
    if lease.status=='held' then
      for name,node in pairs(lease.nodes) do if node.exclusive then owners[name]=owners[name] or true end end
    end
  end
  for name,owner in pairs(owners) do
    assert(not shared[name],'owned private inventory cannot become shared: '..name)
    for _,station in ipairs(config.craftingStations) do
      for _,field in ipairs({'buffer','input','output'}) do
        if station[field]==name then
          assert(type(owner)=='table' and station.workerId==owner.workerId
            and station.buffer==owner.buffer and station.input==owner.input and station.output==owner.output,
            'owned private inventory cannot change station: '..name)
        end
      end
    end
  end
end
return M
