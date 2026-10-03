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
