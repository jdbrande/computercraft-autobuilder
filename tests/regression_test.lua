local S=require('tests.support')
test('log records retain newline when truncated',function()
  local f=S.fs(); local log=require('autobuilder.core.log').new(f,'log',{maxBytes=40,backups=2},function() return 0 end)
  assert(log:write('ERROR',string.rep('x',100)))
  eq(f.files.log:sub(-1),'\n'); assert(#f.files.log<=40)
end)

test('config rejects labels and capabilities which cannot be sent on the wire',function()
  local C=require('autobuilder.config')
  for _,label in ipairs({'','bad\nname',string.rep('a',65)}) do
    assert(not pcall(C.load,{role='worker',controllerId=7,label=label}))
  end
  for _,key in ipairs({'','bad\nkey',string.rep('a',65)}) do
    assert(not pcall(C.load,{capabilities={[key]=true}}))
  end
  local caps={}; for i=1,33 do caps['cap'..i]=true end
  assert(not pcall(C.load,{capabilities=caps}))
end)

test('navigation goHome follows coordinates and stops at bounded obstacles',function()
  local t=S.turtle(); local p={known=true,x=2,y=65,z=1,heading='south'}
  local n=require('autobuilder.core.navigation').new(t,p,{depot={x=0,y=64,z=0},minimumFuelReserve=0,movementRetries=2},function() return true end)
  assert(n:goHome()); eq(p.x,0); eq(p.y,64); eq(p.z,0)
  assert(n:face('east')); assert(n:back()); eq(p.x,-1)
  local before=t.calls; t.blocked=true
  assert(not n:forward()); eq(t.calls,before+2); eq(p.x,-1)
  assert(not n:goTo({x=1000,y=64,z=0}))
end)
test('navigation face cannot report a known heading from an uncertain pose',function()
  local t=S.turtle(); local p={known=true,x=0,y=64,z=0,heading='north',uncertain=true}
  local n=require('autobuilder.core.navigation').new(t,p,{},function() return true end)
  assert(not n:face('north')); eq(t.calls,0)
end)
test('hardware exception retains intent and blocks all further movement',function()
  local t=S.turtle(); t.forward=function() error('peripheral failure') end
  local p={known=true,x=0,y=64,z=0,heading='north'}
  local n=require('autobuilder.core.navigation').new(t,p,{minimumFuelReserve=0},function() return true end)
  assert(not n:forward()); assert(p.pending and p.uncertain)
  assert(not n:turnRight()); eq(p.z,0)
end)
test('GPS rejects fractional fixes rather than inventing block coordinates',function()
  local g=require('autobuilder.core.gps').new({locate=function() return 0.4,64,0 end},{})
  local p,err=g:locate(); eq(p,nil); assert(err:find('grid'))
end)
test('checkpoint failed temporary write keeps primary untouched',function()
  local f=S.fs(); local c=require('autobuilder.core.checkpoint').new(f,S.codec(),'state')
  assert(c:save({progress=40})); f.fault.open='state.tmp'
  assert(not c:save({progress=41})); eq(c:load().progress,40)
end)

test('custom excavation allowlist does not silently gain default ores',function()
  local c=require('autobuilder.config').load({allowedMiningBlocks={['minecraft:stone']=true}})
  eq(c.allowedMiningBlocks['minecraft:iron_ore'],nil)
end)

test('mining capability cannot be advertised while its engine is disabled',function()
  local c=require('autobuilder.config').load({capabilities={mining=true}})
  assert(not c.capabilities.mining)
end)

test('navigation detours an occupied route with reservations and retains its path across reboot',function()
  local U=require('autobuilder.core.util');local P=require('autobuilder.core.pathfinding')
  local w=require('tests.build_world').new();local pose=U.copy(w.pose);local saved;local pending;local granted=false
  local occupied={x=1,y=2,z=0};local target={x=3,y=2,z=0};local n
  local function boot()
    n=require('autobuilder.core.navigation').new(w.turtle,pose,{minimumFuelReserve=0},function() saved=U.copy(pose);return true end)
    n.guard=function(_,to)
      if U.distance(to,occupied)==0 then pending=U.copy(to);return false,'movement reservation pending: worker occupies destination' end
      if not pending or U.distance(pending,to)>0 then pending=U.copy(to);granted=false;return false,'movement reservation pending' end
      return granted,'movement reservation pending'
    end
    n.trafficObstacle=function() if pending and U.distance(pending,occupied)==0 then return U.copy(pending) end end
    n.afterMove=function() pending=nil;granted=false;assert(U.distance(pose,occupied)>0) end
  end
  boot();local rebooted=false;local done=false
  for _=1,60 do
    done=n:goTo(target);if done then break end
    if pose.detour and not rebooted and U.distance(pose,{x=0,y=2,z=0})>0 then pose=U.copy(saved);boot();rebooted=true end
    granted=true
  end
  assert(done,'worker remained behind occupied cell');assert(rebooted);eq(P.key(pose),P.key(target));eq(w.digs,0)
end)

test('traffic detours cannot bypass protected space exhausted fuel or an occupied goal',function()
  local U=require('autobuilder.core.util')
  for _,mode in ipairs({'protection','fuel','goal','coverage'}) do
    local w=require('tests.build_world').new();local p=U.copy(w.pose)
    local config={minimumFuelReserve=0}
    if mode=='protection' then
      config.restrictedAreas={{min={x=-2,y=0,z=-2},max={x=5,y=4,z=2}}}
    elseif mode=='fuel' then w.turtle.getFuelLevel=function() return 0 end end
    local n=require('autobuilder.core.navigation').new(w.turtle,p,config,function() return true end)
    local target={x=3,y=2,z=0}
    n.trafficObstacle=function() return mode=='goal' and target or {x=1,y=2,z=0} end
    if mode=='coverage' then n.coverageGuard=function() return false,'UNLOADED_AREA' end end
    assert(not n:goTo(target));eq(U.distance(w.pose,{x=0,y=2,z=0}),0);eq(w.digs,0)
  end
end)

test('checkpoint uses compact native encoding and retains legacy Adler checksums for large payloads',function()
  local fs=S.fs();local base=S.codec();local compact=0
  local codec={unserialize=base.unserialize,serialize=function(value,options)
    assert(options and options.compact==true,'checkpoint serialization is not compact');compact=compact+1;return base.serialize(value)
  end}
  local payload=base.serialize({text=string.rep('large checkpoint\n',6000)})
  local a,b=1,0;for i=1,#payload do a=(a+payload:byte(i))%65521;b=(b+a)%65521 end
  fs.files.large=base.serialize({version=1,payload=payload,checksum=b*65536+a})
  local cp=require('autobuilder.core.checkpoint').new(fs,codec,'large')
  local old=assert(cp:load());assert(cp:save(old));eq(compact,2)
  local saved=base.unserialize(fs.files.large);eq(saved.checksum,b*65536+a)
  eq(cp:load().text,old.text)
end)


test('failed traffic replanning discards its incomplete route and retries after the blocker leaves',function()
  local U=require('autobuilder.core.util');local w=require('tests.build_world').new();local pose=U.copy(w.pose)
  local saved;local obstacle={x=1,y=2,z=0};local target={x=3,y=2,z=0}
  local n=require('autobuilder.core.navigation').new(w.turtle,pose,{minimumFuelReserve=0},function() saved=U.copy(pose);return true end)
  n.trafficObstacle=function() return obstacle end
  n.guard=function() return false,'movement reservation pending' end
  assert(not n:goTo(target));assert(pose.detour and pose.detour.path)
  obstacle=target;assert(not n:goTo(target))
  obstacle=nil;n.guard=function() return true end
  assert(n:goTo(target));eq(U.distance(pose,target),0);eq(w.digs,0)
  assert(not saved.detour)
end)


test('an exhausted traffic cache is checkpointed away so changed traffic can retry',function()
  local U=require('autobuilder.core.util');local w=require('tests.build_world').new();local pose=U.copy(w.pose)
  local target={x=3,y=2,z=0};local saved
  pose.detour={target=U.copy(target),count=16,blocked={},path={},index=1}
  for i=1,16 do pose.detour.blocked[i..',9,0']=true end
  local n=require('autobuilder.core.navigation').new(w.turtle,pose,{minimumFuelReserve=0},function() saved=U.copy(pose);return true end)
  n.trafficObstacle=function() return {x=1,y=2,z=0} end
  assert(not n:goTo(target));eq(pose.detour,nil);eq(saved.detour,nil)
  n.trafficObstacle=function() return nil end
  assert(n:goTo(target));eq(U.distance(pose,target),0);eq(w.digs,0)
end)

test('traffic detour preserves an inspected chest and replans around it across reboot',function()
  local U=require('autobuilder.core.util');local P=require('autobuilder.core.pathfinding')
  local w=require('tests.build_world').new();local pose=U.copy(w.pose);local saved;local denied
  local occupied={x=1,y=2,z=0};local target={x=3,y=2,z=0}
  w.blocks['0,2,1']={name='minecraft:chest',state={}}
  local function boot()
    local n=require('autobuilder.core.navigation').new(w.turtle,pose,{minimumFuelReserve=0},function() saved=U.copy(pose);return true end)
    n.guard=function(_,to)
      denied=U.distance(to,occupied)==0 and U.copy(to) or nil
      return not denied,denied and 'movement reservation pending: worker occupies destination'
    end
    n.trafficObstacle=function() return denied end
    return n
  end
  local n=boot();local done,rebooted=false,false
  for _=1,20 do
    local why;done,why=n:goTo(target);if done then break end
    if why:find('chest',1,true) then
      assert(why:find('movement reservation pending',1,true),'physical detour obstruction became a terminal task error')
      pose=U.copy(saved);n=boot();rebooted=true
    end
  end
  assert(done,'detour stalled at the station chest');assert(rebooted)
  eq(P.key(pose),P.key(target));eq(w.blocks['0,2,1'].name,'minecraft:chest');eq(w.digs,0)
end)
