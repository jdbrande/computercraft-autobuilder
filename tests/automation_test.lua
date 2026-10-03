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

test('compact reports retain correct material quantities without counting air or upper door halves',function()
  local R=require('autobuilder.core.reports')
  local report={counts={correct=5,wrong=1},entries={
    {status='correct',expected={name='minecraft:stone',state={}}},
    {status='correct',expected={name='minecraft:wall_torch',state={}}},
    {status='correct',expected={name='minecraft:oak_door',state={half='lower'}}},
    {status='correct',expected={name='minecraft:oak_door',state={half='upper'}}},
    {status='correct',expected={name='minecraft:air',state={}}},
    {status='wrong',expected={name='minecraft:glass',state={}}}}}
  local compact=R.compact(report);assert(compact.materials,'correct material totals lost in compaction')
  eq(compact.materials['minecraft:stone'],1);eq(compact.materials['minecraft:torch'],1)
  eq(compact.materials['minecraft:oak_door'],1);eq(compact.materials['minecraft:air'],nil);eq(compact.materials['minecraft:glass'],nil)
  eq(R.compact(compact).materials['minecraft:stone'],1)
  eq(R.compact(report,'PREPARE_REGION').materials,nil)
  eq(R.compact({counts={correct=1},entries={}}).materials,nil)
end)

test('task messages reject malformed material totals but retain legacy reports',function()
  local M=require('autobuilder.core.task_messages');local p={jobId='task:7:1',phase='work',progress=1,report={counts={correct=1},materials={['minecraft:stone']=1}}}
  assert(M.validate('task_progress',p))
  for _,bad in ipairs({false,1,{['minecraft:stone']=-1},{['minecraft:stone']=1.5},{['minecraft:stone']=513}}) do
    p.report.materials=bad;assert(not M.validate('task_progress',p),'malformed material counts accepted')
  end
  p.report.materials=nil;assert(M.validate('task_progress',p))
end)

test('owned material progress is bounded by its blocks and survives reconstruction',function()
  local Q=require('autobuilder.core.workflows');local state={};local q=Q.new(state,function() return true end,function() return 1 end,7)
  local j=q:submit('BUILD',{blocks={{x=0,y=0,z=0,name='minecraft:stone',state={}}, {x=1,y=0,z=0,name='minecraft:glass',state={}}}},{});j.workerId=12;j.status='running'
  local p={jobId=j.id,phase='work',progress=1,report={counts={correct=1},materials={['minecraft:stone']=2}}}
  assert(not q:progress(12,p),'overclaimed material accepted');eq(j.progress,0)
  p.report.materials={['minecraft:stone']=1};assert(q:progress(12,p));eq(j.materials['minecraft:stone'],1)
  q=Q.new(state,function() return true end,function() return 2 end,7)
  p.report.materials={['minecraft:glass']=1};assert(not q:progress(12,p),'changed cumulative material accepted')
  p.phase='completed';p.progress=2;p.report.counts.correct=2;p.report.materials={['minecraft:stone']=1,['minecraft:glass']=1}
  assert(q:progress(12,p));j.blocks=nil;j.report=nil;eq(j.materials['minecraft:stone'],1);eq(j.materials['minecraft:glass'],1)
end)
