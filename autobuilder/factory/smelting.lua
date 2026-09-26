local U=require('autobuilder.core.util')
local F=require('autobuilder.factory.factory')
local Recipes=require('autobuilder.factory.recipes')
local Fuel=require('autobuilder.factory.fuel')
local M={}
function M.new(task,e,config,save)
  config=config or {}; assert(type(save)=='function','durable save callback required')
  local r=assert(Recipes.get(task.item),'unknown smelting recipe'); assert(r.kind=='smelt','not a furnace recipe')
  local batches=task.batches or task.quantity
  assert(U.integer(batches) and batches>0,'positive smelt count required')
  local input=next(r.ingredients)
  task.production=task.production or {loaded=0,fuelLoaded=0,delivered=0}
  local s=task.production; local self={task=task}
  local fuelItem=config.smeltingFuelItem or 'minecraft:coal'
  local capacity=assert(Fuel.capacity(fuelItem),'unsupported furnace fuel')
  local neededFuel=math.ceil(batches/capacity)
  local function advance()
    if s.intent then return F.reconcileTransfer(s,e,save) end
    if s.delivered==batches then return 'complete' end
    if task.furnaceLane then
      local configured=false
      for _,name in ipairs(config.furnaces or {}) do if name==task.furnaceLane then configured=true end end
      assert(configured,'assigned furnace lane is no longer configured')
      assert(not s.furnace or s.furnace==task.furnaceLane,'saved furnace does not match assigned lane')
    end
    if not s.furnace then
      local chosen
      for _,name in ipairs(task.furnaceLane and {task.furnaceLane} or config.furnaces or {}) do
        local inv=F.list(e,name)
        if not inv[1] and not inv[3] and (not inv[2] or inv[2].name==fuelItem and not inv[2].nbt) then chosen=name; break end
      end
      assert(chosen,'no available configured furnace')
      F.commit(s,save,function() s.furnace=chosen end)
    end
    local inv=F.list(e,s.furnace)
    assert(not inv[1] or inv[1].name==input and not inv[1].nbt,'furnace input contamination')
    assert(not inv[2] or inv[2].name==fuelItem and not inv[2].nbt,'furnace fuel contamination')
    assert(not inv[3] or inv[3].name==task.item and not inv[3].nbt,'furnace output contamination')
    assert((inv[1] and inv[1].count or 0)+(inv[3] and inv[3].count or 0)+s.delivered<=s.loaded,'furnace contains unowned inputs or output')
    if inv[3] then
      local output=(config.storageInventories or {})[1]; assert(output,'no output storage configured')
      local n=math.min(inv[3].count,batches-s.delivered)
      return F.transfer(s,e,save,s.furnace,3,output,nil,task.item,n,output,1,'delivered')
    end
    if s.loaded<batches and (not inv[1] or inv[1].count<64) then
      local sources=F.sources(e,config,input); local source=sources[1]
      assert(source,'smelting input shortage: '..input)
      local n=math.min(source.count,batches-s.loaded,64-(inv[1] and inv[1].count or 0))
      return F.transfer(s,e,save,source.name,source.slot,s.furnace,1,input,n,source.name,-1,'loaded')
    end
    -- Existing idle fuel can be used, but is never counted as a fresh transfer.
    if s.fuelLoaded<neededFuel and not inv[2] and inv[1] then
      local sources,total=F.sources(e,config,fuelItem)
      local reserve=(config.turtleFuelReserveItems or {})[fuelItem] or 0
      assert(total>reserve,'smelting fuel shortage; turtle fuel reserve is protected')
      local source=sources[1]; assert(source,'smelting fuel unavailable')
      -- Feed one fuel item at a time. Residual burn may remain, never infer it as stock.
      return F.transfer(s,e,save,source.name,source.slot,s.furnace,2,fuelItem,1,source.name,-1,'fuelLoaded')
    end
    assert(s.delivered<=s.loaded,'furnace output exceeds owned inputs')
    F.commit(s,save,function() s.waits=(s.waits or 0)+1 end)
    assert(s.waits<=(config.smeltingWaitSteps or 600),'furnace stalled; check chunks, recipe, output capacity and fuel')
    return 'waiting','furnace processing; waiting for output'
  end
  function self:step() return F.protect(advance) end
  function self:resume() return self:step() end
  return self
end
return M
