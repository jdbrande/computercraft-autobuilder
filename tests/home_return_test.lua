local U=require('autobuilder.core.util')
local function fixture()
  local w=require('tests.build_world').new();w.pose.x=4
  w.items={[1]={name='minecraft:stone',count=5,maxCount=64},[2]={name='minecraft:dirt',count=3,maxCount=64},[15]={name='minecraft:coal',count=2,maxCount=64},[16]={name='minecraft:diamond_pickaxe',count=1,maxCount=1}}
  w.blocks['0,1,0']={name='minecraft:chest',state={}}
  local f={w=w,buffer={},drops=0,config={depot={x=0,y=2,z=0},minimumFuelReserve=0},state={pose=U.copy(w.pose),task={id='return:1',type='RETURN_HOME',phase='work',
    home={x=0,y=2,z=0},returning={node={id='base',inventory='stock',position={x=1,y=1,z=0}},buffer={inventory='buffer',position={x=0,y=2,z=0}},items={['minecraft:stone']=5,['minecraft:dirt']=3}}}}}
  w.turtle.dropDown=function(n)
    assert(w.pose.x==0 and w.pose.y==2 and w.pose.z==0,'drop away from home')
    local v=w.items[w.selected];if f.full then return false end
    local moved=math.min(n,v.count,f.partial or 64);f.buffer[v.name]=(f.buffer[v.name] or 0)+moved;v.count=v.count-moved
    if v.count==0 then w.items[w.selected]=nil end;f.drops=f.drops+1
    if f.crash then f.crash=false;error('power loss after native drop') end
    return true
  end
  function f:save() if self.fail then return false,'disk full' end;self.saved=U.copy(self.state);return true end
  function f:boot(restore)
    if restore then self.state=U.copy(self.saved) end
    local nav=require('autobuilder.core.navigation').new(w.turtle,self.state.pose,self.config,function() return self:save() end)
    self.driver=require('autobuilder.workers.home').new(self.state.task,{turtle=w.turtle},self.config,nav,function() return self:save() end)
  end
  function f:finish()
    for _=1,40 do self.driver:step();if self.state.task.phase=='completed' then return end end
    error(self.state.task.error or 'home did not complete')
  end
  return f
end

test('home return journals mixed cargo and leaves reserved fuel and tools intact',function()
  local f=fixture();f.partial=2;f:boot();f:finish()
  eq(f.w.pose.x,0);eq(f.w.pose.y,2);eq(f.buffer['minecraft:stone'],5);eq(f.buffer['minecraft:dirt'],3)
  eq(f.w.items[15].count,2);eq(f.w.items[16].name,'minecraft:diamond_pickaxe');eq(f.w.items[1],nil);eq(f.w.items[2],nil)
  eq(f.state.task.homeCargo.deposited['minecraft:stone'],5);eq(f.state.task.homeCargo.deposited['minecraft:dirt'],3)
  eq(f.state.task.progress,8)
end)

test('home post-drop reboot reconciles exact cargo without dropping it twice',function()
  local f=fixture();f:boot();f.crash=true;f.driver:step()
  assert(f.saved.task.homeCargo.intent);eq(f.drops,1)
  f:boot(true);f:finish();eq(f.buffer['minecraft:stone'],5);eq(f.buffer['minecraft:dirt'],3);eq(f.drops,2)
end)

test('home refuses missing container changed cargo pauses and failed checkpoints before effects',function()
  for _,reason in ipairs({'container','cargo','paused','save'}) do
    local f=fixture();if reason=='container' then f.w.blocks['0,1,0']=nil
    elseif reason=='cargo' then f.w.items[1].count=4
    elseif reason=='paused' then f.state.task.paused=true else f.fail=true end
    f:boot();f.driver:step();eq(f.drops,0);assert(f.state.task.phase~='completed')
  end
end)

test('cargo telemetry excludes reserved slots and validates bounded clean manifests',function()
  local R=require('autobuilder.storage.returns');local f=fixture()
  local cargo=R.observe(f.w.turtle,f.config);assert(R.validCargo(cargo));eq(cargo.items['minecraft:stone'],5);eq(cargo.items['minecraft:coal'],nil)
  cargo.unknown=cargo;local clean=R.cleanCargo(cargo);eq(clean.unknown,nil);eq(clean.limits['minecraft:stone'],64)
  cargo.items['minecraft:stone']=-1;assert(not R.validCargo(cargo))
  f.w.items[1].nbt='special';cargo=R.observe(f.w.turtle,f.config);assert(cargo.error and R.validCargo(cargo))
  assert(R.validContract(f.state.task));f.state.task.returning.buffer.inventory='stock';assert(not R.validContract(f.state.task))
end)

test('task protocol rejects malformed home contracts and deposit receipts',function()
  local P=require('autobuilder.core.task_messages');local f=fixture()
  assert(P.validate('task_assign',{job=f.state.task}))
  f.state.task.returning.buffer.position.x=9;assert(not P.validate('task_assign',{job=f.state.task}))
  assert(not P.validate('task_progress',{jobId='home',phase='completed',progress=8,homeReceipt={sequence=1,deposited={stone=-1}}}))
end)

test('home retains ambiguous drop intent when an unrelated reserved slot changes',function()
  local f=fixture();f:boot();f.crash=true;f.driver:step();assert(f.saved.task.homeCargo.intent)
  f.w.items[15].count=1;f:boot(true);f.driver:step()
  assert(f.state.task.homeCargo.intent);eq(f.state.task.phase,'blocked');eq(f.drops,1)
end)

test('home retries full container without inferring a deposit and recovers a failed receipt save',function()
  local f=fixture();f.full=true;f:boot();f.driver:step();eq(f.state.task.phase,'blocked');eq(f.drops,0)
  eq(f.state.task.homeCargo.deposited['minecraft:stone'] or 0,0)
  f.full=false;f.driver:resume();local drop=f.w.turtle.dropDown
  f.w.turtle.dropDown=function(n) local ok=drop(n);f.fail=true;return ok end
  f.driver:step();eq(f.drops,1);assert(f.saved.task.homeCargo.intent)
  f.fail=false;f.w.turtle.dropDown=drop;f:boot(true);f:finish()
  eq(f.buffer['minecraft:stone'],5);eq(f.buffer['minecraft:dirt'],3);eq(f.drops,2)
end)

test('mixed cargo returns below a fuel chest through the station side approach across reboot',function()
  local f=fixture();f.config.fuel={enabled=true};f.w.blocks['0,3,0']={name='minecraft:chest',state={}}
  f.crash=true;f:boot();f.driver:step();assert(f.saved.task.homeCargo.intent);eq(f.drops,1)
  f:boot(true);f:finish();eq(f.buffer['minecraft:stone'],5);eq(f.buffer['minecraft:dirt'],3)
  eq(f.w.pose.x,0);eq(f.w.pose.y,2);eq(f.w.pose.z,0);eq(f.w.digs,0);assert(f.w.blocks['0,3,0'])
end)
