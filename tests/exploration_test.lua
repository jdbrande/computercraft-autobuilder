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

test('exploration physical evidence is bounded validated cleaned and optional for older workers',function()
  local E=require('autobuilder.resources.exploration');local N=require('autobuilder.core.mining_messages')
  local r={cursor=1,clearedRouteCount=0,observations={}}
  assert(E.report(r))
  for _,kind in ipairs({'clear','liquid','blocked','protected'}) do
    r.evidence={{x=1,y=0,z=0,kind=kind,name='minecraft:water',reason='observed obstacle',unexpected='discard'}}
    assert(E.report(r));local clean=N.clean('mine_progress',{jobId='mine:1',phase='work',delivered=0,held=0,exploration=r})
    eq(clean.exploration.evidence[1].kind,kind);eq(clean.exploration.evidence[1].unexpected,nil)
  end
  for _,entry in ipairs({{x=1,y=0,z=0,kind='invented'},{x=1.5,y=0,z=0,kind='clear'},
    {x=1,y=0,z=0,kind='blocked',reason=string.rep('x',129)},{x=1,y=0,z=0,kind='liquid',name=string.rep('x',129)}}) do
    r.evidence={entry};assert(not E.report(r),'malformed physical evidence accepted')
  end
  r.evidence={[2]={x=1,y=0,z=0,kind='clear'}};assert(not E.report(r))
  r.evidence={};for i=1,65 do r.evidence[i]={x=i,y=0,z=0,kind='clear'} end;assert(not E.report(r))
end)

test('sector physical evidence stays inside owned geometry and retains only bounded latest observations',function()
  local E=require('autobuilder.resources.exploration')
  local g={sectorId='0,0,0',bounds={min={x=0,y=0,z=0},max={x=7,y=2,z=7}},route={{x=-1,y=0,z=0}},exitRoute={{x=-2,y=0,z=0}}}
  local r={cursor=1,clearedRouteCount=0,observations={},evidence={{x=99,y=0,z=0,kind='clear'}}};local records={}
  assert(not E.record(records,{item='minecraft:coal',exploration=g},r));eq(next(records),nil)
  for _,x in ipairs({-2,-1,0,7}) do r.evidence={{x=x,y=0,z=0,kind='blocked',reason='solid obstacle'}};assert(E.record(records,{item='minecraft:coal',exploration=g},r)) end
  eq(#records['0,0,0'].evidence,4)
  local progress={}
  for i=1,70 do E.addEvidence(progress,{x=i,y=0,z=0},'blocked','minecraft:stone','blocked path') end
  eq(#progress.evidence,64);eq(progress.evidence[1].x,7)
  E.addEvidence(progress,{x=70,y=0,z=0},'clear');eq(#progress.evidence,64);eq(progress.evidence[64].kind,'clear')
  r.evidence={{x=-1,y=0,z=0,kind='clear'}};assert(E.record(records,{item='minecraft:coal',exploration=g},r))
  local seen;for _,p in ipairs(records['0,0,0'].evidence) do if p.x==-1 then seen=p end end;eq(seen.kind,'clear')
end)


test('sector ranking uses observed density confirmed yield and hazard cost before travel ties',function()
  local E=require('autobuilder.resources.exploration');local c=config();c.bounds.min.x=0
  local records={};for _,s in ipairs(E.sectors(c)) do records[s.id]={observations={},surveys={},outcomes={}} end
  records['0,0,0'].observations={{x=1,y=0,z=0,name='minecraft:coal_ore'},{x=2,y=0,z=0,name='minecraft:stone'}}
  records['1,0,0'].observations={{x=8,y=0,z=0,name='minecraft:coal_ore'},{x=9,y=0,z=0,name='minecraft:coal_ore'}}
  local function first() return E.candidates(records,c,'minecraft:coal',{x=0,y=0,z=0})[1] end
  eq(first().id,'1,0,0');eq(first().density,1)
  records['1,0,0'].observations[2].name='minecraft:stone'
  records['1,0,0'].outcomes['minecraft:coal']={delivered=4,mined=4,trips=2}
  eq(first().id,'1,0,0');eq(first().yield,2)
  records['0,0,0'].outcomes['minecraft:coal']={delivered=4,mined=4,trips=2}
  records['0,0,0'].evidence={{x=3,y=0,z=0,kind='liquid',name='minecraft:lava'}}
  eq(first().id,'1,0,0')
  records['1,0,0'].surveys['minecraft:coal']={exhausted=true,bounds=E.sectors(c)[2].bounds,cursor=193}
  eq(first().id,'0,0,0')
end)

test('exploration routes avoid retained hazards and prefer confirmed clear cells without overriding protection',function()
  local E=require('autobuilder.resources.exploration');local c=config();c.bounds.min.x=0;c.bounds.max.z=15
  local sector;for _,s in ipairs(E.sectors(c)) do if s.id=='1,0,1' then sector=s end end
  local ctx={config={exploration=c,maxTravelDistance=1024,minimumFuelReserve=0,mining={pathBudget=4096,returnMargin=0}},
    depot={x=0,y=0,z=0},exitRoute={},protectedAreas={},activeJobs={},availableFuel=1000,records={old={evidence={}}}}
  for z=1,8 do ctx.records.old.evidence[#ctx.records.old.evidence+1]={x=0,y=0,z=z,kind='clear'} end
  local g=assert(E.plan(sector,ctx));eq(g.route[1].z,1)
  ctx.records.old.evidence[#ctx.records.old.evidence+1]={x=0,y=0,z=2,kind='liquid',name='minecraft:water'}
  ctx.protectedAreas={{min={x=0,y=0,z=1},max={x=0,y=0,z=1}}}
  g=assert(E.plan(sector,ctx))
  for _,p in ipairs(g.route) do assert(not (p.x==0 and p.y==0 and (p.z==1 or p.z==2)),'historical clear route bypassed hazard or protection') end
  ctx.availableFuel=1;assert(not E.plan(sector,ctx))
end)
