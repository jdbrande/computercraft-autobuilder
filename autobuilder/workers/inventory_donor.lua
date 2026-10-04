local U=require('autobuilder.core.util')
local F=require('autobuilder.factory.factory')
local R=require('autobuilder.workers.resupply')
local M={}
local function journal(task)
  if not task then return false end
  if task.intent or task.digIntent or task.depositIntent or task.pendingMove or task.supplyRequest then return true end
  for _,name in ipairs({'production','cargo','resupply','homeCargo','fuelRecovery'}) do
    if task[name] and task[name].intent then return true end
  end
  return false
end
function M.new(app,e)
  local self={};local t=e.turtle
  local function save() return app:save() end
  local function snapshot()
    local out=R.snapshot(t)
    for _,v in pairs(out) do
      assert(U.shortString(v.name,128) and U.integer(v.count) and v.count>0 and v.count<=1000000
        and (v.nbt==nil or U.shortString(v.nbt,128)),'invalid recovery inventory')
    end
    return out
  end
  function self:active() return app.state.inventoryRecovery~=nil end
  function self:freeze(p)
    if type(p)~='table' or not U.shortString(p.jobId,100) or not U.position(p.position)
      or not U.shortString(p.originalTask,100) then return false,'invalid inventory recovery contract' end
    local contract={jobId=p.jobId,position=U.copy(p.position),originalTask=p.originalTask}
    local s=app.state;local old=s.inventoryRecovery
    if old then return F.equal(old.contract,contract),'inventory recovery contract changed' end
    local pose=s.position;local task=s.currentTask
    if app.busy or s.fuelRecovery or s.poseRecovery or not pose or not pose.known or pose.pending or pose.uncertain
      or U.distance(pose,p.position)~=0 then return false,'inventory recovery requires a confirmed stationary donor' end
    if not task or task.id~=p.originalTask or task.phase~='blocked' or journal(task) then return false,'blocked task with reconciled physical journals required' end
    local before=snapshot()
    F.commit(s,save,function() s.inventoryRecovery={contract=contract,phase='frozen',expected=before,sequence=0};s.status='quarantined' end)
    return true
  end
  function self:status()
    local r=app.state.inventoryRecovery;if not r then return nil end
    return {jobId=r.contract.jobId,position=U.copy(r.contract.position),originalTask=r.contract.originalTask,
      phase=r.phase,sequence=r.sequence,moved=r.moved or 0,transfer=U.copy(r.transfer or r.last),inventory=U.copy(r.expected),error=r.error}
  end
  function self:grant(p)
    local r=app.state.inventoryRecovery
    if not r or type(p)~='table' or p.jobId~=r.contract.jobId or not U.integer(p.sequence) or p.sequence<1 or p.sequence>4096
      or not U.integer(p.slot) or p.slot<1 or p.slot>16 or not U.integer(p.count) or p.count<1 or p.count>64
      or not U.integer(p.courier) or p.courier<0 or p.courier==app.state.id then return false,'invalid recovery transfer grant' end
    local g={sequence=p.sequence,slot=p.slot,count=p.count,courier=p.courier}
    local prior=r.transfer or r.last
    if prior and p.sequence==prior.sequence then
      for k,v in pairs(g) do if prior[k]~=v then return false,'recovery transfer grant changed' end end
      return true
    end
    if r.phase~='frozen' or p.sequence~=r.sequence+1 then return false,'prior recovery transfer is unsettled' end
    if not F.equal(snapshot(),r.expected) then return false,'donor inventory changed while quarantined' end
    local item=r.expected[p.slot]
    if not item or item.count<p.count then return false,'recovery stack is unavailable' end
    g.item=item.name;g.nbt=item.nbt
    F.commit(r,save,function() r.transfer=g;r.sequence=p.sequence;r.moved=0;r.phase='ready';r.error=nil end)
    return true
  end
  local function reconcile(r)
    local i=r.intent;local now=snapshot();local g=r.transfer
    for slot=1,16 do if slot~=g.slot then assert(F.equal(now[slot],i.before[slot]),'unrelated donor inventory changed during recovery') end end
    local a,b=i.before[g.slot],now[g.slot]
    assert(a and a.name==g.item and a.nbt==g.nbt and (not b or b.name==g.item and b.nbt==g.nbt),'recovery item identity changed')
    local moved=a.count-(b and b.count or 0)
    assert(U.integer(moved) and moved>=0 and moved<=g.count,'ambiguous donor transfer quantity')
    F.commit(r,save,function() r.moved=moved;r.expected=now;r.intent=nil;r.phase='sent';r.error=nil end)
  end
  function self:step()
    local r=app.state.inventoryRecovery;if not r or r.phase=='frozen' or r.phase=='sent' then return true end
    local ok,why=pcall(function()
      if r.intent then reconcile(r);return end
      local pose=app.state.position
      assert(pose.known and not pose.pending and not pose.uncertain and U.distance(pose,r.contract.position)==0,'quarantined donor pose changed')
      assert(F.equal(snapshot(),r.expected),'donor inventory changed while quarantined')
      local present,b=t.inspectUp()
      assert(present and (b.name=='computercraft:turtle_normal' or b.name=='computercraft:turtle_advanced'),'recovery courier missing; refusing world drop')
      assert(e.peripheral.getType('top')=='turtle' and e.peripheral.call('top','getID')==r.transfer.courier,'recovery courier ID mismatch')
      F.commit(r,save,function() r.intent={before=snapshot()} end)
      assert(t.select(r.transfer.slot),'cannot select recovery donor stack');t.dropUp(r.transfer.count);reconcile(r)
    end)
    if not ok then
      local detail=tostring(why);pcall(F.commit,r,save,function() r.error=detail end);return false,detail
    end
    return true
  end
  function self:ack(p)
    local r=app.state.inventoryRecovery
    if not r or type(p)~='table' or p.jobId~=r.contract.jobId or p.sequence~=r.sequence or p.moved~=r.moved then return false,'recovery receipt mismatch' end
    if r.phase=='frozen' and r.last then return true end
    if r.phase~='sent' or r.intent or not F.equal(snapshot(),r.expected) then return false,'recovery transfer needs reconciliation' end
    F.commit(r,save,function() r.last=r.transfer;r.transfer=nil;r.phase='frozen';r.error=nil end)
    return true
  end
  return self
end
return M
