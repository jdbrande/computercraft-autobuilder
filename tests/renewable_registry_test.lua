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

test('renewable definitions reject executable assignment data and unsupported reserve sizes',function()
 local R=require('autobuilder.resources.renewables')
 local farm={kind='carrot',sites={{x=0,y=64,z=0},{x=1,y=64,z=0}},seedReserve=1}
 eq(pcall(R.reserve,farm),false);farm.seedReserve=257;eq(pcall(R.reserve,farm),false)
 local ok=require('autobuilder.core.task_messages').validate('task_assign',{job={id='task:7:1',type='FARM',farm={adapter={mode='crop',block='a',item='b',seed='c',age=4,callback=true}}}})
 eq(ok,false)
 for _,value in ipairs({true,7,'bad'}) do eq(require('autobuilder.core.task_messages').validate('task_assign',{job={id='task:7:1',type='FARM',farm=value}}),false) end
end)

test('new renewable contracts require a matching updated role while legacy plots remain compatible',function()
 local R=require('autobuilder.resources.renewables')
 eq(R.capability({kind='wheat'},false),'farming');eq(R.capability({kind='carrot'},false),'registeredFarmingV1')
 eq(R.capability({kind='oak',seedReserve=3},true),'registeredLoggingV1')
 local C=require('autobuilder.config');local c=C.load({role='worker',controllerId=7,automation={farming=true}})
 eq(c.capabilities.registeredFarmingV1,true);eq(c.capabilities.registeredLoggingV1,nil)
 local state={};local q=require('autobuilder.core.workflows').new(state,function() return true end,function() return 1 end,7)
 local job=q:submit('FARM',{item='minecraft:carrot',quantity=1,farm={kind='carrot',sites={{x=1,y=64,z=0}}}},{})
 eq(job.requiredCapability,'registeredFarmingV1')
 local workers={['12']={id=12,online=true,telemetry={status='idle',capabilities={farming=true}}}}
 eq(q:assign(workers),nil);workers['12'].telemetry.capabilities.registeredFarmingV1=true;eq(q:assign(workers).id,job.id)
end)

test('replanting health gates provider selection and assignment but not columns or recovery',function()
 local H=require('autobuilder.workers.health')
 local t={status='idle',capabilities={registeredFarmingV1=true},health={placing=false,movement=true,digging=true,left='minecraft:diamond_pickaxe',right='unknown',software={status='unmanaged'}}}
 local farm={kind='carrot',sites={{x=30,y=1,z=0}},item='minecraft:carrot'}
 local workers={['12']={id=12,online=true,telemetry=t}}
 local p=require('autobuilder.resources.providers').select(farm.item,{farms={farm}},{workers=workers})
 eq(p.available,false)
 local q=require('autobuilder.core.workflows').new({},function() return true end,function() return 1 end,7)
 local j=q:submit('FARM',{item=farm.item,quantity=1,farm=farm})
 eq(q:assign(workers),nil);eq(H.eligible(t,{type='RETURN_HOME'}),true)
 eq(H.eligible(t,{type='FARM',farm={kind='bamboo'}}),true)
 t.health.placing=true;eq(q:assign(workers).id,j.id)
end)
