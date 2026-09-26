local U=require('autobuilder.core.util')
local M,registry={},{}
local slots={[1]=true,[2]=true,[3]=true,[5]=true,[6]=true,[7]=true,[9]=true,[10]=true,[11]=true}
function M.register(item,recipe)
  if type(item)=='table' then recipe=item; item=recipe.item end
  assert(U.shortString(item,128),'invalid recipe item')
  assert(type(recipe)=='table' and (recipe.kind=='craft' or recipe.kind=='smelt'),'invalid recipe kind')
  assert(U.integer(recipe.yield) and recipe.yield>0 and recipe.yield<=64,'invalid recipe yield')
  assert(type(recipe.ingredients)=='table' and next(recipe.ingredients),'recipe needs ingredients')
  local total=0
  for name,count in pairs(recipe.ingredients) do
    assert(U.shortString(name,128) and U.integer(count) and count>0 and count<=64,'invalid ingredient')
    total=total+count
  end
  if recipe.kind=='craft' then
    assert(type(recipe.grid)=='table','craft recipe needs exact turtle slot grid')
    local counts={}
    for slot,name in pairs(recipe.grid) do assert(slots[slot] and recipe.ingredients[name],'invalid grid slot or ingredient'); counts[name]=(counts[name] or 0)+1 end
    for name,count in pairs(recipe.ingredients) do assert(counts[name]==count,'grid does not match ingredients') end
  else assert(total==1 and recipe.yield==1,'furnace recipes must consume and yield one item') end
  registry[item]=U.copy(recipe); registry[item].item=item
  return M.get(item)
end
function M.get(item) return U.copy(registry[item]) end
function M.all() return U.copy(registry) end
local function mc(s) return 'minecraft:'..s end
local function craft(item,yield,grid)
  local ingredients,mapped={},{}
  for slot,name in pairs(grid) do mapped[slot]=mc(name); ingredients[mc(name)]=(ingredients[mc(name)] or 0)+1 end
  M.register(mc(item),{kind='craft',yield=yield,ingredients=ingredients,grid=mapped})
end
local function shape(item,yield,material,pattern)
  local grid={}; for _,slot in ipairs(pattern) do grid[slot]=material end; craft(item,yield,grid)
end
local function smelt(item,input) M.register(mc(item),{kind='smelt',yield=1,ingredients={[mc(input)]=1}}) end
for _,wood in ipairs({'oak','spruce','birch','jungle','acacia','dark_oak','mangrove','cherry','crimson','warped'}) do
  local log=(wood=='crimson' or wood=='warped') and 'stem' or 'log'
  shape(wood..'_planks',4,wood..'_'..log,{1})
  shape(wood..'_stairs',4,wood..'_planks',{1,5,6,9,10,11})
  shape(wood..'_slab',6,wood..'_planks',{1,2,3})
  shape(wood..'_door',3,wood..'_planks',{1,2,5,6,9,10})
  shape(wood..'_trapdoor',2,wood..'_planks',{1,2,3,5,6,7})
  shape(wood..'_pressure_plate',1,wood..'_planks',{1,2})
  shape(wood..'_button',1,wood..'_planks',{1})
  craft(wood..'_fence',3,{[1]=wood..'_planks',[2]='stick',[3]=wood..'_planks',[5]=wood..'_planks',[6]='stick',[7]=wood..'_planks'})
  craft(wood..'_fence_gate',1,{[1]='stick',[2]=wood..'_planks',[3]='stick',[5]='stick',[6]=wood..'_planks',[7]='stick'})
end
shape('stick',4,'oak_planks',{1,5}); shape('crafting_table',1,'oak_planks',{1,2,5,6})
shape('chest',1,'oak_planks',{1,2,3,5,7,9,10,11})
shape('furnace',1,'cobblestone',{1,2,3,5,7,9,10,11})
smelt('stone','cobblestone'); smelt('smooth_stone','stone'); smelt('glass','sand')
smelt('iron_ingot','raw_iron'); smelt('gold_ingot','raw_gold'); smelt('copper_ingot','raw_copper')
smelt('brick','clay_ball'); smelt('terracotta','clay'); smelt('charcoal','oak_log')
smelt('nether_brick','netherrack'); smelt('cracked_stone_bricks','stone_bricks')
shape('stone_bricks',4,'stone',{1,2,5,6}); shape('bricks',1,'brick',{1,2,5,6})
shape('clay',1,'clay_ball',{1,2,5,6}); shape('nether_bricks',1,'nether_brick',{1,2,5,6})
shape('glass_pane',16,'glass',{1,2,3,5,6,7}); shape('iron_bars',16,'iron_ingot',{1,2,3,5,6,7})
shape('iron_door',3,'iron_ingot',{1,2,5,6,9,10}); shape('iron_trapdoor',1,'iron_ingot',{1,2,5,6})
for _,base in ipairs({'cobblestone','stone','stone_brick','brick','nether_brick','sandstone','red_sandstone','quartz','polished_andesite','polished_diorite','polished_granite'}) do
  local material=({stone_brick='stone_bricks',brick='bricks',nether_brick='nether_bricks',quartz='quartz_block'})[base] or base
  shape(base..'_stairs',4,material,{1,5,6,9,10,11}); shape(base..'_slab',6,material,{1,2,3})
end
for _,stone in ipairs({'andesite','diorite','granite'}) do shape('polished_'..stone,4,stone,{1,2,5,6}) end
shape('sandstone',1,'sand',{1,2,5,6}); shape('red_sandstone',1,'red_sand',{1,2,5,6})
shape('quartz_block',1,'quartz',{1,2,5,6}); shape('smooth_stone_slab',6,'smooth_stone',{1,2,3})
craft('torch',4,{[1]='coal',[5]='stick'}); shape('ladder',3,'stick',{1,3,5,6,7,9,11})
return M
