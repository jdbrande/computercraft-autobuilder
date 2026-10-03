local U=require('autobuilder.core.util')
local function fixture()
  local h={inventories={a={},b={}},sizes={a=3,b=2},limits={},maxCounts={coal=64,bucket=16,lava=1}}
  h.peripheral={call=function(name,method,slot)
    local inv=assert(h.inventories[name],'inventory disconnected')
    if method=='list' then return U.copy(inv) end
    if method=='size' then return h.sizes[name] end
    if method=='getItemLimit' then return h.limits[name..':'..slot] or 64 end
    if method=='getItemDetail' then local item=U.copy(inv[slot]); if item then item.maxCount=h.maxCounts[item.name] end; return item end
    error('unexpected peripheral call')
  end}
  local f={h=h,state={}}
  function f:boot()
    self.capacity=require('autobuilder.storage.capacity').new(self.state,function()
      if self.fail then return false,'disk full' end
      self.saved=U.copy(self.state); return true
    end)
  end
  f:boot(); return f
end
local function request(name,items,limits,exclusive) return {inventory=name,items=items,limits=limits,exclusive=exclusive} end

test('capacity claims allocate concrete slots without spending another owners room',function()
  local f=fixture(); f.h.inventories.a[1]={name='coal',count=60}
  local a=assert(f.capacity:reserve('one',{request('a',{coal=6},{coal=64})},f.h))
  eq(a.nodes.a.allocations[1].slot,1); eq(a.nodes.a.allocations[1].count,4)
  eq(a.nodes.a.allocations[2].slot,2); eq(a.nodes.a.allocations[2].count,2)
  local b=assert(f.capacity:reserve('two',{request('a',{coal=63},{coal=64})},f.h))
  eq(b.nodes.a.allocations[1].slot,2); eq(b.nodes.a.allocations[1].count,62)
  eq(b.nodes.a.allocations[2].slot,3); eq(b.nodes.a.allocations[2].count,1)
  local no,why=f.capacity:reserve('three',{request('a',{coal=64},{coal=64})},f.h)
  eq(no,nil); assert(why:find('capacity'))
end)

test('unknown stack limits reserve one per slot and native slot limits bound known items',function()
  local f=fixture(); f.h.limits['a:1']=0; f.h.limits['a:2']=1
  local a=assert(f.capacity:reserve('one',{request('a',{lava=2})},f.h))
  eq(a.nodes.a.allocations[1].slot,2); eq(a.nodes.a.allocations[1].count,1)
  eq(a.nodes.a.allocations[2].slot,3); eq(a.nodes.a.allocations[2].count,1)
  f.capacity:release('one')
  local b=assert(f.capacity:reserve('two',{request('a',{coal=65},{coal=64})},f.h))
  eq(b.nodes.a.allocations[1].count,1); eq(b.nodes.a.allocations[2].count,64)
end)

test('exclusive capacity leases persist across reboot and reject both directions of sharing',function()
  local f=fixture(); assert(f.capacity:reserve('one',{request('a',{coal=2},{coal=64},true)},f.h))
  f.state=U.copy(f.saved); f:boot()
  eq(f.capacity:reserve('two',{request('a',{bucket=1})},f.h),nil)
  f.capacity:release('one'); assert(f.capacity:reserve('two',{request('a',{bucket=1})},f.h))
  eq(f.capacity:reserve('three',{request('a',{coal=1},nil,true)},f.h),nil)
end)

test('capacity contracts are immutable and failed multi-inventory checkpoints roll back',function()
  local f=fixture(); local requests={request('a',{coal=2},{coal=64}),request('b',{bucket=1})}
  f.fail=true; assert(not pcall(f.capacity.reserve,f.capacity,'one',requests,f.h))
  eq(next(f.state.capacityLedger.leases),nil)
  f.fail=false; local lease=assert(f.capacity:reserve('one',requests,f.h))
  f.h.inventories.a=nil -- duplicate does not need a fresh physical snapshot
  assert(require('autobuilder.factory.factory').equal(f.capacity:reserve('one',requests,f.h),lease))
  assert(not pcall(f.capacity.reserve,f.capacity,'one',{request('b',{bucket=2})},f.h))
  f.fail=true; assert(not pcall(f.capacity.release,f.capacity,'one')); eq(f.state.capacityLedger.leases.one.status,'held')
  f.fail=false; f.capacity:release('one'); f.capacity:release('one')
  eq(f.capacity:reserve('one',requests,f.h),nil)
end)

test('full disconnected and contaminated destinations never produce a partial capacity claim',function()
  local f=fixture(); for i=1,3 do f.h.inventories.a[i]={name='coal',count=64} end
  eq(f.capacity:reserve('full',{request('b',{bucket=1}),request('a',{coal=1})},f.h),nil)
  eq(next(f.state.capacityLedger.leases),nil)
  f.h.inventories.a={[1]={name='coal',count=1,nbt='protected'}}; f.h.sizes.a=1
  eq(f.capacity:reserve('nbt',{request('a',{coal=1},{coal=64})},f.h),nil)
  assert(not pcall(f.capacity.reserve,f.capacity,'missing',{request('missing',{coal=1})},f.h))
  eq(next(f.state.capacityLedger.leases),nil)
end)

test('capacity requests reject malformed shape sizes limits and item quantities',function()
  local f=fixture()
  for _,requests in ipairs({{}, {[2]=request('a',{coal=1})}, {request('a',{coal=0})},
    {request('a',{coal=1},{coal=0})}, {request('a',{coal=1}),request('a',{bucket=1})}}) do
    assert(not pcall(f.capacity.reserve,f.capacity,'invalid',requests,f.h))
  end
  f.h.sizes.a=-1
  assert(not pcall(f.capacity.reserve,f.capacity,'bad-size',{request('a',{coal=1})},f.h))
  eq(next(f.state.capacityLedger.leases),nil)
end)

test('capacity preview shares allocation rules without claims or repeated peripheral observations',function()
  local f=fixture();local calls=0;local call=f.h.peripheral.call
  f.h.peripheral.call=function(...) calls=calls+1;return call(...) end
  assert(f.capacity:reserve('held',{request('a',{coal=64},{coal=64})},f.h))
  local observed=require('autobuilder.storage.capacity').observe(f.h)
  calls=0
  local no,why=f.capacity:preview('new',{request('a',{lava=3})},observed)
  eq(no,nil);assert(why:find('capacity'));local first=calls
  local fit=assert(f.capacity:preview('new',{request('a',{lava=2})},observed))
  eq(calls,first);eq(fit.nodes.a.allocations[1].slot,2);eq(fit.nodes.a.allocations[2].slot,3)
  eq(f.state.capacityLedger.leases.new,nil)
  f.h.inventories.a[2]={name='coal',count=64}
  eq(f.capacity:reserve('new',{request('a',{lava=2})},f.h),nil)
  eq(f.state.capacityLedger.leases.new,nil)
end)
