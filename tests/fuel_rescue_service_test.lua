local U=require('autobuilder.core.util')
local C=require('autobuilder.config')
local Q=require('autobuilder.core.workflows')
local Rescue=require('autobuilder.core.fuel_rescue_service')
local function fixture()
  local app={state={id=1,jobs={},workers={},fuel={stations={}}}}
  function app:save() self.saved=U.copy(self.state); return true end
  local config=C.load({fuel={enabled=true,target=160,low=80,stations={{id='courier',workerId=3,inventory='fuel',position={x=0,y=0,z=0},targetItems=2}}}})
  local h={stock=2,sent={}}
  h.peripheral={call=function(_,method) if method=='list' then return {[1]={name='minecraft:coal',count=h.stock}} end; if method=='getItemDetail' then return {maxCount=64} end; error(method) end}
  local clock=function() return 1 end
  local q=Q.new(app.state,function() return app:save() end,clock,1)
  local p={inventoryAction=function(_,fn) return fn() end}
  local network={send=function(_,id,kind,payload) h.sent[#h.sent+1]={id=id,kind=kind,payload=U.copy(payload)}; return true end}
  app.state.workers['2']={id=2,online=true,telemetry={fuel=0,status='idle',position={known=true,x=5,y=0,z=0},depot={x=0,y=0,z=0},capabilities={telemetry=true,fuelV1=true}}}
  app.state.workers['3']={id=3,online=true,telemetry={fuel=500,status='idle',position={known=true,x=0,y=0,z=0},depot={x=0,y=0,z=0},capabilities={telemetry=true,fuelV1=true,courier=true}}}
  local f={app=app,h=h,q=q}
  function f:boot() self.r=Rescue.new(app,config,h,q,p,network,clock) end
  f:boot(); return f
end

test('rescue dispatch waits for recipient freeze and holds both worker and station ownership',function()
  local f=fixture(); f.r:tick(); local j
  for _,job in pairs(f.q.state.jobs) do if job.type=='RESCUE' then j=job end end
  assert(j); eq(j.targetWorker,2); eq(j.preferredWorker,3); eq(f.q:assign(f.app.state.workers),nil)
  assert(Q.workerBusy(f.app.state,2)); assert(Q.workerBusy(f.app.state,3))
  assert(f.r:handle(2,{jobId=j.id,phase='frozen',capacity=2,quantity=0,fuel=0,position={x=5,y=0,z=0}}))
  f.r:tick(); eq(f.q:assign(f.app.state.workers).id,j.id)
  f.app.state.workers['3'].online=false; local count=f.q.state.sequence
  for _=1,5 do f.r:tick() end; eq(f.q.state.sequence,count)
  eq(j.rescueSettled,nil)
end)

test('rescue refuses an unfueled courier and records actionable shortage instead of duplicate work',function()
  local f=fixture(); f.app.state.workers['3'].telemetry.fuel=1; f.r:tick()
  eq(next(f.q.state.jobs),nil); assert(f.app.state.fuel.errors['2']:find('courier'))
end)

test('rescue releases recipient only after measured full delivery and courier return',function()
  local f=fixture(); f.r:tick(); local j; for _,job in pairs(f.q.state.jobs) do j=job end
  assert(f.r:handle(2,{jobId=j.id,phase='frozen',capacity=2,quantity=0,fuel=0,position={x=5,y=0,z=0}})); f.r:tick()
  f.q:assign(f.app.state.workers); j.fuelDelivered=1; f.h.sent={}; f.r:tick()
  for _,m in ipairs(f.h.sent) do assert(m.kind~='task_fuel_consume') end
  j.fuelDelivered=2; f.r:tick(); eq(f.h.sent[#f.h.sent].kind,'task_fuel_consume')
  assert(f.r:handle(2,{jobId=j.id,phase='consumed',quantity=2,capacity=2,fuel=160,position={x=5,y=0,z=0}}))
  f.h.sent={}; f.r:tick(); eq(#f.h.sent,0)
  j.status='completed'; f.r:tick(); eq(f.h.sent[#f.h.sent].kind,'task_fuel_release')
  assert(f.r:handle(2,{jobId=j.id,phase='released',quantity=2,capacity=2,fuel=160,position={x=5,y=0,z=0}})); f.r:tick()
  eq(j.rescueSettled,true); assert(not Q.workerBusy(f.app.state,2))
end)

test('completed rescue waits for a fresh recipient heartbeat before creating another mission',function()
  local f=fixture(); local w=f.app.state.workers['2']; w.boot=1; w.sequence=1
  f.r:tick(); local j; for _,job in pairs(f.q.state.jobs) do j=job end
  j.status='completed'; j.receiverPhase='released'; j.receiverFuel=160; j.fuelDelivered=2
  f.r:tick(); local count=f.q.state.sequence
  f.r:tick(); eq(f.q.state.sequence,count)
  w.sequence=2; w.telemetry.fuel=0; f.r:tick(); eq(f.q.state.sequence,count+1)
end)
