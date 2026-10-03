local U=require('autobuilder.core.util')
local F=require('autobuilder.factory.factory')
local M={}
local function bounded(n,max) return U.integer(n) and n>=1 and n<=max end
local function contract(requests)
  assert(type(requests)=='table' and #requests>=1 and #requests<=128,'capacity requests required')
  local seen,n={},0
  for i,r in pairs(requests) do
    n=n+1; assert(bounded(i,#requests) and type(r)=='table','invalid capacity request array')
    assert(U.shortString(r.inventory,128) and not seen[r.inventory],'invalid/duplicate capacity inventory'); seen[r.inventory]=true
    assert(r.exclusive==nil or type(r.exclusive)=='boolean','invalid exclusive capacity flag')
    assert(type(r.items)=='table' and next(r.items),'capacity item quantities required')
    local count=0
    for item,amount in pairs(r.items) do count=count+1; assert(count<=64 and U.shortString(item,128) and bounded(amount,100000000),'invalid capacity quantity') end
    assert(r.limits==nil or type(r.limits)=='table','invalid capacity stack limits')
    for item,limit in pairs(r.limits or {}) do assert(r.items[item] and bounded(limit,1000000),'invalid capacity stack limit') end
  end
  assert(n==#requests,'sparse capacity request array')
  return U.copy(requests)
end
function M.new(state,save)
  assert(type(state)=='table' and type(save)=='function','capacity state and persistence required')
  state.capacityLedger=state.capacityLedger or {leases={}}
  local s=state.capacityLedger; assert(type(s.leases)=='table','invalid capacity ledger')
  local self={state=s}
  local function commit(id,lease)
    local before=s.leases[id]; s.leases[id]=lease
    local called,ok,why=pcall(save)
    if not called or not ok then s.leases[id]=before; error('capacity checkpoint failed: '..tostring(called and why or ok),0) end
  end
  -- Callers combining stock and capacity grants hold the shared inventory action
  -- lock across this observation and their physical transfer journal.
  function self:reserve(id,requests,e)
    assert(U.shortString(id,160),'invalid capacity claim ID')
    requests=contract(requests)
    local old=s.leases[id]
    if old then
      assert(F.equal(old.contract,requests),'changed capacity claim')
      if old.status~='held' then return nil,'capacity claim already closed' end
      return U.copy(old)
    end
    local lease={id=id,status='held',contract=requests,nodes={}}
    for _,r in ipairs(requests) do
      local taken={}
      for _,other in pairs(s.leases) do if other.status=='held' then
        local node=other.nodes[r.inventory]
        if node then
          if r.exclusive or node.exclusive then return nil,'capacity inventory owned: '..r.inventory end
          for _,a in ipairs(node.allocations) do
            local t=taken[a.slot]
            assert(not t or t.item==a.item,'conflicting saved capacity slot')
            taken[a.slot]={item=a.item,count=(t and t.count or 0)+a.count}
          end
        end
      end end
      local inv=F.list(e,r.inventory); local size=e.peripheral.call(r.inventory,'size')
      assert(bounded(size,4096),'invalid inventory size')
      local slots={}
      for i=1,size do
        local limit=e.peripheral.call(r.inventory,'getItemLimit',i)
        assert(U.integer(limit) and limit>=0 and limit<=1000000,'invalid inventory slot limit')
        local stack=inv[i]; local max
        if stack then
          local detail=e.peripheral.call(r.inventory,'getItemDetail',i)
          assert(detail and detail.name==stack.name and detail.count==stack.count,'inventory changed during capacity observation')
          max=detail.maxCount; assert(max==nil or bounded(max,1000000),'invalid measured item stack limit')
        end
        slots[i]={limit=limit,stack=stack,max=max}
      end
      local node={exclusive=r.exclusive==true,allocations={}}; lease.nodes[r.inventory]=node
      local items={}; for item in pairs(r.items) do items[#items+1]=item end; table.sort(items)
      for _,item in ipairs(items) do
        local left=r.items[item]
        for i,slot in ipairs(slots) do
          local stack,t=slot.stack,taken[i]
          if (not stack or stack.name==item and not stack.nbt) and (not t or t.item==item) then
            local max=slot.max or (r.limits or {})[item] or 1
            local room=math.max(0,math.min(slot.limit,max)-(stack and stack.count or 0)-(t and t.count or 0))
            local n=math.min(left,room)
            if n>0 then
              node.allocations[#node.allocations+1]={slot=i,item=item,count=n}
              taken[i]={item=item,count=(t and t.count or 0)+n}; left=left-n
            end
          end
          if left==0 then break end
        end
        if left>0 then return nil,'insufficient capacity in '..r.inventory..' for '..item end
      end
    end
    commit(id,lease); return U.copy(lease)
  end
  function self:release(id)
    local old=assert(s.leases[id],'unknown capacity claim')
    if old.status=='released' then return true end
    assert(old.status=='held','capacity claim already closed')
    local lease=U.copy(old); lease.status='released'; commit(id,lease); return true
  end
  return self
end
return M
