local U=require('autobuilder.core.util')
local Equal=require('autobuilder.factory.factory').equal
local M={}
local function count(n) return U.integer(n) and n>=0 and n<=100000000 end
local function quantities(values)
  assert(type(values)=='table','inventory quantities must be a map')
  local out,n={},0
  for item,value in pairs(values) do
    n=n+1; assert(n<=4096 and U.shortString(item,128) and count(value),'invalid inventory quantity')
    if value>0 then out[item]=value end
  end
  return out
end
function M.new(state,save)
  assert(type(state)=='table' and type(save)=='function','inventory state and persistence required')
  state.inventoryLedger=state.inventoryLedger or {leases={}}
  local s=state.inventoryLedger; assert(type(s.leases)=='table','invalid inventory ledger')
  local self={state=s}
  local function commit(id,replacement)
    local before=s.leases[id]; s.leases[id]=replacement
    local called,ok,why=pcall(save)
    if not called or not ok then
      s.leases[id]=before
      error('inventory checkpoint failed: '..tostring(called and why or ok),0)
    end
  end
  function self:view(item,physical,demand)
    assert(U.shortString(item,128) and (demand==nil or count(demand)),'invalid inventory view')
    local v={reserved=0,transit=0,expected=0,demand=demand or 0}
    for _,lease in pairs(s.leases) do if lease.status=='held' then
      v.reserved=v.reserved+(lease.inputs[item] or 0)-(lease.withdrawn[item] or 0)
      v.transit=v.transit+(lease.transit[item] or 0)
      v.expected=v.expected+(lease.outputs[item] or 0)-(lease.delivered[item] or 0)
    end end
    if physical~=nil then
      assert(type(physical)=='table' and count(physical[item] or 0),'invalid measured inventory')
      v.physical=physical[item] or 0; v.available=math.max(0,v.physical-v.reserved)
    end
    return v
  end
  function self:reserve(id,inputs,outputs,physical,options)
    options=options or {}
    assert(U.shortString(id,160),'invalid inventory claim ID')
    inputs=quantities(inputs); outputs=quantities(outputs)
    assert(options.project==nil or U.shortString(options.project,128),'invalid inventory project')
    local protected=quantities(options.protected or {})
    local old=s.leases[id]
    if old then
      assert(Equal(old.inputs,inputs) and Equal(old.outputs,outputs) and old.project==options.project,'changed inventory claim')
      if old.status~='held' then return nil,'inventory claim already closed' end
      return U.copy(old)
    end
    if physical==nil then return nil,'physical inventory unavailable' end
    quantities(physical)
    for item,n in pairs(inputs) do
      local v=self:view(item,physical)
      if n>math.max(0,v.available-(protected[item] or 0)) then return nil,'insufficient unreserved '..item end
    end
    local lease={id=id,inputs=inputs,outputs=outputs,project=options.project,status='held',
      withdrawn={},delivered={},transit={},sequence=0}
    commit(id,lease); return U.copy(lease)
  end
  function self:receipt(id,withdrawn,delivered,transit,sequence)
    local old=assert(s.leases[id],'unknown inventory claim')
    withdrawn=quantities(withdrawn); delivered=quantities(delivered); transit=quantities(transit)
    assert(U.integer(sequence) and sequence>=1 and sequence<=9007199254740991,'invalid inventory receipt sequence')
    for item,n in pairs(withdrawn) do assert(n<=(old.inputs[item] or 0),'withdrawal exceeds inventory claim') end
    for item,n in pairs(delivered) do assert(n<=(old.outputs[item] or 0),'delivery exceeds inventory claim') end
    for item,n in pairs(transit) do
      assert(n<=math.max(0,(withdrawn[item] or 0)-(delivered[item] or 0)),'transit exceeds confirmed withdrawal')
    end
    if sequence<old.sequence then return true end
    if sequence==old.sequence then
      assert(Equal(old.withdrawn,withdrawn) and Equal(old.delivered,delivered) and Equal(old.transit,transit),'changed duplicate inventory receipt')
      return true
    end
    assert(old.status=='held','inventory claim already closed')
    for item,n in pairs(old.withdrawn) do assert((withdrawn[item] or 0)>=n,'inventory withdrawal regressed') end
    for item,n in pairs(old.delivered) do assert((delivered[item] or 0)>=n,'inventory delivery regressed') end
    local lease=U.copy(old); lease.withdrawn=withdrawn; lease.delivered=delivered; lease.transit=transit; lease.sequence=sequence
    commit(id,lease); return true
  end
  function self:release(id)
    local old=assert(s.leases[id],'unknown inventory claim')
    if old.status=='released' then return true end
    assert(old.status=='held' and not next(old.transit),'inventory transit still owned')
    for item,n in pairs(old.outputs) do assert((old.delivered[item] or 0)==n,'inventory output not delivered') end
    local lease=U.copy(old); lease.status='released'; commit(id,lease); return true
  end
  function self:cancel(id)
    local old=assert(s.leases[id],'unknown inventory claim')
    if old.status=='cancelled' then return true end
    assert(old.status=='held' and not next(old.withdrawn) and not next(old.delivered) and not next(old.transit),'cannot cancel started inventory claim')
    local lease=U.copy(old); lease.status='cancelled'; commit(id,lease); return true
  end
  return self
end
return M
