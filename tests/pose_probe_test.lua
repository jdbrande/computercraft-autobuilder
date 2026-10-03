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

test('backup recovery restores probe heading evidence before its mandatory backtrack',function()
  local f=fixture();f:step();f:grant();f:step();eq(f.forward,1)
  assert(f.driver:observe(U.copy(f.actual)));eq(f.app.state.poseRecovery.stage,'return')
  f.app.state.position.heading=nil;f.app.state.position.known=false;f.app.state.position.uncertain=true;f.app:save();f:boot(true)
  for _=1,6 do f:step() end
  eq(f.back,1);eq(f.app.state.position.heading,'east');f:ack();assert(f.recovered)
end)

test('workers without a configured depot retain the probe round trip fuel reserve',function()
  local f=fixture();f.config.depot=nil;f:step();f:grant()
  for _=1,8 do f:step() end;f:ack();eq(f.forward,1);eq(f.back,1);eq(f.fuel,98)
  f=fixture();f.config.depot=nil;f.fuel=1;f:step();f:grant();f:step();eq(f.forward,0)
end)

test('mining only workers accept matching pose controls without enabling generic effects',function()
  local f=fixture();f.app.state.currentTask.type='MINE';f.config.mining.enabled=true;f.config.automation.enabled=false
  f:step();local r=assert(f.app.state.poseRecovery)
  local executor=require('autobuilder.workers.executor').new(f.app,f.config,{}, {send=function() return true end},function() return f.now end)
  f.app.poseRecovery=f.driver
  local function control(sender,kind,sequence)
    return executor:handle(sender,{boot=1,sequence=sequence,type=kind,payload={jobId=r.jobId,sequence=r.sequence,origin=U.copy(r.origin),granted=true}})
  end
  assert(not control(8,'task_pose_grant',1));assert(control(7,'task_pose_grant',2),'mining pose grant rejected')
  for _=1,8 do f:step() end
  assert(control(7,'task_pose_ack',3));assert(f.recovered);eq(f.app.state.poseRecovery,nil)
end)

test('settled physical recovery retries its durable receipt even after GPS disappears',function()
  local f=fixture();f:step();f:grant();for _=1,6 do f:step() end
  eq(f.app.state.poseRecovery.stage,'settling');local before=#f.packets
  f.noGPS=true;f:step();assert(#f.packets>before,'settled receipt incorrectly depends on another GPS fix')
  eq(f.packets[#f.packets].kind,'task_pose_done');f:ack();assert(f.app.state.poseReceipt)
end)

test('restored probe heading does not bypass validation of a pending backtrack journal',function()
  local f=fixture();f:step();f:grant();f:step();assert(f.driver:observe(U.copy(f.actual)))
  local p=f.app.state.position;p.heading=nil;p.pending={action='back',from={x=9,y=64,z=8,heading='east'},to={x=6,y=64,z=8,heading='east'}};p.uncertain=true
  assert(not f.driver:observe(U.copy(f.actual)));eq(f.back,0);assert(p.pending);eq(p.heading,nil)
end)

test('a new controller acknowledgement revokes an unexecuted old grant and fences delayed controls',function()
  local f=fixture();f:step();f:grant();f.app.state.controllerBoot=1
  local messages={};local network={send=function(_,_,kind,p) messages[#messages+1]={kind=kind,p=p};return true,'request' end}
  local agent=require('autobuilder.workers.agent').new(f.app.state,f.config,network,S.turtle(),function() return f.app:save() end)
  assert(agent:tick(f.now));assert(agent:handle(7,{type='ack',boot=2,payload={requestId='request'}},f.now))
  eq(f.app.state.controllerBoot,2);assert(not f.app.state.poseRecovery.granted,'old controller grant survived new boot acknowledgement')
  local ex=require('autobuilder.workers.executor').new(f.app,f.config,{},network,function() return f.now end);f.app.poseRecovery=f.driver
  local r=f.app.state.poseRecovery
  assert(not ex:handle(7,{boot=1,sequence=100,type='task_pose_grant',payload={jobId=r.jobId,sequence=r.sequence,origin=r.origin,granted=true}}),'delayed old controller grant was accepted')
  eq(agent:telemetry().controllerBoot,2)
end)
