local U=require('autobuilder.core.util')
local C=require('tests.loaded_config')
local c=C.load({depot={x=0,y=0,z=0},minimumFuelReserve=20})
local function telemetry(fuel) return {fuel=fuel or 1000,position={known=true,x=0,y=0,z=0},depot=U.copy(c.depot)} end
local function budget(j,t,config) return assert(require('autobuilder.resources.fuel_budget').mission(config or c,j,t or telemetry())) end

test('construction fuel exposes the existing overhead excursion and progressed targets',function()
  local j={id='build',type='BUILD',blocks={{x=10,y=0,z=0,name='minecraft:stone'},{x=2,y=0,z=0,name='minecraft:stone'}}}
  local b=budget(j,telemetry(55));eq(b.outward,13);eq(b.returning,13);eq(b.work,8);eq(b.reserve,20);eq(b.required,54);eq(b.allowed,true);eq(b.scope,'excursion')
  eq(budget(j,telemetry(53)).shortfall,1)
  j.index=2;eq(budget(j).required,38)
  j.index=3;eq(budget(j).required,0)
  local _,why=require('autobuilder.resources.fuel_budget').mission(C.load({maxTravelDistance=8}),j,telemetry());assert(not why)
  j.index=1;local b,why=require('autobuilder.resources.fuel_budget').mission(C.load({maxTravelDistance=8}),j,telemetry());eq(b,nil);assert(why:find('maxTravelDistance'))
end)

test('survey and preparation budgets retain access overhead and actual worker depot',function()
  local t=telemetry();t.depot={x=5,y=0,z=0}
  local j={id='survey',type='SURVEY_SITE',clearanceY=4,siteSurvey={columns={{x=10,z=0,minY=-2}}}}
  local b=budget(j,t);eq(b.outward,19);eq(b.returning,14);eq(b.work,8);eq(b.required,61)
  j={id='prep',type='PREPARE_REGION',clearanceY=4,blocks={{x=10,y=0,z=0,name='minecraft:air'}},siteAccess={cells={{x=10,y=0,z=1}},entry={x=10,y=1,z=1},target={x=10,y=0,z=0},stand={x=10,y=0,z=1}}}
  local b=budget(j,t);assert(b.work>=12);eq(b.reserve,20)
end)

test('hauling rescue station and home budgets cover finite delivery and return legs',function()
  local source={x=10,y=0,z=0};local dest={x=20,y=0,z=0}
  local j={id='haul',type='TRANSPORT',source=source,destination=dest,quantity=64}
  local b=budget(j);eq(b.outward,18);eq(b.work,18);eq(b.returning,28);eq(b.required,84)
  j.cargo={stage='destination'};local t=telemetry();t.position=source;t.position.known=true
  b=budget(j,t);eq(b.outward,0);eq(b.work,18);eq(b.returning,28)
  j.type='RESCUE';j.home=c.depot;j.cargo=nil;b=budget(j);eq(b.required,84)
  b=budget({id='home',type='RETURN_HOME',home=c.depot},t);eq(b.outward,0);eq(b.returning,18);eq(b.required,38)
  b=budget({id='fuel',type='REFUEL',station={position=c.depot}},telemetry(0));eq(b.required,0);eq(b.allowed,true)
end)

test('mining budgets retain bounded route work and recorded return trail',function()
  local j={id='mine',type='MINE',exploration={entry={x=3,y=0,z=0},exitRoute={{x=1,y=0,z=0}},route={{x=2,y=0,z=0},{x=3,y=0,z=0}}}}
  local b=budget(j);eq(b.outward,3);eq(b.work,2);eq(b.returning,3);eq(b.reserve,28);eq(b.required,36)
  j.trail={{x=1,y=0,z=0},{x=2,y=0,z=0},{x=3,y=0,z=0},{x=3,y=0,z=1}};j.phase='survey'
  local t=telemetry();t.position={known=true,x=3,y=0,z=1};b=budget(j,t);eq(b.outward,0);eq(b.returning,4)
  j.phase='return';b=budget(j,t);eq(b.work,0);eq(b.required,32)
end)

test('renewable budgets include configured canopy clearance and next work site',function()
  local j={id='farm',type='HARVEST',farm={kind='oak',maxHeight=8,sites={{x=10,y=0,z=0}}}}
  local b=budget(j);eq(b.outward,22);eq(b.returning,22);eq(b.work,4);eq(b.required,68)
  j.type='FARM';j.farm.kind='wheat';b=budget(j);eq(b.outward,29);eq(b.returning,29)
  j.stage='deposit';b=budget(j);eq(b.outward,0);eq(b.work,0);eq(b.returning,0)
end)

test('stationary craft needs no fuel and unknown movement geometry is unavailable',function()
  eq(budget({id='craft',type='CRAFT'},telemetry(0)).required,0)
  local B=require('autobuilder.resources.fuel_budget');local t=telemetry();t.position.known=false
  eq(B.mission(c,{id='haul',type='TRANSPORT'},t),nil)
  eq(B.mission(c,{id='haul',type='TRANSPORT'},telemetry()),nil)
  eq(budget({id='craft',type='CRAFT'},telemetry('unlimited')).allowed,true)
  local j={id='access',type='PREPARE_SITE',sitePlan={points={{x=1,y=0,z=0},{x=2,y=0,z=0}}}}
  local b=budget(j);eq(b.outward,0);eq(b.work,2);eq(b.returning,2);eq(b.reserve,20)
end)

test('fuel forecast matches distinct ready jobs and favors workers already fueled for the route',function()
  local B=require('autobuilder.resources.fuel_budget');local config=C.load({fuel={enabled=true},minimumFuelReserve=20})
  local state={workers={},jobs={},automation={jobs={}}}
  for i,fuel in ipairs({21,1000}) do state.workers[tostring(i)]={id=i,online=true,telemetry=telemetry(fuel)};local t=state.workers[tostring(i)].telemetry;t.status='idle';t.capabilities={building=true} end
  local j={id='one',created=1,type='BUILD',status='queued',requiredCapability='building',blocks={{x=10,y=0,z=0,name='minecraft:stone'}}};state.automation.jobs.one=j
  local f=B.forecast(state,config);eq(f.workers['1'],nil);eq(f.workers['2'].taskId,'one');eq(f.required,54);eq(f.shortfall,0)
  state.automation.jobs.two=U.copy(j);state.automation.jobs.two.id='two';state.automation.jobs.two.created=2
  f=B.forecast(state,config);eq(f.workers['1'].taskId,'two');eq(f.shortfall,33);eq(f.items['minecraft:coal'],1)
  state.automation.jobs.two.paused=true;eq(B.forecast(state,config).workers['1'],nil)
  state.automation.jobs.one.dependencies={'two'};eq(B.forecast(state,config).required,0)
end)

test('fuel admission refuses new unsafe work but retains owners and mandatory recovery',function()
  local B=require('autobuilder.resources.fuel_budget');local config=C.load({fuel={enabled=true},minimumFuelReserve=20})
  local j={id='one',type='BUILD',blocks={{x=10,y=0,z=0,name='minecraft:stone'}}}
  local w={id=1,online=true,telemetry=telemetry(30)}
  local ok,why=B.admit(config,j,w);eq(ok,false);assert(why:find('54'));assert(why:find('30'))
  w.telemetry.fuel=54;eq(B.admit(config,j,w),true)
  w.telemetry.fuel=0;j.workerId=1;eq(B.admit(config,j,w),true)
  j.workerId=nil;j.type='RETURN_HOME';eq(B.admit(config,j,w),true)
  j.type='CRAFT';eq(B.admit(config,j,w),true)
  config.fuel.enabled=false;j.type='BUILD';eq(B.admit(config,j,w),true)
end)

test('workflow fuel admission tries another worker and rechecks after a yielding coverage observation',function()
  local config=C.load({fuel={enabled=true},minimumFuelReserve=20})
  local state={workers={},jobs={}};local saved
  for i,fuel in ipairs({30,100}) do state.workers[tostring(i)]={id=i,online=true,telemetry=telemetry(fuel)};local t=state.workers[tostring(i)].telemetry;t.status='idle';t.capabilities={building=true} end
  local Q=require('autobuilder.core.workflows').new(state,function() saved=U.copy(state);return true end,function() return 1 end,7,nil,config)
  local j=Q:submit('BUILD',{blocks={{x=10,y=0,z=0,name='minecraft:stone'}}})
  eq(Q:assign(state.workers),j);eq(j.workerId,2);eq(saved.automation.jobs[j.id].workerId,2)
  local state2={workers={['1']=U.copy(state.workers['2'])},jobs={}};state2.workers['1'].id=1
  local chunks={reserve=function() state2.workers['1'].telemetry.fuel=30;return {status='disabled'} end}
  local q=require('autobuilder.core.workflows').new(state2,function() return true end,function() return 1 end,7,chunks,config)
  local blocked=q:submit('BUILD',{blocks={{x=10,y=0,z=0,name='minecraft:stone'}}})
  eq(q:assign(state2.workers),nil);eq(blocked.workerId,nil);assert(blocked.coverageError:find('fuel'))
end)

test('offline mission owners retain work but do not contribute stale physical fuel to forecast',function()
  local B=require('autobuilder.resources.fuel_budget');local t=telemetry(1000);t.status='work';t.task='one'
  local j={id='one',type='BUILD',workerId=1,status='assigned',blocks={{x=10,y=0,z=0,name='minecraft:stone'}}}
  local state={workers={['1']={id=1,online=false,telemetry=t}},automation={jobs={one=j}}}
  local f=B.forecast(state,c);eq(f.current,0);eq(f.required,0);eq(f.unknown,1);eq(f.workers['1'].taskId,'one');eq(j.workerId,1)
end)

test('mining telemetry keeps the remaining outbound leg while a route is in progress',function()
  local j={id='mine',type='MINE',phase='travel',trail={{x=0,y=0,z=0},{x=1,y=0,z=0}},exploration={entry={x=3,y=0,z=0},exitRoute={{x=1,y=0,z=0}},route={{x=2,y=0,z=0},{x=3,y=0,z=0}}}}
  local t=telemetry();t.position={known=true,x=1,y=0,z=0}
  local b=budget(j,t);eq(b.outward,2);assert(b.returning>=3)
end)
