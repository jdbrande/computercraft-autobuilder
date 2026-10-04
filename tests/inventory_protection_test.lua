local U=require('autobuilder.core.util')
local function cell(x,y,z) return {min={x=x,y=y or 0,z=z or 0},max={x=x,y=y or 0,z=z or 0}} end
local function fixture()
 local c=require('tests.loaded_config').load({storageInventories={'stock'},furnaces={'furnace'},craftingStation={input='input',output='output'},
  inventoryAreas={stock=cell(10),furnace=cell(20),input=cell(30),output=cell(40)},turtleFuelReserveItems={}})
 local s={workers={},jobs={},automation={jobs={},projects={},cells={},sequence=0,requests={}}}
 return c,s
end
test('inventory bounds validate names boxes and replacement semantics',function()
 local C=require('autobuilder.config')
 for _,map in ipairs({{left=cell(0)},{bad={min={x=1,y=0,z=0},max={x=0,y=0,z=0}}},{bad=cell(0/0)}}) do
  assert(not pcall(C.load,{inventoryAreas=map}))
 end
 local c=C.load({inventoryAreas={chest={min={x=1,y=0,z=0},max={x=2,y=0,z=0}}}})
 eq(c.inventoryAreas.chest.max.x,2);eq(next(C.overlay({inventoryAreas={old=cell(0)}},{inventoryAreas={}}).inventoryAreas),nil)
end)
test('factory inventory bounds protect both chest halves and own project mutations with offline workers',function()
 local c,s=fixture();local I=require('autobuilder.core.inventory_geometry');local P=require('autobuilder.core.protection')
 c.inventoryAreas.output.max.x=41;c.inventoryAreas.processor={min={x=50,y=0,z=0},max={x=51,y=2,z=1}}
 c.processors.machines={{id='mill',inventory='processor'}};I.initialize(s,c)
 local j={id='work',type='REPAIR',project='own',workerId=9,status='running',bounds={min={x=0,y=-2,z=-2},max={x=60,y=4,z=4}}}
 s.automation.jobs.work=j;s.automation.projects.own={name='own',protectedBounds=U.copy(j.bounds)}
 s.workers['8']={id=8,online=false,telemetry={task='old-craft'}}
 for _,x in ipairs({10,20,30,40,41,50,51}) do assert(not P.canModify(s,c,j,{x=x,y=0,z=0}),'unprotected endpoint '..x) end
 assert(P.canModify(s,c,j,{x=42,y=0,z=0}))
 s=U.copy(s);I.initialize(s,c);assert(not P.canModify(s,c,s.automation.jobs.work,{x=41,y=0,z=0}))
 j=s.automation.jobs.work;j.type='MINE';j.miningArea=U.copy(j.bounds);j.project=nil;s.automation.projects={}
 assert(not P.canModify(s,c,j,{x=20,y=0,z=0}));assert(P.canModify(s,c,j,{x=42,y=0,z=0}))
end)
test('legacy missing inventory location blocks destructive admission but keeps observation and return available',function()
 local c,s=fixture();local I=require('autobuilder.core.inventory_geometry');local P=require('autobuilder.core.protection')
 c.inventoryAreas.furnace=nil;I.initialize(s,c);assert(s.inventoryGeometry.error:find('furnace',1,true))
 for _,kind in ipairs({'MINE','BUILD','REPAIR','CLEAR','PREPARE_SITE','PREPARE_REGION','HARVEST','FARM'}) do
  local ok,why=P.ready(s,c,{type=kind});eq(ok,false);assert(why:find('furnace',1,true))
 end
 for _,kind in ipairs({'SURVEY_SITE','VERIFY','RETURN_HOME','CRAFT','SMELT','RESCUE'}) do assert(P.ready(s,c,{type=kind})) end
 c.inventoryAreas.furnace=cell(20);I.initialize(s,c);assert(P.ready(s,c,{type='MINE'}));eq(s.inventoryGeometry.error,nil)
end)
test('geometry changes cannot erase offline ownership leases pending transfers or existing grants',function()
 local c,s=fixture();local I=require('autobuilder.core.inventory_geometry');I.initialize(s,c)
 local function denied(change,own)
  local cc,ss=U.copy(c),U.copy(s);own(ss);local before=U.copy(ss.inventoryGeometry);change(cc)
  assert(not pcall(I.initialize,ss,cc));assert(require('autobuilder.factory.factory').equal(before,ss.inventoryGeometry))
 end
 denied(function(x) x.inventoryAreas.furnace=cell(21) end,function(x) x.automation.jobs.craft={id='craft',type='CRAFT',workerId=8,status='blocked'};x.workers['8']={id=8,online=false,telemetry={task='craft'}} end)
 denied(function(x) x.inventoryAreas.input=nil end,function(x) x.capacityLedger={leases={held={status='held',nodes={input={}}}}} end)
 denied(function(x) x.inventoryAreas.output=nil end,function(x) x.automation.jobs.old={status='completed',production={intent={action='transfer',from='input',to='output'}}} end)
 denied(function(x) x.inventoryAreas.new=cell(5) end,function(x) x.automation.cells['5,0,0']={owner=8,jobId='work',work=true} end)
 denied(function(x) x.inventoryAreas.new=cell(5) end,function(x) x.jobs.mine={type='MINE',workerId=8,status='running',miningArea={min={x=0,y=0,z=0},max={x=6,y=2,z=2}}} end)
 s.automation.jobs.craft={id='craft',type='CRAFT',workerId=8,status='blocked',privateStation={input='input',output='output',buffer='buffer'}}
 c.inventoryAreas.buffer=cell(45);I.initialize(s,c);eq(s.inventoryGeometry.areas.buffer.min.x,45)
end)
test('registered endpoint identities normalize container cells and bound larger explicit footprints',function()
 local I=require('autobuilder.core.inventory_geometry');local c,s=fixture()
 c.logistics.nodes={{id='base',inventory='stock',position={x=10,y=0,z=0},buffers={{inventory='buffer',position={x=12,y=1,z=0}}}}}
 c.supplyStations={{workerId=8,inventory='supply',position={x=14,y=1,z=0,heading='east'},side='front'}}
 c.fuel.stations={{inventory='fuel',position={x=16,y=1,z=0}}}
 c.inventoryAreas.stock.max.x=11;I.initialize(s,c)
 eq(s.inventoryGeometry.areas.stock.max.x,11);eq(s.inventoryGeometry.areas.buffer.min.y,0)
 eq(s.inventoryGeometry.areas.supply.min.x,15);eq(s.inventoryGeometry.areas.fuel.min.y,2)
 c.inventoryAreas.stock=cell(9);assert(not pcall(I.initialize,s,c))
end)
test('retained factory contracts and transfer endpoints remain required when configuration disconnects',function()
 local c,s=fixture();local I=require('autobuilder.core.inventory_geometry')
 s.automation.jobs.old={status='blocked',privateStation={buffer='retained_buffer',input='retained_input',output='retained_output'},processor={inventory='old_processor'},production={furnace='old_furnace',intent={action='transfer',from='journal_source',to='journal_target'}}}
 s.capacityLedger={leases={held={status='held',nodes={leased_node={}}}}}
 I.initialize(s,c);local missing=table.concat(s.inventoryGeometry.missing,',')
 for _,name in ipairs({'retained_buffer','retained_input','retained_output','old_processor','old_furnace','journal_source','journal_target','leased_node'}) do assert(missing:find(name,1,true),missing) end
end)

test('new destructive dispatch rechecks location completeness after yielding coverage',function()
 local c,s=fixture();local I=require('autobuilder.core.inventory_geometry');I.initialize(s,c)
 s.workers['9']={id=9,online=true,telemetry={status='idle',capabilities={building=true}}}
 local chunks={reserve=function() c.furnaces[#c.furnaces+1]='new_furnace';return {status='disabled'} end}
 local q=require('autobuilder.core.workflows').new(s,function() return true end,function() return 1 end,7,chunks,c)
 local j=q:submit('BUILD',{blocks={{x=60,y=0,z=0,name='minecraft:stone',state={}}}})
 eq(q:assign(s.workers),nil);eq(j.workerId,nil);assert(j.coverageError:find('new_furnace',1,true))
 local v=q:submit('VERIFY',{blocks={{x=60,y=0,z=0,name='minecraft:stone',state={}}}})
 eq(q:assign(s.workers).id,v.id)
end)
test('protection compacts contained inventory boxes and explicitly refuses overflowing exploration payloads',function()
 local c,s=fixture();local P=require('autobuilder.core.protection');local E=require('autobuilder.resources.exploration')
 c.restrictedAreas={{min={x=0,y=0,z=0},max={x=100,y=0,z=0}}}
 local b=P.areas(s,c,nil,true);eq(#b,1);eq(b[1].max.x,100)
 c.inventoryAreas={};c.restrictedAreas={};c.storageInventories={};c.furnaces={};c.craftingStation={}
 for i=1,129 do c.inventoryAreas['chest_'..i]=cell(i*2) end
 b=P.areas(s,c,nil,true);eq(#b,129)
 local plan,why=E.plan({bounds=cell(0)},{config=c,protectedAreas=b});eq(plan,nil);assert(why:find('Too many protection boxes',1,true))
end)

test('crafter announces wired endpoint names and retains missing-location protection while offline',function()
 local c,s=fixture();local I=require('autobuilder.core.inventory_geometry');local P=require('autobuilder.core.protection')
 c.capabilities.crafting=true;local names=I.craftingNames(c);eq(#names,2);assert(I.validNames(names));names[1]='changed';eq(c.craftingStation.input,'input')
 for _,v in ipairs({{'left'},{'same','same'},{[2]='sparse'},{'a','b','c','d'}}) do eq(I.validNames(v),false) end
 s.workers['8']={id=8,online=false,telemetry={craftingInventories={'remote_input','remote_output'}}}
 I.initialize(s,c);local ok,why=P.ready(s,c,{type='BUILD'});eq(ok,false);assert(why:find('remote_input',1,true))
 c.inventoryAreas.remote_input=cell(70);c.inventoryAreas.remote_output=cell(72);I.initialize(s,c);assert(P.ready(s,c,{type='BUILD'}))
end)

test('derived inventory registration respects the checkpoint limit before saving and survives restart',function()
 local I=require('autobuilder.core.inventory_geometry');local c,s=fixture()
 c.inventoryAreas={};c.storageInventories={};c.furnaces={};c.craftingStation={}
 for i=1,511 do c.inventoryAreas['chest_'..i]=cell(i*2) end
 c.fuel.stations={{inventory='fuel',position={x=-10,y=1,z=0}}}
 I.initialize(s,c);local before=U.copy(s.inventoryGeometry)
 I.initialize(s,c);assert(require('autobuilder.factory.factory').equal(before,s.inventoryGeometry))
 c.inventoryAreas.chest_512=cell(1024)
 local ok,why=pcall(I.initialize,s,c);eq(ok,false);assert(tostring(why):find('maximum512',1,true))
 assert(require('autobuilder.factory.factory').equal(before,s.inventoryGeometry))
 local fresh={};eq(pcall(I.initialize,fresh,c),false);eq(fresh.inventoryGeometry,nil)
 c.inventoryAreas.chest_512=nil;I.initialize(s,c)
 assert(require('autobuilder.factory.factory').equal(before,s.inventoryGeometry))
end)
