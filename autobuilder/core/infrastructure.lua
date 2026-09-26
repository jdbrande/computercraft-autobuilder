-- One explicit depot footprint, built once and independently verified. Capacity
-- observations trigger construction; they never authorize inventory transfers.
local U=require('autobuilder.core.util')
local Placement=require('autobuilder.build.placement')
local M={}
function M.new(app,config,e,queue)
  queue.state.infrastructure=queue.state.infrastructure or {status='idle'}
  local s=queue.state.infrastructure; local self={state=s}
  local function persist()
    local ok,err=app:save(); assert(ok,err or 'infrastructure checkpoint failed')
  end
  local function blocked(reason)
    s.status='blocked'; s.error=tostring(reason); persist(); return false,s.error
  end
  local function plan()
    assert(config.build and config.build.enabled,'Enable building before requesting depot expansion')
    local source=config.depotExpansion
    assert(type(source)=='table' and #source>=1 and #source<=512,'depotExpansion requires 1..512 explicit cells')
    local count=0; for k in pairs(source) do count=count+1; assert(U.integer(k) and k>=1 and k<=#source,'depotExpansion must be a dense array') end
    assert(count==#source,'depotExpansion must be a dense array')
    local blocks={}
    for _,sourceBlock in ipairs(source) do
      assert(type(sourceBlock)=='table' and U.position(sourceBlock),'invalid expansion coordinate')
      local b={x=sourceBlock.x,y=sourceBlock.y,z=sourceBlock.z,name=sourceBlock.name,state={}}
      assert(sourceBlock.state==nil or type(sourceBlock.state)=='table','invalid expansion block states')
      for key,value in pairs(sourceBlock.state or {}) do
        assert(type(key)=='string' and (type(value)=='string' or type(value)=='boolean' or U.finite(value)),'invalid expansion block state')
        b.state[key]=tostring(value)
      end
      local placement,why=Placement.plan(b); assert(placement,why)
      assert(placement.item,'Expansion cells must place blocks, not clear terrain')
      for _,area in ipairs(config.restrictedAreas or {}) do
        for _,p in ipairs({b,placement.stand,placement.pair}) do
          assert(not (p.x>=area.min.x and p.x<=area.max.x and p.y>=area.min.y and p.y<=area.max.y and p.z>=area.min.z and p.z<=area.max.z),'Expansion overlaps a restricted target or access cell')
        end
      end
      blocks[#blocks+1]=b
    end
    local ordered={}
    for _,region in ipairs(require('autobuilder.blueprint.blueprint').regions(blocks,8)) do
      for _,b in ipairs(region.blocks) do ordered[#ordered+1]=b end
    end
    return ordered
  end
  local function build()
    if not s.buildId then
      -- The plan is already durable. A crash after submit and before this ID save
      -- recovers the same task via the queue's durable deduplication key.
      local job=queue:submit('BUILD',{blocks=U.copy(s.plan),infrastructure=true,deferConnections=true},{},'depot-expansion')
      s.buildId=job.id; s.status='building'; s.error=nil; persist()
    end
    return true,s.buildId
  end
  function self:request()
    if s.plan and s.status=='blocked' then return false,s.error end
    if s.plan then return build() end
    local ok,result=pcall(plan)
    if not ok then return blocked(result) end
    s.plan=result; s.status='pending'; s.error=nil; persist()
    return build()
  end
  local function capacity()
    local names=config.storageInventories or {}; assert(#names>0,'No storage inventories configured for capacity monitoring')
    local free,seen=0,{}
    for _,name in ipairs(names) do
      assert(not seen[name],'Duplicate storage inventory in capacity monitoring'); seen[name]=true
      local size=e.peripheral.call(name,'size'); local items=e.peripheral.call(name,'list')
      assert(U.integer(size) and size>=1 and size<=1000000 and type(items)=='table','Invalid storage capacity response')
      local occupied=0
      for slot,item in pairs(items) do
        assert(U.integer(slot) and slot>=1 and slot<=size and type(item)=='table' and U.shortString(item.name,128)
          and U.integer(item.count) and item.count>0,'Invalid occupied storage slot')
        occupied=occupied+1
      end
      free=free+size-occupied
    end
    return free
  end
  function self:tick()
    if not s.plan then
      local automatic=config.autoDepotExpansion or {}
      if not automatic.enabled then return true end
      if not U.integer(automatic.freeSlots) or automatic.freeSlots<0 then return blocked('Invalid automatic expansion free-slot threshold') end
      local ok,free=pcall(capacity)
      if not ok then return blocked(free) end
      s.freeSlots=free
      if free<=automatic.freeSlots then return self:request() end
      s.status='idle'; s.error=nil; persist(); return true
    end
    if s.status=='completed' then return true end
    build()
    local job=queue.state.jobs[s.buildId]
    if not job then return blocked('Expansion build ownership is missing; preserve state for reconciliation') end
    if job.status~='completed' then
      if job.status=='blocked' or job.status=='failed' then return blocked(job.error or 'Expansion build is blocked') end
      s.status='building'; s.error=nil; persist(); return true
    end
    if not s.verifyId then
      local verify=queue:submit('VERIFY',{blocks=U.copy(s.plan),infrastructure=true},{s.buildId},'depot-expansion:verify')
      s.verifyId=verify.id; s.status='verifying'; s.error=nil; persist()
    end
    local verify=queue.state.jobs[s.verifyId]
    if not verify then return blocked('Expansion verification ownership is missing; preserve state for reconciliation') end
    if verify.status=='blocked' or verify.status=='failed' then return blocked(verify.error or 'Expansion verification is blocked') end
    if verify.status~='completed' then s.status='verifying'; s.error=nil; persist(); return true end
    local report=verify.report; local counts=report and report.counts
    if type(counts)~='table' or counts.correct~=#s.plan then return blocked('Expansion verification did not confirm every planned cell') end
    for kind,n in pairs(counts) do
      if not U.integer(n) or n<0 or kind~='correct' and n~=0 then return blocked('Expansion verification reported defects or inaccessible cells') end
    end
    s.report=U.copy(report); s.status='completed'; s.error=nil; persist(); return true
  end
  return self
end
return M
