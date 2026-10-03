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
