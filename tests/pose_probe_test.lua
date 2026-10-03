local U=require('autobuilder.core.util')
local S=require('tests.support')
local function fixture()
  local f={actual={x=8,y=64,z=8,heading='east'},forward=0,back=0,fuel=100,now=100,packets={}}
  local config=require('tests.loaded_config').load({role='worker',controllerId=7,minimumFuelReserve=0,depot={x=8,y=64,z=8},automation={courier=true}})
  local app={state={position={x=8,y=64,z=8,known=true},currentTask={id='task:7:1',type='RETURN_HOME',phase='blocked',poseBlocked=true}}}
  function app:save() if f.failSave then return false,'disk full' end;f.saved=U.copy(self.state);return true end
  function app:poseRecovered() f.recovered=true end
  local t={getFuelLevel=function() return f.fuel end,inspect=function() return f.obstructed==true,{name='minecraft:stone'} end}
  t.forward=function() f.forward=f.forward+1;f.actual.x=f.actual.x+1;f.fuel=f.fuel-1;if f.crash then f.crash=false;error('power lost after probe') end;return true end
  t.back=function() f.back=f.back+1;f.actual.x=f.actual.x-1;f.fuel=f.fuel-1;if f.crashBack then f.crashBack=false;error('power lost after backtrack') end;return true end
  local gps={locate=function() if not f.noGPS then return U.copy(f.actual) end;return nil,'GPS unavailable' end}
  local net={send=function(_,_,kind,p) f.packets[#f.packets+1]={kind=kind,p=U.copy(p)};return true end}
  function f:boot(restore)
    if restore then app.state=U.copy(self.saved) end
    app.navigation=require('autobuilder.core.navigation').new(t,app.state.position,config,function() return app:save() end)
    self.driver=require('autobuilder.workers.pose_recovery').new(app,config,{turtle=t},net,function() return self.now end,gps)
    self.app=app;self.config=config
  end
  function f:step() self.now=self.now+config.heartbeatInterval;return self.driver:step() end
  function f:grant()
    local r=assert(app.state.poseRecovery);assert(self.driver:handle('task_pose_grant',{jobId=r.jobId,sequence=r.sequence,origin=U.copy(r.origin),granted=true}))
  end
  function f:ack()
    local r=assert(app.state.poseRecovery);assert(self.driver:handle('task_pose_ack',{jobId=r.jobId,sequence=r.sequence,origin=U.copy(r.origin)}))
  end
  f:boot();return f
end

test('heading probe needs a grant and returns to its origin before releasing task recovery',function()
  local f=fixture();assert(f.driver:needed());f:step();eq(f.forward,0);eq(f.packets[#f.packets].kind,'task_pose_reserve')
  f:grant();for _=1,8 do f:step() end
  eq(f.forward,1);eq(f.back,1);eq(f.actual.x,8);eq(f.app.state.position.heading,'east')
  eq(f.packets[#f.packets].kind,'task_pose_done');assert(not f.recovered)
  f:ack();assert(f.recovered);eq(f.app.state.poseRecovery,nil)
end)

test('probe and backtrack post effect reboots reconcile GPS without repeating either move',function()
  for _,cut in ipairs({'crash','crashBack'}) do
    local f=fixture();f:step();f:grant();f[cut]=true
    for _=1,8 do f:step();if not f[cut] then break end end
    f:boot(true);for _=1,10 do f:step() end;f:ack()
    eq(f.forward,1);eq(f.back,1);eq(f.actual.x,8);eq(f.app.state.position.heading,'east')
  end
end)

test('GPS outages and unrelated fixes never authorize another blind probe or erase its intent',function()
  local f=fixture();f:step();f:grant();f.crash=true;f:step();eq(f.forward,1)
  f.noGPS=true;f:boot(true);for _=1,5 do f:step() end;eq(f.forward,1);eq(f.back,0);assert(f.app.state.poseRecovery)
  f.noGPS=false;f.actual.x=15;f:step();eq(f.back,0);eq(f.app.state.poseRecovery.stage,'probe')
  f.actual.x=9;for _=1,8 do f:step() end;f:ack();eq(f.forward,1);eq(f.back,1)
end)

test('heading probe refuses paused disabled protected unfueled obstructed and unsaved effects',function()
  for _,cause in ipairs({'paused','disabled','protected','unloaded','fuel','obstructed','save'}) do
    local f=fixture();f:step();f:grant()
    if cause=='paused' then f.app.state.currentTask.paused=true
    elseif cause=='disabled' then f.config.automation.enabled=false
    elseif cause=='protected' then f.config.restrictedAreas={{min={x=9,y=64,z=8},max={x=9,y=64,z=8}}}
    elseif cause=='unloaded' then f.config.chunkLoading.enabled=true;f.config.chunkLoading.areas={}
    elseif cause=='fuel' then f.fuel=1
    elseif cause=='obstructed' then f.obstructed=true
    else f.failSave=true end
    pcall(function() f:step() end);eq(f.forward,0);eq(f.back,0)
  end
end)

test('pose controls reject changed identity and premature completion acknowledgements',function()
  local f=fixture();f:step();local r=f.app.state.poseRecovery
  assert(not f.driver:handle('task_pose_ack',{jobId=r.jobId,sequence=r.sequence,origin=r.origin}))
  assert(not f.driver:handle('task_pose_grant',{jobId=r.jobId,sequence=r.sequence+1,origin=r.origin,granted=true}))
  assert(not f.driver:handle('task_pose_grant',{jobId=r.jobId,sequence=r.sequence,origin={x=9,y=64,z=8},granted=true}))
  f:step();eq(f.forward,0)
end)
