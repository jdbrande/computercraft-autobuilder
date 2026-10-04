local U=require('autobuilder.core.util')
local function fixture()
  local c=require('tests.loaded_config').load({depot={x=0,y=2,z=0},storageInventories={'stock'},
    logistics={nodes={{id='base',inventory='stock',position={x=10,y=0,z=0},buffers={{inventory='buffer',position={x=12,y=1,z=0}}}}}},
    fuel={stations={{id='fuel',inventory='fuel',workerId=12,position={x=20,y=1,z=0}}}},
    farms={{kind='wheat',sites={{x=30,y=1,z=0}},maxHeight=8}},treeFarms={{kind='oak',sites={{x=40,y=1,z=0}},maxHeight=12}}})
  local s={workers={['12']={id=12,online=false,telemetry={depot={x=50,y=1,z=0},position={x=51,y=1,z=0,known=true}}}},
    jobs={},automation={jobs={},projects={own={name='own',protectedBounds={min={x=60,y=0,z=0},max={x=65,y=4,z=4}}},
      other={name='other',protectedBounds={min={x=70,y=0,z=0},max={x=75,y=4,z=4}}}},cells={}}}
  local j={id='prep',project='own',workerId=13,status='running',bounds={min={x=-5,y=-5,z=-5},max={x=100,y=30,z=10}}}
  s.automation.jobs[j.id]=j
  return c,s,j
end

test('site protection covers registered home logistics fuel farms and other project volumes',function()
  local c,s,j=fixture();local P=require('autobuilder.core.protection')
  for _,p in ipairs({{x=0,y=1,z=0},{x=1,y=2,z=0},{x=10,y=0,z=0},{x=12,y=0,z=0},{x=20,y=2,z=0},
    {x=30,y=0,z=0},{x=40,y=12,z=0},{x=50,y=1,z=0},{x=70,y=1,z=0}}) do
    local ok,why=P.canModify(s,c,j,p);assert(not ok and why,'missed protected '..p.x..','..p.y..','..p.z)
  end
  assert(P.canModify(s,c,j,{x=60,y=1,z=1}),'own project volume must remain executable')
  assert(not P.canModify(s,c,j,{x=101,y=1,z=1}),'escaped owned bounds')
end)

test('mutation protection retains offline positions active work and pending routes until settlement',function()
  local c,s,j=fixture();local P=require('autobuilder.core.protection')
  assert(not P.canModify(s,c,j,{x=51,y=1,z=0}))
  s.automation.cells['80,1,0']={owner=99,jobId='other'};assert(not P.canModify(s,c,j,{x=80,y=1,z=0}))
  s.jobs.mine={id='mine',workerId=99,status='running',exploration={bounds={min={x=85,y=0,z=0},max={x=86,y=2,z=1}},route={{x=84,y=1,z=0}},exitRoute={{x=83,y=1,z=0}}}}
  for _,x in ipairs({83,84,85}) do assert(not P.canModify(s,c,j,{x=x,y=1,z=0})) end
  s.jobs.mine.physicalComplete=true;assert(P.canModify(s,c,j,{x=85,y=1,z=0}))
  s.automation.jobs.other={id='other',workerId=99,status='running',bounds={min={x=90,y=0,z=0},max={x=92,y=3,z=1}}}
  assert(not P.canModify(s,c,j,{x=91,y=1,z=0}))
  s.automation.jobs.other.status='completed';assert(P.canModify(s,c,j,{x=91,y=1,z=0}))
end)

test('construction mutation grants share traffic cells and refuse protected or unplanned targets',function()
  local c,s,j=fixture();j.type='REPAIR';j.blocks={{x=60,y=1,z=1,name='minecraft:air',state={}},{x=50,y=1,z=0,name='minecraft:air',state={}}}
  local Q=require('autobuilder.core.workflows').new(s,function() return true end,function() return 100 end,7,nil,c)
  assert(not Q:reserve(13,j.id,{x=61,y=2,z=1},{x=61,y=1,z=1},s.workers,true),'unplanned target accepted')
  assert(not Q:reserve(13,j.id,{x=50,y=2,z=0},{x=50,y=1,z=0},s.workers,true),'depot mutation accepted')
  assert(Q:reserve(13,j.id,{x=60,y=2,z=1},{x=60,y=1,z=1},s.workers,true))
  eq(s.automation.cells['60,1,1'].owner,13)
end)

test('traffic cannot enter another active preparation region and failed grants restore ownership',function()
  local c,s,j=fixture();j.type='SURVEY_SITE';j.siteSurvey={identity=string.rep('a',64)}
  s.automation.jobs.courier={id='courier',type='TRANSPORT',workerId=14,status='running'}
  local Q=require('autobuilder.core.workflows').new(s,function() return true end,function() return 100 end,7,nil,c)
  assert(not Q:reserve(14,'courier',{x=60,y=1,z=0},{x=60,y=1,z=1},s.workers),'route entered owned survey region')
  j.status='completed';assert(Q:reserve(14,'courier',{x=60,y=1,z=0},{x=60,y=1,z=1},s.workers))
  local before=U.copy(s.automation.cells)
  Q=require('autobuilder.core.workflows').new(s,function() return false,'disk full' end,function() return 100 end,7,nil,c)
  assert(not pcall(Q.reserve,Q,14,'courier',{x=60,y=1,z=1},{x=60,y=1,z=2},s.workers))
  assert(require('autobuilder.factory.factory').equal(before,s.automation.cells),'failed movement claim mutated durable ownership')
end)

test('worker mutation reservations cannot consume movement grants or bypass disabled ownership',function()
  local C=require('tests.loaded_config');local w=require('tests.build_world').new()
  local c=C.load({role='worker',controllerId=7,automation={building=true},depot=U.copy(w.pose)})
  local app={navigation={pose=w.pose},state={id=12,position=w.pose,currentTask={id='task:7:1',type='REPAIR',phase='work'}}}
  function app:save() return true end
  local sent={};local net={send=function(_,_,kind,p) sent[#sent+1]={kind=kind,p=U.copy(p)};return true end}
  local ex=require('autobuilder.workers.executor').new(app,c,{turtle=w.turtle},net,function() return 100 end)
  local target={x=0,y=1,z=0};assert(not app.navigation.workGuard(target));assert(sent[#sent].p.work)
  local seq=0;local function grant(work)
    seq=seq+1;return ex:handle(7,{boot=1,sequence=seq,type='task_grant',payload={jobId='task:7:1',target=target,granted=true,work=work}})
  end
  assert(not grant(nil),'movement grant authorized mutation');assert(grant(true));assert(app.navigation.workGuard(target))
  assert(not app.navigation.guard(w.pose,target),'mutation grant authorized movement');assert(not grant(true));assert(grant(nil))
  c.automation.enabled=false;c.mining.enabled=true;assert(not app.navigation.workGuard(target))
  assert(not grant(nil),'enabled mining admitted generic task control')
  c.automation.enabled=true;app.state.currentTask=nil;assert(not app.navigation.workGuard(target))
end)

test('access lease admission is rechecked after yielding coverage and allows its recovery survey',function()
  local c,s=fixture();s.automation.jobs={};s.automation.sequence=0;s.workers={['13']={id=13,online=true,telemetry={status='idle',capabilities={building=true}}}}
  local bounds={min={x=60,y=0,z=0},max={x=65,y=4,z=4}}
  local site={identity=string.rep('a',64)};s.automation.projects.own.site=site
  local chunks={reserve=function() site.accessLease={bounds=U.copy(bounds),region=1};return {status='disabled'} end}
  local Q=require('autobuilder.core.workflows').new(s,function() return true end,function() return 100 end,7,chunks,c)
  local j=Q:submit('VERIFY',{project='own',blocks={{x=60,y=1,z=1,name='minecraft:stone',state={}}}})
  assert(not Q:assign(s.workers),'lease acquired during yielding coverage was ignored');assert(not j.workerId)
  local P=require('autobuilder.core.protection')
  local recovery={type='SURVEY_SITE',project='own',bounds=bounds,clearanceY=4,siteSurvey={identity=site.identity,region=1}}
  assert(P.canOwn(s,recovery,13));recovery.siteSurvey.region=2;assert(not P.canOwn(s,recovery,13))
  site.accessLease=nil;assert(P.canOwn(s,j,13))
end)

test('independent workers can use a clear overhead plane without entering preparation work cells',function()
  local c,s,j=fixture();j.type='SURVEY_SITE';j.siteSurvey={};j.clearanceY=4;j.bounds={min={x=60,y=0,z=0},max={x=65,y=4,z=4}}
  s.automation.jobs.courier={id='courier',type='TRANSPORT',workerId=14,status='running'}
  local Q=require('autobuilder.core.workflows').new(s,function() return true end,function() return 100 end,7,nil,c)
  assert(Q:reserve(14,'courier',{x=60,y=4,z=0},{x=60,y=4,z=1},s.workers),'clear survey overhead corridor was blocked')
  assert(not Q:reserve(14,'courier',{x=60,y=4,z=1},{x=60,y=3,z=1},s.workers))
end)

test('preparation admission waits for prior occupied cells and mining routes but admits independent regions',function()
  local c,s=fixture();s.automation.jobs={};s.automation.sequence=0;s.workers={
    ['13']={id=13,online=true,telemetry={status='idle',capabilities={siteSurveyV1=true},position={x=59,y=4,z=0,known=true}}},
    ['14']={id=14,online=false,telemetry={position={x=61,y=2,z=1,known=true}}}}
  local Q=require('autobuilder.core.workflows').new(s,function() return true end,function() return 100 end,7,nil,c)
  local payload={siteSurvey={},clearanceY=4,bounds={min={x=60,y=0,z=0},max={x=65,y=4,z=4}}}
  local j=Q:submit('SURVEY_SITE',payload)
  assert(not Q:assign(s.workers),'region captured an offline worker')
  s.workers['14'].telemetry.position.y=4
  s.automation.cells['62,2,1']={owner=14,jobId='older'}
  assert(not Q:assign(s.workers),'region captured pending movement')
  s.automation.cells={};s.jobs.mine={id='mine',workerId=14,status='running',exploration={bounds={min={x=80,y=0,z=0},max={x=82,y=2,z=2}},route={{x=63,y=1,z=1}},exitRoute={}}}
  assert(not Q:assign(s.workers),'region captured an owned return route')
  s.jobs.mine.physicalComplete=true
  eq(Q:assign(s.workers).id,j.id);eq(j.workerId,13)
end)

test('preparation admission is rechecked after yielding chunk coverage observation',function()
  local c,s=fixture();s.automation.jobs={};s.automation.sequence=0;s.workers={['13']={id=13,online=true,telemetry={status='idle',capabilities={siteSurveyV1=true}}}}
  local chunks={reserve=function(_,j,w)
    s.workers['14']={id=14,telemetry={position={x=61,y=2,z=1,known=true}}}
    return {status='disabled'}
  end}
  local Q=require('autobuilder.core.workflows').new(s,function() return true end,function() return 100 end,7,chunks,c)
  local j=Q:submit('SURVEY_SITE',{siteSurvey={},clearanceY=4,bounds={min={x=60,y=0,z=0},max={x=65,y=4,z=4}}})
  assert(not Q:assign(s.workers),'yielding coverage observation invalidated admission');assert(not j.workerId)
end)

test('structural assignment requires current preparation evidence before acquiring a worker',function()
  local c,s=fixture();s.automation.jobs={};s.automation.sequence=0
  s.workers={['13']={id=13,online=true,telemetry={status='idle',capabilities={building=true}}}}
  local Q=require('autobuilder.core.workflows').new(s,function() return true end,function() return 100 end,7,nil,c)
  local j=Q:submit('BUILD',{project='own',requiresSite=true,blocks={{x=60,y=1,z=1,name='minecraft:stone',state={}}}}, {})
  assert(not Q:assign(s.workers),'missing preparation verifier allowed construction')
  Q.preparationReady=function() return false,'foundation region pending' end
  assert(not Q:assign(s.workers));assert(not j.workerId)
  Q.preparationReady=function() return true end;eq(Q:assign(s.workers).id,j.id)
end)

test('door mutation grants reserve generated halves atomically and reject occupied or protected upper cells',function()
  local c,s,j=fixture();j.type='BUILD'
  local lower={x=60,y=1,z=1,name='minecraft:oak_door',state={half='lower',facing='north',hinge='left',open='false',powered='false'}}
  local upper=U.copy(lower);upper.y=2;upper.state.half='upper';j.blocks={lower,upper}
  local Q=require('autobuilder.core.workflows').new(s,function() return true end,function() return 100 end,7,nil,c)
  local from={x=60,y=1,z=2}
  s.workers['99']={id=99,online=false,telemetry={position={x=60,y=2,z=1,known=true}}}
  assert(not Q:reserve(13,j.id,from,lower,s.workers,true),'door generated into an offline worker')
  eq(next(s.automation.cells),nil);s.workers['99']=nil
  c.restrictedAreas={{min={x=60,y=2,z=1},max={x=60,y=2,z=1}}}
  assert(not Q:reserve(13,j.id,from,lower,s.workers,true),'door generated into protected upper cell')
  eq(next(s.automation.cells),nil);c.restrictedAreas={}
  assert(Q:reserve(13,j.id,from,lower,s.workers,true))
  eq(s.automation.cells['60,1,1'].jobId,j.id);eq(s.automation.cells['60,2,1'].jobId,j.id)
  eq(s.automation.cells['60,1,2'].owner,13)
end)

test('generated door cells cannot escape owned bounds and failed grants restore every prior cell',function()
  local c,s,j=fixture();j.type='BUILD';j.blocks={{x=60,y=1,z=1,name='minecraft:oak_door',state={half='lower',facing='north',hinge='left',open='false',powered='false'}}}
  j.bounds={min={x=60,y=1,z=1},max={x=60,y=1,z=1}}
  local fail=false
  local Q=require('autobuilder.core.workflows').new(s,function() return not fail,'disk full' end,function() return 100 end,7,nil,c)
  local from={x=60,y=1,z=2};local target=j.blocks[1]
  assert(not Q:reserve(13,j.id,from,target,s.workers,true),'generated upper half escaped owned territory')
  j.bounds.max.y=2;s.automation.cells['59,1,2']={owner=13,jobId=j.id};local before=U.copy(s.automation.cells);fail=true
  assert(not pcall(Q.reserve,Q,13,j.id,from,target,s.workers,true))
  assert(require('autobuilder.factory.factory').equal(before,s.automation.cells),'failed paired reservation changed traffic ownership')
end)

test('preparation gates require bounded project identity and valid structural task metadata',function()
  local M=require('autobuilder.core.task_messages')
  local job={id='task:7:1',type='BUILD',project='house',projectRun=0,requiresSite=true,blocks={{x=3,y=0,z=0,name='minecraft:stone',state={}}}}
  assert(M.validate('task_assign',{job=job}))
  for _,change in ipairs({{requiresSite='true'},{projectRun=-1},{projectRun=0.5},{project=string.rep('a',65)},{type='TRANSPORT'}}) do
    local bad=U.copy(job);for key,value in pairs(change) do bad[key]=value end
    assert(not M.validate('task_assign',{job=bad}),'invalid preparation gate accepted')
  end
  local bad=U.copy(job);bad.project=nil;assert(not M.validate('task_assign',{job=bad}))
end)

test('mining mutation grants enforce territory routes infrastructure and active preparation ownership',function()
  local c,s=fixture();s.automation.jobs={}
  local j={id='mine:7:1',type='MINE',workerId=13,status='running',miningArea={min={x=80,y=0,z=0},max={x=90,y=2,z=2}}};s.jobs[j.id]=j
  local Q=require('autobuilder.core.workflows').new(s,function() return true end,function() return 100 end,7,nil,c)
  assert(Q:reserve(13,j.id,{x=82,y=1,z=0},{x=83,y=1,z=0},s.workers,true),'owned mine cannot excavate')
  assert(not Q:reserve(13,j.id,{x=79,y=1,z=0},{x=78,y=1,z=0},s.workers,true),'mine escaped assigned territory')
  s.automation.jobs.prep={id='prep',type='PREPARE_REGION',siteWork={},workerId=14,status='running',bounds={min={x=85,y=0,z=0},max={x=87,y=2,z=2}}}
  assert(not Q:reserve(13,j.id,{x=84,y=1,z=0},{x=85,y=1,z=0},s.workers,true))
  j.exploration={bounds=U.copy(j.miningArea),route={{x=78,y=1,z=0},{x=79,y=1,z=0}},exitRoute={{x=77,y=1,z=0}},protectedAreas={}}
  assert(Q:reserve(13,j.id,{x=77,y=1,z=0},{x=78,y=1,z=0},s.workers,true),'owned exploration route denied')
  assert(not Q:reserve(13,j.id,{x=78,y=1,z=0},{x=77,y=1,z=0},s.workers,true),'traversal-only exit excavated')
  j.exploration.protectedAreas={{min={x=78,y=1,z=0},max={x=78,y=1,z=0}}}
  assert(not Q:reserve(13,j.id,{x=77,y=1,z=0},{x=78,y=1,z=0},s.workers,true),'immutable mission protection ignored')
  j.exploration=nil;j.miningArea={min={x=49,y=0,z=0},max={x=51,y=2,z=0}}
  assert(not Q:reserve(13,j.id,{x=49,y=1,z=0},{x=50,y=1,z=0},s.workers,true),'registered depot excavated')
end)

test('mining base exclusion allows authorized construction while retaining actual infrastructure protection',function()
  local c,s,j=fixture();c.exploration.baseProtection={min={x=-5,y=-5,z=-5},max={x=100,y=30,z=10}}
  local P=require('autobuilder.core.protection');j.type='BUILD'
  assert(P.canModify(s,c,j,{x=60,y=1,z=1}),'mining exclusion incorrectly forbids building the base')
  assert(not P.canModify(s,c,j,{x=0,y=1,z=0}),'construction exemption removed actual depot protection')
  j.type='MINE';j.miningArea=U.copy(j.bounds)
  assert(not P.canModify(s,c,j,{x=60,y=1,z=1}),'miner excavated the base exclusion')
end)

test('structural admission rechecks preparation proof at the final chunk ownership boundary',function()
  for _,enabled in ipairs({false,true}) do
    local c,s=fixture();s.automation.jobs={};s.automation.sequence=0
    c.chunkLoading.enabled=enabled;c.chunkLoading.areas={{minX=3,maxX=4,minZ=0,maxZ=0}}
    s.workers={['13']={id=13,online=true,telemetry={status='idle',capabilities={building=true,chunkCoverageV1=true},position={x=60,y=2,z=1,known=true},depot={x=60,y=2,z=1}}}}
    local chunks=require('autobuilder.core.chunks').new(s,c,function() return true end)
    local original=chunks.reserve;local ready=true
    function chunks:reserve(j,w,assign,prepared) ready=false;return original(self,j,w,assign,prepared) end
    local Q=require('autobuilder.core.workflows').new(s,function() return true end,function() return 100 end,7,chunks,c)
    Q.preparationReady=function() return ready,'region proof was lost during coverage check' end
    local j=Q:submit('BUILD',{project='own',projectRun=0,requiresSite=true,blocks={{x=60,y=1,z=1,name='minecraft:stone',state={}}}}, {})
    assert(not Q:assign(s.workers),'stale preparation proof acquired a structural owner')
    assert(not j.workerId);assert(not (s.chunkLedger and s.chunkLedger.leases[j.id]))
  end
end)

test('registered farm mutations reserve only their own renewable cells',function()
 local c,s,j=fixture();s.automation.jobs={};j.type='FARM';j.farm=U.copy(c.farms[1]);j.item='minecraft:wheat';s.automation.jobs[j.id]=j
 local Q=require('autobuilder.core.workflows').new(s,function() return true end,function() return 100 end,7,nil,c)
 local target={x=30,y=1,z=0};local from={x=30,y=2,z=0}
 assert(Q:reserve(13,j.id,from,target,s.workers,true),'own registered crop was denied')
 assert(not Q:reserve(13,j.id,target,{x=30,y=0,z=0},s.workers,true),'farm soil could be removed')
 assert(not Q:reserve(13,j.id,{x=40,y=2,z=0},{x=40,y=1,z=0},s.workers,true),'foreign farm was authorized')
 s.workers['99']={id=99,online=false,telemetry={position={x=30,y=1,z=0,known=true}}}
 assert(not Q:reserve(13,j.id,from,target,s.workers,true),'offline occupant was ignored')
 s.workers['99']=nil;c.restrictedAreas={{min=target,max=target}}
 assert(not Q:reserve(13,j.id,from,target,s.workers,true),'registered farm bypassed explicit protection')
end)

test('renewable grants preserve column bases and reject changed or concurrently owned farms',function()
 local c,s,j=fixture();s.automation.jobs={};j.type='HARVEST';j.farm=U.copy(c.treeFarms[1]);s.automation.jobs[j.id]=j
 local Q=require('autobuilder.core.workflows').new(s,function() return true end,function() return 100 end,7,nil,c)
 local p={x=40,y=1,z=0};local from={x=40,y=2,z=0}
 assert(Q:reserve(13,j.id,from,p,s.workers,true))
 local other=U.copy(j);other.id='other-harvest';other.workerId=14;other.bounds=nil;s.automation.jobs[other.id]=other
 assert(not Q:reserve(13,j.id,from,p,s.workers,true),'overlapping farm owner was ignored')
 other.status='completed';j.farm.sites[1].x=41
 assert(not Q:reserve(13,j.id,{x=41,y=2,z=0},{x=41,y=1,z=0},s.workers,true),'changed registered farm contract was accepted')
 c.farms={{kind='bamboo',sites={{x=60,y=1,z=0}},maxHeight=4}};j.type='FARM';j.farm=U.copy(c.farms[1]);j.bounds=nil
 assert(not Q:reserve(13,j.id,{x=60,y=2,z=0},{x=60,y=1,z=0},s.workers,true),'renewable column base was removed')
 assert(Q:reserve(13,j.id,{x=60,y=3,z=0},{x=60,y=2,z=0},s.workers,true))
 assert(not Q:reserve(13,j.id,{x=60,y=6,z=0},{x=60,y=5,z=0},s.workers,true),'column height limit escaped')
end)

test('farm admission keeps overlapping renewable work queued until the first owner settles',function()
 local c,s=fixture();s.automation.jobs={};s.automation.sequence=0
 s.workers={['13']={id=13,online=true,telemetry={status='idle',capabilities={farming=true}}},['14']={id=14,online=true,telemetry={status='idle',capabilities={farming=true}}}}
 local Q=require('autobuilder.core.workflows').new(s,function() return true end,function() return 100 end,7,nil,c)
 local first=Q:submit('FARM',{farm=U.copy(c.farms[1]),item='minecraft:wheat',quantity=1})
 local second=Q:submit('FARM',{farm=U.copy(c.farms[1]),item='minecraft:wheat',quantity=1})
 eq(Q:assign(s.workers).id,first.id);first.status='running'
 assert(not Q:assign(s.workers),'second farm owner would deadlock both mutation grants');eq(second.workerId,nil)
 first.status='completed';eq(Q:assign(s.workers).id,second.id)
end)

test('legacy preparation grants only canonical access above its own home while preserving infrastructure',function()
 local c,s,j=fixture();s.automation.jobs={};c.depot={x=0,y=2,z=0}
 c.logistics.nodes[1].buffers={{inventory='buffer',position=U.copy(c.depot)}}
 s.workers['13']={id=13,telemetry={depot=U.copy(c.depot),position={x=0,y=2,z=0,known=true}}}
 j.type='PREPARE_SITE';j.sitePlan=require('autobuilder.build.site').plan({x=0,y=2,z=0,heading='north'});j.bounds=U.copy(j.sitePlan.bounds);s.automation.jobs[j.id]=j
 local Q=require('autobuilder.core.workflows').new(s,function() return true end,function() return 100 end,7,nil,c)
 assert(Q:reserve(13,j.id,{x=0,y=2,z=0},{x=0,y=3,z=0},s.workers,true),'own above-depot access denied')
 assert(not Q:reserve(13,j.id,{x=0,y=2,z=0},{x=0,y=1,z=0},s.workers,true),'depot container could be dug')
 assert(not Q:reserve(13,j.id,{x=1,y=3,z=0},{x=1,y=3,z=1},s.workers,true),'non-waypoint change was accepted')
 c.fuel.stations={{position={x=0,y=2,z=0}}}
 assert(not Q:reserve(13,j.id,{x=0,y=2,z=0},{x=0,y=3,z=0},s.workers,true),'fuel infrastructure was exempted with access')
 c.fuel.stations={};s.workers['14']={id=14,telemetry={depot=U.copy(c.depot)}}
 assert(not Q:reserve(13,j.id,{x=0,y=2,z=0},{x=0,y=3,z=0},s.workers,true),'another registered home lost protection')
 s.workers['14']=nil;j.sitePlan.points[1].x=1
 assert(not Q:reserve(13,j.id,{x=0,y=2,z=0},{x=0,y=3,z=0},s.workers,true),'changed canonical access was accepted')
end)

test('mutation reservations protect above and below foreign workers in both grant orders',function()
  for _,dy in ipairs({-1,1}) do
    local c,s,j=fixture();j.type='REPAIR';j.blocks={{x=60,y=1,z=1,name='minecraft:air',state={}}}
    local worker={x=60,y=1+dy,z=1,known=true}
    s.workers['14']={id=14,online=false,telemetry={position=U.copy(worker)}}
    local q=require('autobuilder.core.workflows').new(s,function() return true end,function() return 100 end,7,nil,c)
    local from,target={x=61,y=1,z=1},j.blocks[1]
    assert(not require('autobuilder.core.protection').canModify(s,c,j,target),'mutation directly above or beneath an offline worker was permitted')
    assert(not q:reserve(13,j.id,from,target,s.workers,true))
    s.workers['14'].telemetry.position={x=61,y=worker.y,z=1,known=true}
    s.automation.jobs.courier={id='courier',type='TRANSPORT',workerId=14,status='running'}
    assert(q:reserve(13,j.id,from,target,s.workers,true))
    assert(not q:reserve(14,'courier',s.workers['14'].telemetry.position,worker,s.workers),'worker entered the vertical action envelope')
    assert(q:reserve(13,j.id,from,{x=62,y=1,z=1},s.workers))
    assert(q:reserve(14,'courier',s.workers['14'].telemetry.position,worker,s.workers))
    assert(not q:reserve(13,j.id,from,target,s.workers,true),'mutation ignored the earlier vertical movement reservation')
  end
end)

test('frozen renewable providers retain controller mutation geometry across registry changes',function()
 for _,kind in ipairs({'wheat','carrot','reed'}) do
  local c,s=fixture();s.automation.jobs={};s.automation.sequence=0
  c.farmAdapters={reed={mode='column',block='test:reed',item='test:reed'}}
  c.farms={{kind=kind,item='test:output',sites={{x=30,y=1,z=0}},maxHeight=4}}
  local farm=require('autobuilder.resources.providers').select('test:output',c,{}).farm
  local cap=require('autobuilder.resources.renewables').capability(farm,false)
  s.workers={['13']={id=13,online=true,telemetry={status='idle',capabilities={[cap]=true,farming=true}}},['14']={id=14,online=true,telemetry={status='idle',capabilities={[cap]=true,farming=true}}}}
  local function queue() return require('autobuilder.core.workflows').new(s,function() return true end,function() return 100 end,7,nil,c) end
  local q=queue();local j=q:submit('FARM',{farm=farm,item='test:output',quantity=1})
  local other=q:submit('FARM',{farm=U.copy(farm),item='test:output',quantity=1})
  local assigned=q:assign(s.workers);assert(assigned,kind..': '..tostring(j.coverageError));eq(assigned.id,j.id);j.status='running';eq(q:assign(s.workers),nil);eq(other.workerId,nil)
  c.farmAdapters.reed={mode='crop',block='test:other',item='test:output',seed='test:seed',age=4}
  s=U.copy(s);q=queue();j=s.automation.jobs[j.id]
  local y=kind=='reed' and 2 or 1
  assert(q:reserve(13,j.id,{x=30,y=y+1,z=0},{x=30,y=y,z=0},s.workers,true),'frozen provider denied')
  assert(not q:reserve(13,j.id,{x=30,y=1,z=0},{x=30,y=0,z=0},s.workers,true),'soil allowed')
  if kind=='reed' then assert(not q:reserve(13,j.id,{x=30,y=2,z=0},{x=30,y=1,z=0},s.workers,true),'column base allowed') end
  j.farm.sites[1].x=31
  assert(not q:reserve(13,j.id,{x=31,y=y+1,z=0},{x=31,y=y,z=0},s.workers,true),'changed territory allowed')
 end
end)

test('paired bed ownership includes generated head and denies foreign territory and legacy workers',function()
 local c,s=fixture();s.automation.jobs={};s.automation.sequence=0;s.automation.projects={}
 s.workers={['13']={id=13,online=true,telemetry={status='idle',capabilities={building=true},health={software={status='verified',version='0.32.0'},movement=true,placing=true,digging=true,left='unknown',right='unknown'}}},
 ['14']={id=14,online=true,telemetry={status='idle',capabilities={building=true,placementV1=true}}}}
 local q=require('autobuilder.core.workflows').new(s,function() return true end,function() return 1 end,7,nil,c)
 local b={x=60,y=1,z=1,name='minecraft:red_bed',state={part='foot',facing='east',occupied='false'}}
 local j=q:submit('BUILD',{blocks={b}})
 eq(j.requiredCapability,'placementV1');eq(j.bounds.max.x,61);eq(q:assign(s.workers).workerId,14)
 assert(q:reserve(14,j.id,{x=60,y=2,z=1},b,s.workers,true))
 s.automation.cells['61,1,1']={owner=13,jobId='foreign'}
 assert(not q:reserve(14,j.id,{x=60,y=2,z=1},b,s.workers,true))
 s.automation.cells={};c.restrictedAreas={{min={x=61,y=1,z=1},max={x=61,y=1,z=1}}}
 assert(not q:reserve(14,j.id,{x=60,y=2,z=1},b,s.workers,true))
end)

test('placement capability covers new verification and substrate survey while owned recovery persists',function()
 local state={};local q=require('autobuilder.core.workflows').new(state,function() return true end,function() return 1 end,7)
 local b={x=15,y=1,z=0,name='minecraft:red_bed',state={part='foot',facing='east',occupied='false'}}
 local j=q:submit('VERIFY',{blocks={b}})
 local workers={['12']={id=12,online=true,telemetry={status='idle',capabilities={building=true}}}}
 eq(q:assign(workers),nil);workers['12'].telemetry.capabilities.placementV1=true;eq(q:assign(workers).id,j.id)
 workers['12'].telemetry.capabilities.placementV1=nil;eq(q:assign(workers).id,j.id)
 local area=assert(require('autobuilder.core.chunks').area(j,{position={x=15,y=2,z=0,known=true},depot={x=15,y=2,z=0}}));assert(area.maxX>=1)
 local c=require('autobuilder.config').load({role='worker',controllerId=7,automation={building=true}});eq(c.capabilities.placementV1,true)
 local survey={identity=string.rep('a',64),region=1,columns={{x=0,z=0,minY=-1,foundationY=-1,substrateY=-1,clearanceY=2}}}
 j=q:submit('SURVEY_SITE',{siteSurvey=survey,clearanceY=2,bounds={min={x=0,y=-1,z=0},max={x=0,y=2,z=0}}});eq(j.requiredCapability,'placementV1')
end)


test('container tasks reserve neighboring chest footprint and negotiate observation capability',function()
 local state={};local q=require('autobuilder.core.workflows').new(state,function() return true end,function() return 1 end,7)
 local b={x=15,y=1,z=0,name='minecraft:chest',state={facing='south',type='single',waterlogged='false'}}
 local j=q:submit('BUILD',{blocks={b}})
 eq(j.requiredCapability,'metadataV1');eq(j.bounds.min.x,14);eq(j.bounds.max.x,16);eq(j.bounds.min.z,-1);eq(j.bounds.max.z,1)
 local workers={['12']={id=12,online=true,telemetry={status='idle',capabilities={building=true,placementV1=true}}}}
 eq(q:assign(workers),nil);workers['12'].telemetry.capabilities.metadataV1=true;eq(q:assign(workers).id,j.id)
 state.workers=workers;j.status='running'
 local other=q:submit('BUILD',{blocks={{x=16,y=1,z=0,name='minecraft:stone',state={}}}})
 workers['13']={id=13,online=true,telemetry={status='idle',capabilities={building=true}}}
 eq(q:assign(workers),nil);eq(other.workerId,nil)
 local c=require('autobuilder.config').load({role='worker',controllerId=7,automation={building=true}});eq(c.capabilities.metadataV1,true)
end)
