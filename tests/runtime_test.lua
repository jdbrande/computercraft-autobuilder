local S=require('tests.support')
local function env(id,files)
  local e={fs=files or S.fs(),textutils=S.codec(),turtle=S.turtle(),now=100,packets={},screen={}}
  e.os={getComputerID=function() return id end,epoch=function() return e.now*1000 end}
  e.peripheral={getNames=function() return {'left'} end,getType=function() return 'modem' end,call=function() return true end}
  e.rednet={isOpen=function() return true end,open=function() end,send=function(to,m,p) e.packets[#e.packets+1]={to=to,message=m,protocol=p}; return true end}
  e.gps={locate=function() return nil end}
  e.term={getSize=function() return 51,19 end,clear=function() e.screen={} end,setCursorPos=function(_,y) e.row=y end,write=function(s) e.screen[e.row]=s end}
  return e
end
local function cfg(role,id)
  return require('autobuilder.config').load({role=role,controllerId=id})
end
local function deliver(from,to)
  local p=from.packets[#from.packets]; assert(p)
  return to:receive(p.message.sender,p.message,p.protocol)
end

test('real controller and worker models communicate and survive both restarts',function()
  local R=require('autobuilder.core.runtime'); local ce,we=env(7),env(12)
  local c=R.new(cfg('controller'),ce); local w=R.new(cfg('worker',7),we)
  assert(w:tick()); assert(deliver(we,c)); assert(deliver(ce,w))
  eq(c.state.workers['12'].telemetry.fuel,100); eq(w.agent.connected,true)
  assert(c:command('workers')); c:draw(); assert(table.concat(ce.screen,'\n'):find('12'))
  local c2=R.new(cfg('controller'),ce); eq(c2.state.workers['12'].online,false)
  we.now=116; assert(w:tick()); assert(deliver(we,c2)); assert(deliver(ce,w))
  local w2=R.new(cfg('worker',7),we); assert(w2.state.boot>w.state.boot)
  assert(w2:tick()); assert(deliver(we,c2)); eq(c2.state.workers['12'].boot,w2.state.boot)
  assert(w2:updateGPS()); eq(w2.state.position.known,false)
  we.gps.locate=function() return 100,64,-200 end
  assert(w2:updateGPS()); eq(w2.state.position.x,100)
  we.gps.locate=function() return nil end
  assert(w2:updateGPS()); eq(w2.state.position.x,100); eq(w2.state.position.source,'local')
end)
test('runtime refuses corrupt and foreign checkpoints instead of resetting identity',function()
  local R=require('autobuilder.core.runtime'); local e=env(12)
  R.new(cfg('worker',7),e)
  e.os.getComputerID=function() return 13 end
  assert(not pcall(R.new,cfg('worker',7),e))
  e.fs.files['/autobuilder/data/worker.state']='broken'
  e.fs.files['/autobuilder/data/worker.state.bak']=nil
  assert(not pcall(R.new,cfg('worker',7),e))
end)
test('runtime recovery never moves a turtle and interrupted turn requires heading',function()
  local R=require('autobuilder.core.runtime'); local e=env(12)
  local w=R.new(cfg('worker',7),e)
  w.state.position={x=1,y=64,z=2,known=true,heading='north',pending={action='turnRight'}}
  assert(w:save())
  local restored=R.new(cfg('worker',7),e)
  eq(restored.state.status,'recovery_required'); eq(e.turtle.calls,0)
  e.gps.locate=function() return 1,64,2 end
  assert(restored:updateGPS()); eq(restored.state.position.heading,nil)
  assert(not restored.navigation:forward()); eq(e.turtle.calls,0)
end)
test('malformed runtime packets cannot alter durable worker registry',function()
  local R=require('autobuilder.core.runtime'); local e=env(7)
  local c=R.new(cfg('controller'),e)
  assert(not c:receive(12,{type='register'},'autobuilder.v1'))
  eq(next(c.state.workers),nil)
end)

test('backup recovery uses a fresh boot generation after last primary was lost',function()
  local R=require('autobuilder.core.runtime'); local e=env(12)
  local w=R.new(cfg('worker',7),e); assert(w:tick())
  local previous=w.state.boot
  e.now=101
  local second=R.new(cfg('worker',7),e)
  assert(second.state.boot>previous)
  local lastBoot=second.state.boot
  e.fs.files['/autobuilder/data/worker.state']='corrupt'
  e.now=102
  local recovered=R.new(cfg('worker',7),e)
  assert(recovered.state.boot>lastBoot,'boot generation reused after backup recovery')
end)

test('runtime event loop handles heartbeats while GPS coroutine waits',function()
  local R=require('autobuilder.core.runtime'); local e=env(12)
  local timers=0
  e.os.startTimer=function() timers=timers+1; return timers end
  e.os.pullEvent=function(filter)
    while true do
      local event={coroutine.yield(filter)}
      if event[1]=='terminate' then error('Terminated') end
      if not filter or event[1]==filter then return table.unpack(event) end
    end
  end
  e.sleep=function() e.os.pullEvent('timer') end
  e.gps.locate=function() e.os.pullEvent('modem_message'); return 1,64,2 end
  -- A small event broadcaster mirrors parallel's independent event filters.
  -- Production modules, serialization, networking, and app loop remain real.
  e.parallel={waitForAny=function(...)
    local threads,filters={},{}
    for i,fn in ipairs({...}) do threads[i]=coroutine.create(fn); local ok,f=coroutine.resume(threads[i]); assert(ok,f); filters[i]=f end
    local function broadcast(ev)
      for i,co in ipairs(threads) do
        if not filters[i] or filters[i]==ev[1] then
          local ok,f=coroutine.resume(co,table.unpack(ev)); assert(ok,f); filters[i]=f
          if coroutine.status(co)=='dead' then return true end
        end
      end
    end
    local req=e.packets[#e.packets].message.id
    broadcast({'rednet_message',7,{version=1,id='7:1:1',sender=7,boot=1,sequence=1,type='ack',payload={requestId=req}},'autobuilder.v1'})
    e.now=106; broadcast({'timer',1})
    eq(e.packets[#e.packets].message.type,'heartbeat')
    assert(broadcast({'char','q'}))
  end}
  local app=R.run(cfg('worker',7),e)
  eq(app.agent.connected,true); eq(app.state.position.known,false)
end)

test('backup pose requires explicit heading confirmation before any movement',function()
  local R=require('autobuilder.core.runtime'); local e=env(12)
  local config=cfg('worker',7); config.initialPosition={x=0,y=64,z=0,heading='north'}
  local w=R.new(config,e)
  -- Backup is a clean pre-turn snapshot, primary is the interrupted turn intent.
  w.state.position.pending={action='turnRight'}; w:save()
  e.fs.files['/autobuilder/data/worker.state']='corrupt'
  local recovered=R.new(config,e)
  eq(recovered.state.status,'recovery_required'); eq(recovered.state.position.heading,nil)
  e.gps.locate=function() return 0,64,0 end; recovered:updateGPS()
  assert(not recovered.navigation:forward()); eq(e.turtle.calls,0)
  assert(recovered:confirmPose({x=0,y=64,z=0},'east'))
  eq(recovered.state.position.heading,'east'); eq(recovered.state.status,'idle')
end)

test('controller scheduling survives its timer being consumed by a yielding peripheral call',function()
  local R=require('autobuilder.core.runtime'); local e=env(1)
  local timers,latest=0,nil; local pending=false
  e.os.startTimer=function() timers=timers+1; latest=timers; return timers end
  e.os.cancelTimer=function() end
  e.os.pullEvent=function(filter)
    while true do
      local event={coroutine.yield(filter)}
      if not filter or filter==event[1] then return table.unpack(event) end
    end
  end
  e.sleep=function() e.os.pullEvent('sleep') end
  e.peripheral.call=function()
    if pending then pending=false; e.os.pullEvent('task_complete') end
    return true
  end
  e.parallel={waitForAny=function(...)
    local threads,filters={},{}
    for i,fn in ipairs({...}) do
      threads[i]=coroutine.create(fn)
      local ok,f=coroutine.resume(threads[i]); assert(ok,f); filters[i]=f
    end
    local function broadcast(event)
      for i,co in ipairs(threads) do
        if not filters[i] or filters[i]==event[1] then
          local ok,f=coroutine.resume(co,table.unpack(event)); assert(ok,f); filters[i]=f
          if coroutine.status(co)=='dead' then return true end
        end
      end
    end
    local telemetry={label='Builder',status='idle',position={known=false},fuel=1600,inventory={used=1,slots=16},capabilities={telemetry=true}}
    pending=true
    broadcast({'rednet_message',2,{version=1,id='2:1:1',sender=2,boot=1,sequence=1,type='register',payload=telemetry},'autobuilder.v1'})
    local yielding=false; for _,filter in pairs(filters) do if filter=='task_complete' then yielding=true end end
    assert(yielding,'fixture did not enter a yielding peripheral call')
    broadcast({'rednet_message',3,{version=1,id='3:1:1',sender=3,boot=1,sequence=1,type='register',payload=telemetry},'autobuilder.v1'})
    e.now=102; broadcast({'timer',latest}) -- discarded by peripheral's event filter
    broadcast({'task_complete'})
    assert(timers>1,'scheduler timer was lost forever while the peripheral yielded')
    e.now=140; broadcast({'timer',latest})
    assert(broadcast({'char','q'}))
  end}
  local app=R.run(cfg('controller'),e)
  eq(app.state.workers['2'].online,false) -- periodic expiration still runs
  assert(app.state.workers['3'],'network packet was discarded during a yielding peripheral call')
end)

test('disabled worker automation retains an active return task without physical effects',function()
  local R=require('autobuilder.core.runtime');local e=env(12);e.turtle.fuel=1000
  local c=require('tests.loaded_config').load({role='worker',controllerId=7,automation={enabled=false},
    initialPosition={x=3,y=64,z=0,heading='west'},depot={x=0,y=64,z=0},minimumFuelReserve=0})
  local w=R.new(c,e);w.state.currentTask={id='task:7:1',type='RETURN_HOME',phase='work'};w:save()
  w:workStep();eq(e.turtle.calls,0);eq(w.state.currentTask.phase,'work')
end)

test('fleet status and limits use normal controller commands persist across reboot and draw role diagnostics',function()
  local R=require('autobuilder.core.runtime');local e=env(7);local c=R.new(cfg('controller'),e)
  assert(c:command('fleet limit mining 1 3'));assert(c:command('fleet status'));eq(c.state.view,'fleet')
  c:draw();assert(table.concat(e.screen,'\n'):find('mining',1,true))
  assert(not c:command('fleet limit mining 4 2'));assert(not c:command('fleet limit missing 0 1'))
  c=R.new(cfg('controller'),e);eq(require('autobuilder.core.scaling').limits(c.state,c.config,'mining').max,3)
end)

test('traffic home requests never displace offline busy paused or already home workers',function()
  for _,mode in ipairs({'idle','offline','busy','paused','home'}) do
    local e=env(7);local c=require('autobuilder.core.runtime').new(cfg('controller'),e);c.config.chunkLoading.enabled=false
    local target={x=1,y=1,z=0,known=true};local from={x=0,y=1,z=0,known=true}
    c.state.workers['12']={id=12,online=true,boot=1,sequence=0,telemetry={status='work',position=from}}
    c.state.workers['13']={id=13,online=mode~='offline',boot=2,sequence=0,telemetry={status=mode=='paused' and 'paused' or 'idle',
      position=target,depot=mode=='home' and target or {x=5,y=1,z=0},capabilities={returnCargoV1=true}}}
    local j=c.automation.queue:submit('VERIFY',{blocks={{x=1,y=0,z=0,name='minecraft:stone',state={}}}},{})
    j.workerId=12;j.status='running'
    if mode=='busy' then c.state.jobs.other={id='other',workerId=13,status='running'} end
    local ok=c.automation:handle(12,{type='task_reserve',boot=1,sequence=1,payload={jobId=j.id,from=from,target=target}})
    assert(not ok);local n=0;for _ in pairs(c.state.automation.returns) do n=n+1 end
    eq(n,mode=='idle' and 1 or 0)
  end
end)


test('controller drains a queued network burst in bounded turns without losing or reordering packets',function()
  local R=require('autobuilder.core.runtime');local e=env(1);local timer=0;local blocked=false
  local processed,turnCount={},0
  e.os.startTimer=function() timer=timer+1;return timer end;e.os.cancelTimer=function() end
  e.os.pullEvent=function(filter)
    turnCount=0
    while true do local ev={coroutine.yield(filter)};if not filter or ev[1]==filter then return table.unpack(ev) end end
  end
  e.sleep=function() e.os.pullEvent('sleep') end
  e.peripheral.call=function(_,method)
  if blocked or blockLists and method=='list' then blocked=false;e.os.pullEvent('task_complete') end
  if method=='list' then return {} end;return true
 end
  local send=e.rednet.send;e.rednet.send=function(to,m,p)
    if m.type=='ack' then turnCount=turnCount+1;assert(turnCount<=8,'unbounded message burst exceeded CraftOS turn budget');processed[#processed+1]=to end
    return send(to,m,p)
  end
  e.parallel={waitForAny=function(...)
    local threads,filters={},{}
    for i,fn in ipairs({...}) do threads[i]=coroutine.create(fn);local ok,f=coroutine.resume(threads[i]);assert(ok,f);filters[i]=f end
    local function broadcast(ev)
      for i,co in ipairs(threads) do if not filters[i] or filters[i]==ev[1] then
        local ok,f=coroutine.resume(co,table.unpack(ev));assert(ok,f);filters[i]=f;if coroutine.status(co)=='dead' then return true end
      end end
    end
    local telemetry={label='Worker',status='idle',position={known=false},fuel=1000,inventory={used=0,slots=16},capabilities={telemetry=true}}
    local function packet(id) return {'rednet_message',id,{version=1,id=id..':1:1',sender=id,boot=1,sequence=1,type='register',payload=telemetry},'autobuilder.v1'} end
    blocked=true;broadcast(packet(2))
    for id=3,22 do broadcast(packet(id)) end
    broadcast({'task_complete'})
    for _=1,30 do if #processed==21 then break end;e.now=e.now+0.1;broadcast({'timer',timer}) end
    eq(#processed,21);for i,id in ipairs(processed) do eq(id,i+1) end
    assert(broadcast({'char','q'}))
  end}
  local app=R.run(cfg('controller'),e);for id=2,22 do assert(app.state.workers[tostring(id)]) end
end)

test('runtime reports changing equipment without probing physical APIs or changing configured roles',function()
  local e=env(12);local left='minecraft:diamond_pickaxe'
  e.turtle.getEquippedLeft=function() return left and {name=left} or nil end
  e.turtle.getEquippedRight=function() return nil end
  local c=cfg('worker',7);local w=require('autobuilder.core.runtime').new(c,e)
  local before=e.turtle.calls;local t=w.agent:telemetry();assert(t.health);eq(t.health.left,left);eq(t.health.software.status,'unmanaged')
  left=nil;t=w.agent:telemetry();eq(t.health.left,'none');eq(e.turtle.calls,before)
  eq(t.capabilities.telemetry,true)
end)

-- Broadcast through parallel's real filter semantics while an ordinary peripheral
-- call is suspended. Keep runtime, dispatcher, storage and command handlers real.
local function operatorLoop(events,before,blockLists)
 local R=require('autobuilder.core.runtime');local e=env(1);local timer=0;local blocked=false
 e.os.startTimer=function() timer=timer+1;return timer end;e.os.cancelTimer=function() end
 e.os.pullEvent=function(filter)
  while true do local ev={coroutine.yield(filter)};if not filter or ev[1]==filter then return table.unpack(ev) end end
 end
 e.sleep=function() e.os.pullEvent('sleep') end
 e.peripheral.call=function(_,method)
  if blocked or blockLists and method=='list' then blocked=false;e.os.pullEvent('task_complete') end
  if method=='list' then return {} end;return true
 end
 local replies={};e.os.queueEvent=function(...) replies[#replies+1]={...} end
 local app,commands;local original=R.new
 R.new=function(...)
  app=original(...);commands={};local command=app.command
  app.command=function(self,line) commands[#commands+1]=line;return command(self,line) end
  return app
 end
 e.parallel={waitForAny=function(...)
  local threads,filters={},{}
  for i,fn in ipairs({...}) do threads[i]=coroutine.create(fn);local ok,f=coroutine.resume(threads[i]);assert(ok,f);filters[i]=f end
  local function broadcast(ev)
   for i,co in ipairs(threads) do if not filters[i] or filters[i]==ev[1] then
    local ok,f=coroutine.resume(co,table.unpack(ev));assert(ok,f);filters[i]=f;if coroutine.status(co)=='dead' then return true end
   end end
  end
  if before then before(broadcast,app) end
  blocked=true
  broadcast({'rednet_message',2,{version=1,id='2:1:1',sender=2,boot=1,sequence=1,type='register',payload={label='Worker',status='idle',position={known=false},fuel=1000,inventory={used=0,slots=16},capabilities={telemetry=true}}},'autobuilder.v1'})
  local yielding=false;for _,f in pairs(filters) do if f=='task_complete' then yielding=true end end;assert(yielding)
  events(broadcast,app,commands,replies,function()
   broadcast({'task_complete'})
   for _=1,40 do e.now=e.now+.1;broadcast({'timer',timer}) end
  end)
  assert(broadcast({'char','q'}))
 end}
 local ok,result=pcall(R.run,cfg('controller'),e);R.new=original;assert(ok,result)
 return app,commands,replies
end

test('yielding runtime retains keyboard paste and local commands once through the normal dispatcher',function()
 local app,commands,replies=operatorLoop(function(send,app,commands,replies,release)
  send({'paste','fleet limit mining 1 '});send({'char','9'});send({'key',14});send({'char','3'});send({'key',28})
  send({'autobuilder_command','script:1','fleet limit mining 2 4'});release()
  eq(#commands,2);eq(commands[1],'fleet limit mining 1 3');eq(commands[2],'fleet limit mining 2 4');eq(#replies,1);eq(replies[1][1],'autobuilder_command_result');eq(replies[1][2],'script:1');eq(replies[1][3],true)
  send(replies[1]);eq(#commands,2);eq(#replies,1)
  send({'paste','workers'});send({'key',28});eq(#commands,3);eq(commands[3],'workers')
 end)
 eq(require('autobuilder.core.scaling').limits(app.state,app.config,'mining').min,2)
end)

test('operator queue overflow discards a complete command and replies that discarded scripts were not executed',function()
 operatorLoop(function(send,app,commands,replies,release)
  send({'paste','fleet limit mining 1 3'})
  send({'autobuilder_command','discarded:1','fleet limit mining 2 4'})
  for _=1,140 do send({'char',' '}) end
  send({'char','q'});send({'char','N'});send({'char','P'});send({'key',28});release()
  eq(#commands,0);eq(app.page,0);eq(#replies,1);eq(replies[1][2],'discarded:1');eq(replies[1][3],false);assert(replies[1][4]:find('not executed',1,true))
  send({'paste','fleet limit mining 0 2'});send({'key',28});eq(#commands,1)
  eq(require('autobuilder.core.scaling').limits(app.state,app.config,'mining').max,2)
 end,function(send) send({'paste','fleet limit mining 1 3'}) end)
end)

test('overlong terminal commands are rejected as a whole and local command IDs and results are bounded',function()
 local e=env(1);local app=require('autobuilder.core.runtime').new(cfg('controller'),e);local replies={}
 e.os.queueEvent=function(...) replies[#replies+1]={...} end
 app:event('paste','fleet limit mining 1 3'..string.rep(' ',256));app:event('key',28)
 eq((app.state.fleet or {}).limits,nil);assert(app.state.commandResult:find('discarded',1,true))
 app:event('autobuilder_command','valid','fleet limit mining 1 3'..string.rep(' ',256));eq(replies[1][3],false)
 app:event('autobuilder_command',{},'workers');eq(#replies,1)
 app:event('paste','fleet limit mining 0 2');app:event('key',28)
 eq(require('autobuilder.core.scaling').limits(app.state,app.config,'mining').max,2)
end)

test('dashboard aliases use cached views and monitor failures never stop controller commands',function()
 local e=env(7);local c=cfg('controller');c.monitor={name='monitor_0',scale=.5,interval=1}
 local detached=true;local writes=0
 e.peripheral.wrap=function() if detached then return nil end;return {getSize=function() return 30,10 end,setTextScale=function() end,clear=function() end,setCursorPos=function() end,write=function() writes=writes+1 end} end
 local app=require('autobuilder.core.runtime').new(c,e)
 assert(app:command('fleet workers'));eq(app.state.view,'workers')
 assert(app:command('project list'));assert(app:command('dashboard'))
 e.peripheral.call=function() error('drawing queried a physical inventory') end
 app:draw();assert(app.monitorError);eq(app.state.view,'dashboard')
 detached=false;e.now=e.now+1;app:draw();eq(app.monitorError,nil);assert(writes>0)
 local before=writes;app:draw();eq(writes,before)
 local p=app.monitor.page;assert(app:event('monitor_touch','monitor_0',1,1));eq(app.monitor.page,p+1)
 assert(not app:command('fleet worker 99'));assert(not app:command('project status missing'))
end)

test('structured log disk failure cannot unwind a successful stock checkpoint',function()
 local e=env(7);e.textutils.serializeJSON=e.textutils.serialize
 local app=require('autobuilder.core.runtime').new(cfg('controller'),e)
 e.fs.fault.open='/autobuilder/logs/controller.events.jsonl'
 local l=app.automation.production.ledger
 assert(l:reserve('test-stock',{stone=1},{stone=1},{stone=1}))
 eq(l.state.leases['test-stock'].status,'held');assert(app.state.eventLogError:find('disk full',1,true))
 local saved=require('autobuilder.core.checkpoint').new(e.fs,e.textutils,'/autobuilder/data/controller.state'):load()
 eq(saved.inventoryLedger.leases['test-stock'].status,'held')
 e.fs.fault.open=nil;assert(l:receipt('test-stock',{stone=1},{stone=1},{},1));eq(app.state.eventLogError,nil)
end)

test('production failure events require a committed transition and omit unchanged retries',function()
 local e=env(7);local app=require('autobuilder.core.runtime').new(cfg('controller'),e);local events={}
 app.record=function(self,kind,fields) events[#events+1]={kind=kind,fields=fields};return true end
 local production=app.automation.production;local r=production:request({['minecraft:stone']=2},'test-event')
 eq(events[1].kind,'production_request');eq(events[2].kind,'requirement')
 local function states() local n=0;for _,event in ipairs(events) do if event.kind=='production_state' then n=n+1 end end;return n end
 local save=app.save;app.save=function() return false,'disk failed' end
 assert(not pcall(production.tick,production));eq(states(),0);eq(r.status,'queued')
 app.save=save;production:tick();eq(states(),1);eq(r.status,'blocked')
 production:tick();eq(states(),1)
end)

test('project events follow imported analyzed priority and pause checkpoints without status-query noise',function()
 local e=env(7);e.textutils.unserializeJSON=e.textutils.unserialize;e.textutils.serializeJSON=e.textutils.serialize
 e.fs.files['/event.json']=e.textutils.serialize({schema=1,size={x=1,y=1,z=1},palette={{name='minecraft:stone',state={}}},runs={{id=1,count=1}},metadata={},requirements={['minecraft:stone']=1}})
 local app=require('autobuilder.core.runtime').new(cfg('controller'),e);local events={}
 app.record=function(self,kind,fields)
  if kind=='project_state' then
   local saved=require('autobuilder.core.checkpoint').new(e.fs,e.textutils,'/autobuilder/data/controller.state'):load()
   eq(saved.automation.projects[fields.project].phase,fields.phase);events[#events+1]=fields
  end
  return true
 end
 assert(app:command('build import /event.json event'));eq(events[1].phase,'imported')
 assert(app:command('build analyze event'));eq(events[2].phase,'analyzed')
 assert(app:command('build priority event 80'));eq(events[3].priority,80)
 assert(app:command('project pause event'));eq(events[4].paused,true)
 assert(app:command('project pause event'));eq(#events,4)
 assert(app:command('project resume event'));eq(events[5].paused,false)
 assert(app:command('project status event'));eq(#events,5)
end)


test('overflow during a yielding command drain preserves its reply and rejects queued scripts without crashing',function()
 operatorLoop(function(send,app,commands,replies,release)
  app.config.storageInventories[1]='chest'
  send({'autobuilder_command','running','resources'})
  send({'autobuilder_command','queued:1','workers'});send({'autobuilder_command','queued:2','workers'})
  for _=1,10 do send({'task_complete'});if #commands>0 then break end end -- ordinary tick reads finish before resources
  eq(#commands,1);eq(commands[1],'resources')
  for _=1,140 do send({'char',' '}) end
  send({'task_complete'});eq(#replies,3)
  local seen={};for _,r in ipairs(replies) do assert(not seen[r[2]]);seen[r[2]]=r end
  eq(seen.running[3],true);eq(seen['queued:1'][3],false);eq(seen['queued:2'][3],false)
  send({'key',28});send({'paste','workers'});send({'key',28});eq(#commands,2)
 end,nil,true)
end)

test('quick monitor replacement redraws an identical cached page',function()
 local e=env(7);local c=cfg('controller');c.monitor={name='front',scale=.5,interval=1}
 local attached=true;local writes=0
 e.peripheral.wrap=function() if attached then return {getSize=function() return 30,10 end,setTextScale=function() end,
  clear=function() end,setCursorPos=function() end,write=function() writes=writes+1 end} end end
 local app=require('autobuilder.core.runtime').new(c,e);app:tick();app:draw();assert(writes>0)
 e.now=e.now+.1;attached=false;app:event('peripheral_detach','front');app:draw()
 e.now=e.now+.1;attached=true;writes=0;app:event('peripheral','front')
 e.now=e.now+1;app:draw();assert(writes>0,'replacement monitor kept an old screen signature and stayed blank')
end)
