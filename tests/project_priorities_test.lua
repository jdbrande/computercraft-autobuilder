local U=require('autobuilder.core.util')
test('project priority follows durable lineage and defaults old independent work to fifty',function()
 local P=require('autobuilder.core.scheduling')
 local state={automation={projects={castle={name='castle',priority=80},station={name='station',priority=20},old={name='old'}},requests={
  ['request:1']={id='request:1',project='castle'},['request:2']={id='request:2',key='project:station'}},jobs={}},jobs={},exploration={groups={}}}
 eq(P.priority(state,{}),50);eq(P.priority(state,{project='old'}),50)
 eq(P.priority(state,{project='castle'}),80);eq(P.priority(state,{productionRequest='request:1'}),80)
 eq(P.priority(state,{consumer='request:1'}),80);eq(P.priority(state,{key='request:1:minecraft:stone'}),80)
 eq(P.priority(state,{productionRequest='request:2'}),20)
 state.exploration.groups['acquire:7:1']={key='request:1:minecraft:stone'}
 eq(P.priority(state,{exploration={groupId='acquire:7:1'}}),80)
 assert(P.before(state,{project='castle',created=20,id='later'},{project='station',created=1,id='earlier'}))
 assert(P.before(state,{created=1,id='a'},{created=1,id='b'}))
end)
test('priority changes validate range persist across restart and roll back failed checkpoints',function()
 local P=require('autobuilder.core.scheduling');local s={automation={projects={castle={name='castle'}},jobs={owned={id='owned',workerId=12,status='running',project='castle'}}}}
 local saved;P.set(s,'castle',80,function() saved=U.copy(s);return true end);eq(P.priority(saved,saved.automation.jobs.owned),80)
 for _,n in ipairs({-1,101,1.5,'90'}) do assert(not pcall(P.set,s,'castle',n,function() return true end)) end
 assert(not pcall(P.set,s,'missing',50,function() return true end))
 assert(not pcall(P.set,s,'castle',20,function() return false,'disk full' end));eq(s.automation.projects.castle.priority,80)
 eq(s.automation.jobs.owned.workerId,12);eq(s.automation.jobs.owned.status,'running')
end)
test('generic dispatch prefers higher priority project without changing already assigned owners',function()
 local Q=require('autobuilder.core.workflows');local c=require('tests.loaded_config').load({minimumFuelReserve=0})
 local s={workers={},jobs={}};local q=Q.new(s,function() return true end,function() return 1 end,7,nil,c)
 s.automation.projects.low={name='low',priority=20};s.automation.projects.high={name='high',priority=80}
 local low=q:submit('BUILD',{project='low',blocks={{x=1,y=0,z=0,name='minecraft:stone',state={}}}},{})
 local high=q:submit('BUILD',{project='high',blocks={{x=8,y=0,z=0,name='minecraft:stone',state={}}}},{})
 s.workers['12']={id=12,online=true,telemetry={status='idle',fuel=1000,position={x=0,y=2,z=0,known=true},depot={x=0,y=2,z=0},capabilities={building=true}}}
 eq(q:assign(s.workers).id,high.id);eq(high.workerId,12);eq(low.workerId,nil)
 require('autobuilder.core.scheduling').set(s,'low',100,function() return true end)
 eq(q:assign(s.workers).id,high.id);eq(high.workerId,12);eq(low.workerId,nil)
end)
test('scarce unclaimed stock goes to higher priority while paused new claims wait and held grants stay',function()
 local f=require('tests.managed_logistics_support').new();local s=f.queue.state
 s.projects.low={name='low',priority=20};s.projects.high={name='high',priority=80}
 local function job(project)
  return f.queue:submit('SMELT',{project=project,item='minecraft:stone_bricks',quantity=20,batches=20,
   stockInputs={['minecraft:stone']=20},stockOutputs={['minecraft:stone_bricks']=20}},{})
 end
 local low,high=job('low'),job('high');f.production:syncClaims()
 assert(f.production.ledger.state.leases[high.id]);eq(f.production.ledger.state.leases[low.id],nil)
 require('autobuilder.core.scheduling').set(f.app.state,'low',100,function() return f.app:save() end);f.production:syncClaims()
 assert(f.production.ledger.state.leases[high.id]);eq(f.production.ledger.state.leases[low.id],nil)
 f=require('tests.managed_logistics_support').new();s=f.queue.state;s.projects.low={name='low',priority=20};s.projects.high={name='high',priority=80}
 low,high=job('low'),job('high');high.paused=true;f.production:syncClaims()
 assert(f.production.ledger.state.leases[low.id]);eq(f.production.ledger.state.leases[high.id],nil)
end)
test('blocked high priority production cannot starve independent stock-only project work',function()
 local f=require('tests.managed_logistics_support').new();local s=f.queue.state
 s.projects.low={name='low',priority=20};s.projects.high={name='high',priority=80}
 local high=f.production:request({['minecraft:diamond']=100},'project:high',{projectName='high',stockOnly=true})
 local low=f.production:request({['minecraft:stone']=1},'project:low',{projectName='low',stockOnly=true})
 eq(high.project,'high');eq(low.project,'low')
 for _=1,3 do f.production:tick() end
 eq(high.status,'blocked');eq(low.status,'completed')
end)
test('task dispatch prefers cheaper feasible travel over smaller worker ID',function()
 local Q=require('autobuilder.core.workflows');local c=require('tests.loaded_config').load({minimumFuelReserve=0})
 local s={workers={},jobs={}};local q=Q.new(s,function() return true end,function() return 1 end,7,nil,c)
 for id,x in pairs({[12]=100,[13]=9}) do s.workers[tostring(id)]={id=id,online=true,telemetry={status='idle',fuel=1000,
  position={x=x,y=2,z=0,known=true},depot={x=x,y=2,z=0},capabilities={building=true}}} end
 local j=q:submit('BUILD',{blocks={{x=10,y=0,z=0,name='minecraft:stone',state={}}}},{})
 eq(q:assign(s.workers).workerId,13)
end)
test('higher project priority beats a different role bottleneck but preserves committed work',function()
 local f=require('tests.managed_logistics_support').new();local s=f.app.state;local a=s.automation
 a.projects.high={name='high',priority=80};a.projects.low={name='low',priority=20}
 local low=f.queue:submit('TRANSPORT',{project='low',quantity=100,source={x=0,y=0,z=0},destination={x=20,y=0,z=0}},{})
 local high=f.queue:submit('BUILD',{project='high',blocks={{x=1,y=0,z=0,name='minecraft:stone',state={}}}},{})
 local w=s.workers['12'];w.telemetry.capabilities.building=true;w.telemetry.depot={x=2,y=1,z=2}
 assert(require('autobuilder.core.scaling').canAssign(s,f.config,high,w,{},100))
 low.workerId=12;low.status='running';eq(require('autobuilder.core.scaling').canAssign(s,f.config,high,w,{},100),false)
end)
test('material forecast allocates shared unreserved stock by the same project priority',function()
 local high={name='z_high',priority=80,requirements={['minecraft:stone']=4}};local low={name='a_low',priority=20,requirements={['minecraft:stone']=4}}
 local s={automation={projects={z_high=high,a_low=low}}}
 local result=require('autobuilder.resources.material_forecast').build(s,{['minecraft:stone']=4},{{project=low,work={}},{project=high,work={}}})
 eq(result.z_high.items['minecraft:stone'].stored,4);eq(result.a_low.items['minecraft:stone'].stored,0)
 eq(result.z_high.priority,80)
end)
