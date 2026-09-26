local U=require('autobuilder.core.util')
local F=require('autobuilder.factory.factory')
local Recipes=require('autobuilder.factory.recipes')
local M={}
local function suffix(side) return ({up='Up',down='Down',front=''})[side] end
function M.new(task,e,config,save)
  config=config or {}; assert(type(save)=='function','durable save callback required')
  local recipe=assert(Recipes.get(task.item),'unknown crafting recipe'); assert(recipe.kind=='craft','not a crafting recipe')
  local batches=task.batches or math.ceil(assert(task.quantity,'craft count required')/recipe.yield)
  assert(U.integer(batches) and batches>0,'positive craft count required')
  task.production=task.production or {crafted=0,delivered=0,phase='init'}
  local s=task.production; local self={}; local station=config.craftingStation or {}
  local function reconcile()
    local i=assert(s.intent)
    if i.action=='transfer' then return F.reconcileTransfer(s,e,save) end
    local current=F.turtleItems(e)
    if i.action=='craft' then
      if F.equal(current,i.after) then
        F.commit(s,save,function() s.crafted=s.crafted+1; s.phase='deliver'; s.intent=nil end)
        return 'running'
      end
      assert(F.equal(current,i.before),'ambiguous craft result; preserve inventory and journal')
      F.commit(s,save,function() s.intent=nil end)
      return 'blocked','craft did not change inventory; verify Crafty upgrade and recipe'
    end
    assert(i.action=='suck' or i.action=='drop','unknown turtle production action')
    local chest=F.list(e,i.chest)
    local td=F.count(current,i.item)-F.count(i.before,i.item)
    local cd=F.count(chest,i.item)-F.count(i.chestBefore,i.item)
    local moved=i.action=='suck' and td or -td
    assert(U.integer(moved) and moved>=0 and moved<=i.limit and td==-cd,'ambiguous station transfer; preserve inventories and journal')
    local expected=U.copy(i.before)
    if moved>0 then
      local count=(expected[i.slot] and expected[i.slot].count or 0)+(i.action=='suck' and moved or -moved)
      expected[i.slot]=count>0 and {name=i.item,count=count} or nil
    end
    assert(F.equal(current,expected),'unexpected turtle slots changed during station transfer')
    F.commit(s,save,function()
      if i.action=='suck' and moved==i.limit then s.stagedSlot=nil end
      s.intent=nil
    end)
    if moved==0 then return 'blocked','station transfer made no progress; check chest position and capacity' end
    return 'running'
  end
  local function stationAction(action,slot,item,limit,chest)
    local before=F.turtleItems(e); local chestBefore=F.list(e,chest)
    F.commit(s,save,function() s.intent={action=action,slot=slot,item=item,limit=limit,chest=chest,before=before,chestBefore=chestBefore} end)
    assert(e.turtle.select(slot),'cannot select crafting slot')
    local side=action=='suck' and (station.inputSide or 'up') or (station.outputSide or 'down')
    local method=action..assert(suffix(side),'invalid station side')
    assert(type(e.turtle[method])=='function','station turtle API unavailable')
    e.turtle[method](limit)
    return reconcile()
  end
  local function advance()
    assert(e.turtle and type(e.turtle.craft)=='function','local Crafty turtle required')
    assert(station.input and station.output and station.input~=station.output,'dedicated crafting input/output chests required')
    for _,name in ipairs(config.storageInventories or {}) do assert(name~=station.input and name~=station.output,'station chests cannot be shared storage inventories') end
    if s.intent then return reconcile() end
    if s.delivered==batches*recipe.yield then return 'complete' end
    local slots=F.turtleItems(e); local staging=F.list(e,station.input); local output=F.list(e,station.output)
    if s.phase=='init' then
      assert(not next(slots),'crafting requires an empty turtle, including reserved slots 15 and 16')
      assert(not next(staging),'craft staging chest must start empty')
      assert(not next(output),'craft output chest must start empty')
      F.commit(s,save,function() s.phase='load' end)
    end
    if s.phase=='deliver' then
      assert(F.count(slots,task.item)+F.count(output,task.item)+s.delivered==s.crafted*recipe.yield,'crafted output ownership changed; operator reconciliation required')
      for slot,item in pairs(slots) do
        assert(slot==13 and item.name==task.item and not item.nbt,'unexpected crafting leftovers')
        return stationAction('drop',slot,item.name,item.count,station.output)
      end
      for slot,item in pairs(output) do
        assert(item.name==task.item and not item.nbt,'output chest contamination')
        local destination=(config.storageInventories or {})[1]; assert(destination,'output storage is not configured')
        return F.transfer(s,e,save,station.output,slot,destination,nil,item.name,item.count,destination,1,'delivered')
      end
      assert(s.delivered==s.crafted*recipe.yield,'crafted output missing; operator reconciliation required')
      if s.crafted==batches then return 'complete' end
      F.commit(s,save,function() s.phase='load' end)
      return 'running'
    end
    assert(not next(output),'craft output changed unexpectedly')
    for slot,item in pairs(slots) do
      assert(recipe.grid[slot]==item.name and item.count==1 and not item.nbt,'crafting grid contamination')
    end
    if s.stagedSlot then
      local item=recipe.grid[s.stagedSlot]
      assert(not slots[s.stagedSlot] and F.count(staging,item)==1,'staged ingredient changed unexpectedly')
      for _,stack in pairs(staging) do assert(stack.name==item and not stack.nbt,'craft staging contamination') end
      return stationAction('suck',s.stagedSlot,item,1,station.input)
    end
    assert(not next(staging),'craft staging chest contains unowned items')
    for slot=1,11 do
      local item=recipe.grid[slot]
      if item and not slots[slot] then
        local sources,total=F.sources(e,config,item)
        local reserve=(config.turtleFuelReserveItems or {})[item] or 0
        assert(total>reserve,'crafting input shortage: '..item)
        local source=sources[1]; assert(source,'craft ingredient unavailable')
        return F.transfer(s,e,save,source.name,source.slot,station.input,1,item,1,station.input,1,nil,{stagedSlot=slot})
      end
    end
    local after={[13]={name=task.item,count=recipe.yield}}
    F.commit(s,save,function() s.intent={action='craft',before=slots,after=after} end)
    assert(e.turtle.select(13),'cannot select craft output slot')
    e.turtle.craft(1)
    return reconcile()
  end
  function self:step() return F.protect(advance) end
  function self:resume() return self:step() end
  return self
end
return M
