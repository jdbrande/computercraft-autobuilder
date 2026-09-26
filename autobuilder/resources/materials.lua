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
-- Missing and empty lists preserve unrestricted legacy miners. Reject sparse
-- arrays and maps so a malformed advertisement cannot silently become unrestricted.
function M.validResources(resources)
  if resources==nil then return true end
  if type(resources)~='table' then return false end
  local count,seen=0,{}
  for k,item in pairs(resources) do
    if type(k)~='number' or k%1~=0 or k<1 or k>64 or type(item)~='string' or not registry[item] or seen[item] then return false end
    count=count+1; seen[item]=true
  end
  for i=1,count do if resources[i]==nil then return false end end
  return true
end
function M.accepts(resources,item)
  if not M.validResources(resources) then return false end
  if not resources or #resources==0 then return true end
  for _,name in ipairs(resources) do if name==item then return true end end
  return false
end
function M.sameResources(a,b)
  if not M.validResources(a) or not M.validResources(b) then return false end
  if #(a or {})~=#(b or {}) then return false end
  for _,name in ipairs(a or {}) do if not M.accepts(b,name) then return false end end
  return true
end
function M.get(item) return registry[item] end
function M.all() return registry end
return M
