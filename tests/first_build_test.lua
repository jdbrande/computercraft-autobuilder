local U=require('autobuilder.core.util')
local S=require('tests.support')
local IS=require('tests.install_support')
local function fixture(autoSite)
  local world=require('tests.build_world').new()
  world.fuel=6000
  -- Both pilot origins have existing support; this fixture tests the shortcut,
  -- with a finite allowance for the added survey and preparation travel.
  if autoSite then
    for x=0,7 do for z=2,9 do world.blocks[x..',1,'..z]={name='minecraft:stone',state={}} end end
  else
    for x=8,15 do for z=0,7 do world.blocks[x..',-1,'..z]={name='minecraft:stone',state={}} end end
  end
  world.turtle.getFuelLevel=function() return world.fuel end
  for _,action in ipairs({'forward','up','down'}) do
    local move=world.turtle[action]
    world.turtle[action]=function() local ok,err=move(); if ok then world.fuel=world.fuel-1 end; return ok,err end
  end
  local stock={[1]={name='minecraft:cobbled_deepslate',count=13},[2]={name='minecraft:sandstone',count=15}}
  local stage={};local storage=require('tests.managed_logistics_support').new()
  storage.size=27;storage.inventories={stock=stock,stage=stage,home={}}
  world.blocks['0,1,0']={name='minecraft:chest',state={}}
  world.turtle.dropDown=function(n)
    assert(world.pose.x==0 and world.pose.y==2 and world.pose.z==0,'wrong return position')
    local v=world.items[world.selected];if not v then return false end
    local home=storage.inventories.home
    for slot=1,27 do if not home[slot] or home[slot].name==v.name and home[slot].count<64 then
      local moved=math.min(n,v.count,64-(home[slot] and home[slot].count or 0))
      home[slot]=home[slot] or {name=v.name,count=0};home[slot].count=home[slot].count+moved
      v.count=v.count-moved;if v.count==0 then world.items[world.selected]=nil end;return moved>0
    end end
    return false
  end
  world.blocks['0,2,-1']={name='minecraft:chest',state={}}
  world.turtle.getItemSpace=function(slot) return 64-world.turtle.getItemCount(slot) end
  world.turtle.suck=function(n)
    assert(world.pose.x==0 and world.pose.y==2 and world.pose.z==0 and world.pose.heading=='north','wrong supply position')
    local item=stage[1]; if not item then return false end
    local count=math.min(n,item.count); local slot=world.selected
    if world.items[slot] then assert(world.items[slot].name==item.name); world.items[slot].count=world.items[slot].count+count
    else world.items[slot]={name=item.name,count=count} end
    item.count=item.count-count; if item.count==0 then stage[1]=nil end; return true
  end
  local function env(id)
    local codec=S.codec(); codec.serializeJSON=codec.serialize; codec.unserializeJSON=codec.unserialize
    local e={fs=IS.fs(),textutils=codec,now=100,packets={},screen={}}
    e.os={getComputerID=function() return id end,epoch=function() return e.now*1000 end}
    e.rednet={isOpen=function() return true end,open=function() end,send=function(to,m,p) e.packets[#e.packets+1]={to=to,m=U.copy(m),protocol=p}; return true end}
    e.peripheral={getNames=function() return {'right'} end,getType=function() return 'modem' end,call=function(name,method,...)
      if method=='isWireless' then return true end
      return storage.e.peripheral.call(name,method,...)
    end}
    e.term={getSize=function() return 51,19 end,clear=function() e.screen={} end,setCursorPos=function(_,y) e.row=y end,write=function(s) e.screen[e.row]=s end}
    return e
  end
  local ce,we=env(1),env(8); we.turtle=world.turtle
  local C=require('tests.loaded_config'); local cc=C.load({storageInventories={'stock'},logistics={nodes={{id='base',inventory='stock',position={x=-3,y=1,z=0},buffers={{inventory='home',position={x=0,y=2,z=0}}}}}},supply={inventory='stage'},build={enabled=true,origin={x=8,y=0,z=0}}})
  local wc=C.load({role='worker',controllerId=1,initialPosition=U.copy(world.pose),depot=U.copy(world.pose),supply={inventory='stage'},automation={building=true}})
  local R=require('autobuilder.core.runtime'); local c,b=R.new(cc,ce),R.new(wc,we)
  local function pump(from,to)
    local packets=from.packets; from.packets={}; for _,p in ipairs(packets) do to:receive(p.m.sender,p.m,p.protocol) end
  end
  local function step()
    ce.now=ce.now+1; we.now=ce.now
    b:tick(); pump(we,c); c:tick(); pump(ce,b); c:workStep(); b:workStep(); pump(we,c); pump(ce,b)
  end
  step()
  return {world=world,ce=ce,we=we,c=c,b=b,cc=cc,stock=stock,stage=stage,step=step,
    reboot=function() c=R.new(cc,ce); b=R.new(wc,we); return c,b end}
end
test('automatic first build clears terrain then builds and verifies across a clearing restart',function()
  local f=fixture(true); f.cc.build.autoSite=true
  local Site=require('autobuilder.build.site'); local plan=Site.plan(f.world.pose)
  local K=require('autobuilder.core.pathfinding').key
  for _,pos in ipairs(plan.points) do
    if U.distance(pos,f.world.pose)>0 then f.world.blocks[K(pos)]={name='minecraft:stone',state={}} end
  end
  -- Real turtles stack mined stone; this fixture's ordinary dig starts a new slot.
  for _,suffix in ipairs({'','Up','Down'}) do
    local dig=f.world.turtle['dig'..suffix]
    f.world.turtle['dig'..suffix]=function()
      local ok,err=dig()
      for slot=2,14 do
        local item=f.world.items[slot]
        if item then for earlier=1,slot-1 do
          local target=f.world.items[earlier]
          if target and target.name==item.name and target.count+item.count<=64 then
            target.count=target.count+item.count; f.world.items[slot]=nil; break
          end
        end end
      end
      return ok,err
    end
  end
  assert(f.c:command('2'))
  local restarted=false
  for _=1,8000 do
    f.step()
    if not restarted and f.world.digs>5 then
      assert(f.c:command('3')); f.step(); f.c,f.b=f.reboot()
      local before=f.world.digs; for _=1,10 do f.step() end; eq(f.world.digs,before)
      assert(f.c:command('4')); restarted=true
    end
    local p=f.c.state.automation.projects.first_cathedral_test
    if p and p.phase=='built' and not f.b.state.currentTask then break end
  end
  local p=f.c.state.automation.projects.first_cathedral_test
  assert(p and p.phase=='built',f.ce.textutils.serialize({first=f.c.state.firstBuild,project=p,task=f.b.state.currentTask,jobs=f.c.state.automation.jobs}))
  assert(restarted);eq(next(f.world.items),nil);assert(require('autobuilder.factory.factory').count(f.stock,'minecraft:stone')>0);eq(f.world.places,28); eq(p.report.counts.correct,64)
  eq(p.transform.origin.x,plan.origin.x); eq(p.transform.origin.z,plan.origin.z)
  assert(f.world.blocks['0,2,-1'].name=='minecraft:chest'); assert(f.world.fuel>=100)
end)
test('first build refuses missing settings, missing materials and unfueled builders without submitting jobs',function()
  local f=fixture(); f.cc.build.enabled=false
  assert(not f.c:command('pilot start')); eq(f.c.state.firstBuild,nil)
  f.cc.build.enabled=true; f.stock[1].count=12
  local ok,err=f.c:command('2'); assert(not ok and err:find('cobbled deepslate')); eq(f.c.state.firstBuild,nil)
  f.stock[1].count=13; f.c.state.workers['8'].telemetry.fuel=0
  assert(not f.c:command('2')); eq(f.c.state.firstBuild,nil); eq(next(f.c.state.automation.jobs),nil)
end)
test('automatic site requires an updated builder and refuses occupied or protected cells before scheduling',function()
  local f=fixture(true); f.cc.build.autoSite=true
  f.c.state.workers['8'].telemetry.capabilities.sitePreparation=nil
  local ok,err=f.c:command('2'); assert(not ok and err:find('update',1,true)); eq(f.c.state.firstBuild,nil)
  f.c.state.workers['8'].telemetry.capabilities.sitePreparation=true
  f.c.state.workers['9']={id=9,online=false,telemetry={position={x=0,y=4,z=0,known=true}}}
  ok,err=f.c:command('2'); assert(not ok and err:find('turtle 9',1,true)); eq(f.c.state.firstBuild,nil)
  f.c.state.workers['9']=nil
  f.cc.restrictedAreas={{min={x=0,y=3,z=0},max={x=0,y=3,z=0}}}
  ok,err=f.c:command('2'); assert(not ok and err:find('protected',1,true)); eq(f.c.state.firstBuild,nil)
  eq(next(f.c.state.automation.jobs),nil)
end)
test('site fuel recovery burns slot 15 fuel in place and continues the saved route',function()
  local f=fixture(true); f.cc.build.autoSite=true
  f.world.turtle.refuel=function(n)
    eq(f.world.selected,15); local item=f.world.items[15]; eq(item.name,'minecraft:coal_block')
    item.count=item.count-n; f.world.fuel=f.world.fuel+800*n
    if item.count==0 then f.world.items[15]=nil end
    return true
  end
  assert(f.c:command('2'))
  for _=1,200 do f.step(); local t=f.b.state.currentTask; if t and t.index and t.index>=8 then break end end
  local t=assert(f.b.state.currentTask); eq(t.type,'PREPARE_SITE')
  f.world.fuel=200; f.world.items[15]={name='minecraft:coal_block',count=6}
  for _=1,200 do f.step(); if f.world.fuel>200 then break end end
  assert(f.world.fuel>200)
  for _=1,8000 do
    f.step(); local p=f.c.state.automation.projects.first_cathedral_test
    if p and p.phase=='built' then break end
  end
  local p=f.c.state.automation.projects.first_cathedral_test
  assert(p and p.phase=='built',f.ce.textutils.serialize({first=f.c.state.firstBuild,task=f.b.state.currentTask}))
end)
test('first build bundles pilot, resupplies, verifies all cells and survives both restarts',function()
  local f=fixture(); assert(f.c:command('2')); assert(f.c:command('2'))
  local restarted=false
  for _=1,7000 do
    f.step()
    if not restarted and f.world.places==1 then f.c,f.b=f.reboot(); restarted=true end
    local p=f.c.state.automation.projects.first_cathedral_test
    if p and p.phase=='built' and not f.b.state.currentTask and not next(f.b.state.pendingSupplyAcks) then break end
  end
  local p=f.c.state.automation.projects.first_cathedral_test
  assert(restarted,f.ce.textutils.serialize({first=f.c.state.firstBuild,project=p,task=f.b.state.currentTask}))
  assert(p.phase=='built',f.ce.textutils.serialize({phase=p.phase,task=f.b.state.currentTask,requests=f.c.state.automation.requests,supply=f.c.state.automation.supply,jobs=f.c.state.automation.jobs}))
  eq(f.world.places,28); eq(f.world.digs,0); eq(p.report.counts.correct,64)
  eq(next(f.stock),nil); eq(next(f.stage),nil)
  local count=0; for _ in pairs(f.c.state.automation.jobs) do count=count+1 end
  assert(f.c:command('2')); for _=1,5 do f.step() end
  local again=0; for _ in pairs(f.c.state.automation.jobs) do again=again+1 end
  eq(again,count); eq(f.world.places,28)
end)
test('first build pause before scheduling persists through restart until explicit continue',function()
  local f=fixture(); assert(f.c:command('2')); assert(f.c:command('3'))
  f.c,f.b=f.reboot(); for _=1,10 do f.step() end
  eq(f.world.places,0); eq(next(f.c.state.automation.jobs),nil)
  assert(not f.c:command('2')); assert(f.c:command('4'))
  for _=1,20 do f.step() end
  assert(next(f.c.state.automation.jobs),f.ce.textutils.serialize({first=f.c.state.firstBuild,project=f.c.state.automation.projects.first_cathedral_test}))
end)
test('first build will not take over other work or a project with its reserved name',function()
  local f=fixture(); f.c.state.jobs.other={id='other',status='queued'}
  assert(not f.c:command('2')); eq(f.c.state.firstBuild,nil)
  f.c.state.jobs.other=nil; f.c.state.automation.projects.first_cathedral_test={name='first_cathedral_test',phase='imported'}
  assert(not f.c:command('2')); eq(f.c.state.firstBuild,nil)
end)
test('first build refuses changed import and setup changes after a saved start',function()
  local f=fixture(); assert(f.c:command('2')); f.step()
  local p=assert(f.c.state.automation.projects.first_cathedral_test)
  f.ce.fs.files[p.path]='changed'; for _=1,4 do f.step() end
  eq(f.world.places,0); assert(f.c.state.firstBuild.error); eq(next(f.c.state.automation.jobs),nil)
  f=fixture(); assert(f.c:command('2')); f.cc.build.origin.x=99; f.step()
  eq(f.world.places,0); assert(f.c.state.firstBuild.error)
end)
test('guide menu explains first build, preserves worker list and opens setup only after runtime exits',function()
  local f=fixture(); assert(f.c:command('1')); f.c:draw()
  local screen=table.concat(f.ce.screen,'\n'); assert(screen:find('2 Start') and screen:find('7 Setup'))
  assert(f.c:command('5')); eq(f.c.state.view,'workers')
  assert(f.c:command('setup')); eq(f.c.nextProgram,'setup'); eq(f.c.quitRequested,true)
  assert(f.c:command('setup factory')); eq(f.c.nextProgramArgs[1],'factory')
  assert(f.b:command('setup miner stone,coal')); eq(f.b.nextProgramArgs[1],'miner'); eq(f.b.nextProgramArgs[2],'stone,coal')
  local ok,err=f.b:command('2'); eq(ok,false); assert(err:find('controller 1'))
  eq(f.world.places,0)
end)
test('test preparation persists its project link and stays on the beginner guide',function()
  local f=fixture(); local CP=require('autobuilder.core.checkpoint')
  local original=f.c.save; local checked=0
  f.c.save=function(self)
    for id,r in pairs(self.state.automation.requests) do
      if r.key=='project:first_cathedral_test' then
        eq(self.state.automation.projects.first_cathedral_test.requestId,id); checked=checked+1
      end
    end
    return original(self)
  end
  assert(f.c:command('2')); f.step()
  assert(checked>0)
  eq(f.c.state.view,'guide')
  local checkpoint=CP.new(f.ce.fs,f.ce.textutils,'/autobuilder/data/controller.state'):load()
  local p=checkpoint.automation.projects.first_cathedral_test
  assert(p.requestId); eq(checkpoint.automation.requests[p.requestId].stockOnly,true)
  for _=1,5 do f.step() end; eq(f.c.state.view,'guide')
end)
test('startup ends the old runtime before setup and reloads saved settings on return',function()
  local file=assert(io.open('autobuilder/startup.lua','r')); local source=file:read('*a'); file:close()
  local runs=0; local setups=0; local value={version='old'}
  local e={fs={exists=function() return false end},package={path=package.path,loaded={}}}
  e.printError=function(message) error(message) end
  e.require=function(name)
    if name=='autobuilder.settings' then
      e.package.loaded[name]=e.package.loaded[name] or value; return e.package.loaded[name]
    elseif name=='autobuilder.config' then return {load=function(v) return v end}
    elseif name=='autobuilder.core.runtime' then return {run=function(c)
      runs=runs+1
      if runs==1 then eq(c.version,'old'); eq(setups,0); return {nextProgram='setup',nextProgramArgs={'miner','sand'}} end
      eq(runs,2); eq(setups,1); eq(c.version,'new'); return {}
    end} end
    error(name)
  end
  e.shell={run=function(path,arg,role,resource)
    eq(runs,1); eq(path,'/autobuilder/setup.lua'); eq(arg,'--menu')
    eq(role,'miner'); eq(resource,'sand')
    setups=setups+1; value={version='new'}; return true
  end}
  setmetatable(e,{__index=_G}); assert(load(source,'@startup.lua','t',e))()
  eq(runs,2); eq(setups,1)
end)
test('a running pilot stays paused across reboot and resumes the same tasks',function()
  local f=fixture(); assert(f.c:command('2'))
  for _=1,6000 do f.step(); if f.world.places>0 then break end end
  assert(f.world.places>0); assert(f.c:command('3'))
  f.c,f.b=f.reboot(); local before=f.world.places
  for _=1,20 do f.step() end; eq(f.world.places,before)
  assert(f.c:command('4'))
  for _=1,1000 do f.step(); if f.world.places>before then break end end
  assert(f.world.places>before)
end)
test('missing stock during preparation shows an action without queuing mining or crafting',function()
  local f=fixture(); assert(f.c:command('2')); f.step(); f.stock[2]=nil
  for _=1,7 do f.step() end
  assert(f.c:command('1')); assert(table.concat(f.c.state.guideLines,' '):find('Put 15 more sandstone'))
  eq(next(f.c.state.jobs),nil); eq(next(f.c.state.automation.jobs),nil)
end)
test('pilot supply failures keep replenishment manual and do not create fuel-stock mining',function()
  local f=fixture(); assert(f.c:command('2'))
  for _=1,6000 do
    f.step()
    if f.b.state.currentTask and f.b.state.currentTask.supplyRequest then break end
  end
  assert(f.b.state.currentTask.supplyRequest); f.stock[1]=nil
  for _=1,25 do f.step() end
  local found=false
  for _,r in pairs(f.c.state.automation.requests) do
    if r.key:find('supply:',1,true)==1 then eq(r.stockOnly,true); found=true end
  end
  assert(found); eq(next(f.c.state.jobs),nil)
  for _,j in pairs(f.c.state.automation.jobs) do assert(j.type~='CRAFT' and j.type~='SMELT') end
end)
test('pilot chooses the ready builder even if a lower-ID unconfigured builder is online',function()
  local f=fixture(); local unready=U.copy(f.c.state.workers['8']); unready.id=2
  unready.telemetry.position={known=false}; unready.telemetry.fuel=0
  f.c.state.workers['2']=unready
  assert(f.c:command('2')); eq(f.c.state.firstBuild.workerId,8)
  for _=1,8 do f.step() end
  for _,j in pairs(f.c.state.automation.jobs) do eq(j.preferredWorker,8); if j.workerId then eq(j.workerId,8) end end
end)


test('first build hands off to the durable project pipeline when site surveying begins',function()
  local f=fixture();assert(f.c:command('2'))
  for _=1,50 do
    f.step();local p=f.c.state.automation.projects.first_cathedral_test
    if p and p.site then
      assert(p.autoStart,'normal project did not retain automatic continuation')
      assert(not f.c.state.firstBuild.autoStart,'shortcut kept repeating checks after handing off preparation')
      eq(f.c.state.firstBuild.raw,nil);return
    end
  end
  error('pilot did not begin its normal site pipeline')
end)
