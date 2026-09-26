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
