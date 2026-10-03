local U=require('autobuilder.core.util')
local function config()
  return {enabled=true,base={x=0,y=0,z=0},bounds={min={x=-8,y=0,z=0},max={x=15,y=2,z=7}},
    dimensionMinY=-64,dimensionMaxY=319,baseProtection={min={x=0,y=0,z=-2},max={x=0,y=0,z=-1}}}
end
test('exploration validates mode configuration without requiring fixed mine bounds',function()
  local C=require('autobuilder.config')
  eq(C.load().mining.mode,'fixed')
  local c=C.load({role='worker',controllerId=1,depot={x=0,y=0,z=-1},mining={enabled=true,mode='explore',exitRoute={{x=0,y=0,z=0}}}})
  assert(c.capabilities.explorationV1)
  assert(not pcall(C.load,{exploration={enabled=true}}))
end)
test('clipped sector expansion retains grid coverage through later partial trips',function()
  local E=require('autobuilder.resources.exploration'); local c=config(); c.bounds.min.x=0; c.bounds.max.x=7
  local old={min={x=0,y=0,z=0},max={x=5,y=2,z=7}}
  local records={['0,0,0']={surveys={['minecraft:coal']={bounds=old,cursor=120}},observations={}}}
  local sector=E.candidates(records,c,'minecraft:coal',{x=0,y=0,z=0})[1]
  assert(sector.surveyed and #sector.surveyed==119,'old coverage lost during clipping change')
  local seen={}; for _,p in ipairs(sector.surveyed) do assert(p.x<=5); seen[require('autobuilder.core.pathfinding').key(p)]=true end
  assert(seen['0,0,0']); assert(not seen['6,0,0'])
  assert(E.record(records,{item='minecraft:coal',exploration={sectorId=sector.id,bounds=sector.bounds,surveyed=sector.surveyed}},
    {result='fuel',cursor=9,clearedRouteCount=0,observations={}}))
  local nextSector=E.candidates(records,c,'minecraft:coal',{x=0,y=0,z=0})[1]
  assert(#nextSector.surveyed>=121,'partial trip discarded prior coverage')
end)
test('impossible fuel is rejected before any path search',function()
  local E=require('autobuilder.resources.exploration'); local P=require('autobuilder.core.pathfinding'); local c=config()
  local find=P.find; P.find=function() error('path search must not run for zero fuel') end
  local ok,g,why=pcall(E.plan,E.sectors(c)[3],{config={exploration=c,maxTravelDistance=1024,minimumFuelReserve=0,mining={pathBudget=4096,returnMargin=0}},depot={x=0,y=0,z=0},exitRoute={},protectedAreas={},activeJobs={},availableFuel=0})
  P.find=find; assert(ok, g); assert(not g and why:find('fuel'))
end)
test('exploration sector cannot cover another owners access route or cross its owned exit',function()
  local E=require('autobuilder.resources.exploration'); local c=config(); c.bounds.min.x=0
  local ctx={config={exploration=c,maxTravelDistance=1024,minimumFuelReserve=0,mining={pathBudget=4096,returnMargin=0}},
    depot={x=0,y=0,z=7},exitRoute={},protectedAreas={},availableFuel=1000,activeJobs={}}
  local sector=E.sectors(c)[1]
  ctx.activeJobs={{workerId=1,status='running',exploration={bounds=E.sectors(c)[2].bounds,route={{x=1,y=0,z=0}},exitRoute={}}}}
  local g,why=E.plan(sector,ctx); assert(not g and why:find('owned'),'sector overlaps owned excavation')
  ctx.activeJobs[1].exploration.route={}; ctx.exitRoute={{x=1,y=0,z=7},{x=2,y=0,z=7}}
  ctx.activeJobs[1].exploration.exitRoute={{x=1,y=0,z=7}}
  g,why=E.plan(sector,ctx); assert(not g and why:find('owned'),'exit overlaps active traversal')
end)
test('registered explorer depots and clear exits are excavation exclusions',function()
  local E=require('autobuilder.resources.exploration'); local c={exploration=config(),restrictedAreas={}}
  local h={depot={x=6,y=0,z=6},exitRoute={{x=7,y=0,z=6}},protectedAreas={}}
  local boxes=E.protectedAreas({workers={a={telemetry={explorationHome=h}}}},c)
  for _,p in ipairs({h.depot,{x=6,y=-1,z=6},{x=6,y=2,z=6},h.exitRoute[1]}) do assert(E.protected(p,boxes),'home clearance unprotected') end
end)
test('exploration sectors stay anchored across negative coordinates and expansion',function()
  local E=require('autobuilder.resources.exploration'); local c=config()
  assert(E.validate(c)); local s=E.sectors(c); eq(#s,3); eq(s[1].id,'-1,0,0'); eq(s[1].bounds.min.x,-8)
  c.bounds.min.x=-9; local expanded=E.sectors(c); eq(#expanded,4); eq(expanded[2].id,'-1,0,0')
  c.bounds={min={x=0,y=0,z=0},max={x=32767,y=2,z=7}}; assert(E.validate(c))
  c.bounds.max.x=32768; assert(not E.validate(c))
end)
test('exploration prefers known material and preserves unfinished clipped sectors',function()
  local E=require('autobuilder.resources.exploration'); local c=config()
  local records={['1,0,0']={observations={{x=9,y=0,z=1,name='minecraft:coal_ore'}},surveys={}}}
  eq(E.candidates(records,c,'minecraft:coal',{x=0,y=0,z=0})[1].id,'1,0,0')
  records['1,0,0'].surveys['minecraft:coal']={exhausted=true,bounds={min={x=8,y=0,z=0},max={x=12,y=2,z=7}},cursor=120}
  eq(E.candidates(records,c,'minecraft:coal',{x=0,y=0,z=0})[1].id,'1,0,0')
end)
test('exploration routes avoid protected claims and deny insufficient return fuel',function()
  local E=require('autobuilder.resources.exploration'); local c=config(); local sector=E.sectors(c)[3]
  local context={config={exploration=c,maxTravelDistance=1024,minimumFuelReserve=10,mining={pathBudget=4096,returnMargin=8}},
    depot={x=0,y=0,z=-1},exitRoute={{x=0,y=0,z=0}},protectedAreas={c.baseProtection},activeJobs={},availableFuel=100}
  local g=assert(E.plan(sector,context)); assert(#g.route>0); eq(g.entry.x,8)
  context.availableFuel=20; assert(not E.plan(sector,context))
  context.availableFuel=100; context.activeJobs={{workerId=2,status='running',exploration={bounds=sector.bounds,route={}}}}
  local _,why=E.plan(sector,context); assert(why:find('owned'))
end)
