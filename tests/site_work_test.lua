local U=require('autobuilder.core.util')
local function fixture(blocks,stage)
  local w=require('tests.build_world').new();local c={minimumFuelReserve=0,maxTravelDistance=128,movementRetries=1,protectedBlocks={['minecraft:bedrock']=true}}
  local j={id='prep',type='PREPARE_REGION',blocks=blocks,clearanceY=5,bounds={min={x=0,y=-2,z=-1},max={x=5,y=5,z=2}},
    siteWork={identity=string.rep('a',64),region=1,stage=stage or 'clear'}}
  local nav=require('autobuilder.core.navigation').new(w.turtle,w.pose,c,function() return true end)
  nav.workGuard=function() return true end;nav.workDone=function() return true end
  local function engine(save) return require('autobuilder.build.site_work').new(j,{turtle=w.turtle},c,nav,save or function() return true end) end
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
