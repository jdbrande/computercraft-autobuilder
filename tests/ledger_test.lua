local U=require('autobuilder.core.util')
local Ledger=require('autobuilder.storage.ledger')
local function fixture()
  local state={}; local saved
  local ledger=Ledger.new(state,function() saved=U.copy(state); return true end)
  return ledger,state,function() return U.copy(saved) end
end

test('inventory reservations grant complete contracts atomically without double spending',function()
  local l,s=fixture(); local stock={stone=10,coal=2}
  assert(l:reserve('a',{stone=6,coal=1},{bricks=4},stock,{protected={coal=1},project='house'}))
  local grant,why=l:reserve('b',{stone=5},{bricks=4},stock)
  eq(grant,nil); assert(why:find('stone',1,true)); eq(s.inventoryLedger.leases.b,nil)
  eq(l:view('stone',stock,12).physical,10); eq(l:view('stone',stock,12).available,4)
  eq(l:view('stone',stock,12).reserved,6); eq(l:view('stone',stock,12).demand,12)
  eq(l:view('bricks',stock).expected,4); eq(l:view('bricks',stock).available,0)
  eq(l:reserve('c',{coal=1},{},stock,{protected={coal=1}}),nil)
  assert(l:reserve('b',{stone=4},{},stock)); eq(l:view('stone',stock).available,0)
end)

test('inventory claims are immutable idempotent and retained across restart',function()
  local l,s,saved=fixture(); local inputs={stone=3}
  local a=assert(l:reserve('a',inputs,{bricks=4},{stone=3},{project='house'}))
  inputs.stone=99
  assert(l:reserve('a',{stone=3},{bricks=4},{},{project='house'})); eq(a.inputs.stone,3)
  assert(not pcall(l.reserve,l,'a',{stone=4},{bricks=4},{stone=9},{project='house'}))
  assert(not pcall(l.reserve,l,'a',{stone=3},{bricks=4},{stone=9},{project='other'}))
  local restored=saved(); l=Ledger.new(restored,function() return true end)
  eq(l:view('stone',{stone=3}).available,0)
  eq(l:reserve('b',{stone=1},{},{stone=3}),nil)
end)

test('inventory cumulative receipts conserve partial transit and reject changed duplicate receipts',function()
  local l,s=fixture(); assert(l:reserve('haul',{stone=8},{stone=8},{stone=8}))
  l:receipt('haul',{stone=3},{stone=1},{stone=2},1)
  local v=l:view('stone',{stone=6}); eq(v.reserved,5); eq(v.transit,2); eq(v.expected,7); eq(v.available,1)
  l:receipt('haul',{stone=3},{stone=1},{stone=2},1); eq(l:view('stone',{stone=6}).reserved,5)
  assert(not pcall(l.receipt,l,'haul',{stone=4},{stone=1},{stone=3},1))
  assert(not pcall(l.receipt,l,'haul',{stone=9},{},{},2))
  assert(not pcall(l.receipt,l,'haul',{stone=3},{stone=2},{stone=4},2))
  assert(not pcall(l.release,l,'haul')); assert(not pcall(l.cancel,l,'haul'))
  l:receipt('haul',{stone=8},{stone=8},{},3)
  l:receipt('haul',{stone=3},{stone=1},{stone=2},1) -- delayed old report
  eq(l:view('stone',{stone=8}).transit,0); assert(l:release('haul'))
  eq(l:view('stone',{stone=8}).reserved,0); eq(l:view('stone',{stone=8}).expected,0)
  assert(l:release('haul')); assert(not l:reserve('haul',{stone=8},{stone=8},{stone=8}))
end)

test('inventory reservation mutations roll back failed or throwing saves',function()
  local state={}; local fault
  local l=Ledger.new(state,function() if fault=='throw' then error('disk gone') end; return not fault,'disk full' end)
  fault=true; assert(not pcall(l.reserve,l,'a',{stone=2},{stone=2},{stone=4})); eq(state.inventoryLedger.leases.a,nil)
  fault=nil; l:reserve('a',{stone=2},{stone=2},{stone=4})
  fault='throw'; assert(not pcall(l.receipt,l,'a',{stone=2},{stone=2},{},1)); eq(state.inventoryLedger.leases.a.sequence,0)
  assert(not pcall(l.cancel,l,'a')); eq(state.inventoryLedger.leases.a.status,'held')
  fault=nil; assert(l:cancel('a')); eq(l:view('stone',{stone=4}).reserved,0)
end)

test('inventory ledger rejects malformed and unknown stock without creating phantom availability',function()
  local l,s=fixture()
  for _,input in ipairs({{stone=-1},{stone=0/0},{stone=math.huge},{stone=100000001},{['']=1},{stone='2'}}) do
    assert(not pcall(l.reserve,l,'bad',input,{},{}))
  end
  eq(l:reserve('a',{stone=1},{},nil),nil)
  local v=l:view('stone',nil,3); eq(v.physical,nil); eq(v.available,nil); eq(v.demand,3)
  assert(not pcall(l.receipt,l,'missing',{},{},{},1)); eq(next(s.inventoryLedger.leases),nil)
end)
