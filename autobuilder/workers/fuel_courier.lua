local U=require('autobuilder.core.util')
local R=require('autobuilder.workers.resupply')
local F=require('autobuilder.factory.factory')
local M={}
function M.budget(pose,source,destination,home,reserve)
  local function leg(a,b) local d=U.distance(a,b); return d==0 and 0 or d+8 end
  return leg(pose,source)+leg(source,destination)+leg(destination,home)+reserve
end
function M.new(task,e,config,nav,save)
  assert(U.position(task.source) and U.position(task.destination) and U.position(task.home)
    and U.integer(task.targetWorker) and task.targetWorker>=0 and U.shortString(task.item,128)
    and U.integer(task.quantity) and task.quantity>=1 and task.quantity<=64,'invalid fuel courier contract')
  local t=e.turtle; local self={task=task}; local fault
  task.cargo=task.cargo or {stage='source',held=0}; local c=task.cargo
  task.fuelDelivered=task.fuelDelivered or 0
  local function persist()
    local called,ok,why=pcall(save)
    if not called or not ok then fault='rescue courier checkpoint failed: '..tostring(called and why or ok); error(fault,0) end
    return true
  end
  local function reconcile()
    local i=c.intent; local delta,why=R.delta(t,i); assert(delta,why)
    F.commit(task,persist,function()
      if i.kind=='drop' then c.held=c.held-delta; task.fuelDelivered=task.fuelDelivered+delta
      else c.held=c.held+delta end
      c.intent=nil; task.progress=task.fuelDelivered
    end)
    return delta
  end
  local function stage(name) c.stage=name; c.route=nil; c.stationApproach=nil; c.stationApproached=nil; persist() end
  local function transfer(kind,limit)
    assert(t.select(c.slot),'cannot select rescue cargo')
    F.commit(c,persist,function() c.intent={kind=kind,slot=c.slot,item=task.item,limit=limit,before=R.snapshot(t)} end)
    if kind=='suck' then t.suckUp(limit) else t.dropDown(limit) end
    assert(reconcile()>0,kind=='suck' and 'station fuel unavailable' or 'recipient inventory is full')
  end
  local function step()
    if task.phase=='completed' then return true end
    if task.phase=='blocked' and not c.intent then return false,task.error end
    assert(nav.pose.known and not nav.pose.pending and not nav.pose.uncertain,'trusted rescue courier pose required')
    if c.intent then reconcile(); task.error=nil end
    if not c.started then
      local fuel=t.getFuelLevel()
      local required=M.budget(nav.pose,task.source,task.destination,task.home,config.minimumFuelReserve or 100)
      assert(fuel=='unlimited' or fuel>=required,'insufficient courier fuel for delivery and return')
      c.started=true; persist()
    end
    task.phase='work'
    if c.stage=='source' then
      assert(R.stationTravel(c,task,nav,task.source,persist,t,config))
      assert(R.container(t,'up'))
      if not c.slot then c.slot=assert(R.slot(t,config,task.item,true),'no empty rescue cargo slot'); persist() end
      local i=t.getItemDetail(c.slot)
      assert(not i and c.held==0 or i and i.name==task.item and not i.nbt and i.count==c.held,'rescue cargo changed')
      if c.held>=task.quantity then stage('destination'); return true end
      local space=i and t.getItemSpace(c.slot) or 1
      assert(space>0,'rescue batch exceeds cargo stack capacity')
      transfer('suck',math.min(space,task.quantity-c.held))
      if c.held>=task.quantity then stage('destination') end
    elseif c.stage=='destination' then
      if c.held==0 and task.fuelDelivered==task.quantity then stage('home'); return true end
      assert(R.travel(c,task,nav,task.destination,persist,t,config))
      local found,block=t.inspectDown()
      assert(found and (block.name=='computercraft:turtle_normal' or block.name=='computercraft:turtle_advanced'),'rescue recipient turtle missing; refusing world drop')
      assert(e.peripheral.getType('bottom')=='turtle' and e.peripheral.call('bottom','getID')==task.targetWorker,'rescue recipient computer ID mismatch')
      local i=t.getItemDetail(c.slot)
      assert(i and i.name==task.item and not i.nbt and i.count==c.held,'rescue cargo changed before delivery')
      transfer('drop',c.held)
      if c.held==0 then stage('home') end
    else
      assert(c.stage=='home','invalid rescue courier stage')
      assert(R.stationTravel(c,task,nav,task.home,persist,t,config))
      assert(c.held==0 and task.fuelDelivered==task.quantity,'rescue delivery not settled')
      task.phase='completed'; persist()
    end
    return true
  end
  function self:step()
    if fault then return false,fault end
    local ok,result,why=pcall(step)
    if not ok then
      if fault then return false,fault end
      task.phase='blocked'; task.error=tostring(result); persist(); return false,task.error
    end
    return result,why
  end
  function self:resume()
    if fault then return false,fault end
    task.phase='work'; task.error=nil; persist(); return true
  end
  return self
end
return M
