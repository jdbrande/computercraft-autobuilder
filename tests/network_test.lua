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
