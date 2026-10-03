local U=require('autobuilder.core.util')
local function fixture(blocks,stage)
  local w=require('tests.build_world').new();local c={minimumFuelReserve=0,maxTravelDistance=128,movementRetries=1,protectedBlocks={['minecraft:bedrock']=true}}
  local j={id='prep',type='PREPARE_REGION',blocks=blocks,clearanceY=5,bounds={min={x=0,y=-2,z=-1},max={x=5,y=5,z=2}},
    siteWork={identity=string.rep('a',64),region=1,stage=stage or 'clear'}}
  local nav=require('autobuilder.core.navigation').new(w.turtle,w.pose,c,function() return true end)
  nav.workGuard=function() return true end;nav.workDone=function() return true end
  local function engine(save) return require('autobuilder.build.site_work').new(j,{turtle=w.turtle,peripheral=w.peripheral,os={epoch=function() return 100000 end}},c,nav,save or function() return true end) end
  return w,c,j,nav,engine
end
local function air(x,y,retain) return {x=x,y=y or 0,z=0,name='minecraft:air',state={},retain=retain} end
local function run(ex,n) for _=1,n or 80 do ex:step();if ex.task.phase=='completed' or ex.task.phase=='blocked' then break end end end

test('preparation clears occupied and required air cells while retaining exact partial structure',function()
  local kept={name='minecraft:oak_log',state={axis='x'}}
  local w,c,j,nav,new=fixture({air(1,0,kept),air(2),air(3)})
  w.blocks['1,0,0']=U.copy(kept);w.blocks['2,0,0']={name='minecraft:dirt',state={}};w.blocks['3,0,0']={name='minecraft:stone',state={}}
  run(new());eq(j.phase,'completed');eq(j.report.counts.correct,3);eq(w.digs,2);eq(w.places,0)
  eq(w.blocks['1,0,0'].state.axis,'x');assert(not w.blocks['2,0,0']);eq(w.pose.y,5)
end)

test('preparation records exact protected blockers and continues unaffected cells',function()
  local w,c,j,nav,new=fixture({air(1),air(2),air(3)})
  w.blocks['1,0,0']={name='minecraft:chest',state={}};w.blocks['2,0,0']={name='computercraft:turtle_normal',state={}};w.blocks['3,0,0']={name='minecraft:dirt',state={}}
  run(new());eq(j.phase,'completed');eq(w.digs,1);eq(j.report.counts.correct,1)
  eq(j.report.entries[1].x,1);eq(j.report.entries[1].actual.name,'minecraft:chest');assert(j.report.entries[1].reason)
  assert(w.blocks['2,0,0']);assert(not w.blocks['3,0,0'])
end)

test('preparation reconciles no-drop vegetation and a falling replacement after physical reboot',function()
  for _,falling in ipairs({false,true}) do
    local w,c,j,nav,new=fixture({air(1)})
    w.blocks['1,0,0']={name=falling and 'minecraft:gravel' or 'minecraft:grass',state={}}
    local original=w.turtle.digDown;local first=true
    w.turtle.digDown=function()
      if not first then return original() end;first=false;w.digs=w.digs+1
      w.blocks['1,0,0']=falling and {name='minecraft:gravel',state={}} or nil
      if falling then w.items[1]={name='minecraft:gravel',count=1} end
      error('power lost after native excavation')
    end
    local ex=new();run(ex);assert(j.intent);assert(ex:resume());run(new())
    eq(j.phase,'completed');assert(not j.intent);assert(not w.blocks['1,0,0']);eq(w.digs,falling and 2 or 1)
  end
end)

test('preparation preserves reserved inventory and cannot mutate without controller permission or saved intent',function()
  for _,mode in ipairs({'permission','checkpoint','reserved'}) do
    local w,c,j,nav,new=fixture({air(1)});w.blocks['1,0,0']={name='minecraft:dirt',state={}};w.items[15]={name='minecraft:coal',count=2}
    if mode=='permission' then nav.workGuard=function() return false,'movement reservation pending' end end
    local ex=new(function() if mode=='checkpoint' and j.intent then return false,'disk full' end;return true end)
    if mode=='reserved' then
      local dig=w.turtle.digDown;w.turtle.digDown=function() local ok=dig();w.items[15].count=1;return ok end
    end
    local ok=pcall(run,ex);assert(not ok or j.phase=='blocked');eq(w.digs,mode=='reserved' and 1 or 0)
    if mode=='reserved' then assert(j.intent,'ambiguous inventory mutation discarded') end
  end
end)

test('preparation fills missing stable support and retains suitable existing ground',function()
  local blocks={{x=1,y=0,z=0,name='minecraft:cobblestone',state={},support=true},{x=2,y=0,z=0,name='minecraft:cobblestone',state={},support=true}}
  local w,c,j,nav,new=fixture(blocks,'fill');w.blocks['1,0,0']={name='minecraft:grass_block',state={snowy=false}};w.items[1]={name='minecraft:cobblestone',count=2}
  run(new());eq(j.phase,'completed');eq(w.places,1);eq(w.digs,0);eq(w.blocks['1,0,0'].name,'minecraft:grass_block');eq(w.blocks['2,0,0'].name,'minecraft:cobblestone')
end)

test('preparation contracts reject arbitrary fill gravity invalid preservation and escaped cells',function()
  local w,c,j=fixture({air(1)});local M=require('autobuilder.build.site_work');assert(M.validContract(j))
  local bad=U.copy(j);bad.blocks[1].x=100;assert(not M.validContract(bad))
  bad=U.copy(j);bad.blocks[1].retain={name='minecraft:stone',state={nested={}}};assert(not M.validContract(bad))
  bad=U.copy(j);bad.siteWork.stage='fill';bad.blocks[1].name='minecraft:sand';assert(not M.validContract(bad))
  bad=U.copy(j);bad.blocks[3]=U.copy(bad.blocks[1]);assert(not M.validContract(bad))
  j.id='task:7:1';assert(require('autobuilder.core.task_messages').validate('task_assign',{job=j}))
  bad=U.copy(j);bad.type='BUILD';assert(not require('autobuilder.core.task_messages').validate('task_assign',{job=bad}),'preparation metadata accepted on ordinary build')
end)

test('temporary foundation access requires a bounded contiguous route and matching work cells',function()
  local w,c,j=fixture({air(1)},'clear');local M=require('autobuilder.build.site_work')
  local access={entry={x=0,y=5,z=0},cells={},stand={x=1,y=0,z=0},target={x=2,y=0,z=0}}
  for y=4,0,-1 do access.cells[#access.cells+1]={x=0,y=y,z=0} end
  access.cells[#access.cells+1]=U.copy(access.stand);j.siteAccess=access
  assert(M.validContract(j))
  for _,change in ipairs({
    function(a) a.cells[2].x=1 end,
    function(a) a.cells[2]=U.copy(a.cells[1]) end,
    function(a) a.entry.y=4 end,
    function(a) a.stand.x=2 end,
    function(a) a.target.x=10 end,
    function(a) a.cells={} end,
  }) do local bad=U.copy(j);change(bad.siteAccess);assert(not M.validContract(bad),'malformed access route accepted') end
  local bad=U.copy(j);bad.blocks={air(3)};assert(not M.validContract(bad),'unrelated work cell used the access route')
  bad=U.copy(j);bad.blocks={air(2)};assert(not M.validContract(bad),'access excavation removed its foundation target')
  j.siteWork.stage='fill';j.blocks={{x=2,y=0,z=0,name='minecraft:stone',state={},support=true}};assert(M.validContract(j))
  j.blocks[1].support=nil;assert(not M.validContract(j),'name-only access proof accepted for an exact schematic block')
  local wrong=U.copy(j);wrong.id='task:7:1';wrong.type='BUILD';wrong.siteWork=nil
  assert(not require('autobuilder.core.task_messages').validate('task_assign',{job=wrong}),'access metadata escaped preparation validation')
end)

test('temporary access travel exits and reenters an interior tunnel without breaking the retained ceiling',function()
  local w,c,j,nav=fixture({air(1)},'clear');local R=require('autobuilder.workers.resupply')
  j.siteAccess={entry={x=0,y=5,z=0},cells={},stand={x=2,y=0,z=0},target={x=3,y=0,z=0}}
  for y=4,0,-1 do j.siteAccess.cells[#j.siteAccess.cells+1]={x=0,y=y,z=0} end
  for x=1,2 do j.siteAccess.cells[#j.siteAccess.cells+1]={x=x,y=0,z=0} end
  for x=1,3 do w.blocks[x..',1,0']={name='minecraft:stone',state={}} end
  w.pose.x=2;w.pose.y=0;w.pose.z=0
  local home={x=-2,y=2,z=-2};local save=function() return true end
  local travel={}
  nav.guard=function(_,p) if p.x==0 and p.y==1 then return false,'movement reservation pending' end;return true end
  assert(not R.travel(travel,j,nav,home,save,w.turtle,c));eq(w.pose.x,0);eq(w.pose.y,0)
  travel=U.copy(travel);nav.guard=function() return true end -- restored route resumes at its pending shaft step
  assert(R.travel(travel,j,nav,home,save,w.turtle,c));eq(U.distance(w.pose,home),0)
  assert(R.travel({},j,nav,j.siteAccess.stand,save,w.turtle,c));eq(U.distance(w.pose,j.siteAccess.stand),0)
  assert(R.travel({},j,nav,{x=1,y=0,z=0},save,w.turtle,c))
  w.blocks['2,0,0']={name='minecraft:stone',state={}} -- restoration closes the deepest cell behind the turtle
  assert(R.travel({},j,nav,home,save,w.turtle,c));eq(U.distance(w.pose,home),0)
  eq(w.digs,0);eq(w.places,0)
  for x=1,3 do eq(w.blocks[x..',1,0'].name,'minecraft:stone') end
end)

test('preparation opens a tunnel fills and verifies hidden support then restores ground across physical reboots',function()
  local w,c,template,nav=fixture({air(1)},'clear')
  c.restrictedAreas={{min={x=1,y=0,z=0},max={x=3,y=0,z=0}}} -- retained floor cannot be an approach stand
  local access={entry={x=0,y=5,z=0},cells={},stand={x=1,y=-1,z=0},target={x=2,y=-1,z=0}}
  for y=4,-1,-1 do access.cells[#access.cells+1]={x=0,y=y,z=0} end
  access.cells[#access.cells+1]=U.copy(access.stand)
  for x=1,3 do w.blocks[x..',0,0']={name='minecraft:stone',state={}} end
  for x=0,1 do w.blocks[x..',-1,0']={name='minecraft:stone',state={}} end
  w.items[5]={name='minecraft:stone',count=1}
  local function execute(stage,blocks,crash)
    local j=U.copy(template);j.siteAccess=U.copy(access);j.blocks=blocks;j.siteWork.stage=stage
    local function engine() return require('autobuilder.build.site_work').new(j,{turtle=w.turtle},c,nav,function() return true end) end
    if crash=='dig' then w.crashDig=true elseif crash=='place' then w.crashPlace=true end
    local ex=engine();run(ex,200)
    if crash then assert(j.intent,'physical crash lost its intent');assert(ex:resume());run(engine(),200) end
    eq(j.phase,'completed');eq(j.report.counts.correct,#blocks);eq(w.pose.y,5)
    return j
  end
  local opening={};for _,p in ipairs(access.cells) do opening[#opening+1]={x=p.x,y=p.y,z=p.z,name='minecraft:air',state={}} end
  execute('clear',opening,'dig')
  local support={x=2,y=-1,z=0,name='minecraft:stone',state={},support=true}
  execute('fill',{support},'place');local proof=execute('verify',{support});eq(proof.report.counts.correct,1)
  execute('fill',{{x=1,y=-1,z=0,name='minecraft:stone',state={},support=true},{x=0,y=-1,z=0,name='minecraft:stone',state={},support=true}})
  eq(w.digs,2);eq(w.places,3)
  for x=1,3 do eq(w.blocks[x..',0,0'].name,'minecraft:stone') end
  for x=0,2 do eq(w.blocks[x..',-1,0'].name,'minecraft:stone') end
  assert(not next(w.items),'access consumed or duplicated the wrong fill quantity')
end)

test('access fuel admission includes the owned tunnel detour before any physical movement',function()
  local w,_,j,nav=fixture({{x=3,y=0,z=0,name='minecraft:stone',state={},support=true}},'fill')
  j.id='task:7:1';j.siteAccess={entry={x=0,y=5,z=0},cells={},stand={x=2,y=0,z=0},target={x=3,y=0,z=0}}
  for y=4,0,-1 do j.siteAccess.cells[#j.siteAccess.cells+1]={x=0,y=y,z=0} end
  for x=1,2 do j.siteAccess.cells[#j.siteAccess.cells+1]={x=x,y=0,z=0} end
  local c=require('tests.loaded_config').load({role='worker',controllerId=7,automation={building=true},minimumFuelReserve=0,depot=U.copy(w.pose)})
  w.turtle.getFuelLevel=function() return 30 end
  local app={navigation=nav,state={id=12,position=w.pose,currentTask=j}};function app:save() return true end
  local ex=require('autobuilder.workers.executor').new(app,c,{turtle=w.turtle},{send=function() return true end},function() return 1 end)
  local before=U.copy(w.pose);ex:step()
  assert(j.requiredFuel and j.requiredFuel>30,'tunnel detour was omitted from admission')
  eq(U.distance(w.pose,before),0);eq(w.digs,0);eq(w.places,0)
end)

test('access assignments require upgraded workers and retain their immutable route across duplicates',function()
  local w,c,j,nav=fixture({{x=2,y=0,z=0,name='minecraft:stone',state={},support=true}},'fill')
  j.siteAccess={entry={x=0,y=5,z=0},cells={},stand={x=1,y=0,z=0},target={x=2,y=0,z=0}}
  for y=4,0,-1 do j.siteAccess.cells[#j.siteAccess.cells+1]={x=0,y=y,z=0} end
  j.siteAccess.cells[#j.siteAccess.cells+1]=U.copy(j.siteAccess.stand)
  local state={jobs={},workers={['12']={id=12,online=true,telemetry={status='idle',capabilities={siteWorkV1=true}}}}}
  local q=require('autobuilder.core.workflows').new(state,function() return true end,function() return 1 end,7,nil,c)
  local job=q:submit('PREPARE_REGION',j);assert(not q:assign(state.workers),'old preparation worker received tunnel work')
  state.workers['12'].telemetry.capabilities.siteAccessV1=true;eq(q:assign(state.workers).id,job.id)
  local config=require('tests.loaded_config').load({role='worker',controllerId=7,automation={building=true}})
  assert(config.capabilities.siteAccessV1,'updated worker does not advertise access execution')
  local app={navigation=nav,state={id=12,position=w.pose}};function app:save() return true end
  local ex=require('autobuilder.workers.executor').new(app,config,{turtle=w.turtle},{send=function() return true end},function() return 1 end)
  local sequence=0;local function assign(value)
    sequence=sequence+1;return ex:handle(7,{boot=1,sequence=sequence,type='task_assign',payload={job=value}})
  end
  config.capabilities.siteAccessV1=nil;local ok,why=assign(job);assert(not ok and why:find('siteAccessV1',1,true))
  config.capabilities.siteAccessV1=true;assert(assign(job));assert(assign(job))
  local changed=U.copy(job);changed.siteAccess=nil
  assert(not assign(changed),'duplicate downgraded a retained access route');assert(app.state.currentTask.siteAccess)
end)

test('preparation placement reconciles one consumed item across reboot and rejects unrelated inventory loss',function()
  for _,changed in ipairs({false,true}) do
    local blocks={{x=1,y=0,z=0,name='minecraft:cobblestone',state={},support=true}}
    local w,c,j,nav,new=fixture(blocks,'fill');w.items[1]={name='minecraft:cobblestone',count=2};w.items[15]={name='minecraft:coal',count=2}
    w.crashPlace=true;local ex=new();run(ex);assert(j.intent)
    if changed then w.items[15].count=1 end
    assert(ex:resume());run(new())
    if changed then eq(j.phase,'blocked');assert(j.intent,'unrelated placement loss discarded')
    else eq(j.phase,'completed');eq(w.places,1);eq(w.items[1].count,1) end
  end
end)

test('controller refuses incomplete or regressed preparation inspection receipts',function()
  local w,c,j=fixture({air(1),air(2)})
  local state={workers={},jobs={}};local Q=require('autobuilder.core.workflows').new(state,function() return true end,function() return 1 end,7)
  j=Q:submit('PREPARE_REGION',j,{});j.workerId=12;j.status='running'
  assert(not Q:progress(12,{jobId=j.id,phase='completed',progress=2}),'preparation completed without inspection proof')
  local p={jobId=j.id,phase='work',progress=1,report={counts={correct=1},entries={}}}
  assert(Q:progress(12,p));local bad=U.copy(p);bad.report.counts.correct=0;assert(not Q:progress(12,bad))
  bad=U.copy(p);bad.phase='completed';assert(not Q:progress(12,bad),'uninspected cell certified')
  p.phase='completed';p.report.counts.inaccessible=1;p.report.entries={{x=2,y=0,z=0,status='inaccessible',reason='protected'}}
  assert(Q:progress(12,p));eq(j.status,'completed');eq(j.report.counts.inaccessible,1)
end)

test('preparation can inspect and fill beneath a retained partial floor from a side stand',function()
  local w,c,j,nav,new=fixture({{x=1,y=0,z=0,name='minecraft:cobblestone',state={},support=true}},'fill')
  w.blocks['1,1,0']={name='minecraft:stone',state={}};w.items[1]={name='minecraft:cobblestone',count=1}
  run(new(),150);eq(j.phase,'completed');eq(j.report.counts.correct,1);eq(w.places,1);eq(w.digs,0)
  eq(w.blocks['1,1,0'].name,'minecraft:stone');eq(w.blocks['1,0,0'].name,'minecraft:cobblestone')
end)

test('stable foundation fill displaces water or lava with a measured restart-safe placement',function()
  for _,fluid in ipairs({'minecraft:water','minecraft:lava'}) do
    local w,c,j,nav,new=fixture({{x=1,y=0,z=0,name='minecraft:cobblestone',state={},support=true}},'fill')
    w.blocks['1,0,0']={name=fluid,state={level=0}};w.items[1]={name='minecraft:cobblestone',count=2}
    local place=w.turtle.placeDown
    w.turtle.placeDown=function()
      -- A solid block replaces a fluid cell; the fixture's ordinary placement
      -- helper otherwise treats all inspected cells as solid obstacles.
      if w.blocks['1,0,0'] and w.blocks['1,0,0'].name==fluid then w.blocks['1,0,0']=nil end
      return place()
    end
    w.crashPlace=true;local ex=new();run(ex);assert(j.intent);assert(ex:resume());run(new())
    eq(j.phase,'completed');eq(w.digs,0);eq(w.places,1);eq(w.blocks['1,0,0'].name,'minecraft:cobblestone');eq(w.items[1].count,1)
  end
end)

test('foundation verification refuses to certify support sealed beneath a retained floor',function()
  local w,c,j,nav,new=fixture({{x=2,y=0,z=0,name='minecraft:stone',state={},support=true}},'verify')
  for x=1,3 do for y=-1,1 do for z=-1,1 do w.blocks[x..','..y..','..z]={name='minecraft:stone',state={}} end end end
  w.blocks['2,0,0']={name='minecraft:stone',state={}}
  run(new(),200);eq(j.phase,'completed');eq(j.report.counts.correct or 0,0);eq(j.report.counts.inaccessible,1)
  eq(j.report.entries[1].x,2);eq(j.report.entries[1].y,0);eq(j.report.entries[1].z,0)
  assert(j.report.entries[1].reason);eq(w.digs,0);eq(w.places,0)
end)

test('sealed generic foundations use fresh scanner proof without excavating retained floors',function()
  for _,stage in ipairs({'fill','verify'}) do for _,observed in ipairs({'minecraft:stone','minecraft:water','missing','broken-tool'}) do
    local w,c,j,nav,new=fixture({{x=2,y=0,z=0,name='minecraft:stone',state={},support=true}},stage)
    for x=1,3 do for y=-1,1 do for z=-1,1 do w.blocks[x..','..y..','..z]={name='minecraft:stone',state={}} end end end
    local equipped,scans,swaps=false,0,0
    c.scanner={side='left',slot=16,radius=8,cooldown=0,maxCost=0}
    w.items[16]={name='advancedperipherals:geo_scanner',count=1}
    w.turtle.getSelectedSlot=function() return w.selected end
    w.turtle.equipLeft=function()
      swaps=swaps+1
      if equipped and observed=='broken-tool' then return false,'tool jammed' end
      equipped=not equipped;w.items[16]={name=equipped and 'minecraft:diamond_pickaxe' or 'advancedperipherals:geo_scanner',count=1};return true
    end
    w.peripheral={getType=function() return equipped and 'geoScanner' or nil end,call=function(_,method)
      if method=='cost' then return 0 end
      assert(method=='scan');scans=scans+1
      if observed=='missing' then return {} end
      return {{x=2-w.pose.x,y=-w.pose.y,z=-w.pose.z,name=observed=='broken-tool' and 'minecraft:stone' or observed}}
    end}
    run(new(),200)
    eq(w.digs,0);eq(w.places,0);eq(scans,1)
    if observed=='broken-tool' then
      eq(j.phase,'blocked');assert(j.error:find('tool recovery',1,true));eq(j.report.counts.correct or 0,0)
      observed='minecraft:stone';local ex=new();assert(ex:resume());run(ex,200)
    end
    eq(j.phase,'completed');assert(not equipped);eq(w.items[16].name,'advancedperipherals:geo_scanner')
    eq(j.report.counts.correct or 0,observed=='minecraft:stone' and 1 or 0)
    if observed~='minecraft:stone' then eq(j.report.counts.inaccessible,1) end
  end end
end)

test('fluid sealing only replaces water and lava and retains journal evidence through reboot',function()
  for _,fluid in ipairs({'minecraft:water','minecraft:lava'}) do
    local blocks={};for x=1,3 do blocks[x]={x=x,y=0,z=0,name='minecraft:cobblestone',state={}} end
    local w,c,j,nav,new=fixture(blocks,'seal')
    w.blocks['1,0,0']={name=fluid,state={level=0}};w.blocks['2,0,0']={name='minecraft:glass',state={}}
    w.items[1]={name='minecraft:cobblestone',count=2}
    local place=w.turtle.placeDown;w.turtle.placeDown=function()
      if w.blocks['1,0,0'] and w.blocks['1,0,0'].name==fluid then w.blocks['1,0,0']=nil end
      return place()
    end
    w.crashPlace=true;local ex=new();run(ex);assert(j.intent);assert(ex:resume());run(new())
    eq(j.phase,'completed');eq(j.report.counts.correct,3);eq(w.places,1);eq(w.digs,0)
    eq(w.blocks['1,0,0'].name,'minecraft:cobblestone');eq(w.blocks['2,0,0'].name,'minecraft:glass');eq(w.blocks['3,0,0'],nil)
    eq(w.items[1].count,1)
  end
end)

test('fluid displacement preserves explicitly protected fluid blocks',function()
  for _,stage in ipairs({'fill','seal'}) do
    local w,c,j,nav,new=fixture({{x=1,y=0,z=0,name='minecraft:cobblestone',state={}}},stage)
    c.protectedBlocks['minecraft:water']=true;w.blocks['1,0,0']={name='minecraft:water',state={level=0}}
    w.items[1]={name='minecraft:cobblestone',count=1}
    run(new());eq(j.phase,'completed');eq(j.report.counts.unsupported,1);eq(w.places,0);eq(w.items[1].count,1)
  end
end)
