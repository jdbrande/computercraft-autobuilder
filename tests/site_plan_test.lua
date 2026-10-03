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

local function workPlan(source,options)
  local plan=require('autobuilder.build.site_plan').new(source,{origin={x=10,y=0,z=10}},string.rep('a',64),options or {margin=0,minY=-4,maxY=15})
  local payload=plan:survey(1,1,64)
  local record={identity=plan.identity,region=1,clearanceY=payload.clearanceY,report={identity=plan.identity,region=1,observations={}}}
  for _,c in ipairs(payload.siteSurvey.columns) do record.report.observations[#record.report.observations+1]={x=c.x,y=-3,z=c.z,status='surface',name='minecraft:stone'} end
  return plan,record
end

test('foundation access routes stay within owned terrain and preserve every schematic cell',function()
  local data={schema=1,size={x=3,y=1,z=3},palette={{name='minecraft:stone',state={}}},runs={{id=1,count=9}},metadata={},requirements={}}
  local p=plan(data,{origin={x=10,y=0,z=10}},{margin=1,minY=-4,maxY=15})
  local target={x=11,y=-1,z=11}
  local route,restore=p:access(1,target,2);assert(route);eq(U.distance(route.stand,target),1)
  eq(route.entry.y,2);assert(#route.cells>3 and #route.cells<=128)
  local previous=route.entry;local seen={}
  for _,cell in ipairs(route.cells) do
    eq(U.distance(previous,cell),1);assert(require('autobuilder.core.pathfinding').inside(cell,p:region(1).bounds))
    assert(not p:wanted(cell),'access would remove a retained schematic cell')
    assert(U.distance(cell,target)>0,'access route destroys its own target')
    local key=cell.x..','..cell.y..','..cell.z;assert(not seen[key]);seen[key]=true;previous=cell
    eq(restore[key]==true,cell.y<0) -- reopening the shaft must not refill required working air
  end
  eq(U.distance(previous,route.stand),0)
  assert(not p:access(1,{x=9,y=-1,z=9},2),'workspace is not a foundation target')
  assert(not p:access(1,{x=11,y=0,z=11},2),'explicit floor became generic access target')
  local sealed=plan(data,{origin={x=10,y=0,z=10}},{margin=0,minY=-4,maxY=15})
  assert(not sealed:access(1,target,2),'sealed footprint invented an exterior access lease')
  local deep=plan(data,{origin={x=10,y=0,z=10}},{margin=1,minY=-4,maxY=319})
  assert(not deep:access(1,target,200),'unbounded access route accepted')
end)

test('survey-derived work clears hills while preserving planned states and fills actual depressions',function()
  local source={schema=1,size={x=2,y=2,z=1},palette={{name='minecraft:air',state={}},{name='minecraft:oak_log',state={axis='x'}}},
    runs={{id=2,count=1},{id=1,count=3}},metadata={},requirements={}}
  local plan,record=workPlan(source);record.report.observations[2].y=2
  local j,nextCursor=plan:work(1,record,'clear',1,64)
  eq(nextCursor,nil);eq(#j.blocks,6);eq(j.blocks[1].y,2)
  local keep=0;for _,b in ipairs(j.blocks) do if b.retain then keep=keep+1;eq(b.retain.name,'minecraft:oak_log');eq(b.retain.state.axis,'x') end end;eq(keep,1)
  j,nextCursor=plan:work(1,record,'fill',1,64,'minecraft:cobblestone')
  eq(nextCursor,nil);eq(#j.blocks,3)
  eq(j.blocks[1].x,10);eq(j.blocks[1].y,-2);eq(j.blocks[2].y,-1);eq(j.blocks[3].x,11);eq(j.blocks[3].y,-1)
  for _,b in ipairs(j.blocks) do assert(b.support);eq(b.name,'minecraft:cobblestone') end
  assert(require('autobuilder.build.site_work').validContract(j))
end)

test('stepped preparation never fills explicit air below the planned elevated foundation',function()
  local source={schema=1,size={x=1,y=3,z=1},palette={{name='minecraft:air',state={}},{name='minecraft:stone',state={}}},
    runs={{id=1,count=2},{id=2,count=1}},metadata={site={foundation={columns={{x=0,z=0,y=2}}}}},requirements={}}
  local plan,record=workPlan(source)
  local j=plan:work(1,record,'fill',1,64,'minecraft:cobblestone')
  eq(#j.blocks,3);eq(j.blocks[1].y,-2);eq(j.blocks[2].y,-1);eq(j.blocks[3].y,2);eq(j.blocks[3].name,'minecraft:stone');assert(not j.blocks[3].support)
  local seen={};j=plan:work(1,record,'clear',1,64)
  for _,b in ipairs(j.blocks) do seen[b.y]=b end
  assert(seen[0] and seen[1] and not seen[0].retain and not seen[1].retain);eq(seen[2].retain.name,'minecraft:stone')
end)

test('work batches are bounded resumable and refuse blocked mismatched or unstable fill evidence',function()
  local source={schema=1,size={x=8,y=8,z=8},palette={{name='minecraft:stone',state={}}},runs={{id=1,count=512}},metadata={},requirements={}}
  local plan,record=workPlan(source,{margin=0,minY=-64,maxY=319})
  local cursor,total,seen=1,0,{}
  repeat
    local j,nextCursor=plan:work(1,record,'verify_clear',cursor,7)
    eq(j.siteWork.stage,'verify');assert(#j.blocks<=7)
    for _,b in ipairs(j.blocks) do local key=b.x..','..b.y..','..b.z;assert(not seen[key]);seen[key]=true;total=total+1 end
    cursor=nextCursor
  until not cursor
  eq(total,64*9)
  local bad=U.copy(record);bad.report.observations[1].status='blocked';bad.report.observations[1].reason='inaccessible';bad.report.observations[1].name=nil
  assert(not pcall(plan.work,plan,1,bad,'clear',1,8))
  bad=U.copy(record);bad.identity=string.rep('b',64);assert(not pcall(plan.work,plan,1,bad,'clear',1,8))
  assert(not pcall(plan.work,plan,1,record,'fill',1,8,'minecraft:sand'))
  assert(not pcall(plan.work,plan,1,record,'clear',0,8))
  assert(not pcall(plan.work,plan,1,record,'clear',1,513))
end)

test('structural region prerequisites include its foundation tiles and adjacent working clearance',function()
  local source={schema=1,size={x=32,y=1,z=8},palette={{name='minecraft:stone',state={}}},runs={{id=1,count=256}},metadata={},requirements={}}
  local plan=require('autobuilder.build.site_plan').new(source,{origin={x=100,y=0,z=100}},string.rep('a',64))
  local regions=plan:requiredRegions({{x=100,y=0,z=100},{x=107,y=0,z=107}})
  eq(table.concat(regions,','),'1,2,6,7')
  regions=plan:requiredRegions({{x=124,y=0,z=100},{x=131,y=0,z=107}})
  eq(table.concat(regions,','),'4,5,9,10')
  assert(not pcall(plan.requiredRegions,plan,{{x=1000,y=0,z=0}}))
end)

test('an air-only schematic clears its requested volume without inventing an unrequested foundation',function()
  local source={schema=1,size={x=1,y=1,z=1},palette={{name='minecraft:air',state={}}},runs={{id=1,count=1}},metadata={},requirements={}}
  local plan=require('autobuilder.build.site_plan').new(source,{origin={x=10,y=5,z=10}},string.rep('a',64),{margin=0})
  local j=plan:survey(1,1,64);assert(not j.siteSurvey.columns[1].foundationY);eq(j.siteSurvey.columns[1].minY,5)
  local evidence={identity=plan.identity,region=1,clearanceY=j.clearanceY,report={identity=plan.identity,region=1,observations={{x=10,y=5,z=10,name='minecraft:stone',status='surface'}}}}
  eq(plan:work(1,evidence,'fill',1,8,'minecraft:cobblestone'),nil)
end)

test('fluid sealing covers the bounded clearance volume with stable temporary blocks',function()
  local source={schema=1,size={x=2,y=2,z=1},palette={{name='minecraft:air',state={}},{name='minecraft:glass',state={}}},
    runs={{id=2,count=1},{id=1,count=3}},metadata={},requirements={}}
  local plan,record=workPlan(source)
  local j,nextCursor,total=plan:work(1,record,'seal',1,4,'minecraft:cobblestone')
  eq(total,6);eq(nextCursor,5);eq(j.siteWork.stage,'seal');eq(#j.blocks,4)
  for _,b in ipairs(j.blocks) do eq(b.name,'minecraft:cobblestone');assert(not b.retain and not b.support) end
  assert(require('autobuilder.build.site_work').validContract(j))
  j,nextCursor=plan:work(1,record,'seal',nextCursor,4,'minecraft:cobblestone');eq(#j.blocks,2);eq(nextCursor,nil)
  assert(not pcall(plan.work,plan,1,record,'seal',1,4,'minecraft:sand'))
end)

test('interior foundation access declares its cross-region tunnel envelope inside the project margin',function()
  local data={schema=1,size={x=6,y=1,z=6},palette={{name='minecraft:stone',state={}}},runs={{id=1,count=36}},metadata={},requirements={}}
  local p=plan(data,{origin={x=10,y=0,z=10}},{margin=1,regionSize=2,minY=-4,maxY=15})
  local target={x=12,y=-1,z=12};local region
  for r=1,p.regionCount do if require('autobuilder.core.pathfinding').inside(target,p:region(r).bounds) then region=r end end
  local route,restore=p:access(region,target,2)
  assert(route,'interior region could not reach the project margin');assert(route.bounds)
  assert(require('autobuilder.resources.exploration').overlaps(route.bounds,p:region(region).bounds))
  local crossed=false
  for _,cell in ipairs(route.cells) do
    assert(require('autobuilder.core.pathfinding').inside(cell,route.bounds))
    assert(require('autobuilder.core.pathfinding').inside(cell,p.bounds))
    assert(not p:wanted(cell));if not require('autobuilder.core.pathfinding').inside(cell,p:region(region).bounds) then crossed=true end
    eq(restore[require('autobuilder.core.pathfinding').key(cell)]==true,cell.y<0)
  end
  assert(crossed)
end)
