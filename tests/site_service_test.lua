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
