test('acknowledged task receipts stay bounded without forgetting exact replay protection',function()
  local R=require('autobuilder.core.receipts'); local state={}
  for i=1,400 do R.record(state,'tasks','task:1:'..(i*2),{progress=1}) end
  local count=0; for _ in pairs(state.tasks) do count=count+1 end
  assert(count<=64); assert(R.archived(state,'tasks','task:1:2'))
  assert(not R.archived(state,'tasks','task:1:3'))
  assert(not R.archived(state,'tasks','task:2:2'))
  local saved=require('tests.support').codec(); state=saved.unserialize(saved.serialize(state))
  assert(R.archived(state,'tasks','task:1:2'))
  for i=1,400 do R.record(state,'tasks','task:1:'..(i*2-1),{progress=1}) end
  assert(R.archived(state,'tasks','task:1:1'))
  assert(#state.tasksArchive['task:1:']<350)
  R.record(state,'mines','mine:1:100:2',10)
  assert(not R.archived(state,'mines','mine:1:200:2'))
end)
test('timestamped mining receipts use compact exact identifiers instead of thousands of map keys',function()
  local R=require('autobuilder.core.receipts'); local s={}
  for i=1,7116 do R.record(s,'mines','mine:1:'..(1790440000000+i*5000)..':'..i,10) end
  local keys=0; for _ in pairs(s.minesArchive) do keys=keys+1 end
  eq(keys,1)
  local codec=require('tests.support').codec(); assert(#codec.serialize(s)<120000)
  assert(R.archived(s,'mines','mine:1:1790440005000:1'))
  assert(not R.archived(s,'mines','mine:1:1790440005001:1'))
  assert(not R.archived(s,'mines','mine:1:1790440005000:2'))
end)
