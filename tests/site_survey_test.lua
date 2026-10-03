local U=require('autobuilder.core.util')
local function fixture()
  local w=require('tests.build_world').new()
  local c={minimumFuelReserve=0,maxTravelDistance=64,movementRetries=1,depot=U.copy(w.pose)}
  local j={type='SURVEY_SITE',id='survey',clearanceY=4,bounds={min={x=0,y=-2,z=0},max={x=3,y=4,z=2}},
    siteSurvey={identity=string.rep('a',64),region=1,columns={{x=2,z=0,minY=-2,clearanceY=4,foundationY=1},{x=3,z=2,minY=0,clearanceY=4,foundationY=1}}}}
  local saved;local save=function() saved=U.copy(j);return true end
  local nav=require('autobuilder.core.navigation').new(w.turtle,w.pose,c,function() return true end)
  return w,c,j,nav,save,function() return U.copy(saved) end
end

test('native site survey records real surface and empty columns without digging or placing',function()
  local w,c,j,nav,save=fixture();w.blocks['2,1,0']={name='minecraft:dirt',state={}}
  local survey=require('autobuilder.build.site_survey').new(j,{turtle=w.turtle},c,nav,save)
  for _=1,80 do survey:step();if j.phase=='completed' then break end end
  eq(j.phase,'completed');eq(j.progress,2);eq(w.digs,0);eq(w.places,0)
  local observations=j.siteReport.observations
  eq(observations[1].name,'minecraft:dirt');eq(observations[1].y,1);eq(observations[1].status,'surface')
  eq(observations[2].name,'minecraft:air');eq(observations[2].y,0);eq(observations[2].status,'empty')
  assert(require('autobuilder.build.site_survey').validReport(j,j.siteReport,true))
end)

test('site survey resumes bounded column progress after restart and pauses without moving',function()
  local w,c,j,nav,save,read=fixture();w.blocks['2,-1,0']={name='minecraft:stone',state={}}
  local M=require('autobuilder.build.site_survey');local survey=M.new(j,{turtle=w.turtle},c,nav,save)
  for _=1,30 do survey:step();if w.pose.x==2 and w.pose.y==2 then break end end
  j=assert(read());survey=M.new(j,{turtle=w.turtle},c,nav,function() return true end)
  j.paused=true;local at=U.copy(w.pose);survey:step();eq(U.distance(at,w.pose),0)
  j.paused=false;for _=1,80 do survey:step();if j.phase=='completed' then break end end
  eq(j.phase,'completed');eq(#j.siteReport.observations,2);eq(j.siteReport.observations[1].y,-1)
end)

test('site survey rejects changed duplicate columns malformed reports and failed observation checkpoints',function()
  local w,c,j,nav=fixture();local M=require('autobuilder.build.site_survey')
  assert(M.validContract(j));local bad=U.copy(j);bad.siteSurvey.columns[2]=U.copy(bad.siteSurvey.columns[1]);assert(not M.validContract(bad))
  bad=U.copy(j);bad.siteSurvey.columns[1].x=500;assert(not M.validContract(bad))
  local engine=M.new(j,{turtle=w.turtle},c,nav,function() if j.progress and j.progress>0 then return false,'disk full' end;return true end)
  w.blocks['2,3,0']={name='minecraft:stone',state={}}
  for _=1,20 do engine:step() end
  eq(j.progress,0);eq(#j.siteReport.observations,0);local at=U.copy(w.pose);engine:step();eq(U.distance(at,w.pose),0)
  local report={identity=j.siteSurvey.identity,region=1,observations={{x=2,z=0,y=1000,name='minecraft:stone',status='surface'}}}
  assert(not M.validReport(j,report,false))
end)

test('site survey protocol and controller receipts reject changed observations before completion',function()
  local w,c,j=fixture();local T=require('autobuilder.core.task_messages')
  assert(T.validate('task_assign',{job=j}),'site survey assignment unsupported')
  local state={workers={},jobs={}};local Q=require('autobuilder.core.workflows').new(state,function() return true end,function() return 100 end,7)
  local job=Q:submit('SURVEY_SITE',j,{});job.workerId=12;job.status='running'
  local report={identity=j.siteSurvey.identity,region=1,observations={{x=2,y=1,z=0,status='surface',name='minecraft:stone'}}}
  local p={jobId=job.id,phase='work',progress=1,siteReport=report}
  assert(T.validate('task_progress',p));assert(Q:progress(12,p));eq(job.siteReport.observations[1].y,1)
  local bad=U.copy(p);bad.siteReport.observations[1].y=0;assert(not Q:progress(12,bad),'changed observation accepted')
  bad=U.copy(p);bad.phase='completed';assert(not Q:progress(12,bad),'incomplete survey accepted')
  bad=U.copy(p);bad.siteReport.observations[1].status='invented';assert(not T.validate('task_progress',bad))
  report.observations[2]={x=3,y=0,z=2,status='empty',name='minecraft:air'};p.progress=2;p.phase='completed'
  assert(Q:progress(12,p));eq(job.status,'completed')
end)

test('site survey retains an unreachable column and continues another accessible column',function()
  local w,c,j,nav,save=fixture();j.siteSurvey.columns[2].x=0
  w.blocks['2,4,0']={name='minecraft:stone',state={}}
  local engine=require('autobuilder.build.site_survey').new(j,{turtle=w.turtle},c,nav,save)
  for _=1,80 do engine:step();if j.phase=='completed' then break end end
  eq(j.phase,'completed');eq(j.siteReport.observations[1].status,'blocked')
  eq(j.siteReport.observations[1].x,2);assert(j.siteReport.observations[1].reason)
  eq(j.siteReport.observations[2].status,'empty');eq(w.digs,0)
end)

test('survey retains territory until the turtle leaves its interior after its final observation',function()
  local w,c,j,nav,save=fixture();w.blocks['2,1,0']={name='minecraft:stone',state={}}
  local engine=require('autobuilder.build.site_survey').new(j,{turtle=w.turtle},c,nav,save)
  for _=1,80 do engine:step();if j.progress==2 then break end end
  eq(j.progress,2);assert(j.phase~='completed','worker released interior before reaching clearance')
  local saved=U.copy(j);local engine2=require('autobuilder.build.site_survey').new(saved,{turtle=w.turtle},c,nav,function() return true end)
  for _=1,30 do engine2:step();if saved.phase=='completed' then break end end
  eq(saved.phase,'completed');eq(w.pose.y,j.clearanceY);eq(#saved.siteReport.observations,2)
end)
