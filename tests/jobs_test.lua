local U=require('autobuilder.core.util')
test('jobs subtract storage, persist ownership and never reassign offline work',function()
  local stock=30; local saved=0; local state={}
  local j=require('autobuilder.core.jobs').new(state,function() saved=saved+1; return true end,function() return 100 end,7)
  local job=assert(j:submit('minecraft:raw_iron',100,stock)); eq(job.quantity,70)
  local workers={['12']={id=12,online=true,telemetry={capabilities={mining=true},task=nil,status='idle'}},['13']={id=13,online=true,telemetry={capabilities={mining=true},task=nil,status='idle'}}}
  assert(j:assign(workers)); eq(job.workerId,12)
  workers['12'].online=false; j:assign(workers); eq(job.workerId,12)
  assert(not j:progress(13,{jobId=job.id,phase='completed',delivered=70,held=0},100))
  assert(j:progress(12,{jobId=job.id,phase='completed',delivered=70,held=0},100)); eq(job.status,'completed')
  assert(saved>=3)
end)
test('job completion waits for live storage confirmation and keeps assigned owner',function()
  local j=require('autobuilder.core.jobs').new({},function() return true end,function() return 1 end,7)
  local job=j:submit('minecraft:raw_iron',100,0); job.workerId=12; job.status='running'
  assert(j:progress(12,{jobId=job.id,phase='completed',delivered=100,held=0},90))
  eq(job.status,'blocked'); eq(job.workerId,12); assert(job.error:find('storage'))
end)
test('jobs complete immediately when existing storage satisfies request and enforce dependencies',function()
  local j=require('autobuilder.core.jobs').new({},function() return true end,function() return 1 end,7)
  local a=j:submit('minecraft:raw_iron',10,20); eq(a.status,'completed'); eq(a.quantity,0)
  local b=j:submit('minecraft:coal',10,0); b.dependencies={'missing'}
  eq(j:assign({['12']={id=12,online=true,telemetry={capabilities={mining=true},status='idle'}}}),nil)
end)
test('network job messages validate and strip arbitrary fields',function()
  local N=require('autobuilder.core.network')
  local p={jobId='mine:7:1:1',item='minecraft:raw_iron',quantity=100}
  local m={version=1,id='7:1:1',sender=7,boot=1,sequence=1,type='mine_assign',payload=p}
  assert(N.validate(7,m)); p.quantity=-1; assert(not N.validate(7,m))
  p.quantity=100; p.item='minecraft:bedrock'; assert(not N.validate(7,m))
end)

test('queued job uses storage available at assignment, not an old snapshot',function()
  local j=require('autobuilder.core.jobs').new({},function() return true end,function() return 1 end,7)
  local job=j:submit('minecraft:raw_iron',100,0)
  local workers={['12']={id=12,online=true,telemetry={capabilities={mining=true},status='idle'}}}
  j:assign(workers,{['minecraft:raw_iron']=60}); eq(job.quantity,40)
end)

test('completed physical tranche schedules a durable supplemental storage shortfall',function()
  local state={}; local j=require('autobuilder.core.jobs').new(state,function() return true end,function() return 1 end,7)
  local root=j:submit('minecraft:raw_iron',100,50); root.workerId=12; root.status='running'
  assert(j:progress(12,{jobId=root.id,phase='completed',delivered=50,held=0},90))
  assert(root.physicalComplete); local child=state.jobs[root.childId]; assert(child)
  eq(child.quantity,10); eq(child.target,100)
  local workers={['12']={id=12,online=true,telemetry={capabilities={mining=true},status='idle'}}}
  eq(j:assign(workers,{['minecraft:raw_iron']=90}).id,child.id)
  assert(j:progress(12,{jobId=child.id,phase='completed',delivered=10,held=0},100))
  eq(root.status,'completed'); eq(root.progress.delivered,60)
  assert(j:progress(12,{jobId=child.id,phase='completed',delivered=10,held=0},100)); eq(root.progress.delivered,60)
end)

test('production-owned mining accepts its durable acquired-stock proof after supply consumption',function()
  for _,mode in ipairs({'acquired','unconfirmed','unrelated','smaller','manual'}) do
    local state={automation={requests={r={id='r',acquired=mode~='unconfirmed',targets={['minecraft:cobblestone']=mode=='smaller' and 0 or 1},mines={}}}}}
    local q=require('autobuilder.core.jobs').new(state,function() return true end,function() return 1 end,7)
    local j=q:submit('minecraft:cobblestone',1,0,mode~='manual' and 'r' or nil);j.workerId=12;j.status='running'
    state.automation.requests.r.mines['minecraft:cobblestone']=mode=='unrelated' and 'different' or j.id
    q=require('autobuilder.core.jobs').new(state,function() return true end,function() return 2 end,7)
    assert(q:progress(12,{jobId=j.id,phase='completed',delivered=1,held=0},0))
    if mode=='acquired' then eq(j.status,'completed');eq(j.childId,nil)
    else eq(j.status,'blocked');assert(j.childId,'unproved or manual stock shortfall disappeared') end
  end
end)
