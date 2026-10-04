local C=require('autobuilder.config')
local function settings()
 return {turtleFuelReserveItems={},storageInventories={'stock'},processors={machines={{id='a',inventory='machine:a'},{id='b',inventory='machine:b'}},recipes={
  ['test:alloy']={yield=2,inputs={['test:iron']={count=2,slot=1},['test:copper']={count=1,slot=2}},outputSlot=4,seconds=5,machines={'a','b'},fuel={item='minecraft:coal',slot=3,batchesPerItem=8}}}}}
end
test('registered processors expand finite lanes exact fuel and shared ingredient dependencies',function()
 local c=C.load(settings());local p=require('autobuilder.blueprint.planner').expand({['test:alloy']=260},{},c)
 eq(p.missing['test:iron'],260);eq(p.missing['test:copper'],130);eq(p.missing['minecraft:coal'],130)
 local op=p.operations[1];eq(op.type,'PROCESS');eq(op.quantity,260);eq(op.inputs['minecraft:coal'],130)
 eq(#op.lanes,4);eq(op.lanes[1].batches,64);eq(op.lanes[2].batches,1);eq(op.lanes[3].batches,64);eq(op.lanes[4].batches,1)
 eq(op.lanes[1].machineId,'a');eq(op.lanes[2].machineId,'a');eq(op.lanes[3].machineId,'b')
 local provider=require('autobuilder.resources.providers').select('test:alloy',c,{available=0,required=1,workers={}})
 eq(provider.type,'processing');eq(provider.available,true)
end)
test('processor registry rejects overlapping endpoints slots cycles and sparse lists',function()
 for _,mutate in ipairs({
  function(c) c.processors.machines[1].inventory='stock' end,
  function(c) c.processors.machines[2].inventory='machine:a' end,
  function(c) c.processors.recipes['test:alloy'].inputs['test:iron'].slot=4 end,
  function(c) c.processors.recipes['test:alloy'].fuel.slot=2 end,
  function(c) c.processors.recipes['test:alloy'].machines={'missing'} end,
  function(c) c.processors.machines[4]=c.processors.machines[1] end,
  function(c) c.processors.recipes['test:alloy'].seconds=0 end,
  function(c) c.processors.recipes['test:alloy'].callback=function() end end,
 }) do local c=settings();mutate(c);eq(pcall(C.load,c),false) end
 local c=settings();c.processors.recipes['test:alloy'].fuel.item='test:alloy'
 eq(pcall(function() require('autobuilder.blueprint.planner').expand({['test:alloy']=1},{},C.load(c)) end),false)
end)
test('configured processor recipe overrides vanilla recipe without mutating recipe registry',function()
 local c=settings();c.processors.recipes['minecraft:stone']=c.processors.recipes['test:alloy'];c=C.load(c)
 local p=require('autobuilder.blueprint.planner').expand({['minecraft:stone']=2},{},c);eq(p.operations[1].type,'PROCESS')
 eq(require('autobuilder.factory.recipes').get('minecraft:stone').kind,'smelt')
end)

test('processor work balances per-machine quotas before splitting finite job waves',function()
 local r=require('autobuilder.factory.processors').recipe(C.load(settings()),'test:alloy')
 local lanes=require('autobuilder.factory.processors').lanes(r,192);local counts={a=0,b=0}
 for _,lane in ipairs(lanes) do assert(lane.batches<=64);counts[lane.machineId]=counts[lane.machineId]+lane.batches end
 eq(counts.a,96);eq(counts.b,96)
end)
