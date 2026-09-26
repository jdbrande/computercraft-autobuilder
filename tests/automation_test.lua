local S=require('tests.support')
test('generic task queue preserves ownership and dependencies across reconstruction',function()
  local Q=require('autobuilder.core.workflows'); local state={}; local writes=0
  local q=Q.new(state,function() writes=writes+1; return true end,function() return 10 end,7)
  local a=q:submit('CRAFT',{item='minecraft:oak_planks',quantity=4,batches=1},{},'planks')
  local b=q:submit('BUILD',{blocks={{x=2,y=0,z=0,name='minecraft:oak_planks',state={}}}},{a.id},'build')
  eq(q:submit('CRAFT',{}, {},'planks').id,a.id)
  local workers={['12']={id=12,online=true,telemetry={status='idle',capabilities={crafting=true,building=true}}}}
  eq(q:assign(workers).id,a.id)
  q=Q.new(state,function() return true end,function() return 20 end,7)
  workers['12'].online=false; eq(q:assign(workers),nil); eq(state.automation.jobs[a.id].workerId,12)
  assert(not q:progress(13,{jobId=a.id,phase='completed',progress=4}))
  assert(q:progress(12,{jobId=a.id,phase='completed',progress=4}))
  workers['12'].online=true; eq(q:assign(workers).id,b.id); assert(writes>0)
end)
test('task messages reject cycles oversized jobs and unknown operation types',function()
  local M=require('autobuilder.core.task_messages')
  local p={job={id='build:1',type='BUILD',blocks={{x=0,y=0,z=0,name='minecraft:stone',state={}}}}}
  assert(M.validate('task_assign',p)); p.job.type='EXEC'; assert(not M.validate('task_assign',p))
  p.job.type='BUILD'; p.job.blocks[1].state.loop=p; assert(not M.validate('task_assign',p))
end)
test('coordinate reservations survive offline workers and refuse another owner',function()
  local Q=require('autobuilder.core.workflows'); local s={}; local q=Q.new(s,function() return true end,function() return 1 end,7)
  local a=q:submit('BUILD',{blocks={{x=2,y=0,z=0,name='minecraft:stone',state={}}}}, {},'a')
  a.workerId=12; a.status='running'
  local b=q:submit('BUILD',{blocks={{x=20,y=0,z=0,name='minecraft:stone',state={}}}}, {},'b'); b.workerId=13; b.status='running'
  assert(q:reserve(12,a.id,{x=1,y=1,z=1},{x=1,y=1,z=2},{}))
  assert(not q:reserve(13,b.id,{x=1,y=1,z=3},{x=1,y=1,z=2},{}))
  q=Q.new(s,function() return true end,function() return 10000 end,7)
  assert(not q:reserve(13,b.id,{x=1,y=1,z=3},{x=1,y=1,z=2},{}))
end)
test('maximum region verification report transmits exact counts and bounded issue details',function()
  local report={counts={correct=384,wrong=128},entries={}}
  for i=1,512 do report.entries[i]={x=i,y=0,z=0,index=i,status=i<=384 and 'correct' or 'wrong',
    expected={name='minecraft:oak_stairs',state={facing='north',shape='straight',half='bottom',waterlogged='false'}},
    actual={name='minecraft:oak_stairs',state={facing='south',shape='straight',half='bottom',waterlogged='false'}}} end
  local compact=require('autobuilder.core.reports').compact(report)
  eq(compact.counts.correct,384); eq(compact.counts.wrong,128); eq(#compact.entries,16); eq(compact.omittedEntries,112)
  assert(require('autobuilder.core.task_messages').validate('task_progress',{jobId='task:7:1',phase='completed',progress=384,report=compact}))
end)
