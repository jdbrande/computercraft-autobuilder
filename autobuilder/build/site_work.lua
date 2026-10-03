local U=require('autobuilder.core.util')
local C=require('autobuilder.build.blockstates')
local E=require('autobuilder.resources.exploration')
local R=require('autobuilder.workers.resupply')
local F=require('autobuilder.factory.factory')
local M={}
local vegetation={}
for name in ('grass short_grass fern dead_bush vine glow_lichen dandelion poppy blue_orchid allium azure_bluet red_tulip orange_tulip white_tulip pink_tulip oxeye_daisy cornflower lily_of_the_valley wither_rose brown_mushroom red_mushroom'):gmatch('%S+') do vegetation['minecraft:'..name]=true end
local drops={}
for item,spec in pairs(require('autobuilder.resources.materials').all()) do
  for name in pairs(spec.blocks) do drops[name]=drops[name] or {};drops[name][item]=true end
end
for name,items in pairs({grass_block={'dirt'},gravel={'flint'},glowstone={'glowstone_dust'},sea_lantern={'prismarine_crystals'},melon={'melon_slice'},wall_torch={'torch'},soul_wall_torch={'soul_torch'}}) do
  local key='minecraft:'..name;drops[key]=drops[key] or {}
  for _,item in ipairs(items) do drops[key]['minecraft:'..item]=true end
end
function M.support(name)
  return C.family(name)=='cube' or C.family(name)=='log' or name=='minecraft:grass_block'
end
function M.fluid(name) return name=='minecraft:water' or name=='minecraft:lava' end
function M.drops(block,config)
  if (config.protectedBlocks or {})[block.name] then return nil end
  local name=block.name;local family=C.family(name)
  local plant=vegetation[name] or name:match('^minecraft:[a-z_]+_leaves$') or name:match('^minecraft:[a-z_]+_sapling$')
  if not plant and not drops[name] and not ({cube=true,log=true,gravity=true,slab=true,stairs=true,pane=true,fence=true,torch=true,wall_torch=true,carpet=true,ladder=true,lantern=true})[family] then return nil end
  local allowed=U.copy(drops[name] or {});allowed[name]=true
  if plant then
    allowed['minecraft:wheat_seeds']=true;allowed['minecraft:stick']=true
    local wood=name:match('^minecraft:(.+)_leaves$');if wood then allowed['minecraft:'..wood..'_sapling']=true end
    if wood=='oak' or wood=='dark_oak' then allowed['minecraft:apple']=true end
  end
  local noDrop=plant or name=='minecraft:glass' or name=='minecraft:glass_pane' or name:match('_stained_glass$') or name:match('_stained_glass_pane$')
  return allowed,noDrop==true or type(noDrop)=='string'
end
function M.reconcileDig(intent,t,config,found,actual)
  local allowed,noDrop=M.drops(intent.block,config);if not allowed then return false,'recorded excavation block is no longer permitted' end
  local before,after=intent.inventory,R.snapshot(t);local gained=0;local reserved=R.reserved(config)
  for slot=1,16 do
    local a,b=before[slot],after[slot]
    if reserved[slot] and not F.equal(a,b) then return false,'reserved inventory changed during excavation' end
    if a and (not b or a.name~=b.name or a.nbt~=b.nbt or a.count>b.count) then return false,'inventory decreased or changed during excavation' end
    local delta=(b and b.count or 0)-(a and a.count or 0)
    if delta>0 and (b.nbt or not allowed[b.name]) then return false,'unexpected excavation drop; preserve physical evidence' end
    gained=gained+delta
  end
  if gained>0 then return true end -- Falling replacements remain work, not completion.
  if not found and noDrop then return true end
  if found and F.equal(actual,intent.block) then return true end -- No measurable effect; bounded retry is safe.
  return false,'excavation outcome has no matching world and inventory evidence'
end
local function state(block)
  if type(block)~='table' or not U.shortString(block.name,128) or type(block.state)~='table' then return false end
  local count=0
  for k,v in pairs(block.state) do count=count+1;if count>32 or not U.shortString(k,64) or not U.shortString(v,128) then return false end end
  return true
end
function M.validContract(j)
  if type(j)~='table' or j.type~='PREPARE_REGION' or not E.box(j.bounds) or not U.integer(j.clearanceY) or j.clearanceY>j.bounds.max.y then return false end
  local s=j.siteWork
  if type(s)~='table' or type(s.identity)~='string' or #s.identity~=64 or not s.identity:match('^[a-f0-9]+$')
    or not U.integer(s.region) or s.region<1 or not ({clear=true,fill=true,verify=true})[s.stage] then return false end
  if type(j.blocks)~='table' then return false end
  local count,seen=0,{}
  for key in pairs(j.blocks) do if not U.integer(key) or key<1 or key>512 then return false end;count=count+1 end
  if count<1 then return false end
  for i=1,count do
    local b=j.blocks[i]
    if not U.position(b) or not state(b) or not require('autobuilder.core.pathfinding').inside(b,j.bounds) or b.y>=j.clearanceY then return false end
    local key=b.x..','..b.y..','..b.z;if seen[key] then return false end;seen[key]=true
    if b.support~=nil and type(b.support)~='boolean' or b.retain~=nil and not state(b.retain) then return false end
    local air=C.isAir(b.name)
    if s.stage=='clear' and not air or s.stage=='fill' and air then return false end
    if not air and (C.family(b.name)~='cube' or C.classify(b.name,b.state)~='SUPPORTED' or b.retain~=nil) then return false end
    if air and b.support then return false end
  end
  return true
end
function M.new(task,e,config,nav,save)
  assert(M.validContract(task),'invalid preparation region contract')
  return require('autobuilder.build.builder').new(task,e,config,nav,save,'prepare')
end
function M.validProgress(j,p)
  local counts=p.report and p.report.counts
  if not counts then return p.phase~='completed' and (p.progress or 0)==0 and not j.report end
  if type(counts)~='table' then return false end
  local total=0
  for status,n in pairs(counts) do
    if not ({correct=true,wrong=true,missing=true,inaccessible=true,unsupported=true,inventory_full=true,attempt_limit=true})[status]
      or not U.integer(n) or n<0 then return false end
    total=total+n
  end
  for status,n in pairs(j.report and j.report.counts or {}) do if (counts[status] or 0)<n then return false end end
  return total<=#j.blocks and (p.phase~='completed' or total==#j.blocks) and (p.progress or 0)==(counts.correct or 0)
end
return M
