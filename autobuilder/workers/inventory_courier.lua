local U=require('autobuilder.core.util')
local F=require('autobuilder.factory.factory')
local R=require('autobuilder.workers.resupply')
local M={}
function M.valid(j)
  return type(j)=='table' and j.type=='RECOVER_CARGO' and U.position(j.source) and U.position(j.home)
    and U.integer(j.targetWorker) and j.targetWorker>=0 and U.shortString(j.item,128)
    and (j.nbt==nil or U.shortString(j.nbt,128)) and U.integer(j.quantity) and j.quantity>=1 and j.quantity<=64
    and U.shortString(j.recoveryId,100) and U.integer(j.recoverySequence) and j.recoverySequence>=1 and j.recoverySequence<=4096
end
function M.receipt(task)
  if task.type~='RECOVER_CARGO' then return nil end
  local c=task.recoveryCargo or {}
  return {sequence=task.recoverySequence,stage=c.stage or 'source',capacity=c.capacity or 0,pickedUp=c.pickedUp or 0,delivered=c.delivered or 0}
end
function M.validReceipt(r)
  return type(r)=='table' and U.integer(r.sequence) and r.sequence>=1 and r.sequence<=4096
    and ({source=true,receiving=true,home=true})[r.stage]==true and U.integer(r.capacity) and r.capacity>=0 and r.capacity<=64
    and U.integer(r.pickedUp) and r.pickedUp>=0 and r.pickedUp<=r.capacity
    and U.integer(r.delivered) and r.delivered>=0 and r.delivered<=r.pickedUp
end
function M.new(task,e,config,nav,save)
  assert(M.valid(task),'invalid inventory recovery courier contract')
  local self={task=task};local t=e.turtle;local fault
  task.recoveryCargo=task.recoveryCargo or {stage='source',pickedUp=0,delivered=0}
  local c=task.recoveryCargo
  local function persist()
    local called,ok,why=pcall(save)
    if not called or not ok then fault='recovery courier checkpoint failed: '..tostring(called and why or ok);error(fault,0) end
    return true
  end
  local function identity(i) return i and i.name==task.item and i.nbt==task.nbt end
  local function same(now,expected) assert(F.equal(now,expected),'recovery courier inventory changed outside its transfer') end
  function self:received(p)
    if fault then return false,fault end
    if type(p)~='table' or p.jobId~=task.id or p.sequence~=task.recoverySequence
      or not U.integer(p.moved) or p.moved<0 or p.moved>task.quantity then return false,'invalid donor delivery receipt' end
    if c.stage=='home' or task.phase=='completed' then return c.pickedUp==p.moved,'donor delivery receipt changed' end
    if c.stage~='receiving' then return false,'courier has not reserved receiving inventory' end
    local ok,why=pcall(function()
      assert(nav.pose.known and not nav.pose.pending and not nav.pose.uncertain and U.distance(nav.pose,task.source)==0,'receiving courier moved')
      local now=R.snapshot(t);local held,total={},0
      for slot=1,16 do
        local a,b=c.before[slot],now[slot]
        if identity(b) and (not a or identity(a)) then
          local n=b.count-(a and a.count or 0);assert(n>=0,'receiving inventory decreased');held[slot]=n;total=total+n
        else assert(F.equal(a,b),'foreign recovery cargo or unrelated inventory change') end
      end
      assert(total==p.moved and total<=c.capacity,'donor and courier quantities disagree')
      F.commit(c,persist,function() c.pickedUp=total;c.held=held;c.expected=now;c.stage='home';c.route=nil end)
      task.phase='work';task.error=nil;persist()
    end)
    return ok,not ok and tostring(why) or nil
  end
  local function reconcile()
    local i=c.intent;if not i then return end
    local now=R.snapshot(t)
    for slot=1,16 do if slot~=i.slot then assert(F.equal(now[slot],i.before[slot]),'unrelated inventory changed during recovery deposit') end end
    local a,b=i.before[i.slot],now[i.slot]
    assert(identity(a) and (not b or identity(b)),'recovery deposit item identity changed')
    local n=a.count-(b and b.count or 0)
    assert(U.integer(n) and n>=0 and n<=i.limit,'ambiguous recovery deposit quantity')
    F.commit(c,persist,function() c.held[i.slot]=c.held[i.slot]-n;c.delivered=c.delivered+n;c.expected=now;c.intent=nil end)
    task.progress=c.delivered;task.phase='work';task.error=nil;persist();return n
  end
  local function step()
    if task.paused then return false,'inventory recovery paused' end
    if task.phase=='completed' then return true end
    if task.phase=='blocked' and not c.intent then return false,task.error end
    assert(nav.pose.known and not nav.pose.pending and not nav.pose.uncertain,'trusted recovery courier pose required')
    if c.intent then reconcile() end
    task.phase='work'
    if not c.started then
      assert(U.position(config.depot) and U.distance(config.depot,task.home)==0,'recovery destination differs from courier depot')
      local fuel=t.getFuelLevel();local required=require('autobuilder.workers.fuel_courier').budget(nav.pose,task.source,task.home,task.home,config.minimumFuelReserve or 100)
      assert(fuel=='unlimited' or type(fuel)=='number' and fuel>=required,'insufficient recovery courier return fuel')
      F.commit(c,persist,function() c.started=true end)
    end
    if c.stage=='source' then
      assert(R.travel(c,task,nav,task.source,persist,t,config))
      local found,b=t.inspectDown()
      assert(found and (b.name=='computercraft:turtle_normal' or b.name=='computercraft:turtle_advanced'),'recovery donor turtle missing')
      assert(e.peripheral.getType('bottom')=='turtle' and e.peripheral.call('bottom','getID')==task.targetWorker,'recovery donor computer ID mismatch')
      local before=R.snapshot(t);local capacity=0
      for slot=1,16 do local item=before[slot];if not item or identity(item) then capacity=capacity+math.max(0,t.getItemSpace(slot)) end end
      capacity=math.min(task.quantity,capacity);assert(capacity>0,'no recovery receiving capacity')
      F.commit(c,persist,function() c.before=before;c.capacity=capacity;c.stage='receiving';c.route=nil end)
    elseif c.stage=='receiving' then
      return true -- The controller reconciles the donor before authorizing departure.
    else
      assert(c.stage=='home','invalid recovery courier stage');same(R.snapshot(t),c.expected)
      assert(R.travel(c,task,nav,task.home,persist,t,config))
      if c.delivered==c.pickedUp then task.phase='completed';task.progress=c.delivered;persist();return true end
      assert(R.container(t,'down'))
      for slot=1,16 do local n=c.held[slot] or 0;if n>0 then
        assert(t.select(slot),'cannot select recovery deposit stack')
        F.commit(c,persist,function() c.intent={slot=slot,limit=n,before=R.snapshot(t)} end)
        t.dropDown(n);assert(reconcile()>0,'recovery destination is full');return true
      end end
      error('recovery cargo count is inconsistent')
    end
    return true
  end
  function self:step()
    if fault then return false,fault end
    local ok,result,why=pcall(step)
    if ok then return result,why end
    if fault then return false,fault end
    task.phase='blocked';task.error=tostring(result);local saved,err=pcall(persist);return false,saved and task.error or err
  end
  function self:resume() if fault then return false,fault end;task.phase='work';task.error=nil;persist();return true end
  return self
end
return M
