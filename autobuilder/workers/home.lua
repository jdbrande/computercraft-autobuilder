local U=require('autobuilder.core.util')
local R=require('autobuilder.workers.resupply')
local Cargo=require('autobuilder.storage.returns')
local F=require('autobuilder.factory.factory')
local M={}
function M.new(task,e,config,nav,save)
  assert(Cargo.validContract(task),'invalid home cargo contract')
  local t=e.turtle;local self={task=task};local fault
  local function persist()
    local ok,result,why=pcall(save)
    if not ok or not result then fault='home cargo checkpoint failed: '..tostring(ok and why or result);error(fault,0) end
  end
  task.homeCargo=task.homeCargo or {deposited={},sequence=0}
  local s=task.homeCargo
  local function reconcile()
    local i=s.intent;if not i then return end
    assert(i.kind=='drop' and U.position(i.position) and U.distance(i.position,task.home)==0 and U.distance(nav.pose,i.position)==0,'home drop position changed')
    local n,why=R.delta(t,i);assert(n,why)
    assert((s.deposited[i.item] or 0)+n<=(task.returning.items[i.item] or 0),'home deposit exceeds contract')
    F.commit(s,save,function() s.deposited[i.item]=(s.deposited[i.item] or 0)+n;s.sequence=s.sequence+1;s.intent=nil end)
    task.progress=0;for _,count in pairs(s.deposited) do task.progress=task.progress+count end
    task.phase='work';task.error=nil;persist();return n
  end
  local function step()
    if task.paused then return false,'home return paused' end
    if task.phase=='completed' then return true end
    if task.phase=='blocked' and not s.intent then return false,task.error end
    assert(U.position(config.depot) and U.distance(config.depot,task.home)==0,'home return differs from configured depot')
    assert(nav.pose.known and U.heading(nav.pose.heading) and not nav.pose.pending and not nav.pose.uncertain,'trusted position required for home return')
    reconcile()
    local cargo=Cargo.observe(t,config);assert(not cargo.error,cargo.error)
    local remaining={};local deposited=0
    for item,n in pairs(task.returning.items) do
      local done=s.deposited[item] or 0;assert(done<=n,'home deposit exceeds assignment')
      deposited=deposited+done;if n>done then remaining[item]=n-done end
    end
    assert(F.equal(remaining,cargo.items),'home cargo differs from assigned remaining inventory')
    task.progress=deposited
    task.homeRoute=task.homeRoute or {}
    local ok,why=R.travel(task.homeRoute,task,nav,config.depot,persist,t,config)
    if not ok then error(why,0) end
    if not next(remaining) then task.phase='completed';task.error=nil;persist();return true end
    local suffix,why=R.container(t,'down');if not suffix then task.homeRetryable=true;error(why,0) end
    local reserved=R.reserved(config)
    for slot=1,16 do if not reserved[slot] then
      local v=t.getItemDetail(slot)
      if v then
        assert(t.select(slot),'cannot select return cargo')
        s.intent={kind='drop',position=U.copy(task.home),slot=slot,item=v.name,limit=v.count,before=R.snapshot(t)};persist()
        t.dropDown(v.count);local n=reconcile()
        if n==0 then task.homeRetryable=true;error('home cargo container full or unavailable',0) end
        task.homeRetryable=nil;return true
      end
    end end
    error('home cargo slots unavailable',0)
  end
  function self:step()
    if fault then return false,fault end
    local ok,result,why=pcall(step)
    if ok then return result,why end
    if fault then return false,fault end
    task.phase='blocked';task.error=tostring(result)
    local saved,err=pcall(persist);return false,saved and task.error or err
  end
  function self:resume()
    if fault then return false,fault end
    task.phase='work';task.error=nil;persist();return true
  end
  return self
end
return M
