local U=require('autobuilder.core.util')
test('renewable definitions cover native crop maturity and bound custom data',function()
 local R=require('autobuilder.resources.renewables')
 eq(R.get({},'carrot').block,'minecraft:carrots');eq(R.get({},'carrot').seed,'minecraft:carrot')
 eq(R.get({},'beetroot').age,3);eq(R.get({},'potato').age,7)
 local c={farmAdapters={reed={mode='column',block='test:reed',item='test:reed'}}}
 assert(R.validate(c));eq(R.get(c,'reed').mode,'column')
 for _,bad in ipairs({{mode='crop',block='test:crop',item='test:fruit'}, {mode='column',block='test:reed',item='test:reed',callback=function() end},
  {mode='crop',block='test:crop',item='test:fruit',seed='test:seed',age=math.huge}}) do
  eq(pcall(R.validate,{farmAdapters={custom=bad}}),false)
 end
end)
test('renewable provider freezes a selected adapter and reserves in durable farm geometry',function()
 local Providers=require('autobuilder.resources.providers')
 local c={farms={{kind='custom',item='test:fruit',seedReserve=3,sites={{x=1,y=64,z=0}}}},farmAdapters={custom={mode='crop',block='test:crop',item='test:fruit',seed='test:seed',age=4}}}
 local p=Providers.select('test:fruit',c,{available=0,required=1});assert(p.farm.adapter);eq(p.farm.adapter.age,4)
 c.farmAdapters.custom.age=5;eq(p.farm.adapter.age,4)
 eq(require('autobuilder.resources.renewables').reserve(p.farm),3)
end)
test('unhealthy preferred farm worker does not displace healthy alternate acquisition',function()
 local p=require('autobuilder.resources.providers').select('minecraft:cobblestone',{
  farms={{kind='custom',item='minecraft:cobblestone'}},providerPreferences={['minecraft:cobblestone']={'farm','mining'}}},
  {available=0,required=1,workers={['12']={online=true,telemetry={capabilities={farming=true},health={movement=true,digging=false,left='unknown',right='unknown',software={status='unmanaged'}}}},
   ['13']={online=true,telemetry={capabilities={mining=true}}}}})
 eq(p.type,'mining');eq(p.available,true)
end)
