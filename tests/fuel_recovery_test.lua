local U=require('autobuilder.core.util')
local C=require('autobuilder.config')
local Recovery=require('autobuilder.workers.fuel_recovery')
local function fixture()
  local app={state={id=2,position={known=true,x=5,y=10,z=0,heading='north'},status='blocked',
    currentTask={id='mine:1',type='MINE',phase='blocked',error='insufficient fuel for movement and return reserve'}}}
  function app:save() if self.fail then return false,'disk full' end; self.saved=U.copy(self.state); return true end
  local h={slots={[1]={name='minecraft:coal',count=4}},fuel=0,burns=0}
  h.turtle={getItemDetail=function(slot) return U.copy(h.slots[slot]) end,getFuelLevel=function() return h.fuel end,
    getItemSpace=function(slot) return 64-(h.slots[slot] and h.slots[slot].count or 0) end,
    select=function(slot) h.selected=slot; return true end,refuel=function(n)
      local i=h.slots[h.selected]; local used=math.min(n,i.count)
      i.count=i.count-used; if i.count==0 then h.slots[h.selected]=nil end
      h.fuel=h.fuel+used*80; h.burns=h.burns+1
      if h.crash then h.crash=false; error('power loss after consuming fuel') end
      return true
    end}
  local f={app=app,h=h,config=C.load({fuel={enabled=true,target=160,low=80}})}
  f.contract={jobId='task:1:9',item='minecraft:coal',quantity=2,position={x=5,y=10,z=0},fuelTarget=160}
  function f:boot() self.r=Recovery.new(app,self.config,h) end
  f:boot(); return f
end

test('fuel recovery freezes the original task and burns only measured delivered fuel',function()
  local f=fixture(); assert(f.r:freeze(f.contract)); assert(f.r:active())
  eq(f.app.state.currentTask.id,'mine:1'); eq(f.h.burns,0)
  f.h.slots[1].count=6
  assert(f.r:consume({jobId=f.contract.jobId,quantity=2})); eq(f.h.burns,0)
  for _=1,3 do f.r:step() end
  eq(f.h.fuel,160); eq(f.h.slots[1].count,4); eq(f.r:status().phase,'consumed')
  assert(f.r:release({jobId=f.contract.jobId})); assert(not f.r:active())
  eq(f.app.state.currentTask.id,'mine:1')
  assert(f.r:freeze(f.contract)); assert(not f.r:active()); eq(f.h.burns,1)
end)

test('fuel consumption reconciles a reboot after the physical effect without a second burn',function()
  local f=fixture(); assert(f.r:freeze(f.contract)); f.h.slots[1].count=6
  assert(f.r:consume({jobId=f.contract.jobId,quantity=2})); f.h.crash=true; pcall(f.r.step,f.r)
  eq(f.h.fuel,160); f.app.state=U.copy(f.app.saved); f:boot()
  for _=1,3 do f.r:step() end
  eq(f.h.burns,1); eq(f.r:status().phase,'consumed')
end)

test('fuel recovery rejects changed contracts, unrelated inventory changes and failed checkpoints',function()
  local f=fixture(); f.app.fail=true; assert(not pcall(function() assert(f.r:freeze(f.contract)) end)); assert(not f.r:active())
  f.app.fail=nil; assert(f.r:freeze(f.contract))
  local changed=U.copy(f.contract); changed.quantity=3; assert(not f.r:freeze(changed))
  f.h.slots[2]={name='minecraft:dirt',count=1}; f.h.slots[1].count=6
  assert(not f.r:consume({jobId=f.contract.jobId,quantity=2})); eq(f.h.burns,0)
  assert(not f.r:release({jobId=f.contract.jobId})); assert(f.r:active())
end)

test('recovery freeze refuses moving workers and ambiguous or non-fuel task state',function()
  local f=fixture(); f.app.busy=true; assert(not f.r:freeze(f.contract)); f.app.busy=false
  f.app.state.position.uncertain=true; assert(not f.r:freeze(f.contract)); f.app.state.position.uncertain=nil
  f.app.state.currentTask.error='protected block'; assert(not f.r:freeze(f.contract))
  eq(f.h.burns,0); assert(not f.r:active())
end)

test('recovery rejects inventory tampering between delivery grant and native consumption',function()
  local f=fixture(); assert(f.r:freeze(f.contract)); f.h.slots[1].count=6
  assert(f.r:consume({jobId=f.contract.jobId,quantity=2})); f.h.slots[1].count=4
  local ok=f.r:step(); eq(ok,false); eq(f.h.burns,0)
end)

test('rescue receiving capacity and failed consumption checkpoints prevent unsafe physical effects',function()
  local f=fixture()
  for i=1,16 do f.h.slots[i]={name='minecraft:stone',count=64} end
  assert(not f.r:freeze(f.contract)); assert(not f.r:active())
  f=fixture(); assert(f.r:freeze(f.contract)); f.h.slots[1].count=6
  assert(f.r:consume({jobId=f.contract.jobId,quantity=2})); f.app.fail=true
  pcall(f.r.step,f.r); eq(f.h.burns,0); eq(f.h.fuel,0)
end)

test('rescue consumption preserves the native lava bucket return without consuming prior inventory',function()
  local f=fixture(); f.contract.item='minecraft:lava_bucket'; f.contract.quantity=1; f.contract.fuelTarget=1000
  assert(f.r:freeze(f.contract)); f.h.slots[2]={name='minecraft:lava_bucket',count=1}
  f.h.turtle.refuel=function(n)
    eq(n,1); eq(f.h.selected,2); f.h.slots[2]={name='minecraft:bucket',count=1}; f.h.fuel=1000; return true
  end
  assert(f.r:consume({jobId=f.contract.jobId,quantity=1}))
  for _=1,3 do f.r:step() end
  eq(f.r:status().phase,'consumed'); eq(f.h.slots[1].count,4); eq(f.h.slots[2].name,'minecraft:bucket')
end)

test('rescue protocol rejects malformed identities quantities poses and fuel telemetry',function()
  local messages=require('autobuilder.core.task_messages')
  local f=fixture(); assert(messages.validate('task_fuel_freeze',f.contract))
  for _,field in ipairs({'quantity','fuelTarget'}) do local bad=U.copy(f.contract); bad[field]=-1; assert(not messages.validate('task_fuel_freeze',bad)) end
  assert(not messages.validate('task_fuel_consume',{jobId='task:1:9',quantity=65}))
  assert(not messages.validate('task_fuel_status',{jobId='task:1:9',phase='consumed',quantity=1,capacity=1,fuel=160,position={x='5',y=10,z=0}}))
  assert(not messages.validate('task_progress',{jobId='task:1:9',phase='work',progress=0,fuelDelivered=-1}))
end)
