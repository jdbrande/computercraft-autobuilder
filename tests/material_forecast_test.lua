local U=require('autobuilder.core.util')
local function scope(name,required,jobs)
  return {project={name=name,requirements=required,jobs={'build'}},work=jobs or {}}
end

test('project forecasts allocate shared available stock once and separate confirmed from expected materials',function()
  local s={automation={jobs={}},workers={},inventoryLedger={leases={}}}
  local a=scope('a',{stone=10});local b=scope('b',{stone=10})
  a.work.build={id='build',type='BUILD',materials={stone=2},progress=2,status='running',workerId=12}
  b.project.jobs={}
  s.workers['12']={id=12,online=true,telemetry={task='build',cargo={items={stone=1}}}}
  a.work.mine={id='mine',item='stone',quantity=2,progress={delivered=0},status='running',workerId=13}
  s.inventoryLedger.leases.factory={status='held',inputs={stone=2},withdrawn={},outputs={glass=2},delivered={},transit={}}
  local f=require('autobuilder.resources.material_forecast').build(s,{stone=9},{b,a})
  local x,y=f.a.items.stone,f.b.items.stone
  eq(x.placed,2);eq(x.held,1);eq(x.mining,2);eq(x.stored,5);eq(x.deficit,0)
  eq(y.stored,2);eq(y.deficit,8);eq(x.sharedPhysical,9);eq(x.sharedReserved,2)
  eq(x.stored+y.stored,7);eq(s.inventoryLedger.leases.factory.status,'held')
end)

test('project forecast separates active production lanes transit and legacy unknown progress',function()
  local s={automation={jobs={}},workers={},inventoryLedger={leases={
    craft={status='held',inputs={log=2},outputs={planks=8},withdrawn={log=2},delivered={planks=4},transit={}},
    haul={status='held',inputs={planks=3},outputs={planks=3},withdrawn={planks=3},delivered={},transit={planks=3}}}}}
  local a=scope('a',{planks=20,glass=5});a.work={
    build={id='build',type='BUILD',progress=1,status='running'},
    craft={id='craft',type='CRAFT',item='planks',quantity=8,status='collecting',stockOutputs={planks=8}},
    furnace={id='furnace',type='SMELT',item='glass',quantity=5,status='running',stockOutputs={glass=5}},
    haul={id='haul',type='TRANSPORT',item='planks',quantity=3,status='running'}}
  local f=require('autobuilder.resources.material_forecast').build(s,{planks=4,glass=0},{a}).a
  eq(f.items.planks.crafting,4);eq(f.items.planks.inTransit,3);eq(f.items.planks.stored,4)
  eq(f.items.planks.deficit,9);eq(f.items.glass.processing,5);eq(f.items.glass.deficit,0);eq(f.materialUnknown,true)
  a.work.craft.status='completed';a.work.furnace.status='completed'
  f=require('autobuilder.resources.material_forecast').build(s,nil,{a}).a
  eq(f.items.planks.crafting,0);eq(f.items.planks.stored,nil);eq(f.items.planks.deficit,nil)
end)

test('project forecasts do not credit stale offline cargo or count one linked job twice',function()
  local s={workers={['12']={id=12,online=false,telemetry={task='build',cargo={items={stone=9}}}}}}
  local a=scope('a',{stone=10});a.work.build={id='build',type='BUILD',materials={stone=1},progress=1,status='running',workerId=12}
  local b=scope('b',{stone=10});b.project.jobs={};a.work.mine={id='mine',item='stone',quantity=4,progress={delivered=1},status='running'};b.work.mine=a.work.mine
  local f=require('autobuilder.resources.material_forecast').build(s,{stone=0},{b,a})
  eq(f.a.items.stone.held,0);eq(f.a.items.stone.mining,3);eq(f.b.items.stone.mining,0)
  eq(f.a.materialUnknown,true)
end)

test('builder lookahead notices low positive cargo and excludes reserved or tagged inventory',function()
  local F=require('autobuilder.resources.material_forecast');local t=require('tests.support').turtle()
  local items={[1]={name='minecraft:stone',count=1},[15]={name='minecraft:stone',count=64},[2]={name='minecraft:stone',count=12,nbt='tag'}}
  t.getItemDetail=function(slot) return items[slot] end
  local task={type='BUILD',phase='work',index=1,blocks={}}
  for i=1,8 do task.blocks[i]={x=i,y=0,z=0,name='minecraft:stone',state={}} end
  local c={supply={inventory='stage',batch=4}}
  local p=assert(F.upcoming(task,t,c));eq(p.item,'minecraft:stone');eq(p.held,1);eq(p.remaining,8);eq(p.count,4)
  items[1].count=3;eq(F.upcoming(task,t,c),nil)
  items[1].count=1;task.index=8;eq(F.upcoming(task,t,c),nil)
  task.index=7;p=assert(F.upcoming(task,t,c));eq(p.count,1)
end)

test('builder lookahead does not revive paused complete supply or speculative foundation work',function()
  local F=require('autobuilder.resources.material_forecast');local t=require('tests.support').turtle()
  t.getItemDetail=function(slot) if slot==1 then return {name='minecraft:glass',count=1} end end
  local task={type='REPAIR',phase='work',blocks={{name='minecraft:oak_door',state={half='upper'}},{name='minecraft:glass',state={}},{name='minecraft:glass',state={}}}}
  local c={supply={inventory='stage',batch=4}};eq(F.upcoming(task,t,c).item,'minecraft:glass')
  for _,kind in ipairs({'PREPARE_REGION','VERIFY','CLEAR','CRAFT'}) do task.type=kind;eq(F.upcoming(task,t,c),nil) end
  task.type='BUILD';task.paused=true;eq(F.upcoming(task,t,c),nil);task.paused=nil
  task.phase='completed';eq(F.upcoming(task,t,c),nil);task.phase='work'
  task.supplyRequest={};eq(F.upcoming(task,t,c),nil);task.supplyRequest=nil
  task.intent={kind='place'};eq(F.upcoming(task,t,c),nil);task.intent=nil
  task.phase='blocked';task.error='inventory full';eq(F.upcoming(task,t,c),nil)
  task.error='movement reservation pending';assert(F.upcoming(task,t,c))
  task.moveRoute={};eq(F.upcoming(task,t,c),nil);task.moveRoute=nil
  t.getItemDetail=function() return nil end;eq(F.upcoming(task,t,c),nil)
end)

test('early replenishment bounds native capacity including smaller stacks and skips full cargo',function()
  local F=require('autobuilder.resources.material_forecast');local t=require('tests.support').turtle()
  local items={};for s=1,16 do items[s]={name='minecraft:dirt',count=64} end
  items[1]={name='minecraft:stone',count=1}
  t.getItemDetail=function(s) return items[s] end
  local limit=64;t.getItemSpace=function(s) return limit-(items[s] and items[s].count or 0) end
  local task={type='BUILD',blocks={}};for i=1,65 do task.blocks[i]={name='minecraft:stone'} end
  local c={supply={inventory='stage',batch=64}}
  eq(F.upcoming(task,t,c).count,63)
  limit=16;eq(F.upcoming(task,t,c).count,15)
  limit=1;eq(F.upcoming(task,t,c),nil)
  items[2]=nil;eq(F.upcoming(task,t,c).count,1)
  items[2]={name='minecraft:stone',count=1,nbt='tag'};eq(F.upcoming(task,t,c),nil)
end)

test('harvest forecast separates held output from future yield and measured delivery',function()
  local F=require('autobuilder.resources.material_forecast')
  local j={id='harvest',type='HARVEST',item='log',quantity=5,progress=5,status='running',workerId=12}
  local a=scope('a',{log=5},{harvest=j});local t={task='harvest',harvestDelivered=0,cargo={items={log=5}}}
  local s={workers={['12']={online=true,telemetry=t}}}
  local f=F.build(s,{log=0},{a}).a;eq(f.items.log.held,5);eq(f.items.log.harvesting,0);eq(f.items.log.deficit,0);eq(f.materialUnknown,false)
  t.harvestDelivered=2;t.cargo.items.log=3
  f=F.build(s,{log=2},{a}).a;eq(f.items.log.held,3);eq(f.items.log.harvesting,0);eq(f.items.log.stored,2);eq(f.items.log.deficit,0)
  t.harvestDelivered=nil;f=F.build(s,{log=2},{a}).a;eq(f.materialUnknown,true);eq(f.items.log.held,3)
  s.workers['12'].online=false;f=F.build(s,{log=2},{a}).a;eq(f.materialUnknown,true);eq(f.items.log.held,0)
end)
