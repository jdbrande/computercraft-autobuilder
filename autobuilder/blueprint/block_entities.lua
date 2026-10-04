local U=require('autobuilder.core.util')
local M={}
local supported={['minecraft:chest']=true,['minecraft:trapped_chest']=true,['minecraft:barrel']=true,['minecraft:furnace']=true,['minecraft:blast_furnace']=true,['minecraft:smoker']=true}
local function position(p,size)
 return U.position(p) and p.x>=0 and p.x<size.x and p.y>=0 and p.y<size.y and p.z>=0 and p.z<size.z
end
function M.valid(records,size)
 if type(records)~='table' then return false end
 local seen,count={},0
 for index,r in pairs(records) do
  count=count+1
  if count>4096 or not U.integer(index) or index<1 or index>4096 or type(r)~='table' or not position(r,size)
    or r.kind~='empty_inventory' or not supported[r.id] then return false end
  for k in pairs(r) do if not ({x=true,y=true,z=true,id=true,kind=true})[k] then return false end end
  local key=r.x..','..r.y..','..r.z;if seen[key] then return false end;seen[key]=true
 end
 for i=1,count do if not records[i] then return false end end
 return true
end
function M.decode(node,size,version)
 if type(node)~='table' or node.kind~=10 then return nil,'invalid block entity compound' end
 local e=node.value;local id=e.Id;local pos=e.Pos
 if not id or id.kind~=8 or not supported[id.value] then return nil,'unsupported block entity type or metadata observation' end
 if not pos or pos.kind~=11 or pos.count~=3 then return nil,'invalid block entity coordinates' end
 local r={x=pos.value[1],y=pos.value[2],z=pos.value[3],id=id.value,kind='empty_inventory'}
 if not position(r,size) then return nil,'block entity coordinates outside schematic' end
 local data=e
 if version==3 then
  for key in pairs(e) do if key~='Id' and key~='Pos' and key~='Data' then return nil,'unsupported block entity field '..key end end
  if e.Data and e.Data.kind~=10 then return nil,'invalid block entity Data' end
  data=e.Data and e.Data.value or {}
 end
 for key,v in pairs(data) do
  local header=version==2 and (key=='Id' or key=='Pos')
  local empty=key=='Items' and v.kind==9 and v.count==0
  local furnace=r.id=='minecraft:furnace' or r.id=='minecraft:blast_furnace' or r.id=='minecraft:smoker'
  local inactive=furnace and (key=='BurnTime' or key=='CookTime') and v.kind==2 and v.value==0
  local recipeTime=furnace and key=='CookTimeTotal' and v.kind==2 and (v.value==0 or v.value==200)
  local recipes=furnace and key=='RecipesUsed' and v.kind==10 and next(v.value)==nil
  if not (header or empty or inactive or recipeTime or recipes) then return nil,'unsupported or nonempty block entity field '..key end
 end
 return r
end
function M.inBlueprint(records,d)
 if not M.valid(records,d.size) then return false end
 local ordered={}
 for _,r in ipairs(records) do ordered[#ordered+1]={record=r,index=r.y*d.size.x*d.size.z+r.z*d.size.x+r.x+1} end
 table.sort(ordered,function(a,b) return a.index<b.index end)
 local cursor,last=1,0
 for _,run in ipairs(d.runs) do
  last=last+run.count
  while ordered[cursor] and ordered[cursor].index<=last do
   if not M.matches(ordered[cursor].record,d.palette[run.id]) then return false end
   cursor=cursor+1
  end
 end
 return cursor>#ordered
end
function M.matches(record,block)
 return block and block.name==record.id
end
return M
