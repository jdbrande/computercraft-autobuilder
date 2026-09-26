local U=require('autobuilder.core.util')
local function mc(x) return 'minecraft:'..x end

test('production planner expands yields and shared surplus in dependency order',function()
  local P=require('autobuilder.blueprint.planner')
  local p=P.expand({[mc('oak_stairs')]=4,[mc('oak_slab')]=6},{[mc('oak_log')]=3})
  eq(p.raw[mc('oak_log')],3); eq(next(p.missing),nil)
  eq(p.available[mc('oak_planks')],3)
  local made={}; for _,op in ipairs(p.operations) do
    for item in pairs(op.ingredients) do if item==mc('oak_planks') then assert(made[item]) end end
    made[op.item]=true
  end
end)
test('production planner honors finished stock and separates fuel reserves',function()
  local p=require('autobuilder.blueprint.planner').expand({[mc('stone_bricks')]=8},
    {[mc('stone_bricks')]=4,[mc('cobblestone')]=4,[mc('coal')]=2},
    {turtleFuelReserveItems={[mc('coal')]=2}})
  eq(p.raw[mc('cobblestone')],4); eq(p.fuel.items,1); eq(p.missing[mc('coal')],1)
  eq(p.operations[1].kind,'smelt'); eq(p.operations[2].kind,'craft')
end)
test('production registry validates grid and planner rejects dependency cycles',function()
  local R=require('autobuilder.factory.recipes')
  assert(not pcall(R.register,'bad',{kind='craft',yield=1,ingredients={a=2},grid={[1]='a'}}))
  local cycle={get=function(item) return {kind='craft',yield=1,ingredients={[item=='a' and 'b' or 'a']=1}} end}
  assert(not pcall(require('autobuilder.blueprint.planner').expand,{a=1},{},{recipes=cycle}))
end)

-- Inventories are isolated snapshots, like CC peripheral.list, and transfers can be partial.
local function hardware()
  local h={inventories={store={},furnace={},input={},output={}},slots={},selected=1,limit=64,calls=0}
  local function put(inv,slot,item,n)
    inv[slot]=inv[slot] or {name=item,count=0}; assert(inv[slot].name==item)
    inv[slot].count=inv[slot].count+n
    if inv[slot].count==0 then inv[slot]=nil end
  end
  local function move(src,slot,dst,target,n)
    if not src[slot] then return 0 end
    local item=src[slot].name
    if not target then for i=1,27 do if not dst[i] or dst[i].name==item and dst[i].count<64 then target=i; break end end end
    if not target or dst[target] and dst[target].name~=item then return 0 end
    n=math.min(n or 64,src[slot].count,64-(dst[target] and dst[target].count or 0),h.limit)
    if n>0 then put(src,slot,item,-n); put(dst,target,item,n) end
    return n
  end
  h.peripheral={call=function(name,method,...)
    if h.offline==name then error('detached') end
    local inv=assert(h.inventories[name],'missing peripheral')
    if method=='list' then return U.copy(inv) end
    if method=='pushItems' then
      local to,slot,n,target=...; h.calls=h.calls+1
      local moved=move(inv,slot,assert(h.inventories[to]),target,n)
      if h.crash then h.crash=false; error('power loss after transfer') end
      return moved
    end
    error('unexpected API '..method)
  end}
  h.turtle={getItemDetail=function(slot) return U.copy(h.slots[slot]) end,
    select=function(slot) h.selected=slot; return true end,
    suckUp=function(n) h.calls=h.calls+1; for slot in pairs(h.inventories.input) do return move(h.inventories.input,slot,h.slots,h.selected,n)>0 end; return false end,
    dropDown=function(n) h.calls=h.calls+1; return move(h.slots,h.selected,h.inventories.output,nil,n)>0 end,
    craft=function(limit)
      h.calls=h.calls+1
      local R=require('autobuilder.factory.recipes'); local recipe=R.get(h.craftItem)
      for slot,item in pairs(recipe.grid) do assert(h.slots[slot] and h.slots[slot].name==item) end
      for slot,item in pairs(recipe.grid) do put(h.slots,slot,item,-1) end
      put(h.slots,h.selected,h.craftItem,recipe.yield)
      if h.craftCrash then h.craftCrash=false; error('power loss after craft') end
      return true
    end}
  function h:smelt()
    local inv=self.inventories.furnace
    if inv[1] and (inv[2] or (self.burn or 0)>0) then
      if (self.burn or 0)==0 then put(inv,2,mc('coal'),-1); self.burn=8 end
      put(inv,1,mc('cobblestone'),-1); put(inv,3,mc('stone'),1); self.burn=self.burn-1
    end
  end
  return h
end
local cfg={storageInventories={'store'},furnaces={'furnace'},smeltingFuelItem=mc('coal'),
  turtleFuelReserveItems={[mc('coal')]=2},craftingStation={input='input',output='output',inputSide='up',outputSide='down'}}
local function drive(executor,h,steps)
  local status,reason
  for i=1,steps or 100 do status,reason=executor:step(); if status=='complete' or status=='blocked' then return status,reason end; if h then h:smelt() end end
  return status,reason
end

test('smelting uses actual transfers and asynchronously delivers stone without turtle fuel',function()
  local h=hardware(); h.limit=2; h.inventories.store={[1]={name=mc('cobblestone'),count=4},[2]={name=mc('coal'),count=3}}
  local task={item=mc('stone'),batches=4}
  local ex=require('autobuilder.factory.smelting').new(task,h,cfg,function() return true end)
  local status,why=drive(ex,h); eq(status,'complete')
  eq(h.inventories.store[2].count,2); eq(task.production.delivered,4)
end)
test('smelting reconciles a crash after input transfer and handles disconnected hardware',function()
  local h=hardware(); h.inventories.store={[1]={name=mc('cobblestone'),count=2},[2]={name=mc('coal'),count=3}}
  local task={item=mc('stone'),batches=2}; local saved
  local function save() saved=U.copy(task); return true end
  local S=require('autobuilder.factory.smelting')
  local ex=S.new(task,h,cfg,save); h.crash=true
  eq(ex:step(),'blocked'); assert(saved.production.intent)
  task=U.copy(saved); ex=S.new(task,h,cfg,save)
  h.offline='furnace'; eq(ex:resume(),'blocked'); h.offline=nil
  eq(drive(ex,h),'complete'); eq(task.production.delivered,2)
end)
test('production refuses hardware effects when saving intent fails',function()
  local h=hardware(); h.inventories.store[1]={name=mc('cobblestone'),count=2}
  local ex=require('autobuilder.factory.smelting').new({item=mc('stone'),batches=2},h,cfg,function() return false,'disk full' end)
  eq(ex:step(),'blocked'); eq(h.calls,0)
end)
test('crafting stages exact slots, recovers crafted output, and delivers all batches',function()
  local h=hardware(); h.craftItem=mc('stone_bricks'); h.inventories.store[1]={name=mc('stone'),count=8}
  local task={item=h.craftItem,batches=2}; local saved
  local function save() saved=U.copy(task); return true end
  local C=require('autobuilder.factory.crafting'); local ex=C.new(task,h,cfg,save)
  h.craftCrash=true
  eq(drive(ex),'blocked'); assert(saved.production.intent)
  task=U.copy(saved); ex=C.new(task,h,cfg,save)
  eq(drive(ex),'complete'); eq(task.production.delivered,8)
  eq(next(h.slots),nil); eq(require('autobuilder.factory.factory').count(h.inventories.store,mc('stone_bricks')),8)
end)
test('crafting blocks contaminated turtle and occupied staging chest',function()
  local C=require('autobuilder.factory.crafting'); local h=hardware(); h.slots[4]={name=mc('dirt'),count=1}
  eq(C.new({item=mc('stone_bricks'),batches=1},h,cfg,function() return true end):step(),'blocked'); eq(h.calls,0)
  h.slots={}; h.inventories.input[1]={name=mc('dirt'),count=1}
  eq(C.new({item=mc('stone_bricks'),batches=1},h,cfg,function() return true end):step(),'blocked'); eq(h.calls,0)
end)
test('production planning acquires missing fuel reserve as well as smelting fuel',function()
  local p=require('autobuilder.blueprint.planner').expand({[mc('stone')]=16},{[mc('cobblestone')]=16},
    {turtleFuelReserveItems={[mc('coal')]=8}})
  eq(p.missing[mc('coal')],10); eq(p.reserveMissing[mc('coal')],8)
end)
test('production substitutions select explicit final recipes without altering their grids',function()
  local p=require('autobuilder.blueprint.planner').expand({[mc('oak_stairs')]=4},{},
    {substitutions={[mc('oak_stairs')]=mc('spruce_stairs')}})
  eq(p.requirements[mc('spruce_stairs')],4); eq(p.raw[mc('spruce_log')],2)
  eq(p.operations[#p.operations].item,mc('spruce_stairs'))
end)
test('recipe registry encodes real pane bar clay and brick yields',function()
  local R=require('autobuilder.factory.recipes')
  eq(R.get(mc('glass_pane')).yield,16); eq(R.get(mc('iron_bars')).ingredients[mc('iron_ingot')],6)
  eq(R.get(mc('clay')).ingredients[mc('clay_ball')],4)
  eq(R.get(mc('bricks')).ingredients[mc('brick')],4)
  eq(R.get(mc('iron_ingot')).ingredients[mc('raw_iron')],1)
  eq(R.get(mc('pale_oak_planks')),nil)
end)
test('production restores intent after post-effect checkpoint failure',function()
  local h=hardware(); h.inventories.store={[1]={name=mc('cobblestone'),count=1},[2]={name=mc('coal'),count=3}}
  local task={item=mc('stone'),batches=1}; local saved; local reject=true
  local function save()
    if reject and h.calls>0 and not task.production.intent then return false,'disk full after effect' end
    saved=U.copy(task); return true
  end
  local S=require('autobuilder.factory.smelting'); local ex=S.new(task,h,cfg,save)
  eq(ex:step(),'blocked'); assert(task.production.intent and saved.production.intent)
  reject=false; eq(drive(ex,h),'complete'); eq(task.production.delivered,1)
end)
test('production completes raw cobblestone to stone bricks through both physical executors',function()
  local h=hardware(); h.craftItem=mc('stone_bricks')
  h.inventories.store={[1]={name=mc('cobblestone'),count=8},[2]={name=mc('coal'),count=3}}
  local p=require('autobuilder.blueprint.planner').expand({[mc('stone_bricks')]=8},
    {[mc('cobblestone')]=8,[mc('coal')]=3},cfg)
  eq(next(p.missing),nil)
  for _,op in ipairs(p.operations) do
    local ex=require('autobuilder.factory.factory').new(op,h,cfg,function() return true end)
    local status,why=drive(ex,op.type=='SMELT' and h or nil,150); assert(status=='complete',why)
  end
  eq(require('autobuilder.factory.factory').count(h.inventories.store,mc('stone_bricks')),8)
  eq(require('autobuilder.factory.factory').count(h.inventories.store,mc('coal')),2)
end)
test('smelting empty fuel supply blocks without spending turtle reserve',function()
  local h=hardware(); h.inventories.store={[1]={name=mc('cobblestone'),count=1},[2]={name=mc('coal'),count=2}}
  local ex=require('autobuilder.factory.smelting').new({item=mc('stone'),batches=1},h,cfg,function() return true end)
  eq(drive(ex),'blocked'); eq(h.inventories.store[2].count,2)
end)
test('crafting partially fills output storage and keeps undelivered output for resume',function()
  local h=hardware(); h.limit=1; h.craftItem=mc('glass_pane'); h.inventories.store[1]={name=mc('glass'),count=6}
  local task={item=h.craftItem,batches=1}
  eq(drive(require('autobuilder.factory.crafting').new(task,h,cfg,function() return true end),nil,100),'complete')
  eq(task.production.delivered,16)
  eq(require('autobuilder.factory.factory').count(h.inventories.store,h.craftItem),16)
end)
test('smelting bounds unobservable processing stalls',function()
  local h=hardware(); h.inventories.store={[1]={name=mc('cobblestone'),count=1},[2]={name=mc('coal'),count=3}}
  local config=U.copy(cfg); config.smeltingWaitSteps=3
  local ex=require('autobuilder.factory.smelting').new({item=mc('stone'),batches=1},h,config,function() return true end)
  local status,why=drive(ex,nil,10); eq(status,'blocked'); assert(why:find('stalled'))
end)
test('smelting refuses output which exceeds its recorded owned inputs',function()
  local h=hardware(); h.inventories.store={[1]={name=mc('cobblestone'),count=1},[2]={name=mc('coal'),count=3}}
  local task={item=mc('stone'),batches=1}; local ex=require('autobuilder.factory.smelting').new(task,h,cfg,function() return true end)
  eq(ex:step(),'running'); h.inventories.furnace[3]={name=mc('stone'),count=2}
  eq(ex:step(),'blocked'); eq(task.production.delivered,0)
end)
test('crafting rejects unowned output instead of crediting it as a completed recipe',function()
  local h=hardware(); h.craftItem=mc('stone_bricks'); h.inventories.store[1]={name=mc('stone'),count=4}
  local task={item=h.craftItem,batches=1}; local ex=require('autobuilder.factory.crafting').new(task,h,cfg,function() return true end)
  for i=1,20 do eq(ex:step(),'running'); if task.production.phase=='deliver' then break end end
  h.inventories.output[1]={name=h.craftItem,count=4}
  eq(ex:step(),'blocked'); eq(task.production.delivered,0)
end)
test('crafting preserves an ambiguous post-crash journal for operator review',function()
  local h=hardware(); h.craftItem=mc('stone_bricks'); h.inventories.store[1]={name=mc('stone'),count=4}
  local task={item=h.craftItem,batches=1}; local ex=require('autobuilder.factory.crafting').new(task,h,cfg,function() return true end)
  h.craftCrash=true; eq(drive(ex),'blocked'); assert(task.production.intent)
  h.slots[13].count=3
  eq(ex:resume(),'blocked'); assert(task.production.intent)
end)
