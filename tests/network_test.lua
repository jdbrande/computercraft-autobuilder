local S=require('tests.support')
local function telemetry()
  return {label='Turtle 12',status='idle',position={known=false},fuel=100,inventory={used=0,slots=16},capabilities={telemetry=true}}
end
local function packet(kind,seq,boot)
  return {version=1,id='12:'..(boot or 1)..':'..seq,sender=12,boot=boot or 1,sequence=seq,type=kind,payload=telemetry()}
end
local function net(id,boot)
  local modem=true; local sent={}
  local p={getNames=function() return modem and {'left'} or {} end,
    getType=function() return 'modem' end,call=function() return true end}
  local r={isOpen=function() return false end,open=function() end,send=function(to,m,protocol) sent[#sent+1]={to,m,protocol}; return true end}
  local n=require('autobuilder.core.network').new({rednet=r,peripheral=p}, {protocol='test',dedupLimit=2,dedupTTL=10},id,boot)
  return n,sent,function(v) modem=v end
end

test('message validation rejects malformed telemetry, spoofed sender and unsupported versions',function()
  local N=require('autobuilder.core.network')
  assert(N.validate(12,packet('register',1)))
  assert(not N.validate(9,packet('register',1)))
  local m=packet('register',1); m.version=2; assert(not N.validate(12,m))
  m=packet('heartbeat',1); m.payload.position={known=true,x='bad',y=1,z=2}; assert(not N.validate(12,m))
  m=packet('heartbeat',1); m.payload.fuel={}; assert(not N.validate(12,m))
  m=packet('heartbeat',1); m.payload.inventory.used=17; assert(not N.validate(12,m))
end)
test('network deduplicates messages, bounds cache and reconnects modem',function()
  local n,sent,modem=net(7,1)
  assert(n:accept(12,packet('register',1),'test',0))
  assert(not n:accept(12,packet('register',1),'test',1))
  assert(not n:accept(12,packet('register',2),'wrong',1))
  assert(n:accept(12,packet('register',2),'test',1))
  assert(n:accept(12,packet('register',3),'test',2))
  assert(n:cacheSize()<=2)
  modem(false); assert(not n:send(12,'ack',{requestId='12:1:1'}))
  modem(true); assert(n:send(12,'ack',{requestId='12:1:1'})); eq(#sent,1)
  local n2,s2=net(7,2); assert(n2:send(12,'ack',{requestId='12:1:1'}))
  assert(sent[1][2].id~=s2[1][2].id)
end)
test('registry restores peers offline, expires heartbeats and rejects old boots',function()
  local W=require('autobuilder.workers.workers')
  local state={workers={}}; local saves=0
  local w=W.new(state,{workerTimeout=30,maxWorkers=10},function() saves=saves+1; return true end)
  assert(w:handle(packet('register',1),100)); eq(state.workers['12'].online,true)
  assert(w:handle(packet('heartbeat',2),110)); eq(state.workers['12'].lastSeen,110)
  assert(w:expire(141)); eq(state.workers['12'].online,false)
  assert(w:handle(packet('register',1,2),142))
  assert(not w:handle(packet('heartbeat',3,1),143))
  eq(state.workers['12'].lastSeen,142)
  local restored=W.new(state,{workerTimeout=30,maxWorkers=10},function() return true end)
  eq(state.workers['12'].online,false)
  assert(restored:handle(packet('register',2,2),150)); eq(state.workers['12'].online,true)
  assert(saves>=4)
end)
test('registry does not acknowledge non-durable registration',function()
  local state={workers={}}
  local w=require('autobuilder.workers.workers').new(state,{maxWorkers=10},function() return false,'disk full' end)
  local ok,err=w:handle(packet('register',1),1); assert(not ok and err:find('disk'))
  eq(state.workers['12'],nil)
end)
test('worker registers, sends telemetry, times out and registers after controller reboot',function()
  local n,sent=net(12,1); local t=S.turtle()
  local state={position={known=false},status='idle'}
  local a=require('autobuilder.workers.agent').new(state,{controllerId=7,heartbeatInterval=5,registrationInterval=15,workerTimeout=30,capabilities={telemetry=true}},n,t,function() return true end)
  assert(a:tick(0)); eq(sent[1][2].type,'register'); eq(sent[1][2].payload.position.known,false)
  assert(a:handle(7,{type='ack',payload={requestId=sent[1][2].id}},1)); eq(a.connected,true)
  assert(a:tick(5)); eq(sent[#sent][2].type,'heartbeat')
  assert(a:tick(16)); eq(sent[#sent][2].type,'register')
  assert(a:tick(40)); eq(a.connected,false)
  local restored=require('autobuilder.workers.agent').new(state,{controllerId=7,heartbeatInterval=5,registrationInterval=15,workerTimeout=30},n,t,function() return true end)
  assert(restored:tick(41)); eq(sent[#sent][2].type,'register')
end)

test('duplicate at full cache capacity does not evict itself before validation',function()
  local n=net(7,1)
  assert(n:accept(12,packet('register',1),'test',0))
  assert(n:accept(12,packet('register',2),'test',1))
  assert(not n:accept(12,packet('register',1),'test',2),'duplicate accepted at capacity')
end)

test('network validates and preserves resource restrictions on telemetry and mining assignments',function()
  local N=require('autobuilder.core.network')
  for _,kind in ipairs({'register','heartbeat','mine_assign'}) do
    local m=packet(kind,1)
    if kind=='mine_assign' then m.payload={jobId='mine:1',item='minecraft:coal',quantity=2} end
    m.payload.miningResources={'minecraft:coal'}
    assert(N.validate(12,m))
    local accepted=assert(net(7,1):accept(12,m,'test',0))
    eq(accepted.payload.miningResources[1],'minecraft:coal')
    m.payload.miningResources[1]='minecraft:sand'; eq(accepted.payload.miningResources[1],'minecraft:coal')
    for _,bad in ipairs({false,{'minecraft:invalid'},{[2]='minecraft:coal'},{'minecraft:coal','minecraft:coal'},{coal=true}}) do
      m.payload.miningResources=bad; assert(not N.validate(12,m))
    end
    m.payload.miningResources={}; assert(N.validate(12,m))
    m.payload.miningResources=nil; assert(N.validate(12,m))
  end
end)

test('network validates cargo manifests and strips unknown cyclic cargo fields',function()
  local n=net(7,1);local m=packet('heartbeat',1)
  m.payload.cargo={items={['minecraft:stone']=5},limits={['minecraft:stone']=64}};m.payload.cargo.extra=m.payload.cargo
  local clean=assert(n:accept(12,m,'test',1));eq(clean.payload.cargo.items['minecraft:stone'],5);eq(clean.payload.cargo.extra,nil)
  m=packet('heartbeat',2);m.payload.cargo={items={['minecraft:stone']=-1},limits={['minecraft:stone']=64}}
  assert(not n:accept(12,m,'test',2))
end)

test('mission fuel telemetry validates arithmetic identity and current fuel and strips unknown fields',function()
  local U=require('autobuilder.core.util');local N=require('autobuilder.core.network')
  local m=packet('heartbeat',1);m.payload.task='task:1';m.payload.fuel=100
  local b={taskId='task:1',scope='excursion',current=100,outward=20,work=10,returning=20,reserve=100,required=150,shortfall=50,allowed=false}
  m.payload.fuelBudget=U.copy(b);m.payload.fuelBudget.extra=m.payload.fuelBudget
  local got=assert(net(7,1):accept(12,m,'test',1));assert(got.payload.fuelBudget,'mission budget missing');eq(got.payload.fuelBudget.required,150);eq(got.payload.fuelBudget.extra,nil)
  for _,change in ipairs({{work=-1},{work=1.5},{required=149},{shortfall=0},{allowed=true},{taskId='other'},{current=99},{scope='guaranteed'},{reserve=math.huge}}) do
    m.payload.fuelBudget=U.copy(b);for k,v in pairs(change) do m.payload.fuelBudget[k]=v end
    assert(not N.validate(12,m),'malformed budget accepted')
  end
  m.payload.fuelBudget=nil;assert(N.validate(12,m),'legacy telemetry rejected')
end)

test('worker publishes current mission fuel and explicit unavailable geometry without losing telemetry',function()
  local c=require('tests.loaded_config').load({role='worker',controllerId=7,depot={x=0,y=0,z=0},minimumFuelReserve=20})
  local t=S.turtle();t.fuel=100
  local state={id=12,position={known=true,x=0,y=0,z=0,heading='north'},currentTask={id='build',type='BUILD',blocks={{x=10,y=0,z=0,name='minecraft:stone'}}}}
  local a=require('autobuilder.workers.agent').new(state,c,net(12,1),t,function() return true end)
  local p=a:telemetry();assert(p.fuelBudget,'missing worker budget');eq(p.fuelBudget.required,54);eq(p.fuelBudget.current,p.fuel);eq(p.fuelBudget.taskId,p.task)
  state.position.known=false;p=a:telemetry();eq(p.fuelBudget,nil);assert(p.fuelBudgetError:find('position'))
  state.currentTask=nil;p=a:telemetry();eq(p.fuelBudget,nil);eq(p.fuelBudgetError,nil)
end)

test('fixed mining route telemetry copies validated worker entry and accepts legacy omission',function()
  local N=require('autobuilder.core.network');local m=packet('heartbeat',1)
  m.payload.miningRoute={entry={x=40,y=-20,z=7},fuelTarget=1000};m.payload.miningRoute.extra=m.payload.miningRoute
  local got=assert(net(7,1):accept(12,m,'test',1));eq(got.payload.miningRoute.entry.x,40);eq(got.payload.miningRoute.extra,nil);eq(got.payload.miningRoute.fuelTarget,1000)
  for _,bad in ipairs({false,{}, {entry={x=0/0,y=1,z=2}},{entry={x=1,y=1.5,z=2}}}) do m.payload.miningRoute=bad;assert(not N.validate(12,m)) end
  for _,bad in ipairs({0,-1,1.5,'1000',math.huge}) do m.payload.miningRoute={entry={x=0,y=0,z=0},fuelTarget=bad};assert(not N.validate(12,m)) end
  m.payload.miningRoute={entry={x=0,y=0,z=0}};assert(N.validate(12,m))
  m.payload.miningRoute=nil;assert(N.validate(12,m))
end)


test('idle explorer advertises its departure fuel target before a trip exists',function()
  local c={mining={enabled=true,fuelTarget=1000,exitRoute={{x=1,y=0,z=0}}},capabilities={explorationV1=true},depot={x=0,y=0,z=0}}
  local state={id=12,position={known=true,x=0,y=0,z=0,heading='east'}}
  local a=require('autobuilder.workers.agent').new(state,c,net(12,1),S.turtle(),function() return true end)
  local p=a:telemetry();eq(p.miningRoute.fuelTarget,1000);eq(p.miningRoute.entry.x,1);eq(p.task,nil)
  c.mining.exitRoute[1].x=2;eq(p.miningRoute.entry.x,1)
end)

test('renewable delivery telemetry is task bound bounded and retained by network cleaning',function()
  local N=require('autobuilder.core.network');local p=packet('heartbeat',1)
  p.payload.task='harvest';p.payload.harvestDelivered=2;assert(N.validate(12,p))
  for _,bad in ipairs({-1,1.5,100000001,'2',false}) do p.payload.harvestDelivered=bad;assert(not N.validate(12,p)) end
  p.payload.harvestDelivered=2;p.payload.task=nil;assert(not N.validate(12,p))
  p.payload.task='harvest';p.payload.harvestPlanting=1
  for _,bad in ipairs({-1,2,0.5,'1',false}) do p.payload.harvestPlanting=bad;assert(not N.validate(12,p)) end
  p.payload.harvestPlanting=1;local n=net(7,1);local m=assert(n:accept(12,p,'test',100));eq(m.payload.harvestDelivered,2);eq(m.payload.harvestPlanting,1)
end)

test('network validates health before deduplication and strips unknown health cycles',function()
  local n=net(7,1);local m=packet('heartbeat',1)
  local h=require('autobuilder.workers.health').observe({}, {status='unmanaged'});h.extra=h
  m.payload.health=h;h.left={};assert(not n:accept(12,m,'test',1))
  h.left='unknown';local accepted=assert(n:accept(12,m,'test',2));assert(accepted.payload.health);eq(accepted.payload.health.extra,nil)
  eq(accepted.payload.health.software.status,'unmanaged')
end)

test('crafting inventory names are bounded validated before deduplication and copied into worker registration',function()
 local n=net(7,1);local m=packet('register',1)
 for _,names in ipairs({{'left'},{'same','same'},{[2]='sparse'},{'a','b','c','d'}}) do m.payload.craftingInventories=names;assert(not n:accept(12,m,'test',0)) end
 m.payload.craftingInventories={'input','output'}
 local accepted=assert(n:accept(12,m,'test',0));m.payload.craftingInventories[1]='changed';eq(accepted.payload.craftingInventories[1],'input')
end)
