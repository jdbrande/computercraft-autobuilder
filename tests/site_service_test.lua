local U=require('autobuilder.core.util')
local function fixture()
  local e={fs=require('tests.install_support').fs(),textutils=require('tests.support').codec()}
  local c=require('tests.loaded_config').load({build={enabled=true,origin={x=100,y=2,z=100},regionSize=2}})
  local app={state={workers={},jobs={}}};function app:save() return true end
  local q=require('autobuilder.core.workflows').new(app.state,function() return app:save() end,function() return 1 end,7,nil,c)
  local p={name='site',hash=string.rep('a',64),transform=U.copy(c.build),jobs={},generation=0,run=0};q.state.projects.site=p
  local source={schema=1,size={x=4,y=2,z=4},palette={{name='minecraft:stone',state={}}},runs={{id=1,count=32}},metadata={},requirements={}}
  local plan=require('autobuilder.build.site_plan').new(source,p.transform,p.hash,{regionSize=2,minY=0,maxY=15})
  local function service() return require('autobuilder.build.site_service').new(app,c,e,q) end
  local function finish(j,blocked)
    j.workerId=12;j.status='completed';j.progress=#j.siteSurvey.columns
    j.siteReport={identity=plan.identity,region=j.siteSurvey.region,observations={}}
    for _,col in ipairs(j.siteSurvey.columns) do j.siteReport.observations[#j.siteReport.observations+1]={x=col.x,z=col.z,y=blocked and j.clearanceY or col.minY,
      status=blocked and 'blocked' or 'empty',name=not blocked and 'minecraft:air' or nil,reason=blocked and 'overhead obstructed' or nil} end
  end
  return e,c,app,q,p,plan,service,finish
end

test('site service bounds queued survey payloads and persists all region evidence across restart',function()
  local e,c,app,q,p,plan,new,finish=fixture();local service=new();service:start(p,plan)
  for _=1,30 do service:tick(p,plan) end
  local count=0;for _ in pairs(p.site.active) do count=count+1 end;eq(count,4)
  for _=1,100 do
    for _,j in pairs(q.state.jobs) do if j.status~='completed' then finish(j) end end
    service=new();service:tick(p,plan);if p.phase=='surveyed' then break end
  end
  eq(p.phase,'surveyed');eq(p.site.completed,plan.regionCount);eq(p.site.blocked,0);eq(p.completed,plan.columnCount)
  for region=1,plan.regionCount do
    local record=assert(service:evidence(p,plan,region));eq(record.identity,plan.identity);eq(#record.report.observations,plan:region(region).columns)
  end
  for _,j in pairs(q.state.jobs) do assert(not j.siteReport and not j.siteSurvey.columns,'expanded survey retained in main checkpoint') end
end)

test('blocked survey creates a new higher immutable attempt without stalling independent regions',function()
  local e,c,app,q,p,plan,new,finish=fixture();local service=new();service:start(p,plan);service:tick(p,plan)
  local first=q.state.jobs[p.site.active['1'].jobId];local original=U.copy(first);finish(first,true)
  for _=1,4 do service:tick(p,plan) end
  local nextJob=q.state.jobs[p.site.active['1'].jobId];assert(nextJob.id~=first.id);assert(nextJob.clearanceY>original.clearanceY)
  eq(first.clearanceY,original.clearanceY);eq(nextJob.siteSurvey.identity,original.siteSurvey.identity)
  for _=1,150 do
    for _,j in pairs(q.state.jobs) do if j.status~='completed' then finish(j,j.siteSurvey.region==1) end end
    service:tick(p,plan);if p.phase=='survey_blocked' then break end
  end
  eq(p.phase,'survey_blocked');eq(p.site.blocked,1);eq(p.site.completed,plan.regionCount)
  eq(service:evidence(p,plan,1).report.observations[1].status,'blocked')
end)

test('site survey evidence failure never consumes a worker report and damaged evidence is not proof',function()
  local e,c,app,q,p,plan,new,finish=fixture();local service=new();service:start(p,plan);service:tick(p,plan)
  local j=q.state.jobs[p.site.active['1'].jobId];finish(j)
  local open=e.fs.open;e.fs.open=function(path,mode) if mode=='w' then return nil,'disk full' end;return open(path,mode) end
  local ok=pcall(service.tick,service,p,plan);assert(not ok);assert(j.siteReport);eq(p.site.completed,0)
  e.fs.open=open;service=new();service:tick(p,plan)
  local record,path=service:evidence(p,plan,1);assert(record and path)
  e.fs.files[path]='corrupt';e.fs.files[path..'.bak']=nil
  assert(not service:evidence(p,plan,1),'corrupt observation treated as survey proof')
  local changed=U.copy(plan);changed.identity=string.rep('b',64)
  assert(not pcall(service.tick,service,p,changed),'changed site geometry accepted')
end)

test('site evidence survives root checkpoint failure without double counting or duplicate work',function()
  local e,c,app,q,p,plan,new,finish=fixture();local service=new();service:start(p,plan);service:tick(p,plan)
  local j=q.state.jobs[p.site.active['1'].jobId];finish(j)
  function app:save() return false,'root disk full' end
  assert(not pcall(service.tick,service,p,plan));eq(p.site.completed,0);assert(j.siteReport)
  assert(service:evidence(p,plan,1),'committed observation was lost with root rollback')
  function app:save() return true end
  service=new();service:tick(p,plan);eq(p.site.completed,1);assert(not j.siteReport)
  service:tick(p,plan);eq(p.site.completed,1)
end)

local function surveyedFixture()
  local e,c,app,q,p,plan,new,finish=fixture();local service=new();service:start(p,plan)
  for _=1,100 do
    for _,j in pairs(q.state.jobs) do if j.status~='completed' then finish(j) end end
    service:tick(p,plan);if p.phase=='surveyed' then break end
  end
  eq(p.phase,'surveyed')
  app.mining={storage={counts={['minecraft:dirt']=30,['minecraft:cobblestone']=10}}}
  app.state.workers['12']={id=12,online=true,lastSeen=101,telemetry={status='idle',cargo={items={},limits={}}}}
  local production={ledger=require('autobuilder.storage.ledger').new(app.state,function() return true end),returns={}}
  function production.returns:request(owner,key)
    for _,r in pairs(q.state.returns or {}) do if r.key==key then return r end end
    q.state.returns=q.state.returns or {};local r={id='return:'..owner,owner=owner,key=key,status='queued'};q.state.returns[r.id]=r;return r
  end
  service=require('autobuilder.build.site_service').new(app,c,e,q,production)
  return e,c,app,q,p,plan,service,production
end

test('preparation service executes bounded batches and verifies every region before certifying it',function()
  local e,c,app,q,p,plan,service,production=surveyedFixture();service:startWork(p,plan)
  for _=1,800 do
    service:workTick(p,plan)
    for _,j in pairs(q.state.jobs) do if j.type=='PREPARE_REGION' and j.status~='completed' then
      assert(#j.blocks<=8);j.workerId=12;j.status='completed';j.completedAt=100;j.progress=#j.blocks;j.report={counts={correct=#j.blocks},entries={}}
    end end
    if p.phase=='site_ready' then break end
  end
  eq(p.phase,'site_ready');eq(p.site.work.completed,plan.regionCount);eq(p.site.work.blocked,0)
  for region=1,plan.regionCount do assert(service:prepared(p,plan,region));eq(service:evidence(p,plan,region).preparation.fill,'minecraft:dirt') end
  local count=0;for _,j in pairs(q.state.jobs) do if j.type=='PREPARE_REGION' then count=count+1;assert(not j.report and not j.blocks,'completed work payload retained') end end
  assert(count>plan.regionCount*2,'verification or fill phase skipped')
end)

test('preparation waits for exact debris settlement and retains bounded defects without stalling other regions',function()
  local e,c,app,q,p,plan,service=surveyedFixture();service:startWork(p,plan);for _=1,8 do service:workTick(p,plan) end
  local first
  for _,j in pairs(q.state.jobs) do if j.type=='PREPARE_REGION' then first=j end end
  assert(first);first.workerId=12;first.status='completed';first.completedAt=100;first.progress=#first.blocks;first.report={counts={correct=#first.blocks},entries={}}
  app.state.workers['12'].telemetry.cargo={items={['minecraft:dirt']=2},limits={['minecraft:dirt']=64}}
  for _=1,8 do service:workTick(p,plan) end
  local r=assert(q.state.returns and next(q.state.returns) and select(2,next(q.state.returns)));eq(r.status,'queued')
  local record=service:evidence(p,plan,first.siteWork.region);eq(record.preparation.jobId,first.id)
  r.status='completed';r.settledAt=102;app.state.workers['12'].telemetry.cargo={items={},limits={}}
  for _=1,1000 do
    service:workTick(p,plan)
    for _,j in pairs(q.state.jobs) do if j.type=='PREPARE_REGION' and j.status~='completed' then
      j.workerId=12;j.status='completed';j.completedAt=100
      local blocked=j.siteWork.region==1 and j.siteWork.stage=='verify'
      j.progress=#j.blocks-(blocked and 1 or 0);j.report={counts={correct=j.progress},entries={}}
      if blocked then j.report.counts.wrong=1;j.report.entries={{x=j.blocks[1].x,y=j.blocks[1].y,z=j.blocks[1].z,status='wrong',actual={name='minecraft:bedrock'},reason='protected'}} end
    end end
    if p.phase=='site_blocked' then break end
  end
  eq(p.phase,'site_blocked');eq(p.site.work.blocked,1)
  assert(not service:prepared(p,plan,1));assert(service:prepared(p,plan,2))
  assert(not service:readyFor(p,plan,{{x=100,y=2,z=100}}));assert(service:readyFor(p,plan,{{x=103,y=2,z=103}}),'unrelated blocked region withheld independent construction')
  local blocked=service:evidence(p,plan,1).preparation;assert(blocked.defects[1].reason);assert(blocked.defects[1].actual.name)
end)

test('preparation retains root receipts until both evidence checkpoints contain their consumption',function()
  local e,c,app,q,p,plan,service=surveyedFixture();service:startWork(p,plan)
  for _=1,8 do service:workTick(p,plan) end
  local first;for _,j in pairs(q.state.jobs) do if j.type=='PREPARE_REGION' then first=j;break end end
  assert(first);local region=first.siteWork.region
  p.site.work.active={[tostring(region)]={region=region}};p.site.work.cursor=plan.regionCount+1
  first.workerId=12;first.status='completed';first.completedAt=100;first.progress=#first.blocks;first.report={counts={correct=#first.blocks},entries={}}
  service:workTick(p,plan)
  local record,path=service:evidence(p,plan,region);eq(record.preparation.lastJob,first.id);assert(first.report)
  e.fs.fault.open=path..'.tmp';assert(not pcall(service.workTick,service,p,plan));assert(first.report,'worker receipt pruned before backup advanced')
  e.fs.fault.open=nil;service:workTick(p,plan);assert(not first.report)
  e.fs.files[path]='corrupt';local backup=assert(service:evidence(p,plan,region));eq(backup.preparation.lastJob,first.id);assert(not backup.preparation.jobId)
end)

test('missing site evidence retains active physical ownership then resurveys before issuing new work',function()
  local e,c,app,q,p,plan,service=surveyedFixture();service:startWork(p,plan)
  for _=1,8 do service:workTick(p,plan) end
  local first;for _,j in pairs(q.state.jobs) do if j.type=='PREPARE_REGION' then first=j;break end end
  assert(first);local region=first.siteWork.region
  p.site.work.active={[tostring(region)]={region=region}};p.site.work.cursor=plan.regionCount+1
  first.workerId=12;first.status='running'
  local _,path=service:evidence(p,plan,region);e.fs.files[path]=nil;e.fs.files[path..'.bak']=nil
  local before=q.state.sequence
  for _=1,5 do service:workTick(p,plan) end
  eq(q.state.sequence,before);eq(first.status,'running');eq(first.workerId,12)
  first.status='completed';first.completedAt=100;first.progress=#first.blocks;first.report={counts={correct=#first.blocks},entries={}}
  for _=1,10 do service:workTick(p,plan) end
  local recovery
  for _,j in pairs(q.state.jobs) do if j.type=='SURVEY_SITE' and j.status~='completed' then recovery=j end end
  assert(recovery,'lost evidence did not produce a new read-only survey');eq(recovery.siteSurvey.region,region)
  recovery.workerId=12;recovery.status='completed';recovery.progress=#recovery.siteSurvey.columns
  recovery.siteReport={identity=plan.identity,region=region,observations={}}
  for _,col in ipairs(recovery.siteSurvey.columns) do recovery.siteReport.observations[#recovery.siteReport.observations+1]={x=col.x,y=col.minY,z=col.z,status='empty',name='minecraft:air'} end
  for _=1,8 do service:workTick(p,plan) end
  local record=assert(service:evidence(p,plan,region));eq(record.jobId,recovery.id);assert(not service:prepared(p,plan,region))
  local newJob=q.state.jobs[record.preparation.jobId];assert(newJob and newJob.id~=first.id,'retired contract was reused after resurvey')
end)

test('advanced region evidence reconciles an older controller root without stranding a completed owner',function()
  local e,c,app,q,p,plan,service=surveyedFixture();service:startWork(p,plan)
  for _=1,8 do service:workTick(p,plan) end
  local j;for _,candidate in pairs(q.state.jobs) do if candidate.type=='PREPARE_REGION' then j=candidate;break end end
  local region=j.siteWork.region;p.site.work.active={[tostring(region)]={region=region}};p.site.work.cursor=plan.regionCount+1
  j.workerId=12;j.status='completed';j.completedAt=100;j.progress=#j.blocks;j.report={counts={correct=#j.blocks},entries={}}
  local done=j.progress;service:workTick(p,plan)
  j.status='running';j.progress=0;j.completedAt=nil;j.report=nil
  service:workTick(p,plan)
  eq(j.status,'completed');eq(j.progress,done);eq(j.completedAt,100);assert(not j.blocks)
end)

test('a saved prepared marker with unresolved defects is rejected as invalid evidence',function()
  local e,c,app,q,p,plan,service=surveyedFixture()
  local record,path=service:evidence(p,plan,1)
  record.preparation={status='prepared',stage='verified',cursor=1,sequence=2,failed=1,defects={},verifiedFill=true,verifiedClear=true}
  assert(require('autobuilder.core.checkpoint').new(e.fs,e.textutils,path):save(record))
  assert(not service:prepared(p,plan,1),'unresolved defects certified as prepared')
end)

local function completePreparation(q,plan)
  for _,j in pairs(q.state.jobs) do if j.status~='completed' then
    j.workerId=12;j.status='completed';j.completedAt=100
    if j.type=='SURVEY_SITE' then
      j.progress=#j.siteSurvey.columns;j.siteReport={identity=plan.identity,region=j.siteSurvey.region,observations={}}
      for _,col in ipairs(j.siteSurvey.columns) do j.siteReport.observations[#j.siteReport.observations+1]={x=col.x,y=col.minY,z=col.z,status='empty',name='minecraft:air'} end
    else j.progress=#j.blocks;j.report={counts={correct=#j.blocks},entries={}} end
  end end
end

test('lost completed preparation proof reopens a bounded census and certifies each region exactly once',function()
  local e,c,app,q,p,plan,service=surveyedFixture();service:startWork(p,plan)
  for _=1,1000 do service:workTick(p,plan);completePreparation(q,plan);if p.site.work.status=='completed' then break end end
  eq(p.site.work.preparedCount,plan.regionCount);p.phase='building'
  local blocks={{x=103,y=2,z=103}};local region=plan:requiredRegions(blocks)[1]
  local _,path=service:evidence(p,plan,region);e.fs.files[path]=nil;e.fs.files[path..'.bak']=nil
  for _=1,3 do assert(not service:readyFor(p,plan,blocks)) end
  eq(p.site.work.cursor,1);eq(p.site.work.status,'working');eq(p.phase,'building')
  for _=1,1000 do
    service:workTick(p,plan);completePreparation(q,plan)
    if p.site.work.status=='completed' then break end
  end
  eq(p.site.work.completed,plan.regionCount);eq(p.site.work.preparedCount,plan.regionCount);eq(p.site.work.blocked,0)
  assert(service:readyFor(p,plan,blocks));eq(p.phase,'building');eq(p.site.work.rechecking,nil)
end)

test('preparation proof recovery preserves all active owners and does not repeatedly reset its census',function()
  local e,c,app,q,p,plan,service=surveyedFixture();service:startWork(p,plan)
  for _=1,8 do service:workTick(p,plan) end
  local held={};for id,j in pairs(q.state.jobs) do if j.type=='PREPARE_REGION' then j.workerId=12;j.status='running';held[id]=true end end
  assert(next(held));local active=U.copy(p.site.work.active)
  local blocks={{x=103,y=2,z=103}};local region=plan:requiredRegions(blocks)[1]
  local _,path=service:evidence(p,plan,region);e.fs.files[path]=nil;e.fs.files[path..'.bak']=nil
  assert(not service:readyFor(p,plan,blocks))
  for key,a in pairs(active) do assert(p.site.work.active[key]);eq(p.site.work.active[key].region,a.region) end
  service:workTick(p,plan);local cursor=p.site.work.cursor
  assert(cursor>1);assert(not service:readyFor(p,plan,blocks));eq(p.site.work.cursor,cursor)
  for id in pairs(held) do eq(q.state.jobs[id].status,'running');eq(q.state.jobs[id].workerId,12) end
  for _=1,1200 do service:workTick(p,plan);completePreparation(q,plan);if p.site.work.status=='completed' then break end end
  eq(p.site.work.completed,plan.regionCount);eq(p.site.work.preparedCount,plan.regionCount)
end)
test('fill selection requires enough stock or an available replenishment provider',function()
 for _,amount in ipairs({1,30}) do
  local e,c,app,q,p,plan,service=surveyedFixture()
  app.mining.storage.counts={['minecraft:dirt']=amount}
  app.state.workers['12'].telemetry.capabilities={mining=true}
  app.state.workers['12'].telemetry.miningResources={'minecraft:cobblestone'}
  service:startWork(p,plan)
  local first
  for _=1,150 do
   service:workTick(p,plan)
   for _,j in pairs(q.state.jobs) do if j.type=='PREPARE_REGION' and j.status~='completed' then
    if j.siteWork.stage=='fill' then first=j;break end
    j.workerId=12;j.status='completed';j.completedAt=100;j.progress=#j.blocks;j.report={counts={correct=#j.blocks},entries={}}
   end end
   if first then break end
  end
  assert(first,'no fill task');eq(first.blocks[1].name,amount==1 and 'minecraft:cobblestone' or 'minecraft:dirt')
 end
end)

test('failed preparation verification resurveys fresh epochs across restart and stops after three retries',function()
  for _,persistent in ipairs({false,true}) do
    local e,c,app,q,p,plan,service,production=surveyedFixture();service:startWork(p,plan)
    local surveys=0;local firstEpoch;local replayed=false
    for _=1,2400 do
      service:workTick(p,plan)
      for _,j in pairs(q.state.jobs) do if j.status~='completed' then
        j.workerId=12;j.status='completed';j.completedAt=100
        if j.type=='SURVEY_SITE' then
          surveys=surveys+1;eq(j.siteSurvey.region,1)
          j.progress=#j.siteSurvey.columns;j.siteReport={identity=plan.identity,region=1,observations={}}
          for _,col in ipairs(j.siteSurvey.columns) do j.siteReport.observations[#j.siteReport.observations+1]={x=col.x,z=col.z,y=col.minY,status='empty',name='minecraft:air'} end
        else
          local defect=j.siteWork.region==1 and j.siteWork.stage=='verify' and (persistent or surveys==0)
          j.progress=#j.blocks-(defect and 1 or 0);j.report={counts={correct=j.progress},entries={}}
          if defect then
            j.report.counts.missing=1;j.report.entries={{x=j.blocks[1].x,y=j.blocks[1].y,z=j.blocks[1].z,status='missing',reason='ground changed after work'}}
            firstEpoch=firstEpoch or j.key
          elseif j.siteWork.region==1 and surveys>0 then assert(j.key~=firstEpoch,'retry reused a physical work ID') end
        end
      end end
      local record=service:evidence(p,plan,1)
      if record and record.retryPending and not replayed then
        local save=app.save
        function app:save() return false,'retry root checkpoint lost' end
        assert(not pcall(service.workTick,service,p,plan))
        app.save=save
        service=require('autobuilder.build.site_service').new(app,c,e,q,production);replayed=true
      end
      if p.phase=='site_ready' or p.phase=='site_blocked' then break end
    end
    eq(surveys,persistent and 3 or 1);assert(replayed)
    eq(p.phase,persistent and 'site_blocked' or 'site_ready')
    local record=assert(service:evidence(p,plan,1));eq(record.preparationRetries,surveys)
    assert(record.retryHistory[1].defect.reason)
    eq(service:prepared(p,plan,1),not persistent);assert(service:prepared(p,plan,2))
    local before=q.state.sequence;for _=1,10 do service:workTick(p,plan) end;eq(q.state.sequence,before)
  end
end)

test('malformed pending retry evidence is rejected without crashing recovery',function()
  local e,c,app,q,p,plan,service=surveyedFixture()
  local original,path=service:evidence(p,plan,1)
  for _,value in ipairs({true,'bad',{},-1}) do
    local record=U.copy(original);record.retryPending=true;record.preparationRetries=value
    record.preparation={status='blocked',stage='verified'}
    assert(require('autobuilder.core.checkpoint').new(e.fs,e.textutils,path):save(record))
    assert(not service:evidence(p,plan,1))
  end
  local record=U.copy(original);record.retryPending=true;record.preparationRetries=1;record.preparation=true
  assert(require('autobuilder.core.checkpoint').new(e.fs,e.textutils,path):save(record))
  assert(not service:evidence(p,plan,1))
end)

test('observed fluid schedules a complete sealing pass before removing temporary solids',function()
  local e,c,app,q,p,plan,service=surveyedFixture();service:startWork(p,plan)
  local wet,sealed,cleared=false,false,false;local sealCells=0
  for _=1,1000 do
    service:workTick(p,plan)
    for _,j in pairs(q.state.jobs) do if j.type=='PREPARE_REGION' and j.status~='completed' then
      j.workerId=12;j.status='completed';j.completedAt=100;j.progress=#j.blocks;j.report={counts={correct=#j.blocks},entries={}}
      if j.siteWork.region==1 then
        if j.siteWork.stage=='clear' and not wet then
          wet=true;j.progress=j.progress-1;j.report.counts.correct=j.progress;j.report.counts.unsupported=1
          j.report.entries={{x=j.blocks[1].x,y=j.blocks[1].y,z=j.blocks[1].z,status='unsupported',actual={name='minecraft:water',state={level='0'}},reason='fluid needs sealing'}}
        elseif j.siteWork.stage=='seal' then
          assert(not cleared);sealed=true;sealCells=sealCells+#j.blocks
        elseif j.siteWork.stage=='clear' and sealed then
          cleared=true
          local record=service:evidence(p,plan,1);local _,_,expected=plan:work(1,record,'seal',1,1,'minecraft:dirt');eq(sealCells,expected)
        elseif j.siteWork.stage=='fill' then assert(sealed and cleared,'foundation phase skipped fluid clearance') end
      end
    end end
    if p.phase=='site_ready' then break end
  end
  assert(wet and sealed and cleared);eq(p.phase,'site_ready');assert(service:prepared(p,plan,1))
end)

test('cross-region fluid stabilization revisits an early failed region after later sources are sealed',function()
 for _,persistent in ipairs({false,true}) do
  local e,c,app,q,p,plan,service,production=surveyedFixture();service:startWork(p,plan)
  local sourceSealed=false;local earlyBlocked=false;local restarted=false;local surveys=0
  for _=1,4500 do
    service:workTick(p,plan)
    local first=service:evidence(p,plan,1)
    if first and first.preparation and first.preparation.status=='blocked' and not first.retryPending and first.preparationRetries==3 then earlyBlocked=true end
    for _,j in pairs(q.state.jobs) do if j.status~='completed' and not (j.siteWork and j.siteWork.region==plan.regionCount and not earlyBlocked) then
      j.workerId=12;j.status='completed';j.completedAt=100
      if j.type=='SURVEY_SITE' then
        if j.siteSurvey.region==1 then surveys=surveys+1 end
        j.progress=#j.siteSurvey.columns;j.siteReport={identity=plan.identity,region=j.siteSurvey.region,observations={}}
        for _,col in ipairs(j.siteSurvey.columns) do j.siteReport.observations[#j.siteReport.observations+1]={x=col.x,z=col.z,y=col.minY,status='empty',name='minecraft:air'} end
      else
        j.progress=#j.blocks;j.report={counts={correct=j.progress},entries={}}
        local r,stage=j.siteWork.region,j.siteWork.stage
        if r==plan.regionCount and stage=='seal' then sourceSealed=true end
        if (r==1 and (not sourceSealed or persistent) or r==plan.regionCount and not sourceSealed) and (stage=='clear' or stage=='verify') then
          j.progress=j.progress-1;j.report.counts.correct=j.progress;j.report.counts.unsupported=1
          j.report.entries={{x=j.blocks[1].x,y=j.blocks[1].y,z=j.blocks[1].z,status='unsupported',actual={name='minecraft:water',state={level='1'}},reason='adjacent fluid inflow'}}
        end
      end
    end end
    if p.site.work.fluidRecheck and not restarted then
      service=require('autobuilder.build.site_service').new(app,c,e,q,production);restarted=true
      local save=app.save;function app:save() return false,'post-fluid checkpoint unavailable' end
      assert(not pcall(service.workTick,service,p,plan));app.save=save
    end
    if p.phase=='site_ready' or p.phase=='site_blocked' then break end
  end
  assert(earlyBlocked,'case did not reach the early retry limit');assert(sourceSealed,'later source was never sealed')
  assert(restarted);eq(p.phase,persistent and 'site_blocked' or 'site_ready');eq(service:prepared(p,plan,1),not persistent)
  eq(surveys,persistent and 7 or 4);assert(service:evidence(p,plan,1).fluidRechecked)
  local sequence=q.state.sequence;for _=1,20 do service:workTick(p,plan) end;eq(q.state.sequence,sequence)
 end
end)

test('controller restores opened foundation access before accepting its hidden support proof across restart',function()
  local e,c,app,q,p,plan,service,production=surveyedFixture();service:startWork(p,plan)
  local target={x=100,y=1,z=100};local phases={};local opened,verified,restored=false,false,false
  for _=1,1500 do
    service:workTick(p,plan)
    service=require('autobuilder.build.site_service').new(app,c,e,q,production)
    for _,j in pairs(q.state.jobs) do if j.status~='completed' then
      assert(j.type=='PREPARE_REGION','access failure unnecessarily restarted the survey')
      j.workerId=12;j.status='completed';j.completedAt=100;j.progress=#j.blocks;j.report={counts={correct=j.progress},entries={}}
      if j.siteAccess then
        assert(require('autobuilder.build.site_work').validContract(j));phases[#phases+1]=j.siteWork.stage
        if j.siteWork.stage=='clear' then
          opened=true;j.report.accessChanges={}
          for i,b in ipairs(j.blocks) do if b.y==target.y then j.report.accessChanges[i]={x=b.x,y=b.y,z=b.z,name='minecraft:stone'} end end
        elseif U.distance(j.blocks[1],target)==0 then
          assert(opened and not restored)
          if j.siteWork.stage=='verify' then verified=true end
        else
          assert(verified,'ground restored before hidden support was verified')
          for _,b in ipairs(j.blocks) do eq(b.y,target.y) end
          if j.siteWork.stage=='verify' then restored=true end
        end
      else
        for _,b in ipairs(j.blocks) do if b.support and U.distance(b,target)==0 then
          assert(not verified,'restored hidden support was sent through an inaccessible ordinary approach')
          j.progress=j.progress-1;j.report.counts.correct=j.progress;j.report.counts.inaccessible=1
          j.report.entries={{x=b.x,y=b.y,z=b.z,status='inaccessible',reason='retained floor blocks inspection'}}
        end end
      end
    end end
    if p.site.work.status=='completed' then break end
  end
  assert(opened and verified and restored,'controller never completed foundation access and restoration')
  eq(p.phase,'site_ready');assert(service:prepared(p,plan,1));assert(#phases>=5)
  local record,path=service:evidence(p,plan,1)
  local checkpoint=require('autobuilder.core.checkpoint').new(e.fs,e.textutils,path)
  local broken=U.copy(record);broken.preparation.accessProofs['100,1,100'].target.x=101
  assert(checkpoint:save(broken));assert(not service:prepared(p,plan,1),'changed target retained hidden support proof')
end)

test('foundation access loss restores from retained receipts and failed restoration keeps region owned',function()
 for _,lost in ipairs({true,false}) do
  local e,c,app,q,p,plan,service,production=surveyedFixture();service:startWork(p,plan)
  local target={x=100,y=1,z=100};local triggered,restoring,restored=false,false,false;local failures=0
  for _=1,1600 do
    service:workTick(p,plan)
    for _,j in pairs(q.state.jobs) do if j.status~='completed' then
      local access=j.siteAccess
      if j.type=='SURVEY_SITE' then
        assert(lost and triggered);completePreparation(q,plan)
      else
        j.workerId=12;j.status='completed';j.completedAt=100;j.progress=#j.blocks;j.report={counts={correct=j.progress},entries={}}
        if access and j.siteWork.stage=='clear' then
          j.report.accessChanges={}
          for i,b in ipairs(j.blocks) do if b.y==target.y then j.report.accessChanges[i]={x=b.x,y=b.y,z=b.z,name='minecraft:stone'} end end
        elseif access and U.distance(j.blocks[1],target)~=0 then
          restoring=true
          if not lost then
            failures=failures+1;j.progress=0;j.report={counts={inaccessible=#j.blocks},entries={{x=j.blocks[1].x,y=j.blocks[1].y,z=j.blocks[1].z,status='inaccessible',reason='restoration obstructed'}}}
          elseif j.siteWork.stage=='verify' then restored=true end
        elseif not access and not triggered then
          for _,b in ipairs(j.blocks) do if b.support and U.distance(b,target)==0 then
            j.progress=j.progress-1;j.report.counts.correct=j.progress;j.report.counts.inaccessible=1
            j.report.entries={{x=b.x,y=b.y,z=b.z,status='inaccessible',reason='retained floor'}}
          end end
        end
      end
    end end
    local record,path=service:evidence(p,plan,1)
    if not triggered and record and record.preparation and record.preparation.access and record.preparation.access.phase=='restore_fill' then
      triggered=true
      if lost then e.fs.files[path]=nil;e.fs.files[path..'.bak']=nil end
      service=require('autobuilder.build.site_service').new(app,c,e,q,production)
    end
    if lost and p.phase=='site_ready' or not lost and failures==3 and p.error then break end
  end
  assert(triggered and restoring)
  if lost then assert(restored);eq(p.phase,'site_ready')
  else
    eq(failures,3);assert(p.site.work.active['1'],'failed restoration released its region')
    assert(not service:prepared(p,plan,1));assert(service:prepared(p,plan,2));assert(p.error:find('restoration'))
  end
 end
end)

test('cross-region access holds its envelope between jobs drains existing owners and releases after restoration',function()
  local e,c,app,q,p,plan,service,production=surveyedFixture();service:startWork(p,plan)
  local target={x=102,y=1,z=102};local held
  for _=1,1200 do
    service:workTick(p,plan)
    for _,j in pairs(q.state.jobs) do if j.status~='completed' then
      if j.siteWork and j.siteWork.region==5 and j.siteWork.stage=='fill' then held=j
      else
        j.workerId=12;j.status='completed';j.completedAt=100;j.progress=#j.blocks;j.report={counts={correct=j.progress},entries={}}
      end
    end end
    if held and p.site.work.preparedCount==plan.regionCount-1 then break end
  end
  assert(held);eq(p.site.work.preparedCount,plan.regionCount-1)
  held.workerId=12;held.status='completed';held.completedAt=100;held.progress=#held.blocks-1
  held.report={counts={correct=held.progress,inaccessible=1},entries={{x=target.x,y=target.y,z=target.z,status='inaccessible',reason='sealed interior'}}}
  for _=1,8 do service:workTick(p,plan);if p.site.accessLease then break end end
  local lease=assert(p.site.accessLease);eq(lease.region,5)
  local foreign
  for r=1,plan.regionCount do if r~=5 and require('autobuilder.resources.exploration').overlaps(lease.bounds,plan:region(r).bounds) then foreign=r;break end end
  assert(foreign);assert(service:evidence(p,plan,foreign).preparation.status=='prepared')
  assert(not service:prepared(p,plan,foreign),'tunnel ownership left neighboring support certified')
  q.state.jobs.foreign={id='foreign',status='running',workerId=13,bounds=U.copy(lease.bounds)}
  service=require('autobuilder.build.site_service').new(app,c,e,q,production)
  for _=1,8 do service:workTick(p,plan) end
  for _,j in pairs(q.state.jobs) do assert(not j.siteAccess,'access began before the existing owner drained') end
  q.state.jobs.foreign.status='completed'
  local saw=false
  for _=1,1200 do
    service:workTick(p,plan)
    for _,j in pairs(q.state.jobs) do if j.status~='completed' then
      j.workerId=12;j.status='completed';j.completedAt=100;j.progress=#j.blocks;j.report={counts={correct=j.progress},entries={}}
      if j.siteAccess then
        saw=true;assert(p.site.accessLease);assert(require('autobuilder.build.site_work').validContract(j))
        if j.siteWork.stage=='clear' then
          j.report.accessChanges={};for i,b in ipairs(j.blocks) do if b.y==1 then j.report.accessChanges[i]={x=b.x,y=b.y,z=b.z,name='minecraft:stone'} end end
        end
      end
    end end
    if p.phase=='site_ready' then break end
  end
  assert(saw);eq(p.phase,'site_ready');assert(not p.site.accessLease);assert(service:prepared(p,plan,foreign))
end)

test('persistent external inflow builds a verified retaining barrier before a fresh preparation census',function()
  local e,c,app,q,p,plan,service,production=surveyedFixture();service:startWork(p,plan)
  local barrierJobs,restored=0,false;local reopened=false
  for _=1,6000 do
    service:workTick(p,plan)
    if p.site.work.containmentRecheck then reopened=true end
    for _,j in pairs(q.state.jobs) do if j.status~='completed' then
      j.workerId=12;j.status='completed';j.completedAt=100
      if j.type=='SURVEY_SITE' then
        j.progress=#j.siteSurvey.columns;j.siteReport={identity=plan.identity,region=j.siteSurvey.region,observations={}}
        for _,col in ipairs(j.siteSurvey.columns) do j.siteReport.observations[#j.siteReport.observations+1]={x=col.x,z=col.z,y=col.minY,status='empty',name='minecraft:air'} end
      else
        j.progress=#j.blocks;j.report={counts={correct=j.progress},entries={}}
        if j.key:find(':barrier:',1,true) then
          barrierJobs=barrierJobs+1;assert(not service:readyFor(p,plan,{{x=103,y=2,z=103}}))
          assert(not pcall(service.start,service,p,plan),'fresh survey abandoned active barrier ownership')
          for _,b in ipairs(j.blocks) do assert(not require('autobuilder.core.pathfinding').inside(b,plan.bounds)) end
          if not restored then service=require('autobuilder.build.site_service').new(app,c,e,q,production);restored=true end
        elseif j.siteWork.region==1 and (j.siteWork.stage=='clear' or j.siteWork.stage=='verify') and not reopened then
          j.progress=j.progress-1;j.report.counts.correct=j.progress;j.report.counts.unsupported=1
          j.report.entries={{x=j.blocks[1].x,y=j.blocks[1].y,z=j.blocks[1].z,status='unsupported',actual={name='minecraft:water',state={level='1'}},reason='continuous external inflow'}}
        end
      end
    end end
    if p.site.work.status=='completed' then break end
  end
  assert(barrierJobs>0,'external inflow never received automatic containment');assert(restored and reopened)
  eq(p.site.barrier.status,'verified');eq(p.phase,'site_ready');assert(service:prepared(p,plan,1))
  assert(p.protectedBounds.min.x<plan.bounds.min.x);assert(service:evidence(p,plan,1).containmentRechecked)
  local outside=p.protectedBounds.min.x;service:start(p,plan);eq(p.protectedBounds.min.x,outside)
end)

test('retaining barrier preserves receipts through failed checkpoints and keeps exact protected-cell blockers',function()
  local e,c,app,q,p,plan,service,production=surveyedFixture();service:startWork(p,plan)
  local fault=false;local blocked
  for _=1,6500 do
    local barrier=p.site.barrier
    if barrier and barrier.jobId and q.state.jobs[barrier.jobId].status=='completed' and not fault then
      local job=q.state.jobs[barrier.jobId];local save=app.save
      function app:save() return false,'barrier checkpoint unavailable' end
      assert(not pcall(service.workTick,service,p,plan));assert(job.report,'failed checkpoint discarded barrier receipt')
      eq(p.site.barrier.jobId,job.id);app.save=save;fault=true
      service=require('autobuilder.build.site_service').new(app,c,e,q,production)
    else service:workTick(p,plan) end
    for _,j in pairs(q.state.jobs) do if j.status~='completed' then
      j.workerId=12;j.status='completed';j.completedAt=100
      if j.type=='SURVEY_SITE' then
        j.progress=#j.siteSurvey.columns;j.siteReport={identity=plan.identity,region=j.siteSurvey.region,observations={}}
        for _,col in ipairs(j.siteSurvey.columns) do j.siteReport.observations[#j.siteReport.observations+1]={x=col.x,z=col.z,y=col.minY,status='empty',name='minecraft:air'} end
      else
        j.progress=#j.blocks;j.report={counts={correct=j.progress},entries={}}
        local isBarrier=j.key:find(':barrier:',1,true)
        if isBarrier and j.siteWork.stage=='verify' and not blocked or not isBarrier and j.siteWork.region==1 and (j.siteWork.stage=='clear' or j.siteWork.stage=='verify') then
          j.progress=j.progress-1;j.report.counts.correct=j.progress;j.report.counts.unsupported=1
          local b=j.blocks[1];j.report.entries={{x=b.x,y=b.y,z=b.z,status='unsupported',actual={name=isBarrier and 'minecraft:chest' or 'minecraft:water'},reason=isBarrier and 'protected storage' or 'external inflow'}}
          if isBarrier then blocked=U.copy(j.report.entries[1]) end
        end
      end
    end end
    if p.site.work.status=='completed' then break end
  end
  assert(fault and blocked);eq(p.site.barrier.status,'blocked');eq(p.phase,'site_blocked')
  eq(p.site.barrier.defects[1].x,blocked.x);assert(p.error:find('protected storage',1,true))
  assert(service:prepared(p,plan,2),'protected boundary withheld unrelated dry regions')
  local before=q.state.sequence;for _=1,20 do service:workTick(p,plan) end;eq(q.state.sequence,before)
end)
