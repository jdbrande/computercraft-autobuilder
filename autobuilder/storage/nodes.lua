local U=require('autobuilder.core.util')
local F=require('autobuilder.factory.factory')
local M={}
local function list(t,min,max)
  assert(type(t)=='table' and #t>=min and #t<=max,'invalid logistics list size')
  local count=0
  for k in pairs(t) do count=count+1;assert(U.integer(k) and k>=1 and k<=#t,'invalid logistics list index') end
  assert(count==#t,'sparse logistics list')
end
function M.get(config,id)
  for _,node in ipairs((config.logistics or {}).nodes or {}) do if node.id==id then return node end end
end
function M.identity(node)
  return {id=node.id,inventory=node.inventory,position={x=node.position.x,y=node.position.y,z=node.position.z}}
end
function M.validContract(job)
  local c=job.logistics
  if job.type~='TRANSPORT' or type(c)~='table' or not U.position(job.source) or not U.position(job.destination)
    or not U.integer(job.quantity) or job.quantity<1 or job.quantity>64 then return false end
  local names={}
  for _,field in ipairs({'source','destination','pickup','drop'}) do
    local v=c[field]
    if type(v)~='table' or not U.shortString(v.inventory,128) or names[v.inventory] or not U.position(v.position) then return false end
    if (field=='source' or field=='destination') and not U.shortString(v.id,64) then return false end
    names[v.inventory]=true
  end
  return c.source.id~=c.destination.id and U.distance(c.pickup.position,job.source)==0 and U.distance(c.drop.position,job.destination)==0
end
function M.validate(config)
  local c=config.logistics
  assert(type(c)=='table' and U.integer(c.batchSize) and c.batchSize>=1 and c.batchSize<=64,'logistics batchSize must be 1..64')
  list(c.nodes,0,64)
  local shared,occupied,ids,stocks,cells={},{},{},{},{}
  for _,name in ipairs(config.storageInventories) do shared[name]=true;occupied[name]='storage' end
  for _,name in ipairs(config.furnaces) do occupied[name]=true end
  occupied[config.supply.inventory]=true
  for _,station in ipairs(config.fuel.stations) do occupied[station.inventory]=true end
  for _,field in ipairs({'buffer','input','output'}) do occupied[config.craftingStation[field]]=true end
  for _,station in ipairs(config.craftingStations) do
    for _,field in ipairs({'buffer','input','output'}) do occupied[station[field]]=true end
  end
  local function cell(p)
    assert(U.position(p),'invalid logistics coordinates')
    local key=p.x..','..p.y..','..p.z
    assert(not cells[key],'overlapping logistics endpoint');cells[key]=true
  end
  for _,node in ipairs(c.nodes) do
    assert(type(node)=='table' and U.shortString(node.id,64) and not ids[node.id],'invalid/duplicate logistics node ID');ids[node.id]=true
    assert(shared[node.inventory] and occupied[node.inventory]=='storage' and not stocks[node.inventory],'logistics node needs distinct registered storage');stocks[node.inventory]=true
    cell(node.position);list(node.buffers,1,8)
    for _,buffer in ipairs(node.buffers) do
      assert(type(buffer)=='table' and U.shortString(buffer.inventory,128) and not occupied[buffer.inventory],'logistics buffer must be private')
      occupied[buffer.inventory]=true;cell(buffer.position)
      cell({x=buffer.position.x,y=buffer.position.y-1,z=buffer.position.z})
    end
    assert(node.targets==nil or type(node.targets)=='table','invalid logistics targets')
    local count=0
    for item,n in pairs(node.targets or {}) do
      count=count+1;assert(count<=64 and U.shortString(item,128) and U.integer(n) and n>=1 and n<=1000000,'invalid logistics target')
    end
  end
end
local function owned(state,visit)
  for _,job in pairs((state.automation or {}).jobs or {}) do
    local lease=(state.capacityLedger or {}).leases and state.capacityLedger.leases[job.id]
    if job.returning and (job.status~='completed' or lease and lease.status=='held') then
      local c=job.returning;visit({source=c.node,destination=c.node,pickup=c.buffer,drop=c.buffer})
    end
    if job.logistics and (job.status~='completed' or lease and lease.status=='held') then visit(job.logistics) end
  end
end
function M.validateSaved(config,state)
  owned(state,function(contract)
    for _,pair in ipairs({{'source','pickup'},{'destination','drop'}}) do
      local saved=contract[pair[1]];local node=M.get(config,saved.id)
      assert(node and F.equal(M.identity(node),saved),'owned logistics node removed or changed: '..saved.id)
      local found=false
      for _,buffer in ipairs(node.buffers) do if F.equal(buffer,contract[pair[2]]) then found=true end end
      assert(found,'owned logistics buffer removed or changed: '..saved.id)
    end
  end)
  local reserved={}
  for _,node in ipairs(config.logistics.nodes) do for _,buffer in ipairs(node.buffers) do reserved[buffer.inventory]=true end end
  for id,lease in pairs((state.capacityLedger or {}).leases or {}) do
    if lease.status=='held' then
      local job=(state.automation or {}).jobs and state.automation.jobs[id]
      for name,node in pairs(lease.nodes) do
        if node.exclusive and reserved[name] then
          assert(job and (job.logistics and (job.logistics.pickup.inventory==name or job.logistics.drop.inventory==name) or job.returning and job.returning.buffer.inventory==name),
            'owned private inventory cannot become logistics buffer: '..name)
        end
      end
    end
  end
  for _,job in pairs((state.automation or {}).jobs or {}) do
    if job.privateStation and job.status~='completed' then
      for _,field in ipairs({'buffer','input','output'}) do assert(not reserved[job.privateStation[field]],'owned crafting inventory cannot become logistics buffer') end
    end
  end
end
function M.protected(config,state,accessHome)
  local areas,seen={},{}
  local function box(p,buffer)
    local b={min={x=p.x,y=p.y-(buffer and 1 or 0),z=p.z},max={x=p.x,y=p.y+(buffer and 2 or 0),z=p.z}}
    if buffer and accessHome and U.distance(p,accessHome)==0 then b.max.y=p.y end
    local key=p.x..','..b.min.y..','..p.z..':'..b.max.y
    if not seen[key] then areas[#areas+1]=b;seen[key]=true end
  end
  for _,node in ipairs((config.logistics or {}).nodes or {}) do
    box(node.position);for _,buffer in ipairs(node.buffers) do box(buffer.position,true) end
  end
  owned(state,function(c) box(c.source.position);box(c.destination.position);box(c.pickup.position,true);box(c.drop.position,true) end)
  return areas
end
return M
