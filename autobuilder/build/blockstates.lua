-- Deliberately finite vanilla families: an unknown block is never assumed to be a cube.
local M={}
local cubes={}
for word in ('stone cobblestone mossy_cobblestone deepslate cobbled_deepslate polished_deepslate deepslate_bricks cracked_deepslate_bricks deepslate_tiles cracked_deepslate_tiles dirt coarse_dirt rooted_dirt granite polished_granite diorite polished_diorite andesite polished_andesite tuff calcite dripstone_block stone_bricks cracked_stone_bricks mossy_stone_bricks chiseled_stone_bricks smooth_stone bricks sandstone cut_sandstone chiseled_sandstone smooth_sandstone red_sandstone cut_red_sandstone chiseled_red_sandstone smooth_red_sandstone glass tinted_glass obsidian crying_obsidian netherrack nether_bricks red_nether_bricks end_stone end_stone_bricks purpur_block quartz_block smooth_quartz chiseled_quartz_block quartz_bricks prismarine prismarine_bricks dark_prismarine sea_lantern glowstone iron_block gold_block diamond_block emerald_block lapis_block coal_block redstone_block netherite_block raw_iron_block raw_gold_block raw_copper_block clay terracotta packed_mud mud_bricks packed_ice blue_ice melon honeycomb_block amethyst_block'):gmatch('%S+') do cubes[word]=true end
local woods={}
local colors={}
for w in ('oak spruce birch jungle acacia dark_oak mangrove cherry bamboo crimson warped'):gmatch('%S+') do woods[w]=true; cubes[w..'_planks']=true end
for c in ('white orange magenta light_blue yellow lime pink gray light_gray cyan purple blue brown green red black'):gmatch('%S+') do
  colors[c]=true
  for _,s in ipairs({'wool','concrete','terracotta','stained_glass'}) do cubes[c..'_'..s]=true end
end
local stairMaterials={stone=true,cobblestone=true,mossy_cobblestone=true,stone_brick=true,mossy_stone_brick=true,brick=true,sandstone=true,smooth_sandstone=true,red_sandstone=true,smooth_red_sandstone=true,quartz=true,smooth_quartz=true,purpur=true,prismarine=true,prismarine_brick=true,dark_prismarine=true,nether_brick=true,red_nether_brick=true,end_stone_brick=true,granite=true,polished_granite=true,diorite=true,polished_diorite=true,andesite=true,polished_andesite=true,cobbled_deepslate=true,polished_deepslate=true,deepslate_brick=true,deepslate_tile=true,mud_brick=true,smooth_stone=true,cut_sandstone=true,cut_red_sandstone=true}
local plants={}
for n in ('dandelion poppy blue_orchid allium azure_bluet red_tulip orange_tulip white_tulip pink_tulip oxeye_daisy cornflower lily_of_the_valley'):gmatch('%S+') do plants[n]=true end
local cropItems={wheat='wheat_seeds',carrots='carrot',potatoes='potato',beetroots='beetroot_seeds'}
local special={bedrock=true,barrier=true,command_block=true,chain_command_block=true,repeating_command_block=true,structure_block=true,jigsaw=true,spawner=true,end_portal_frame=true,reinforced_deepslate=true,budding_amethyst=true}
local function unknown(state,allowed)
  for k in pairs(state) do if allowed[k]~=true then return 'unsupported property '..tostring(k) end end
end
local function dry(state) return state.waterlogged==nil or state.waterlogged==false or state.waterlogged=='false' end
function M.isAir(name) return name=='minecraft:air' or name=='minecraft:cave_air' or name=='minecraft:void_air' end
function M.family(name)
  if type(name)~='string' then return nil end
  local n=name:match('^minecraft:(.+)$'); if not n then return nil end
  if M.isAir(name) then return 'air' end
  if cubes[n] then return 'cube' end
  if n=='sand' or n=='red_sand' or n=='gravel' or n:match('^[a-z_]+_concrete_powder$') and cubes[n:gsub('_powder$','')] then return 'gravity' end
  local base=n:gsub('^stripped_',''):match('^(.-)_log$') or n:gsub('^stripped_',''):match('^(.-)_wood$') or n:gsub('^stripped_',''):match('^(.-)_stem$') or n:gsub('^stripped_',''):match('^(.-)_hyphae$')
  if base and woods[base] then return 'log' end
  local material=n:match('^(.-)_slab$'); if material and (woods[material] or stairMaterials[material]) then return 'slab' end
  material=n:match('^(.-)_stairs$'); if material and (woods[material] or stairMaterials[material]) then return 'stairs' end
  if n=='torch' or n=='soul_torch' then return 'torch' end
  if n=='wall_torch' or n=='soul_wall_torch' then return 'wall_torch' end
  if n=='iron_door' or woods[n:match('^(.-)_door$')] then return 'door' end
  if colors[n:match('^(.-)_carpet$')] or n=='moss_carpet' then return 'carpet' end
  if n=='glass_pane' or n=='iron_bars' or colors[n:match('^(.-)_stained_glass_pane$')] then return 'pane' end
  if woods[n:match('^(.-)_fence$')] or n=='nether_brick_fence' then return 'fence' end
  if n=='lantern' or n=='soul_lantern' then return 'lantern' end
  if n=='ladder' then return 'ladder' end
  if colors[n:match('^(.-)_bed$')] then return 'bed' end
  if n=='lever' or n=='stone_button' or n=='polished_blackstone_button' or woods[n:match('^(.-)_button$')] then return 'control' end
  if n=='rail' or n=='powered_rail' or n=='detector_rail' or n=='activator_rail' then return 'rail' end
  if n=='repeater' or n=='comparator' then return n end
  if n=='redstone_wire' then return 'wire' end
  if n=='redstone_torch' then return 'redstone_torch' end
  if n=='redstone_wall_torch' then return 'redstone_wall_torch' end
  if plants[n] then return 'plant' end
  if ({oak=true,spruce=true,birch=true,jungle=true,acacia=true,dark_oak=true,cherry=true})[n:match('^(.-)_sapling$')] then return 'sapling' end
  if cropItems[n] then return 'crop' end
end
function M.classify(name,state)
  if type(name)~='string' or (state~=nil and type(state)~='table') then return 'UNSUPPORTED','invalid block or state' end
  state=state or {}; local n=name:match('^minecraft:(.+)$')
  if n and special[n] then return 'SPECIAL_ACQUISITION','not obtainable by ordinary crafting/mining' end
  local family=M.family(name); local allowed={}
  if family=='log' then allowed.axis=true
  elseif family=='slab' then allowed.type=true; allowed.waterlogged=true
  elseif family=='stairs' then allowed.half=true; allowed.facing=true; allowed.shape=true; allowed.waterlogged=true
  elseif family=='wall_torch' then allowed.facing=true
  elseif family=='control' then allowed={face=true,facing=true,powered=true}
  elseif family=='rail' then allowed={shape=true,waterlogged=true,powered=n~='rail'}
  elseif family=='repeater' then allowed={facing=true,delay=true,locked=true,powered=true}
  elseif family=='comparator' then allowed={facing=true,mode=true,powered=true}
  elseif family=='wire' then allowed={power=true,north=true,east=true,south=true,west=true}
  elseif family=='redstone_torch' then allowed={lit=true}
  elseif family=='redstone_wall_torch' then allowed={lit=true,facing=true}
  elseif family=='crop' then allowed={age=true}
  elseif family=='sapling' then allowed={stage=true}
  elseif family=='bed' then allowed={part=true,facing=true,occupied=true}
  elseif family=='door' then allowed={half=true,facing=true,hinge=true,open=true,powered=true}
  elseif family=='pane' or family=='fence' then allowed={north=true,east=true,south=true,west=true,waterlogged=true}
  elseif family=='lantern' then allowed={hanging=true,waterlogged=true}
  elseif family=='ladder' then allowed={facing=true,waterlogged=true} end
  local why=unknown(state,allowed); if why then return 'UNSUPPORTED',why end
  if family=='cube' or family=='air' then return 'SUPPORTED' end
  if family=='gravity' then return 'PARTIALLY_SUPPORTED','requires a solid supporting block below' end
  if family=='log' then
    if state.axis and not ({x=true,y=true,z=true})[state.axis] then return 'UNSUPPORTED','invalid log axis' end
    return 'PARTIALLY_SUPPORTED','axis placement requires an accessible solid support face'
  end
  if family=='slab' then
    if not dry(state) or not ({top=true,bottom=true})[state.type or 'bottom'] then return 'UNSUPPORTED','only dry single slabs are supported' end
    return 'PARTIALLY_SUPPORTED','requires solid support below bottom slab or above top slab'
  end
  if family=='stairs' then
    if not dry(state) or not ({top=true,bottom=true})[state.half or 'bottom'] or not ({north=true,east=true,south=true,west=true})[state.facing or 'north'] or (state.shape and state.shape~='straight') then return 'UNSUPPORTED','only dry straight stairs are supported' end
    return 'PARTIALLY_SUPPORTED','requires solid support and no neighboring stair shape conflict'
  end
  if family=='wall_torch' and not ({north=true,east=true,south=true,west=true})[state.facing or 'north'] then return 'UNSUPPORTED','invalid torch facing' end
  if family=='torch' or family=='wall_torch' then return 'PARTIALLY_SUPPORTED','requires solid support and access from the opposite face' end
  if family=='door' then
    if not ({lower=true,upper=true})[state.half] or not ({north=true,east=true,south=true,west=true})[state.facing]
      or state.hinge~='left' or tostring(state.open)~='false' or tostring(state.powered)~='false' then
      return 'UNSUPPORTED','doors require explicit half/facing, left hinge, closed and unpowered states'
    end
    return 'PARTIALLY_SUPPORTED','requires paired empty space, solid floor and isolated hinge sides; upper half is inspection-only'
  end
  local facing=({north=true,east=true,south=true,west=true})[state.facing]
  if family=='control' then
    if not facing or not ({floor=true,wall=true,ceiling=true})[state.face] or tostring(state.powered)~='false' then return 'UNSUPPORTED','controls require explicit face/facing and unpowered state' end
    return 'PARTIALLY_SUPPORTED','requires solid attachment face and final unpowered verification'
  end
  if family=='rail' then
    if not dry(state) or not ({north_south=true,east_west=true})[state.shape] or n~='rail' and tostring(state.powered)~='false' then return 'UNSUPPORTED','only dry flat straight unpowered rails are supported' end
    return 'PARTIALLY_SUPPORTED','requires floor and final neighborhood shape verification'
  end
  if family=='repeater' or family=='comparator' then
    if not facing or tostring(state.powered)~='false' or family=='repeater' and (tostring(state.delay)~='1' or tostring(state.locked)~='false') or family=='comparator' and state.mode~='compare' then return 'UNSUPPORTED','only default unpowered repeater/comparator states are supported' end
    return 'PARTIALLY_SUPPORTED','requires floor and final redstone state verification'
  end
  if family=='wire' then
    if tostring(state.power)~='0' then return 'UNSUPPORTED','only unpowered wire is supported' end
    for _,dir in ipairs({'north','east','south','west'}) do if not ({none=true,side=true,up=true})[state[dir]] then return 'UNSUPPORTED','wire requires explicit connection states' end end
    return 'PARTIALLY_SUPPORTED','requires floor and final connection verification'
  end
  if family=='redstone_torch' or family=='redstone_wall_torch' then
    if tostring(state.lit)~='true' or family=='redstone_wall_torch' and not facing then return 'UNSUPPORTED','only lit redstone torches with explicit wall facing are supported' end
    return 'PARTIALLY_SUPPORTED','requires solid attachment and final redstone state verification'
  end
  if family=='crop' or family=='sapling' or family=='plant' then
    if family=='crop' and tostring(state.age)~='0' or family=='sapling' and tostring(state.stage)~='0' then return 'UNSUPPORTED','only newly planted crop/sapling states are supported' end
    return 'PARTIALLY_SUPPORTED','native planting validates substrate; growth may change state after placement'
  end
  if family=='bed' then
    if not ({foot=true,head=true})[state.part] or not ({north=true,east=true,south=true,west=true})[state.facing] or tostring(state.occupied)~='false' then
      return 'UNSUPPORTED','beds require explicit part/facing and unoccupied state'
    end
    return 'PARTIALLY_SUPPORTED','requires both floors and paired empty cells; head is inspection-only'
  end
  if family=='carpet' then return 'PARTIALLY_SUPPORTED','requires a solid supporting block below' end
  if family=='pane' or family=='fence' then
    if not dry(state) then return 'UNSUPPORTED','waterlogged connections are unsupported' end
    for _,direction in ipairs({'north','east','south','west'}) do
      if state[direction]~=nil and tostring(state[direction])~='true' and tostring(state[direction])~='false' then return 'UNSUPPORTED','invalid connection state' end
    end
    return 'PARTIALLY_SUPPORTED','connections are verified again after all task blocks are placed'
  end
  if family=='lantern' then
    if not dry(state) or state.hanging~=nil and tostring(state.hanging)~='true' and tostring(state.hanging)~='false' then return 'UNSUPPORTED','only dry lanterns with boolean hanging state are supported' end
    return 'PARTIALLY_SUPPORTED','requires solid support below standing lantern or above hanging lantern'
  end
  if family=='ladder' then
    if not dry(state) or not ({north=true,east=true,south=true,west=true})[state.facing] then return 'UNSUPPORTED','ladder requires dry state and explicit horizontal facing' end
    return 'PARTIALLY_SUPPORTED','requires a solid backing block and opposite-side access'
  end
  return 'UNSUPPORTED','no deterministic placement strategy for this block or state'
end
function M.category(name)
  local f=M.family(name)
  if f=='door' or f=='bed' then return 'paired' end
  if name=='minecraft:water' or name=='minecraft:lava' then return 'fluids' end
  if f=='control' or f=='wire' or f=='repeater' or f=='comparator' or f=='redstone_torch' or f=='redstone_wall_torch' then return 'redstone' end
  if f=='wall_torch' or f=='ladder' or f=='lantern' or f=='torch' then return 'attached' end
  if f=='plant' or f=='sapling' or f=='crop' then return 'plants' end
  return f or 'unsupported'
end
function M.connected(family)
  return family=='pane' or family=='fence' or family=='rail' or family=='wire' or family=='control' or family=='repeater' or family=='comparator' or family=='redstone_torch' or family=='redstone_wall_torch'
end
function M.item(block)
  if M.isAir(block.name) then return nil end
  return ({['minecraft:wall_torch']='minecraft:torch',['minecraft:soul_wall_torch']='minecraft:soul_torch',['minecraft:redstone_wall_torch']='minecraft:redstone_torch',['minecraft:redstone_wire']='minecraft:redstone',['minecraft:wheat']='minecraft:wheat_seeds',['minecraft:carrots']='minecraft:carrot',['minecraft:potatoes']='minecraft:potato',['minecraft:beetroots']='minecraft:beetroot_seeds'})[block.name] or block.name
end
return M
