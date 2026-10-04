local U=require('autobuilder.core.util')
local M={}
local defaults={
 wheat={mode='crop',block='minecraft:wheat',item='minecraft:wheat',seed='minecraft:wheat_seeds',age=7},
 carrot={mode='crop',block='minecraft:carrots',item='minecraft:carrot',seed='minecraft:carrot',age=7},
 potato={mode='crop',block='minecraft:potatoes',item='minecraft:potato',seed='minecraft:potato',age=7},
 beetroot={mode='crop',block='minecraft:beetroots',item='minecraft:beetroot',seed='minecraft:beetroot_seeds',age=3},
}
for _,kind in ipairs({'bamboo','cactus','sugar_cane'}) do defaults[kind]={mode='column',block='minecraft:'..kind,item='minecraft:'..kind} end
for _,kind in ipairs({'oak','birch','spruce'}) do defaults[kind]={mode='tree',block='minecraft:'..kind..'_log',item='minecraft:'..kind..'_log',seed='minecraft:'..kind..'_sapling',leaves='minecraft:'..kind..'_leaves'} end
function M.definition(s,custom)
 assert(type(s)=='table','renewable definition required')
 local allowed={mode=true,block=true,item=true,seed=true,age=true,leaves=true}
 for k in pairs(s) do assert(allowed[k],'unknown renewable definition field') end
 assert(s.mode=='crop' or s.mode=='column' or not custom and s.mode=='tree','unsupported renewable mode')
 assert(U.shortString(s.block,128) and U.shortString(s.item,128),'invalid renewable block/item')
 if s.mode=='crop' then
  assert(U.shortString(s.seed,128) and U.integer(s.age) and s.age>=1 and s.age<=31 and s.leaves==nil,'invalid crop planting/maturity definition')
 elseif s.mode=='tree' then assert(U.shortString(s.seed,128) and U.shortString(s.leaves,128) and s.age==nil,'invalid tree definition')
 else assert(s.seed==nil and s.age==nil and s.leaves==nil,'columns preserve their base rather than replanting') end
 return true
end
function M.validate(config)
 local adapters=config.farmAdapters or {};assert(type(adapters)=='table','farmAdapters must be a map');local n=0
 for kind,s in pairs(adapters) do
  n=n+1;assert(n<=64 and U.shortString(kind,64) and not defaults[kind],'invalid, duplicate or built-in farm adapter')
  M.definition(s,true)
 end
 return true
end
function M.get(config,kind)
 local s=defaults[kind] or (config.farmAdapters or {})[kind];return s and U.copy(s)
end
function M.forFarm(farm,config)
 if farm.adapter then M.definition(farm.adapter);return U.copy(farm.adapter) end
 return M.get(config or {},farm.kind)
end
function M.reserve(farm,spec)
 spec=spec or M.forFarm(farm,{})
 if not spec or not spec.seed then return 0 end
 local sites=#(farm.sites or {});local n=farm.seedReserve or sites
 assert(U.integer(n) and n>=math.max(1,sites) and n<=256,'seedReserve must cover all sites and be at most256')
 return n
end
function M.freeze(farm,config)
 local copy=U.copy(farm);local s=M.forFarm(copy,config)
 if s then copy.adapter=s;M.reserve(copy,s) end
 return copy
end
return M
