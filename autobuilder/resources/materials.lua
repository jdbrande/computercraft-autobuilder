local M={}
local registry={}
local function add(item,blocks,depth)
  local set={}; for _,name in ipairs(blocks) do set['minecraft:'..name]=true end
  registry['minecraft:'..item]={item='minecraft:'..item,blocks=set,acquisition='mining',suggestedY=depth}
end
add('raw_iron',{'iron_ore','deepslate_iron_ore'},16)
add('coal',{'coal_ore','deepslate_coal_ore'},96)
add('raw_copper',{'copper_ore','deepslate_copper_ore'},48)
add('raw_gold',{'gold_ore','deepslate_gold_ore'},-16)
add('diamond',{'diamond_ore','deepslate_diamond_ore'},-54)
add('redstone',{'redstone_ore','deepslate_redstone_ore'},-54)
add('lapis_lazuli',{'lapis_ore','deepslate_lapis_ore'},0)
add('cobblestone',{'stone','cobblestone'},16)
add('cobbled_deepslate',{'deepslate','cobbled_deepslate'},-32)
add('sand',{'sand'},64)
add('red_sand',{'red_sand'},64)
add('clay_ball',{'clay'},62)
add('dirt',{'dirt','coarse_dirt'},64)
add('gravel',{'gravel'},64)
add('granite',{'granite'},16)
add('diorite',{'diorite'},16)
add('andesite',{'andesite'},16)
add('netherrack',{'netherrack'},64)
add('quartz',{'nether_quartz_ore'},64)
function M.get(item) return registry[item] end
function M.all() return registry end
return M
