-- Managed plots only. Each physical mutation has durable intent and observed recovery.
local U=require('autobuilder.core.util')
local M={}
local Registry=require('autobuilder.resources.renewables')
local containers={['minecraft:chest']=true,['minecraft:trapped_chest']=true,['minecraft:barrel']=true}
local soil={['minecraft:dirt']=true,['minecraft:grass_block']=true,['minecraft:podzol']=true,['minecraft:coarse_dirt']=true,['minecraft:rooted_dirt']=true,['minecraft:moss_block']=true}
local function same(a,b)
  if not a or not b or a.name~=b.name then return false end
  for k,v in pairs(a.state or {}) do if tostring((b.state or {})[k])~=tostring(v) then return false end end
  return true
end
function M.new(task,e,config,nav,save,treeMode)
  assert(type(task)=='table' and U.integer(task.quantity) and task.quantity>0 and task.quantity<=262144,'bounded renewable quantity required')
  assert(e and e.turtle and nav and type(save)=='function','renewable hardware/navigation/persistence required')
  config=config or {}; local t=e.turtle; local farm=task.farm or {}
  local ok,spec=pcall(Registry.forFarm,farm,config)
  local self={task=task}; local fault; local invalid; local height=farm.maxHeight or 8; local ceiling=-math.huge
  if not ok then invalid=tostring(spec);spec=nil
  elseif not spec or (treeMode and spec.mode~='tree') or (not treeMode and spec.mode=='tree') then invalid='unsupported managed farm kind: '..tostring(farm.kind)
  elseif task.item~=spec.item then invalid='farm output does not match requested item'
  else
    farm.adapter=U.copy(spec);spec.tree=spec.mode=='tree';spec.column=spec.mode=='column'
  end
  if not U.position(config.depot) then invalid='valid depot position required' end
  if not U.integer(height) or height<2 or height>32 then invalid='maxHeight must be 2..32'; height=8 end
  if type(farm.sites)~='table' or #farm.sites<1 or #farm.sites>64 then invalid='farm requires 1..64 explicit sites'
  else
    local seen={}; local entries=0
    for k,p in pairs(farm.sites) do
      entries=entries+1
      if not U.integer(k) or k<1 or k>#farm.sites or not U.position(p) then invalid='invalid farm site'
      else
        local key=p.x..','..p.y..','..p.z
        if seen[key] then invalid='duplicate farm site' end
        seen[key]=true; ceiling=math.max(ceiling,p.y+height+2)
      end
    end
    if entries~=#farm.sites then invalid='farm sites must be a dense array' end
  end
  if farm.travelHeight~=nil then
    if not U.integer(farm.travelHeight) or farm.travelHeight<ceiling or farm.travelHeight>30000000 then invalid='travelHeight must clear every configured column' else ceiling=farm.travelHeight end
  end
  local plantingReserve=0
  if not invalid then local valid,n=pcall(Registry.reserve,farm);if valid then plantingReserve=n else invalid=tostring(n) end end
  task.phase=task.phase or 'setup'; task.stage=task.stage or 'harvest'; task.site=task.site or 1
  task.progress=task.progress or 0; task.delivered=task.delivered or 0
  local reserved={[config.fuelSlot or 15]=true,[16]=true}
  for _,slot in ipairs(config.reservedSlots or {}) do reserved[slot]=true end
  local function persist()
    local ok,result,err=pcall(save)
    if not ok or not result then fault='renewable checkpoint failed: '..tostring(ok and err or result); error(fault,0) end
    return true
  end
  local function block(reason,category)
    task.resumePhase=task.phase~='blocked' and task.phase or task.resumePhase
    task.phase='blocked'; task.error=tostring(reason); task.blockedCategory=category; persist(); return false,task.error
  end
  local function restricted(p)
    for _,a in ipairs(config.restrictedAreas or {}) do
      if p.x>=a.min.x and p.x<=a.max.x and p.y>=a.min.y and p.y<=a.max.y and p.z>=a.min.z and p.z<=a.max.z then return true end
    end
    return false
  end
  local function inspect(suffix)
    local ok,present,b=pcall(t['inspect'..(suffix or 'Down')])
    if not ok then return nil,nil,'inspection failed: '..tostring(present) end
    if type(present)~='boolean' or present and (type(b)~='table' or type(b.name)~='string') then return nil,nil,'invalid inspection response' end
    return present,b
  end
  local function snapshot()
    local out={}
    for slot=1,16 do local item=t.getItemDetail(slot); if item then out[slot]={name=item.name,count=item.count} end end
    return out
  end
  local function equalInventory(a,b)
    for slot=1,16 do local x,y=a[slot],b[slot]; if (x and not y) or (y and not x) or (x and (x.name~=y.name or x.count~=y.count)) then return false end end
    return true
  end
  local function total(inv,name)
    local n=0; for slot,item in pairs(inv) do if not reserved[slot] and item.name==name then n=n+item.count end end; return n
  end
  local function slotFor(name)
    for slot=1,16 do local item=t.getItemDetail(slot); if not reserved[slot] and item and item.name==name then return slot,item.count end end
  end
  local function freeSlot()
    local count,first=0,nil
    for slot=1,16 do if not reserved[slot] and t.getItemCount(slot)==0 then count=count+1; first=first or slot end end
    return first,count
  end
  local function missing()
    task.missingItem=spec.seed; task.missingCount=1; return block('planting item missing: '..spec.seed,'missing_inventory')
  end
  local function routeCost(from,to)
    local high=math.max(ceiling,from.y,to.y)
    return high-from.y+math.abs(from.x-to.x)+math.abs(from.z-to.z)+high-to.y
  end
  local function move(p)
    if restricted(p) then return false,'farm destination is protected' end
    local pose=nav.pose
    if U.distance(pose,p)==0 then return true end
    -- Once inside a cleared column, vertical traversal does not leave its bounds.
    if pose.x==p.x and pose.z==p.z then return nav:goTo(p) end
    local high=math.max(ceiling,pose.y,p.y)
    local ok,err=nav:goTo({x=pose.x,y=high,z=pose.z}); if not ok then return false,err end
    ok,err=nav:goTo({x=p.x,y=high,z=p.z}); if not ok then return false,err end
    return nav:goTo(p)
  end
  local function nextSite()
    task.site=task.site+1; task.cursor=nil; task.harvestedSite=nil; task.stage='harvest'
    if task.site>#farm.sites or task.delivered+math.max(0,total(snapshot(),task.item)-(spec.seed==task.item and plantingReserve or 0))>=task.quantity then task.stage='deposit'; task.passFinished=true end
  end
  local function finishMutation()
    task.intent=nil;task.plantSoilSite=nil;persist();if nav.workDone then nav.workDone() end;return true
  end
  local function permit(target)
    if not nav.workGuard then return false,'controller mutation permission required' end
    return nav.workGuard(target)
  end
  local function finishDig(i,after)
    local gained=total(after,task.item)-total(i.inventory,task.item)
    if gained<0 then return false,'harvest inventory decreased unexpectedly' end
    if i.block.name==spec.block and gained<1 then return false,'harvest target disappeared without collected output' end
    -- Other inventory changes must be additions, never replacement/removal of cargo.
    for slot,before in pairs(i.inventory) do local now=after[slot]; if not now or now.name~=before.name or now.count<before.count then return false,'inventory changed ambiguously during harvest' end end
    task.progress=task.progress+gained
    if i.block.name==spec.block then task.harvestedSite=true end
    if spec.seed and (not spec.tree or i.target.y==farm.sites[task.site].y) then task.stage='plant'
    else task.cursor=task.cursor-1 end
    return finishMutation()
  end
  local function recover()
    local i=task.intent; if not i then return true end
    local ok,err=move(i.stand); if not ok then return false,err end
    local present,b,why=inspect('Down'); if why then return false,why end
    local after=snapshot()
    if i.kind=='dig' then
      if present and same(i.block,b) and equalInventory(after,i.inventory) then return finishMutation() end
      if not present then return finishDig(i,after) end
      return false,'ambiguous harvest outcome: block or inventory differs'
    elseif i.kind=='plant' then
      local item=after[i.slot]; local count=item and item.count or 0
      if item and item.name~=i.item then return false,'planting slot changed during recovery' end
      if present and b.name==i.block and count==i.before-1 then
        task.missingItem=nil; task.missingCount=nil; nextSite(); return finishMutation()
      end
      if not present and count==i.before then return finishMutation() end
      return false,'ambiguous planting outcome: block/inventory do not match intent'
    elseif i.kind=='drop' then
      if not present or not containers[b.name] then return false,'depot chest missing during delivery recovery' end
      local item=after[i.slot]; local count=item and item.count or 0
      if item and item.name~=i.item or count>i.before or i.before-count>i.amount then return false,'ambiguous delivery inventory' end
      for slot,before in pairs(i.inventory) do
        if slot~=i.slot then local now=after[slot]; if not now or now.name~=before.name or now.count~=before.count then return false,'other cargo changed during delivery' end end
      end
      if i.item==task.item then task.delivered=task.delivered+i.before-count end
      task.intent=nil; return persist()
    end
    return false,'unknown renewable action intent'
  end
  local function returnToDepot(reason)
    if task.stage~='deposit' then task.returnStage=task.stage; task.stage='deposit' end
    task.returnReason=reason; return persist()
  end
  local function branchCheck()
    if not spec.tree then return true end
    for _,heading in ipairs({'north','east','south','west'}) do
      local ok,err=nav:face(heading); if not ok then return false,err end
      local found,b,why=inspect(''); if why then return false,why end
      if found and (b.name:match('_log$') or b.name:match('_wood$')) then return false,'branched or multi-column tree requires manual harvest' end
    end
    return true
  end
  local function deposit()
    local ok,err=move(config.depot); if not ok then return block(err,'inaccessible') end
    local present,b,why=inspect('Down'); if why or not present or not containers[b.name] then return block(why or 'depot chest missing; refusing world drop','depot') end
    -- Keep seeds/saplings to maintain every configured planting site.
    local keep=plantingReserve
    for slot=1,16 do
      local item=t.getItemDetail(slot)
      if item and not reserved[slot] then
        local retained=item.name==spec.seed and math.min(keep,item.count) or 0
        if item.name==spec.seed then keep=keep-retained end
        local amount=item.count-retained
        if amount>0 then
          assert(t.select(slot),'cannot select delivery slot')
          task.intent={kind='drop',stand=U.copy(config.depot),slot=slot,item=item.name,before=item.count,amount=amount,inventory=snapshot()}; persist()
          local callOK,result,detail=pcall(t.dropDown,amount)
          if not callOK then return block('delivery hardware error: '..tostring(result),'ambiguous') end
          local moved=item.count-t.getItemCount(slot)
          ok,err=recover(); if not ok then return block(err,'ambiguous') end
          if moved==0 then return block(detail or 'depot chest full','depot_full') end
          return true
        end
      end
    end
    if task.returnStage then
      task.stage=task.returnStage; task.returnStage=nil
      if task.returnReason=='fuel' then task.returnReason=nil; return block('fuel reserve insufficient for managed farm route','fuel') end
      local _,empty=freeSlot()
      if task.returnReason=='inventory' and empty<2 then task.returnReason=nil; return block('two unreserved harvest slots are required','inventory_full') end
      task.returnReason=nil; return persist()
    end
    if task.delivered>=task.quantity then task.phase='completed'; task.error=nil; return persist() end
    return block('configured farm has no more mature yield; waiting for growth','immature')
  end
  function self:resume()
    if fault then return false,fault end
    if task.phase~='blocked' then return false,'renewable task is not blocked' end
    if task.blockedCategory=='immature' then task.site=1; task.cursor=nil; task.stage='harvest'; task.passFinished=nil; task.harvestedSite=nil end
    task.phase=task.resumePhase or 'work'; task.error=nil; task.blockedCategory=nil; task.missingItem=nil; task.missingCount=nil
    return persist()
  end
  function self:step()
    if fault then return false,fault end
    if task.phase=='completed' then return true end
    if task.phase=='blocked' then return false,task.error end
    if invalid then return block(invalid,'unsupported') end
    local pose=nav.pose
    if not pose or not pose.known or pose.pending or pose.uncertain or not U.position(pose) or not U.heading(pose.heading) then return block('trusted position and heading required','inaccessible') end
    task.phase='work'
    if task.intent then local ok,err=recover(); if not ok then return block(err,'ambiguous') end; return true end
    if task.stage=='deposit' then return deposit() end
    if task.site>#farm.sites then task.stage='deposit'; return persist() end
    local site=farm.sites[task.site]
    if task.cursor==nil then task.cursor=(spec.tree or spec.column) and site.y+height-1 or site.y end
    local minimum=spec.column and site.y+1 or site.y
    if task.cursor<minimum and task.stage~='plant' then nextSite(); return persist() end
    local target={x=site.x,y=task.stage=='plant' and site.y or task.cursor,z=site.z}
    local stand={x=target.x,y=target.y+1,z=target.z}
    if restricted(target) then return block('managed target is protected','protected') end
    local fuel=t.getFuelLevel()
    if fuel~='unlimited' then
      if not U.finite(fuel) then return block('invalid fuel response','fuel') end
      local required=routeCost(pose,stand)+routeCost(stand,config.depot)+(config.minimumFuelReserve or 100)+4
      if fuel<required then return returnToDepot('fuel') end
    end
    local ok,err=move(stand); if not ok then return block(err,'inaccessible') end
    ok,err=branchCheck(); if not ok then return block(err,'unsupported') end
    local present,b,why=inspect('Down'); if why then return block(why,'inaccessible') end
    if task.stage=='plant' then
      if present then return block('planting target changed before planting','ambiguous') end
      local slot,before=slotFor(spec.seed); if not slot then return missing() end
      -- A solid turtle in the empty crop cell converts farmland to dirt. Native
      -- seed placement validates farmland without occupying or changing it.
      if spec.tree and task.plantSoilSite~=task.site then
        -- Save the observation before the ascent: its movement grant may arrive
        -- on a later tick or after reboot. Repeating the descent would consume
        -- that grant and prevent replanting indefinitely.
        ok,err=nav:goTo(target); if not ok then return block(err,'inaccessible') end
        local ground,base,readError=inspect('Down')
        if readError or not ground or (spec.tree and not soil[base.name]) or (not spec.tree and base.name~='minecraft:farmland') then return block(readError or 'planting soil is missing or unsupported','unsupported') end
        task.plantSoilSite=task.site;return persist()
      end
      ok,err=permit(target);if not ok then return block(err,'protected') end
      assert(t.select(slot),'cannot select planting item')
      task.intent={kind='plant',stand=stand,target=target,slot=slot,item=spec.seed,before=before,block=spec.tree and spec.seed or spec.block}; persist()
      local callOK,result,detail=pcall(t.placeDown)
      if not callOK then return block('plant hardware error: '..tostring(result),'ambiguous') end
      ok,err=recover(); if not ok then return block(err,'ambiguous') end
      if not result then return block(detail or 'planting failed','placement') end
      if task.stage=='plant' then return block('planting action left its target unchanged','placement') end
      return true
    end
    if not present then
      if not spec.column and target.y==site.y and task.harvestedSite then task.stage='plant'
      else task.cursor=task.cursor-1 end
      return persist()
    end
    if (spec.tree and b.name==spec.seed) or (b.name==spec.block and not spec.column and not spec.tree and tonumber((b.state or {}).age)~=spec.age) then nextSite(); return persist() end
    if b.name~=spec.block and b.name~=spec.leaves then return block('foreign block in managed column: '..b.name,'unsupported') end
    if (config.protectedBlocks or {})[b.name] then return block('protected farm block: '..b.name,'protected') end
    if spec.tree and b.name==spec.block and (b.state or {}).axis~='y' then return block('nonvertical tree log is unsupported','unsupported') end
    if b.name==spec.block and spec.seed and not slotFor(spec.seed) then return missing() end
    local slot,empty=freeSlot()
    if empty<2 then return returnToDepot('inventory') end
    ok,err=permit(target);if not ok then return block(err,'protected') end
    assert(t.select(slot),'cannot select harvest slot')
    task.intent={kind='dig',stand=stand,target=target,block=U.copy(b),inventory=snapshot()}; persist()
    local callOK,result,detail=pcall(t.digDown)
    if not callOK then return block('harvest hardware error: '..tostring(result),'ambiguous') end
    ok,err=recover(); if not ok then return block(err,'ambiguous') end
    if not result then return block(detail or 'harvest failed','harvest') end
    local remains,_,readError=inspect('Down')
    if readError or remains then return block(readError or 'harvest action left its target unchanged','harvest') end
    return true
  end
  return self
end
return M
