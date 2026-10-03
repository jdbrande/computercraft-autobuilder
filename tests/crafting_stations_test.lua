local C=require('autobuilder.config')
local U=require('autobuilder.core.util')
local station={id='west',workerId=12,buffer='buffer',input='input',output='output'}
test('private crafting configuration validates disjoint identities and advertises worker support',function()
  local c=C.load({craftingStations={station},craftingBatchSize=2})
  eq(c.craftingStations[1].buffer,'buffer')
  local w=C.load({role='worker',controllerId=7,automation={crafting=true},craftingStation={buffer='buffer',input='input',output='output'}})
  eq(w.capabilities.isolatedCraftingV1,true)
  eq(C.load().capabilities.isolatedCraftingV1,nil)
  for _,overrides in ipairs({{craftingStations={station,U.copy(station)}}, {craftingStations={[2]=station}},
    {craftingStations={station},storageInventories={'buffer'}}, {craftingStations={station},supply={inventory='input'}},
    {craftingBatchSize=0}, {craftingStation={buffer='input',input='input',output='output'}}}) do
    assert(not pcall(C.load,overrides),'invalid private station accepted')
  end
end)

test('private crafting task protocol refuses incomplete or inconsistent station assignments',function()
  local P=require('autobuilder.core.task_messages')
  local job={id='task:7:1',type='CRAFT',item='minecraft:stone_bricks',quantity=4,batches=1,
    workerId=12,preferredWorker=12,privateStation=U.copy(station)}
  assert(P.validate('task_assign',{job=job}))
  for _,change in ipairs({{buffer=''}, {output='input'}, {workerId=13}}) do
    local j=U.copy(job); for k,v in pairs(change) do j.privateStation[k]=v end
    assert(not P.validate('task_assign',{job=j}),'inconsistent private task accepted')
  end
  job.type='BUILD'; assert(not P.validate('task_assign',{job=job}))
end)

test('private worker completion stays owned and collecting until physical central receipt',function()
  local state={}; local q=require('autobuilder.core.workflows').new(state,function() return true end,function() return 0 end,7)
  local j=q:submit('CRAFT',{privateStation=U.copy(station),quantity=4},{})
  j.workerId=12; j.status='running'
  assert(q:progress(12,{jobId=j.id,phase='completed',progress=4}))
  eq(j.status,'collecting'); eq(j.workerFinished,true)
  assert(require('autobuilder.core.workflows').workerBusy(state,12))
  assert(q:progress(12,{jobId=j.id,phase='work',progress=4})); eq(j.status,'collecting')
  assert(q:progress(12,{jobId=j.id,phase='completed',progress=4})); eq(j.status,'collecting')
end)
