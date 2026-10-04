local function fixture()
  return {schema=1,size={x=2,y=1,z=2},palette={{name='minecraft:air',state={}},{name='minecraft:oak_log',state={axis='x'}}},runs={{id=1,count=1},{id=2,count=2},{id=1,count=1}},metadata={},requirements={}}
end
test('blueprint rejects malformed volumes palettes states and loads bounded JSON',function()
  local S=require('autobuilder.blueprint.schematic')
  local d=fixture(); eq(S.validate(d),d)
  d.runs[1].count=0; assert(not S.validate(d)); d=fixture(); d.runs[1].id=3; assert(not S.validate(d))
  d=fixture(); d.size.x=1000000; assert(not S.validate(d))
  d=fixture(); d.palette[2].state.axis={}; assert(not S.validate(d))
  d=fixture(); d.runs[5]={id=1,count=1}; assert(not S.validate(d))
  local fs=require('tests.support').fs(); fs.files.bp='{}'
  local value=S.load(fs,{unserializeJSON=function() return fixture() end},'bp'); eq(value.size.x,2)
  assert(not S.load(fs,{unserializeJSON=function() error('bad JSON') end},'bp'))
end)
test('blueprint preserves x-z-y order and transforms into positive rotated bounds',function()
  local B=require('autobuilder.blueprint.blueprint')
  local blocks=B.blocks(fixture(),{x=10,y=64,z=-2},90,false,false)
  eq(#blocks,2); eq(blocks[1].x,11); eq(blocks[1].z,-1); eq(blocks[2].x,10); eq(blocks[2].z,-2)
  eq(blocks[1].state.axis,'z'); eq(blocks[1].y,64)
  eq(B.quantities(fixture())['minecraft:oak_log'],2)
end)
test('state transforms rotate facings rails connection keys and handedness',function()
  local T=require('autobuilder.blueprint.transforms')
  local state={facing='north',axis='x',shape='inner_left',rotation='0',north='true',hinge='left'}
  local s=T.state(state,90,true,false)
  eq(s.facing,'east'); eq(s.axis,'z'); eq(s.shape,'inner_right'); eq(s.rotation,'4'); eq(s.east,'true'); eq(s.hinge,'right')
  eq(state.facing,'north'); eq(T.state({shape='ascending_east'},90).shape,'ascending_south')
  eq(T.state({shape='south_east'},90).shape,'south_west')
  eq(T.state({rotation='0'},0,false,true).rotation,'8')
  assert(not pcall(T.state,{},45))
end)
test('material counts handle doors beds and double slabs',function()
  local B=require('autobuilder.blueprint.blueprint'); local d=fixture()
  d.size={x=5,y=1,z=1}; d.palette={{name='minecraft:oak_door',state={half='lower'}},{name='minecraft:oak_door',state={half='upper'}},{name='minecraft:red_bed',state={part='foot'}},{name='minecraft:red_bed',state={part='head'}},{name='minecraft:stone_slab',state={type='double'}}}
  d.runs={{id=1,count=1},{id=2,count=1},{id=3,count=1},{id=4,count=1},{id=5,count=1}}
  local q=B.quantities(d); eq(q['minecraft:oak_door'],1); eq(q['minecraft:red_bed'],1); eq(q['minecraft:stone_slab'],2)
end)
test('regions place support before attachments even across region boundaries',function()
  local B=require('autobuilder.blueprint.blueprint')
  local blocks={{x=0,y=1,z=0,name='minecraft:wall_torch',state={facing='west'}},{x=1,y=1,z=0,name='minecraft:stone',state={}},{x=1,y=0,z=0,name='minecraft:stone',state={}}}
  local r=B.regions(blocks,1); eq(#r,3); eq(r[1].blocks[1].y,0); eq(r[2].blocks[1].x,1); eq(r[3].blocks[1].x,0)
  eq(r[3].dependencies[1],r[2].id)
  local same=B.regions(blocks,8); eq(#same,1); eq(same[1].blocks[1].y,0); eq(same[1].blocks[3].name,'minecraft:wall_torch')
end)
test('blueprint transforms all quarter turns and both reflections without mutation',function()
  local T=require('autobuilder.blueprint.transforms'); local p={x=0,y=2,z=1}; local size={x=2,y=3,z=3}
  local expected={{0,1},{1,0},{1,1},{1,1}}
  for i,rotation in ipairs({0,90,180,270}) do
    local q=T.position(p,size,rotation); eq(q.x,expected[i][1]); eq(q.z,expected[i][2]); eq(q.y,2)
  end
  local q=T.position(p,size,0,true,true); eq(q.x,1); eq(q.z,1)
  eq(T.state({facing='east',shape='outer_left',axis='y'},0,true,true).shape,'outer_left')
  eq(T.state({facing='east'},0,true,true).facing,'west')
end)
test('blueprint refuses cyclic metadata and cyclic placement support',function()
  local S=require('autobuilder.blueprint.schematic'); local B=require('autobuilder.blueprint.blueprint')
  local d=fixture(); d.metadata.self=d.metadata; assert(not S.validate(d))
  local blocks={{x=0,y=0,z=0,name='minecraft:wall_torch',state={facing='west'}},{x=1,y=0,z=0,name='minecraft:wall_torch',state={facing='east'}}}
  assert(not pcall(B.regions,blocks,1))
end)

test('bed foot depends on both floors before generating a cross-region head',function()
 local blocks={{x=0,y=1,z=0,name='minecraft:red_bed',state={part='foot',facing='east',occupied='false'}},
  {x=1,y=1,z=0,name='minecraft:red_bed',state={part='head',facing='east',occupied='false'}},
  {x=0,y=0,z=0,name='minecraft:stone',state={}},{x=1,y=0,z=0,name='minecraft:stone',state={}}}
 local order={};for _,region in ipairs(require('autobuilder.blueprint.blueprint').regions(blocks,1)) do
  for _,b in ipairs(region.blocks) do
   if b.state.part=='foot' then assert(order['0,0'] and order['1,0'],'both floors must precede foot') end
   order[b.x..','..b.y]=true
  end
 end
end)

test('ceiling attachments and cross-tile beds order supports at default region size',function()
 local B=require('autobuilder.blueprint.blueprint')
 for _,size in ipairs({1,8}) do
  for _,name in ipairs({'lever','oak_button','lantern'}) do
   local state=name=='lantern' and {hanging='true',waterlogged='false'} or {face='ceiling',facing='north',powered='false'}
   local regions=B.regions({{x=0,y=7,z=0,name='minecraft:'..name,state=state},{x=0,y=8,z=0,name='minecraft:stone',state={}}},size)
   eq(regions[1].blocks[1].name,'minecraft:stone')
  end
  for _,dir in ipairs({{1,0,'east'},{-1,0,'west'},{0,1,'south'},{0,-1,'north'}}) do
   local x,z=dir[1]<0 and 8 or 7,dir[2]<0 and 8 or 7
   local blocks={{x=x,y=1,z=z,name='minecraft:red_bed',state={part='foot',facing=dir[3],occupied='false'}},
    {x=x+dir[1],y=1,z=z+dir[2],name='minecraft:red_bed',state={part='head',facing=dir[3],occupied='false'}},
    {x=x,y=0,z=z,name='minecraft:stone',state={}},{x=x+dir[1],y=0,z=z+dir[2],name='minecraft:stone',state={}}}
   local regions=B.regions(blocks,size);local floors,foot=0,false
   for _,r in ipairs(regions) do for _,b in ipairs(r.blocks) do
    if b.name=='minecraft:stone' then floors=floors+1 elseif b.state.part=='foot' then eq(floors,2);foot=true else assert(foot) end
   end end
  end
 end
end)


test('sign material aliases survive transforms and wall support dependencies',function()
 local B=require('autobuilder.blueprint.blueprint');local d=fixture()
 d.palette[2]={name='minecraft:oak_wall_sign',state={facing='west',waterlogged='false'}}
 eq(B.quantities(d)['minecraft:oak_sign'],2)
 local blocks=B.blocks(d,{x=0,y=0,z=0},90);eq(blocks[1].state.facing,'north')
 local regions=B.regions({{x=0,y=1,z=0,name='minecraft:oak_wall_sign',state={facing='west',waterlogged='false'}},{x=1,y=1,z=0,name='minecraft:stone',state={}}},1)
 eq(regions[1].blocks[1].name,'minecraft:stone');eq(regions[2].blocks[1].name,'minecraft:oak_wall_sign')
end)
