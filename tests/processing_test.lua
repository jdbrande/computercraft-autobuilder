local U=require('autobuilder.core.util')
local F=require('autobuilder.factory.factory')
local function fixture()
 local f=require('tests.managed_logistics_support').new();f.size=10;f.partial=1
 f.config=require('autobuilder.config').load({storageInventories={'base'},turtleFuelReserveItems={},processors={machines={{id='a',inventory='a'},{id='b',inventory='b'}},recipes={
  ['test:alloy']={yield=2,inputs={['test:iron']={count=2,slot=1},['test:copper']={count=1,slot=2}},outputSlot=4,seconds=1,machines={'a','b'},fuel={item='minecraft:coal',slot=3,batchesPerItem=8}}}}})
 f.inventories={base={[1]={name='test:iron',count=64},[2]={name='test:iron',count=64},[3]={name='test:iron',count=4},[4]={name='test:copper',count=64},[5]={name='test:copper',count=2},[6]={name='minecraft:coal',count=64},[7]={name='minecraft:coal',count=2}},a={},b={}}
 f:boot();f.production:request({['test:alloy']=132})
 f.burn={a=0,b=0};f.processed={a=0,b=0}
 function f:process()
  if self.unpowered then return end
  for _,name in ipairs({'a','b'}) do
   local inv=self.inventories[name]
   if inv[1] and inv[1].count==2 and inv[2] and inv[2].count==1 and (self.burn[name]>0 or inv[3]) and not inv[4] then
    if self.burn[name]==0 then inv[3].count=inv[3].count-1;if inv[3].count==0 then inv[3]=nil end;self.burn[name]=8 end
    inv[1]=nil;inv[2]=nil;inv[4]={name='test:alloy',count=2};self.burn[name]=self.burn[name]-1;self.processed[name]=self.processed[name]+1
    if self.processed.a>0 and self.processed.a<33 and self.processed.b>0 then self.overlap=true end
   end
  end
 end
 function f:drive(n)
  for _=1,n or 2000 do
   self.now=self.now+1;self.production:tick();self.production:step();self:process()
   if self.queue.state.requests['request:1'].status=='completed' then return end
  end
 end
 return f
end
test('processors stream multi-input output through bounded capacity on parallel machines and settle exact stock',function()
 local f=fixture();f:drive()
 local r=f.queue.state.requests['request:1'];eq(r.status,'completed');eq(F.count(f.inventories.base,'test:alloy'),132)
 eq(f.overlap,true);eq(f.processed.a,33);eq(f.processed.b,33);eq(F.count(f.inventories.base,'test:iron'),0);eq(F.count(f.inventories.base,'test:copper'),0)
 eq(F.count(f.inventories.base,'minecraft:coal'),56);eq(next(f.inventories.a),nil);eq(next(f.inventories.b),nil)
 for _,lease in pairs(f.app.state.inventoryLedger.leases) do eq(lease.status,'released') end
 for _,lease in pairs(f.app.state.capacityLedger.leases) do eq(lease.status,'released') end
end)
test('processor journal survives a physical transfer crash and paused reconciliation without duplicate inputs',function()
 local f=fixture();f.production:tick();f.crashTransfer=true
 pcall(function() f.production:step() end);eq(f.crashed,true)
 f:boot(true);local found
 for _,j in pairs(f.queue.state.jobs) do if j.production and j.production.intent then found=j;j.paused=true end end
 assert(found,'physical transfer journal missing');assert(f.app:save());local calls=f.transfers
 f.production:step();eq(found.production.intent,nil);eq(f.transfers,calls)
 found.paused=false;found.status='queued';assert(f.app:save());f:drive();eq(f.queue.state.requests['request:1'].status,'completed')
 eq(F.count(f.inventories.base,'test:alloy'),132)
end)
test('processor stalls never invent output and changed owned configuration is refused',function()
 local f=fixture();f.unpowered=true;f:drive(20)
 eq(F.count(f.inventories.base,'test:alloy'),0);assert(f.queue.state.requests['request:1'].status~='completed')
 local c=U.copy(f.config);c.processors.recipes['test:alloy'].yield=3
 eq(pcall(require('autobuilder.factory.processors').validateSaved,c,f.app.state),false)
 f.unpowered=false;f:drive();eq(f.queue.state.requests['request:1'].status,'completed')
end)

test('processor returns measured unused fuel without promising fuel as product output',function()
 local f=fixture();f.queue.state.requests['request:1'].requirements={['test:alloy']=2};f.burn.a=8
 f.unpowered=true;f:drive(12);local j
 for _,v in pairs(f.queue.state.jobs) do if v.type=='PROCESS' then j=v end end
 assert(j and j.production.withdrawn['minecraft:coal']==1)
 f.unpowered=false;f:drive();eq(f.queue.state.requests['request:1'].status,'completed')
 eq(j.production.fuelReturned,1);eq(F.count(f.inventories.base,'minecraft:coal'),66)
 local lease=f.app.state.inventoryLedger.leases[j.id];eq(lease.outputs['minecraft:coal'],nil);eq(lease.withdrawn['minecraft:coal'],1);eq(lease.status,'released')
end)
test('processor cannot mutate storage before claims persist or dispatch a controller task to a turtle',function()
 local f=fixture();f.production:tick();local save=f.app.save
 f.app.save=function() return false,'disk full' end
 pcall(function() f.production:step() end);eq(f.transfers,0);eq(next(f.app.state.capacityLedger.leases),nil);eq(next(f.app.state.inventoryLedger.leases),nil)
 f.app.save=save;f:drive();eq(f.queue.state.requests['request:1'].status,'completed')
 eq(require('autobuilder.core.task_messages').validate('task_assign',{job={id='task:7:1',type='PROCESS'}}),false)
end)

test('processor release crash resumes exact completion without reopening its machine claim',function()
 local f=fixture();f.queue.state.requests['request:1'].requirements={['test:alloy']=2}
 local save=f.app.save;local tripped=false
 f.app.save=function(app)
  local result=save(app)
  for _,j in pairs(f.queue.state.jobs) do
   local lease=(app.state.capacityLedger or {}).leases and app.state.capacityLedger.leases[j.id]
   if not tripped and lease and lease.status=='released' and j.status~='completed' then tripped=true;f.crashed=true end
  end
  return result
 end
 pcall(function() f:drive() end);eq(tripped,true);f:boot(true);f:drive()
 eq(f.queue.state.requests['request:1'].status,'completed');eq(F.count(f.inventories.base,'test:alloy'),2)
end)
test('processor pause during capacity observation permits no physical loading',function()
 local f=fixture();f.production:tick();local call=f.e.peripheral.call;local paused=false
 f.e.peripheral.call=function(name,method,...)
  local result=call(name,method,...)
  if not paused and name=='base' and method=='size' then
   paused=true;for _,j in pairs(f.queue.state.jobs) do j.paused=true end
  end
  return result
 end
 f.production:step();eq(paused,true);eq(f.transfers,0)
end)
test('processor disconnect and contamination retain ownership without duplicate loading',function()
 local f=fixture();f.unpowered=true;f:drive(12);local j
 for _,v in pairs(f.queue.state.jobs) do if v.machineId=='a' then j=v end end
 assert(j.production);local original=U.copy(f.inventories.a);local calls=f.transfers
 f.offline='a';f:drive(4);eq(j.status,'blocked');assert(f.app.state.capacityLedger.leases[j.id].status=='held')
 f.offline=nil;f.inventories.a[8]={name='test:foreign',count=1};f:drive(4);eq(j.status,'blocked');assert(j.error:find('contamination'))
 eq(F.equal(f.inventories.a[1],original[1]),true);f.inventories.a[8]=nil;f.unpowered=false;f:drive();eq(f.queue.state.requests['request:1'].status,'completed')
end)

test('streamed processor fuel survives lost residual burn across collection pause and restart',function()
 local f=fixture();f.queue.state.requests['request:1'].requirements={['test:alloy']=8}
 local process=f.process;local restarted=false
 f.process=function(self)
  process(self)
  for _,name in ipairs({'a','b'}) do if self.inventories[name][4] then self.burn[name]=0 end end
 end
 for i=1,100 do
  f:drive(1)
  if not restarted and f.processed.a==1 and f.processed.b==1 then
   for _,j in pairs(f.queue.state.jobs) do j.paused=true end;assert(f.app:save());f:boot(true)
   for _,j in pairs(f.queue.state.jobs) do j.paused=false end;assert(f.app:save());restarted=true
  end
  if f.queue.state.requests['request:1'].status=='completed' then break end
 end
 eq(restarted,true);eq(f.queue.state.requests['request:1'].status,'completed');eq(F.count(f.inventories.base,'test:alloy'),8)
end)
test('processor output uses combined chest capacity and resumes between destinations',function()
 local f=fixture();f.queue.state.requests['request:1'].requirements={['test:alloy']=130}
 f.config.storageInventories={'base','overflow'};f.inventories.base[8]={name='test:alloy',count=63};f.inventories.base[9]={name='test:alloy',count=64};f.inventories.base[10]={name='test:alloy',count=64}
 -- Exactly one free measured space per chest; other slots are occupied.
 f.inventories.overflow={};for i=1,10 do f.inventories.overflow[i]={name='test:filler',count=64} end
 f.inventories.overflow[1]={name='test:alloy',count=63};f.queue.state.requests['request:1'].requirements={['test:alloy']=256}
 f.app.mining.storage=require('autobuilder.storage.storage').new(f.e.peripheral,f.config.storageInventories)
 local call=f.e.peripheral.call;local crashed=false
 f.e.peripheral.call=function(name,method,...)
  local args={...};local n=call(name,method,...)
  if not crashed and name=='a' and method=='pushItems' and args[1]=='base' then crashed=true;f.crashed=true;error('power cut after first chest output') end
  return n
 end
 pcall(function() f:drive() end);eq(crashed,true);f:boot(true);f:drive()
 eq(f.queue.state.requests['request:1'].status,'completed');eq(F.count(f.inventories.base,'test:alloy')+F.count(f.inventories.overflow,'test:alloy'),256)
end)
test('first high-yield processor output uses declared safe stack limit and honors smaller stacks',function()
 for _,limit in ipairs({16,64}) do
  local f=fixture();local recipe=f.config.processors.recipes['test:alloy'];recipe.yield=16;recipe.outputStackLimit=limit
  f.queue.state.requests['request:1'].requirements={['test:alloy']=16}
  local process=f.process;f.process=function(self) process(self);for _,name in ipairs({'a','b'}) do local s=self.inventories[name][4];if s then s.count=16 end end end
  f.partial=64;f.maxCount=limit;f:drive();eq(f.queue.state.requests['request:1'].status,'completed');eq(F.count(f.inventories.base,'test:alloy'),16)
 end
end)

test('processor insufficient combined output capacity loads nothing and identifies unknown stack bounds',function()
 local f=fixture();f.queue.state.requests['request:1'].requirements={['test:alloy']=2}
 for i=8,10 do f.inventories.base[i]={name='test:filler',count=64} end
 f:drive(4);eq(f.transfers,0)
 local j=next(f.queue.state.jobs) and select(2,next(f.queue.state.jobs));assert(j.error:find('output stack limit unknown'))
 f.config.processors.recipes['test:alloy'].outputStackLimit=64
 -- Replan a fresh fixture rather than mutating an owned recipe to escape a claim.
 local other=fixture();other.queue.state.requests['request:1'].requirements={['test:alloy']=2};other.config.processors.recipes['test:alloy'].outputStackLimit=64
 for i=8,10 do other.inventories.base[i]={name='test:filler',count=64} end
 other:drive(4);eq(other.transfers,0)
 local _,job=next(other.queue.state.jobs);assert(job.error:find('insufficient combined'))
end)
test('processor repeated burn loss exhausts only its bounded fuel claim and reports explicit blocker',function()
 local f=fixture();f.queue.state.requests['request:1'].requirements={['test:alloy']=2};f.config.smeltingWaitSteps=3
 f.process=function(self) local inv=self.inventories.a;if inv[3] then inv[3]=nil end end
 f:drive(20);local _,j=next(f.queue.state.jobs);eq(j.status,'blocked');assert(j.error:find('fuel budget exhausted'))
 eq(j.production.withdrawn['minecraft:coal'],1);eq(F.count(f.inventories.base,'test:alloy'),0)
end)
