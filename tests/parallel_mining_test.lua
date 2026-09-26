local U=require('autobuilder.core.util')
local Jobs=require('autobuilder.core.jobs')
local function area(x1,x2) return {min={x=x1,y=-20,z=0},max={x=x2,y=0,z=10}} end
local function worker(id,bounds)
  return {id=id,online=true,telemetry={capabilities={mining=true},status='idle',miningArea=bounds}}
end
local function fixture()
  local state={}; local saved
  local function save() saved=U.copy(state); return true end
  local queue=Jobs.new(state,save,function() return 100 end,7)
  local a=assert(queue:submit('minecraft:raw_iron',8,0)); a.priority=2
  local b=assert(queue:submit('minecraft:coal',8,0))
  local workers={['12']=worker(12,area(0,8)),['13']=worker(13,area(20,28))}
  return queue,state,workers,a,b,function() return saved end
end

test('mining agent advertises configured bounds only while mining is enabled',function()
  local config={capabilities={mining=true},mining={enabled=true,bounds=area(0,8)}}
  local agent=require('autobuilder.workers.agent').new({id=12,position={known=false}},config,{},require('tests.support').turtle(),function() return true end)
  local telemetry=agent:telemetry(); eq(telemetry.miningArea.max.x,8)
  telemetry.miningArea.max.x=99; eq(config.mining.bounds.max.x,8)
  config.mining.enabled=false; eq(agent:telemetry().miningArea,nil)
end)

test('disjoint advertised mining areas receive concurrent distinct jobs',function()
  local queue,state,workers,a,b=fixture()
  eq(queue:assign(workers).id,a.id); eq(a.workerId,12)
  assert(queue:progress(12,{jobId=a.id,phase='work',delivered=0,held=0}))
  eq(queue:assign(workers).id,b.id); eq(b.workerId,13)
  eq(a.status,'running'); eq(b.status,'assigned')
  eq(a.miningArea.max.x,8); eq(b.miningArea.min.x,20)
  workers['12'].telemetry.miningArea.max.x=25
  eq(a.miningArea.max.x,8,'assignment bounds must not alias live telemetry')
end)

test('overlapping mining boxes including a shared boundary cannot run together',function()
  local queue,_,workers,a,b=fixture(); workers['13'].telemetry.miningArea=area(8,20)
  queue:assign(workers); queue:progress(12,{jobId=a.id,phase='work',delivered=0,held=0})
  eq(queue:assign(workers),nil); eq(b.workerId,nil)
  workers['13'].telemetry.miningArea=area(9,20)
  eq(queue:assign(workers).id,b.id); eq(b.workerId,13)
end)

test('offline owners keep their mine while disjoint workers can receive another job',function()
  local queue,_,workers,a,b=fixture(); queue:assign(workers); workers['12'].online=false
  eq(queue:assign(workers).id,b.id); eq(a.workerId,12); eq(b.workerId,13)
  workers['14']=worker(14,area(0,8))
  local c=queue:submit('minecraft:raw_gold',3,0)
  queue:progress(13,{jobId=b.id,phase='work',delivered=0,held=0})
  eq(queue:assign(workers),nil); eq(c.workerId,nil); eq(a.workerId,12)
end)

test('legacy miners without advertised bounds retain exclusive physical ownership',function()
  local queue,_,workers,a,b=fixture(); workers['12'].telemetry.miningArea=nil
  queue:assign(workers); queue:progress(12,{jobId=a.id,phase='work',delivered=0,held=0})
  eq(queue:assign(workers),nil); eq(b.workerId,nil)
  queue:progress(12,{jobId=a.id,phase='completed',delivered=8,held=0},8)
  workers['12'].online=false
  eq(queue:assign(workers).id,b.id); eq(b.workerId,13)
end)

test('assignment retransmissions are fair and do not allocate a second job to one owner',function()
  local queue,_,workers,a,b=fixture(); queue:assign(workers); queue:assign(workers)
  local first=queue:assign(workers); local second=queue:assign(workers)
  assert(first and second and first.id~=second.id,'pending acknowledgements starve one assignment')
  eq(a.workerId,12); eq(b.workerId,13)
  queue:progress(12,{jobId=a.id,phase='work',delivered=0,held=0})
  queue:progress(13,{jobId=b.id,phase='work',delivered=0,held=0})
  eq(queue:assign(workers),nil)
end)

test('restored mining job retains its persisted area despite changed or absent telemetry',function()
  local queue,_,workers,a,_,saved=fixture(); queue:assign(workers)
  local restored=saved(); local offline={['12']=worker(12,area(100,108)),['13']=worker(13,area(0,8))}
  offline['12'].online=false
  local fresh=Jobs.new(restored,function() return true end,function() return 101 end,7)
  eq(fresh:assign(offline),nil)
  eq(restored.jobs[a.id].miningArea.min.x,0); eq(restored.jobs[a.id].workerId,12)
end)

test('backup ownership recovery supports disjoint owners and rejects worker or area conflicts',function()
  local queue,_,workers,a,b=fixture()
  workers['12'].telemetry.task=a.id; workers['12'].telemetry.status='work'
  assert(queue:recoverOwner(12,{jobId=a.id,assignedQuantity=8},workers))
  workers['13'].telemetry.task=b.id; workers['13'].telemetry.status='work'
  assert(queue:recoverOwner(13,{jobId=b.id,assignedQuantity=8},workers))
  eq(a.workerId,12); eq(b.workerId,13); eq(b.miningArea.min.x,20)
  local c=queue:submit('minecraft:raw_gold',4,0)
  workers['12'].telemetry.task=c.id
  assert(not queue:recoverOwner(12,{jobId=c.id,assignedQuantity=4},workers)); eq(c.workerId,nil)
  workers['14']=worker(14,area(0,5)); workers['14'].telemetry.task=c.id
  assert(not queue:recoverOwner(14,{jobId=c.id,assignedQuantity=4},workers)); eq(c.workerId,nil)
end)

test('parallel assignment keeps dependency priority stock and duplicate progress rules',function()
  local queue,_,workers,a,b=fixture(); a.dependencies={'not-completed'}
  eq(queue:assign(workers).id,b.id); eq(b.workerId,12)
  queue:progress(12,{jobId=b.id,phase='completed',delivered=8,held=0},8)
  assert(queue:progress(12,{jobId=b.id,phase='completed',delivered=8,held=0},8))
  eq(b.progress.delivered,8)
  a.dependencies={}; eq(queue:assign(workers,{['minecraft:raw_iron']=3}).id,a.id); eq(a.quantity,5)
end)

test('historic single-worker pins do not prevent explicitly bounded parallel assignments',function()
  local queue,state,workers,a,b=fixture(); state.miningWorkerId=99
  eq(queue:assign(workers).id,a.id); eq(a.workerId,12)
  eq(queue:assign(workers).id,b.id); eq(b.workerId,13)
end)

test('invalid mining bounds are rejected instead of claiming an unchecked area',function()
  local queue,_,workers,a=fixture(); workers['12'].telemetry.miningArea=area(10,0)
  eq(queue:assign(workers).id,a.id); eq(a.workerId,13)
  local recovered=queue:submit('minecraft:raw_gold',2,0)
  workers['12'].telemetry.task=recovered.id
  assert(not queue:recoverOwner(12,{jobId=recovered.id,assignedQuantity=2},workers))
end)
