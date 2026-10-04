local U=require('autobuilder.core.util')
local function node(kind,value) return {kind=kind,value=value} end
local function entity(version)
 local data={Items={kind=9,element=10,count=0,value={}}}
 local e={Id=node(8,'minecraft:chest'),Pos={kind=11,count=3,value={1,0,2}}}
 if version==3 then e.Data=node(10,data) else e.Items=data.Items end
 return node(10,e)
end
test('empty inventory metadata normalizes only bounded verifiable contracts',function()
 local M=require('autobuilder.blueprint.block_entities');local size={x=3,y=2,z=3}
 for _,v in ipairs({2,3}) do
  local e=entity(v);local record=assert(M.decode(e,size,v));eq(record.x,1);eq(record.z,2);eq(record.kind,'empty_inventory');eq(record.id,'minecraft:chest')
  assert(M.valid({record},size));eq(M.valid({record,U.copy(record)},size),false)
  local data=v==3 and e.value.Data.value or e.value
  data.Items={kind=9,element=10,count=1,value={{kind=10,value={}}}}
  eq(M.decode(e,size,v),nil)
  data.Items={kind=9,element=10,count=0,value={}};data.LootTable=node(8,'minecraft:chests/simple_dungeon');eq(M.decode(e,size,v),nil)
  data.LootTable=nil;data.CustomName=node(8,'name');eq(M.decode(e,size,v),nil)
  e=entity(v);e.value.Pos.value[1]=3;eq(M.decode(e,size,v),nil)
 end
end)
test('metadata refuses unverifiable signs and active furnace payloads without dropping them silently',function()
 local M=require('autobuilder.blueprint.block_entities');local size={x=3,y=2,z=3}
 local e=entity(3);e.value.Id.value='minecraft:sign';eq(M.decode(e,size,3),nil)
 e=entity(3);e.value.Id.value='minecraft:furnace';e.value.Data.value.BurnTime=node(2,0);e.value.Data.value.CookTime=node(2,0)
 assert(M.decode(e,size,3));e.value.Data.value.BurnTime.value=1;eq(M.decode(e,size,3),nil)
 local record={x=1,y=0,z=2,id='minecraft:chest',kind='empty_inventory',extra=true};eq(M.valid({record},size),false)
end)
