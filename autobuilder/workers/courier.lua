local U=require('autobuilder.core.util')
local R=require('autobuilder.workers.resupply')
local M={}
function M.new(task,e,config,nav,save)
  assert(U.position(task.source) and U.position(task.destination) and U.shortString(task.item,128) and U.integer(task.quantity) and task.quantity>0 and task.quantity<=1000000,'invalid courier task')
  local t=e.turtle; local self={task=task}; local fault
  task.phase=task.phase or 'setup'; task.delivered=task.delivered or 0; task.progress=task.delivered
  task.cargo=task.cargo or {stage='source',held=0}; local s=task.cargo
  local function persist()
    local ok,v,err=pcall(save)
    if not ok or not v then fault='courier checkpoint failed: '..tostring(ok and err or v); error(fault,0) end
  end
  local function block(err)
    task.logisticsRetryable=task.logistics and err=='destination container full or unavailable' or nil
    task.phase='blocked'; task.error=tostring(err); persist(); return false,task.error
  end
  local function reconcile()
    local i=s.intent; if not i then return 0 end
    local delta,err=R.delta(t,i); assert(delta,err)
    if i.kind=='drop' then s.held=s.held-delta; task.delivered=task.delivered+delta; task.progress=task.delivered
    else s.held=s.held+delta;task.pickedUp=(task.pickedUp or 0)+delta end
    task.transportSequence=(task.transportSequence or 0)+1
    s.intent=nil; persist(); return delta
  end
  local function switch(stage)
    s.stage=stage; s.route=nil; persist(); return true
  end
  local function step()
    if task.phase=='completed' then return true end
    if task.phase=='blocked' then return false,task.error end
    if not nav.pose.known or nav.pose.pending or nav.pose.uncertain then return block('trusted position required for courier') end
    task.phase='work'; reconcile()
    if task.delivered>=task.quantity then
      if task.logistics then
        if s.stage~='home' then return switch('home') end
        local ok,err=R.travel(s,task,nav,config.depot,persist,t,config);if not ok then return block(err) end
      end
      task.phase='completed'; persist(); return true
    end
    local target=s.stage=='source' and task.source or task.destination
    local ok,err=R.travel(s,task,nav,target,persist); if not ok then return block(err) end
    local suffix,why=R.container(t,'down'); if not suffix then return block(why) end
    if s.stage=='source' then
      if not s.slot then
        s.slot=R.slot(t,config,task.item,true)
        if not s.slot then return block('inventory full before cargo pickup') end
        persist()
      end
      local item=t.getItemDetail(s.slot)
      if item and (item.name~=task.item or item.nbt or item.count~=s.held) or not item and s.held~=0 then return block('cargo inventory changed outside courier') end
      local space=item and (t.getItemSpace and t.getItemSpace(s.slot) or 0) or 1
      local remaining=task.quantity-task.delivered-s.held
      if remaining<=0 or space<=0 then return switch('destination') end
      local limit=math.min(space,remaining)
      assert(t.select(s.slot),'cannot select cargo slot')
      s.intent={kind='suck',slot=s.slot,item=task.item,limit=limit,before=R.snapshot(t)}; persist()
      t.suckDown(limit); local moved=reconcile()
      if moved==0 then if s.held>0 then return switch('destination') end; return block('source cargo missing or unavailable') end
      if s.held==task.quantity-task.delivered then return switch('destination') end
      return true
    end
    if s.held<=0 then s.slot=nil; return switch('source') end
    local item=t.getItemDetail(s.slot)
    if not item or item.name~=task.item or item.count~=s.held or item.nbt then return block('cargo missing or changed before delivery') end
    assert(t.select(s.slot),'cannot select delivery cargo')
    s.intent={kind='drop',slot=s.slot,item=task.item,limit=s.held,before=R.snapshot(t)}; persist()
    t.dropDown(s.held); local moved=reconcile()
    if moved==0 then return block('destination container full or unavailable') end
    if task.delivered>=task.quantity then
      if task.logistics then return switch('home') end
      task.phase='completed'; persist(); return true
    end
    if s.held==0 then s.slot=nil; return switch('source') end
    return true
  end
  function self:step()
    if fault then return false,fault end
    local ok,result,err=pcall(step)
    if not ok then if fault then return false,fault end; return block(result) end
    return result,err
  end
  function self:resume()
    if fault then return false,fault end
    if task.phase~='blocked' then return false,'courier is not blocked' end
    task.phase='work'; task.error=nil; persist(); return true
  end
  return self
end
return M
