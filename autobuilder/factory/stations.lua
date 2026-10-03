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
  if localStation.buffer~='' then claim(localStation) end
  local count=0
  for i,station in pairs(stations) do
    count=count+1; assert(U.integer(i) and i>=1 and i<=#stations and M.valid(station),'invalid crafting station')
    assert(not ids[station.id] and not workers[station.workerId],'duplicate crafting station identity')
    ids[station.id]=true; workers[station.workerId]=true; claim(station)
  end
  assert(count==#stations,'sparse crafting station array')
end
return M
