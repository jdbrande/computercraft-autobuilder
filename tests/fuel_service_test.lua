local U=require('autobuilder.core.util')
local C=require('autobuilder.config')
local FuelService=require('autobuilder.core.fuel_service')
local function mc(s) return 'minecraft:'..s end
local function fixture(stock)
  local h={inventories={store=stock or {[1]={name=mc('coal'),count=6}},fuel={}},transfers=0}
  h.peripheral={call=function(name,method,...)
    local inv=assert(h.inventories[name],'disconnected inventory')
    if method=='list' then return U.copy(inv) end
    if method=='size' then return 3 end
    if method=='getItemLimit' then return 64 end
    if method=='getItemDetail' then local slot=...; local item=U.copy(inv[slot]); if item then item.maxCount=64 end; return item end
    assert(method=='pushItems','unexpected method '..method)
    local target,slot,n,toSlot=...; local to=assert(h.inventories[target]); local source=inv[slot]
    if not source then return 0 end
    if not toSlot then for i=1,3 do if not to[i] or to[i].name==source.name and to[i].count<64 then toSlot=i; break end end end
    if not toSlot then return 0 end
    local moved=math.min(n,source.count,64-(to[toSlot] and to[toSlot].count or 0),h.maxPush or 64)
    to[toSlot]={name=source.name,count=(to[toSlot] and to[toSlot].count or 0)+moved}
    source.count=source.count-moved; if source.count==0 then inv[slot]=nil end
    h.transfers=h.transfers+1
    if h.crash then h.crash=false; error('interrupted after physical transfer') end
    return moved
  end}
  local config=C.load({storageInventories={'store'},turtleFuelReserveItems={[mc('coal')]=2},
    fuel={enabled=true,target=160,low=80,stations={{id='home',workerId=2,inventory='fuel',position={x=0,y=0,z=0},targetItems=2}}}})
  local app={state={id=1,role='controller',jobs={},workers={}},now=0}
  function app:save() if self.fail then return false,'disk full' end; self.saved=U.copy(self.state); return true end
  function app:report() end
  local f={app=app,h=h,config=config}
  function f:boot()
    local clock=function() return app.now end
    app.mining=require('autobuilder.core.mining_service').new(app,config,h,{send=function() return true end},clock)
    self.q=require('autobuilder.core.workflows').new(app.state,function() return app:save() end,clock,1)
    self.p=require('autobuilder.core.production_service').new(app,config,h,self.q)
    self.fuel=FuelService.new(app,config,h,self.q,self.p,clock)
  end
  function f:tick() app.now=app.now+1; self.fuel:tick(); self.p:tick() end
  f:boot(); return f
end

test('fuel stations require a durable grant and reconcile partial physical fills',function()
  local f=fixture(); f.h.maxPush=1; f.fuel:tick(); f.fuel:step(); eq(f.h.transfers,0)
  for _=1,8 do f:tick(); f.fuel:step() end
  eq(f.h.inventories.fuel[1].count,2); eq(f.h.inventories.store[1].count,4)
  local seen=0
  for _,j in pairs(f.q.state.jobs) do if j.type=='FUEL_STATION' then
    seen=seen+1; eq(j.status,'completed'); eq(f.app.state.inventoryLedger.leases[j.id].status,'released')
  end end
  eq(seen,1)
end)

test('fuel station transfer checkpoints recover across interruption without duplicate fuel',function()
  local f=fixture(); f:tick(); f.h.crash=true; f.fuel:step()
  eq(f.h.inventories.fuel[1].count,2); local calls=f.h.transfers
  f.app.state=U.copy(f.app.saved); f:boot()
  for _=1,5 do f:tick(); f.fuel:step() end
  eq(f.h.transfers,calls); eq(f.h.inventories.fuel[1].count,2)
end)

test('fuel station cannot transfer after a failed intent save and blocks contaminated capacity',function()
  local f=fixture(); f:tick(); f.app.fail=true; assert(not pcall(f.fuel.step,f.fuel)); eq(f.h.transfers,0)
  f.app.fail=nil; f.h.inventories.fuel[1]={name=mc('dirt'),count=64}
  f.fuel:step(); eq(f.h.transfers,0)
end)

test('pending station refuel holds its worker before mining and offline ownership prevents refill',function()
  local f=fixture(); local app=f.app
  app.state.workers['2']={id=2,online=true,telemetry={fuel=0,status='idle',position={known=true,x=0,y=0,z=0},
    depot={x=0,y=0,z=0},capabilities={telemetry=true,mining=true,fuelV1=true}}}
  f:tick(); eq(f.q:assign(app.state.workers),nil)
  assert(require('autobuilder.core.workflows').workerBusy(app.state,2),'pending fuel job must hold the miner')
  for _=1,5 do f.fuel:step(); f:tick() end
  local job=assert(f.q:assign(app.state.workers)); eq(job.type,'REFUEL'); eq(job.preferredWorker,2); eq(job.fuelTarget,160)
  app.state.workers['2'].online=false; f.h.inventories.fuel={}; app:save()
  app.state=U.copy(app.saved); f:boot(); local count=f.q.state.sequence
  for _=1,5 do f:tick(); f.fuel:step() end
  eq(f.q.state.sequence,count); eq(next(f.h.inventories.fuel),nil)
end)

test('empty fuel sources request ordinary acquisition and preserve a visible station shortage',function()
  local f=fixture({}); f:tick()
  local request
  for _,r in pairs(f.q.state.requests) do if r.requirements[mc('coal')] then request=r end end
  assert(request,'station fuel missing from production planning')
  eq(f.h.transfers,0); assert(f.app.state.fuel.stations.home.error)
end)

test('fuel station refuses an ambiguous receipt and keeps its durable journal',function()
  local f=fixture(); f:tick(); f.h.crash=true; f.fuel:step()
  f.h.inventories.fuel[1].count=3
  f.app.state=U.copy(f.app.saved); f:boot(); f.fuel:step()
  local job=f.q.state.jobs[f.app.state.fuel.stations.home.fill]
  eq(job.status,'blocked'); assert(job.production.intent); assert(job.error:find('ambiguous'))
  eq(f.h.transfers,1)
end)

test('station transfer holds the shared inventory lock across yielding peripheral calls',function()
  local f=fixture(); f:tick(); local call=f.h.peripheral.call; local checked=false
  f.h.peripheral.call=function(name,method,...)
    if method=='pushItems' then
      checked=true; local ok,why=f.p:refresh(); eq(ok,false); assert(why:find('in progress'))
      local action=false; f.p:inventoryAction(function() action=true end); eq(action,false)
    end
    return call(name,method,...)
  end
  f.fuel:step(); assert(checked)
end)

test('fuel station measures item stack capacity before moving fuel',function()
  local f=fixture(); f:tick(); local call=f.h.peripheral.call
  f.h.peripheral.call=function(name,method,...)
    if method=='getItemLimit' then return 0 end
    return call(name,method,...)
  end
  f.fuel:step(); eq(f.h.transfers,0)
  local job=f.q.state.jobs[f.app.state.fuel.stations.home.fill]
  eq(job.status,'blocked'); assert(job.error:find('capacity'))
end)

test('remote refuel dispatch budgets overhead travel and the navigation return reserve',function()
  local f=fixture(); f.app.state.workers['2']={id=2,online=true,telemetry={fuel=20,status='idle',
    position={known=true,x=1,y=0,z=0},depot={x=0,y=0,z=0},capabilities={telemetry=true,fuelV1=true}}}
  f:tick()
  for _,j in pairs(f.q.state.jobs) do assert(j.type~='REFUEL','unsafe station trip was queued') end
  assert(f.app.state.fuel.stations.home.error:find('rescue'))
end)
