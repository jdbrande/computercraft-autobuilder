local U=require('autobuilder.core.util')
local F=require('autobuilder.factory.factory')
local R=require('autobuilder.workers.resupply')
local Receipts=require('autobuilder.core.receipts')
local M={}
function M.needsFuel(task)
  if not task or task.phase~='blocked' then return false end
  local err=tostring(task.error):lower()
  return task.blockedCategory=='fuel' or err:find('insufficient fuel',1,true)~=nil
    or err:find('fuel supply missing',1,true)~=nil
end
function M.new(app,config,e)
  local self={}; local t=e.turtle
  local save=function() return app:save() end
  local function completed(id) return (app.state.completedFuelRescues or {})[id] end
  local function replace(record)
    local old=app.state.fuelRecovery; app.state.fuelRecovery=record
    local called,ok,why=pcall(save)
    if not called or not ok then app.state.fuelRecovery=old; error(tostring(called and why or ok),0) end
  end
  function self:active() return app.state.fuelRecovery~=nil end
  function self:status(id)
    local r=app.state.fuelRecovery or id and completed(id)
    if not r then return nil end
    return {jobId=r.contract.jobId,phase=r.phase,quantity=r.quantity or 0,capacity=r.capacity,
      position=U.copy(r.contract.position),fuel=t.getFuelLevel(),error=r.error}
  end
  function self:freeze(p)
    if not config.fuel.enabled or app.busy then return false,'worker is disabled or physically busy' end
    if not U.shortString(p.jobId,100) or not U.position(p.position) or not U.integer(p.quantity)
      or p.quantity<1 or p.quantity>64 or not config.fuel.values[p.item]
      or not U.integer(p.fuelTarget) or p.fuelTarget<1 or p.fuelTarget>100000000 then return false,'invalid rescue contract' end
    local old=app.state.fuelRecovery or completed(p.jobId)
    if old then return F.equal(old.contract,p),'rescue contract changed' end
    if Receipts.archived(app.state,'completedFuelRescues',p.jobId) then return false,'rescue receipt archived' end
    local pose=app.state.position; local task=app.state.currentTask
    if not pose.known or pose.pending or pose.uncertain or U.distance(pose,p.position)~=0 then return false,'rescue requires a confirmed stationary pose' end
    if task and not M.needsFuel(task) then return false,'original task is not blocked on fuel' end
    if task and (task.intent or task.digIntent or task.depositIntent or task.production and task.production.intent
      or task.cargo and task.cargo.intent or task.resupply and task.resupply.intent) then return false,'physical inventory journal needs recovery first' end
    local before=R.snapshot(t); local capacity=0
    for slot=1,16 do
      local i=before[slot]
      if not i then capacity=capacity+1 -- conservative capacity for an unknown stack size
      elseif i.name==p.item and not i.nbt then capacity=capacity+math.max(0,t.getItemSpace(slot)) end
    end
    capacity=math.min(64,capacity)
    if capacity<1 then return false,'no receiving inventory capacity' end
    replace({contract=U.copy(p),phase='frozen',before=before,capacity=capacity,originalTask=task and task.id})
    return true
  end
  local function receipt(r,quantity)
    local now=R.snapshot(t); local added={}; local total=0
    for slot=1,16 do
      local a,b=r.before[slot],now[slot]
      if b and b.name==r.contract.item and not b.nbt and (not a or a.name==b.name and not a.nbt) then
        local delta=b.count-(a and a.count or 0)
        assert(delta>=0,'recipient fuel inventory decreased while frozen')
        if delta>0 then added[slot]=delta; total=total+delta end
      else assert(F.equal(a,b),'unrelated recipient inventory changed while frozen') end
    end
    assert(total==quantity and total<=r.capacity and total<=r.contract.quantity,'delivery does not match measured recipient quantity')
    return added
  end
  function self:consume(p)
    local r=app.state.fuelRecovery
    if not r or r.contract.jobId~=p.jobId then return false,'unknown frozen rescue' end
    if not U.integer(p.quantity) or p.quantity<1 or p.quantity>64 then return false,'invalid receipt quantity' end
    if r.phase~='frozen' then return r.quantity==p.quantity,'delivery receipt changed' end
    local ok,added=pcall(receipt,r,p.quantity); if not ok then return false,tostring(added) end
    F.commit(r,save,function() r.received=added; r.expected=R.snapshot(t); r.quantity=p.quantity; r.consumed={}; r.phase='consuming' end)
    return true
  end
  local function reconcile(r)
    local i=r.intent; local now=R.snapshot(t)
    for slot=1,16 do if slot~=i.slot then assert(F.equal(now[slot],i.before[slot]),'unrelated inventory changed during refuel') end end
    local a,b=i.before[i.slot],now[i.slot]; local consumed
    if not b then consumed=a.count
    elseif b.name==r.contract.item and not b.nbt then consumed=a.count-b.count
    elseif b.name==config.fuel.returns[r.contract.item] and not b.nbt and b.count==a.count then consumed=a.count
    else error('ambiguous refuel container or item') end
    local fuel=t.getFuelLevel()
    assert(U.integer(consumed) and consumed>=0 and consumed<=i.limit,'ambiguous consumed fuel quantity')
    assert(type(fuel)=='number' and fuel>=i.fuel and (consumed==0 or fuel>i.fuel),'ambiguous measured fuel gain')
    F.commit(r,save,function()
      r.consumed[i.slot]=(r.consumed[i.slot] or 0)+consumed; r.expected=now; r.intent=nil
      if consumed==0 then r.error='native refuel made no progress' else r.error=nil end
    end)
    return consumed>0
  end
  function self:step()
    local r=app.state.fuelRecovery
    if not r or r.phase~='consuming' then return true end
    local ok,why=pcall(function()
      if r.intent then reconcile(r); return end
      assert(F.equal(R.snapshot(t),r.expected),'recipient inventory changed after delivery receipt')
      for slot=1,16 do
        local left=(r.received[slot] or 0)-(r.consumed[slot] or 0)
        if left>0 then
          local before=R.snapshot(t); local held=before[slot]
          assert(held and held.name==r.contract.item and not held.nbt and held.count>=left,'granted fuel is missing')
          F.commit(r,save,function() r.intent={slot=slot,limit=left,before=before,fuel=t.getFuelLevel()} end)
          assert(t.select(slot),'cannot select rescue fuel'); t.refuel(left); reconcile(r); return
        end
      end
      F.commit(r,save,function() r.phase='consumed'; r.error=nil end)
    end)
    if not ok then r.error=tostring(why); save(); return false,r.error end
    return true
  end
  function self:release(p)
    local r=app.state.fuelRecovery
    if not r then return completed(p.jobId)~=nil,'unknown rescue' end
    if r.contract.jobId~=p.jobId or r.phase~='consumed' or r.intent then return false,'rescue receipt is not settled' end
    local s=app.state
    local old,archive,resume=U.copy(s.completedFuelRescues),U.copy(s.completedFuelRescuesArchive),s.fuelResume
    Receipts.record(s,'completedFuelRescues',p.jobId,{contract=U.copy(r.contract),phase='released',quantity=r.quantity,capacity=r.capacity})
    if type(t.getFuelLevel())=='number' and t.getFuelLevel()>=r.contract.fuelTarget then s.fuelResume=r.originalTask end
    local ok,why=pcall(replace,nil)
    if not ok then s.completedFuelRescues=old; s.completedFuelRescuesArchive=archive; s.fuelResume=resume; error(why,0) end
    return true
  end
  return self
end
return M
