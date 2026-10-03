local U=require('autobuilder.core.util')
local function source()
  return {schema=1,size={x=2,y=2,z=3},palette={{name='minecraft:stone',state={}},{name='minecraft:air',state={}}},
    runs={{id=1,count=1},{id=2,count=10},{id=1,count=1}},metadata={},requirements={}}
end
local function plan(data,transform,limits)
  return require('autobuilder.build.site_plan').new(data or source(),transform or {origin={x=10,y=64,z=20},rotation=0},string.rep('a',64),limits)
end

test('site plan transforms exact schematic cells and covers every footprint and workspace column once',function()
  local T=require('autobuilder.blueprint.transforms')
  for _,rotation in ipairs({0,90,180,270}) do for _,mx in ipairs({false,true}) do for _,mz in ipairs({false,true}) do
    local data=source();local transform={origin={x=10,y=64,z=20},rotation=rotation,mirrorX=mx,mirrorZ=mz}
    local p=plan(data,transform);local seen={};local count,footprint=0,0
    for index=1,p.regionCount do
      local region=p:region(index);local cursor=1
      repeat
        local columns,nextCursor=p:columns(index,cursor,3);assert(#columns<=3)
        for _,c in ipairs(columns) do
          local key=c.x..','..c.z;assert(not seen[key]);seen[key]=true;count=count+1
          if c.foundationY then footprint=footprint+1;eq(c.foundationY,63) end
          assert(c.x>=region.bounds.min.x and c.x<=region.bounds.max.x)
          assert(c.z>=region.bounds.min.z and c.z<=region.bounds.max.z)
        end
        cursor=nextCursor
      until not cursor
    end
    eq(count,20);eq(footprint,6)
    for i=0,11 do
      local pos=T.position({x=i%2,y=math.floor(i/6),z=math.floor(i/2)%3},data.size,rotation,mx,mz)
      pos.x=pos.x+10;pos.y=pos.y+64;pos.z=pos.z+20
      eq(p:wanted(pos).name,(i==0 or i==11) and 'minecraft:stone' or 'minecraft:air')
    end
    eq(p:wanted({x=9,y=64,z=19}),nil);eq(p.bounds.max.y,67)
  end end end
end)

test('site foundation overrides transform with the source and cannot overwrite required air',function()
  local data=source();data.metadata.site={foundation={columns={{x=0,z=0,y=0},{x=1,z=2,y=1}}}}
  local p=plan(data,{origin={x=10,y=64,z=20},rotation=90,mirrorX=true})
  local heights={};for i=1,p.regionCount do local cs=p:columns(i,1,64);for _,c in ipairs(cs) do if c.foundationY then heights[c.x..','..c.z]=c.foundationY end end end
  eq(heights['12,21'],64);eq(heights['10,20'],65)
  eq(p:wanted({x=10,y=64,z=20}).name,'minecraft:air')
  data.metadata.site.foundation.columns[1].y=1
  assert(not pcall(plan,data),'foundation would fill an explicit schematic air cell')
end)

test('site plan rejects malformed or unbounded geometry and retains immutable source identity',function()
  for _,bad in ipairs({{x=0,z=0,y=0.5},{x=2,z=0,y=-1},{x=0,z=0,y=-1000}}) do
    local data=source();data.metadata.site={foundation={columns={bad}}};assert(not pcall(plan,data))
  end
  local data=source();data.metadata.site={foundation={columns={{x=0,z=0,y=-1},{x=0,z=0,y=-2}}}}
  assert(not pcall(plan,data),'duplicate foundation column')
  data=source();local p=plan(data);local id=p.identity
  data.palette[1].name='minecraft:dirt';eq(p:wanted({x=10,y=64,z=20}).name,'minecraft:stone')
  eq(plan().identity,id);assert(plan(nil,{origin={x=11,y=64,z=20}}).identity~=id)
  assert(not pcall(plan,nil,{origin={x=30000000,y=64,z=20}}))
  assert(not pcall(plan,nil,{origin={x=10,y=318,z=20}}))
  assert(not pcall(plan,nil,nil,{margin=1000}))
  assert(not pcall(p.columns,p,1,1,65));assert(not pcall(p.region,p,0))
end)

test('large site geometry emits bounded clipped regions without expanding the schematic volume',function()
  local d={schema=1,size={x=512,y=1,z=512},palette={{name='minecraft:stone',state={}}},runs={{id=1,count=262144}},metadata={},requirements={}}
  local p=plan(d,{origin={x=-256,y=64,z=-256}}, {regionSize=8,margin=1})
  eq(p.regionCount,65*65);eq(p.blocks,nil);eq(p.cells,nil)
  local last=p:region(p.regionCount);eq(last.columns,4)
  local columns,cursor=p:columns(p.regionCount,1,64);eq(#columns,4);eq(cursor,nil)
  eq(p:wanted({x=255,y=64,z=255}).name,'minecraft:stone')
end)


test('site plan emits valid bounded survey contracts and keeps workspace scans above its floor',function()
  local p=plan();local job,nextCursor=p:survey(1,1,4)
  assert(require('autobuilder.build.site_survey').validContract(job));eq(#job.siteSurvey.columns,4);eq(nextCursor,5)
  eq(job.siteSurvey.columns[1].minY,64);eq(job.siteSurvey.columns[1].foundationY,nil)
  eq(job.siteSurvey.identity,p.identity)
end)
