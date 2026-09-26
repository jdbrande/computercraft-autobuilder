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
