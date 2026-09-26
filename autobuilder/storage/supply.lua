local U=require('autobuilder.core.util')
local M={}
function M.new(state,config,e,save)
  assert(type(state)=='table' and e and e.peripheral and type(save)=='function','supply state/peripheral/persistence required')
  local self={}; local fault
  local stage=(config.supply or {}).inventory
  local function persist()
    local ok,v,err=pcall(save)
    if not ok or not v then fault='supply checkpoint failed: '..tostring(ok and err or v); error(fault,0) end
  end
  local function list(name)
    local inv=e.peripheral.call(name,'list'); assert(type(inv)=='table','inventory unavailable: '..tostring(name))
    for slot,i in pairs(inv) do assert(U.integer(slot) and slot>0 and type(i)=='table' and U.shortString(i.name,128) and U.integer(i.count) and i.count>0,'invalid inventory contents') end
    return inv
  end
  local function staged(item)
    local total=0
    for _,i in pairs(list(stage)) do assert(i.name==item and not i.nbt,'foreign contents in supply chest'); total=total+i.count end
    return total
  end
  local function reconcile(s)
    local i=s.intent; if not i then return end
    local observed=list(i.source)[i.slot]
    assert(not observed or observed.name==s.item and not observed.nbt,'supply source slot changed during recovery')
    local lost=i.sourceBefore-(observed and observed.count or 0)
    local total=staged(s.item); local gained=total-i.stageBefore
    assert(lost>=0 and lost<=i.limit and gained==lost,'ambiguous supply transfer; preserve both inventories')
    s.staged=total; s.intent=nil; persist()
  end
  local function offer(jobId,owner,item,count)
    assert(type(stage)=='string' and #stage>0,'supply inventory is not configured')
    assert(U.shortString(jobId,160) and U.integer(owner) and owner>=0 and U.shortString(item,128) and U.integer(count) and count>0,'invalid supply request')
    assert(not (state.completedSupplyBatches or {})[jobId],'supply batch has already been released')
    local s=state.supply
    if s then
      assert(s.jobId==jobId and s.owner==owner and s.item==item,'supply chest is owned by another request')
      reconcile(s)
      local total=staged(item)
      if s.offered then assert(total<=s.amount,'foreign items added to offered supply batch'); return s.amount end
      assert(total==(s.staged or 0),'supply stage changed before grant')
    else
      assert(next(list(stage))==nil,'supply chest must be empty before ownership')
      s={jobId=jobId,owner=owner,item=item,requested=math.min(count,(config.supply or {}).batch or 64),staged=0}; state.supply=s; persist()
    end
    local sources,total,seen={},0,{}
    for _,name in ipairs(config.storageInventories or {}) do
      assert(not seen[name],'duplicate source inventory'); seen[name]=true
      if name~=stage then
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
      e.peripheral.call(source.name,'pushItems',stage,source.slot,limit)
      reconcile(s); local moved=s.staged-before; available=available-moved
      if moved<limit then break end
    end
    assert(s.staged>0,'supply stock unavailable or staging chest full')
    s.offered=true; s.amount=s.staged; persist(); return s.amount
  end
  function self:offer(jobId,owner,item,count)
    if fault then return nil,fault end
    local ok,result=pcall(offer,jobId,owner,item,count)
    if not ok then return nil,tostring(result) end
    return result
  end
  function self:release(jobId)
    if fault then return false,fault end
    local ok,err=pcall(function()
      local s=state.supply; if not s then return end
      assert(s.jobId==jobId,'cannot release another job supply')
      reconcile(s); assert(next(list(stage))==nil,'supply chest still contains staged items')
      state.completedSupplyBatches=state.completedSupplyBatches or {}
      state.completedSupplyBatches[jobId]=true
      state.supply=nil; persist()
    end)
    return ok,not ok and tostring(err) or nil
  end
  return self
end
return M
