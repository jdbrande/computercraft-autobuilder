local S=require('tests.support')
local IS=require('tests.install_support')
local C=require('autobuilder.config')
local CP=require('autobuilder.core.checkpoint')
local function env(role,answers)
  local e={fs=IS.fs(),textutils=S.codec(),output={},os={getComputerID=function() return role=='worker' and 8 or 1 end,epoch=function() return 1000 end}}
  e.textutils.serializeJSON=e.textutils.serialize; e.textutils.unserializeJSON=e.textutils.unserialize
  e.print=function(s) e.output[#e.output+1]=s end; e.write=e.print
  e.read=function() assert(#answers>0,'unexpected prompt'); return table.remove(answers,1) end
  e.fs.makeDir('/autobuilder'); e.fs.files['/autobuilder/settings.lua']='return {role="'..role..'",controllerId=1,label="Keep me",minimumFuelReserve=123}'
  e.peripheral={getNames=function() return {'right','stock','stage'} end,
    getType=function(n) return n=='right' and 'modem' or 'minecraft:chest' end,
    getMethods=function(n) return n=='right' and {'isWireless'} or {'list','size','pushItems'} end,
    call=function(n,m) if m=='isWireless' then return true elseif m=='list' then return n=='stock' and {[1]={name='minecraft:sandstone',count=15}} or {} elseif m=='size' then return 27 end end}
  e.rednet={isOpen=function() return true end,open=function() end,
    send=function(to,m,protocol) e.packet={to=to,message=m,protocol=protocol}; return true end,
    receive=function(protocol) return 1,{version=1,type='setup_profile',requestId=e.packet.message.requestId,supply={inventory='stage',side='front'}} end}
  e.gps={locate=function() return 12,64,-9 end}
  if role=='worker' then
    e.turtle=S.turtle(); local t=e.turtle
    t.inspect=function() return true,{name='minecraft:chest'} end
    t.items={[15]={name='minecraft:coal',count=16}}; t.selected=3
    t.getSelectedSlot=function() return t.selected end
    t.select=function(slot) t.selected=slot; return true end
    t.getItemDetail=function(slot) return t.items[slot] end
    t.getItemCount=function(slot) return t.items[slot] and t.items[slot].count or 0 end
    t.refuel=function(n)
      local item=t.items[t.selected]
      local values={['minecraft:coal']=80,['minecraft:charcoal']=80,['minecraft:coal_block']=800}
      assert(t.selected==15 and item and values[item.name])
      assert(e.fs.exists('/autobuilder/data/worker.state'),'fuel consumed before settings were saved')
      item.count=item.count-n; t.fuel=t.fuel+values[item.name]*n
      if item.count==0 then t.items[t.selected]=nil end
      return true
    end
  end
  return e
end
local function settings(e) return assert(load(e.fs.files['/autobuilder/settings.lua'],'settings','t',{}))() end
test('factory wizard saves discovered furnaces while preserving a blocked material request',function()
  local e=env('controller',{'none','yes'}); local base=e.peripheral
  local oldType,oldCall=base.getType,base.call
  base.getNames=function() return {'right','left','furnace_0','stock','stage'} end
  base.getType=function(n) if n=='left' then return 'modem' elseif n=='furnace_0' then return 'minecraft:furnace' else return oldType(n) end end
  base.call=function(n,m,...) if n=='left' and m=='isWireless' then return false end; return oldCall(n,m,...) end
  local store=CP.new(e.fs,e.textutils,'/autobuilder/data/controller.state')
  assert(store:save({schema=1,id=1,role='controller',boot=1,phase='telemetry',jobs={},automation={jobs={},projects={p={phase='preparing'}},requests={r={status='blocked',error='No configured furnace'}}}}))
  assert(require('autobuilder.setup_wizard').run({'factory'},e))
  eq(settings(e).furnaces[1],'furnace_0'); eq(store:load().automation.requests.r.status,'blocked')
end)
test('controller setup defaults to automatic site without requesting coordinates',function()
  local e=env('controller',{'1','2','','yes'})
  assert(require('autobuilder.setup_wizard').run({},e))
  local c=C.load(settings(e)); eq(c.build.autoSite,true); eq(c.clearSite,false)
end)
test('setup discovers inventories without moving any items',function()
  local e=env('controller',{}); local list=require('autobuilder.setup_wizard').inventories(e)
  eq(#list,2); eq(list[1].name,'stage'); eq(list[2].items['minecraft:sandstone'],15)
end)
test('builder wizard uses GPS and controller profile and updates an existing checkpoint',function()
  local e=env('worker',{'east','yes','yes'})
  local store=CP.new(e.fs,e.textutils,'/autobuilder/data/worker.state')
  assert(store:save({schema=1,id=8,role='worker',boot=4,phase='telemetry',position={known=false},completedTasks={old=true}}))
  assert(require('autobuilder.setup_wizard').run({},e))
  local c=C.load(settings(e)); eq(c.label,'Keep me'); eq(c.minimumFuelReserve,123)
  eq(c.depot.x,12); eq(c.depot.heading,'east'); eq(c.supply.inventory,'stage'); eq(c.capabilities.building,true)
  local state=store:load(); eq(state.position.known,true); eq(state.position.heading,'east'); eq(state.completedTasks.old,true)
  eq(e.turtle.calls,0); assert(e.fs.exists('/autobuilder/data/settings-before-setup.lua'))
end)
test('controller wizard selects stage and stock and preserves unrelated settings',function()
  local e=env('controller',{'1','2','20 64 -9','yes'})
  assert(require('autobuilder.setup_wizard').run({},e))
  local c=C.load(settings(e)); eq(c.supply.inventory,'stage'); eq(c.storageInventories[1],'stock')
  eq(c.build.origin.x,20); eq(c.build.enabled,true); eq(c.clearSite,false); eq(c.label,'Keep me')
end)
test('setup refuses current tasks, pending receipts, uncertain motion and backup state',function()
  for _,extra in ipairs({{currentTask={phase='completed'}},{pendingSupplyAcks={batch='job'}},{position={known=false,pending={action='forward'}}},{assignmentRecovery=true}}) do
    local e=env('worker',{}); local state={schema=1,id=8,role='worker',boot=1,phase='telemetry',position={known=false}}
    for k,v in pairs(extra) do state[k]=v end
    assert(CP.new(e.fs,e.textutils,'/autobuilder/data/worker.state'):save(state))
    local original=e.fs.files['/autobuilder/settings.lua']; assert(not pcall(require('autobuilder.setup_wizard').run,{},e)); eq(e.fs.files['/autobuilder/settings.lua'],original)
  end
  local e=env('worker',{}); local store=CP.new(e.fs,e.textutils,'/autobuilder/data/worker.state')
  assert(store:save({schema=1,id=8,role='worker',boot=1,phase='telemetry',position={known=false}}))
  assert(store:save({schema=1,id=8,role='worker',boot=2,phase='telemetry',position={known=false}}))
  e.fs.files['/autobuilder/data/worker.state']='broken'
  assert(not pcall(require('autobuilder.setup_wizard').run,{},e))
end)
test('cancelled wizard leaves configuration and checkpoint untouched',function()
  local e=env('worker',{'north','yes','no'}); local original=e.fs.files['/autobuilder/settings.lua']
  eq(require('autobuilder.setup_wizard').run({},e),false); eq(e.fs.files['/autobuilder/settings.lua'],original)
  eq(e.fs.exists('/autobuilder/data/worker.state'),false); eq(e.turtle.calls,0)
end)
test('failed setup promotion restores working settings',function()
  local e=env('controller',{'1','2','20 64 -9','yes'}); local original=e.fs.files['/autobuilder/settings.lua']
  e.fs.fault.move='/autobuilder/settings.lua'
  assert(not pcall(require('autobuilder.setup_wizard').run,{},e)); eq(e.fs.files['/autobuilder/settings.lua'],original)
  assert(e.fs.exists('/autobuilder/data/settings-before-setup.lua'))
  eq(e.fs.exists('/.autobuilder-install/transaction'),false)
end)
test('wizard refuses a controller with queued production and can cancel a missing supply chest',function()
  local e=env('controller',{})
  assert(CP.new(e.fs,e.textutils,'/autobuilder/data/controller.state'):save({schema=1,id=1,role='controller',boot=1,
    phase='telemetry',automation={jobs={},requests={r={status='pending'}}}}))
  assert(not pcall(require('autobuilder.setup_wizard').run,{},e))
  e=env('worker',{'cancel'}); e.turtle.inspect=function() return false end
  local original=e.fs.files['/autobuilder/settings.lua']
  eq(require('autobuilder.setup_wizard').run({},e),false); eq(e.fs.files['/autobuilder/settings.lua'],original)
end)
test('GPS failure asks for one coordinate line and validates heading',function()
  local e=env('worker',{'12 64 -9','bad','w','yes','yes'}); e.gps.locate=function() return nil end
  assert(require('autobuilder.setup_wizard').run({},e)); eq(settings(e).depot.heading,'west'); eq(e.turtle.calls,0)
end)
test('setup profile service only answers known workers on the configured controller',function()
  local e=env('controller',{}); local c=C.load({supply={inventory='stage'}})
  local Share=require('autobuilder.setup_share'); local message={version=1,type='setup_request',requestId='8:1000'}
  assert(not Share.reply(e,c,{},8,message)); eq(e.packet,nil)
  assert(Share.reply(e,c,{['8']={}},8,message)); eq(e.packet.message.supply.inventory,'stage'); eq(e.packet.to,8)
  local w=env('worker',{}); w.rednet.receive=function() return 99,{version=1,type='setup_profile',requestId='8:1000',supply={inventory='bad',side='front'}} end
  assert(not pcall(Share.fetch,w,C.load({role='worker',controllerId=1})))
end)
test('existing runtime fleet discovers setup profile and reconnects as a configured builder',function()
  local Setup=require('autobuilder.setup_wizard'); local Runtime=require('autobuilder.core.runtime')
  local ce=env('controller',{'1','2','20 64 -9','yes'}); assert(Setup.run({},ce))
  local controller=Runtime.new(C.load(settings(ce)),ce)
  local we=env('worker',{'east','yes','yes'}); local worker=Runtime.new(C.load(settings(we)),we)
  assert(worker:tick()); assert(controller:receive(8,we.packet.message,we.packet.protocol))
  we.rednet.receive=function(protocol)
    assert(controller:receive(8,we.packet.message,protocol))
    return 1,ce.packet.message,ce.packet.protocol
  end
  assert(Setup.run({},we))
  local restarted=Runtime.new(C.load(settings(we)),we); assert(restarted:tick())
  assert(controller:receive(8,we.packet.message,we.packet.protocol))
  local t=controller.state.workers['8'].telemetry
  eq(t.capabilities.building,true); eq(t.position.x,12); eq(t.position.heading,'east'); eq(we.turtle.calls,0)
end)
test('controller offers only unambiguous chest defaults and still requires saving',function()
  local e=env('controller',{'','','20 64 -9','yes'})
  assert(require('autobuilder.setup_wizard').run({},e))
  eq(settings(e).supply.inventory,'stage'); eq(settings(e).storageInventories[1],'stock')
  e=env('controller',{'','','20 64 -9',''})
  local original=e.fs.files['/autobuilder/settings.lua']
  eq(require('autobuilder.setup_wizard').run({},e),false)
  eq(e.fs.files['/autobuilder/settings.lua'],original)
end)
test('controller does not guess between two empty supply chests',function()
  local e=env('controller',{'','2','1 3','20 64 -9','yes'})
  e.peripheral.getNames=function() return {'right','stock','stage','extra'} end
  assert(require('autobuilder.setup_wizard').run({},e))
  eq(settings(e).supply.inventory,'stage'); eq(#settings(e).storageInventories,2)
end)
test('controller excludes crafting chests from suggested defaults',function()
  local e=env('controller',{'','','20 64 -9','yes'})
  e.fs.files['/autobuilder/settings.lua']='return {role="controller",craftingStation={input="craft"}}'
  e.peripheral.getNames=function() return {'right','stock','stage','craft'} end
  assert(require('autobuilder.setup_wizard').run({},e))
  eq(settings(e).supply.inventory,'stage'); eq(settings(e).storageInventories[1],'stock')
end)
test('wizard can detect a wireless modem attached after a failed check',function()
  local e=env('worker',{'retry','east','yes','yes'})
  local names=e.peripheral.getNames; local attached=false; local read=e.read
  e.peripheral.getNames=function() return attached and names() or {} end
  e.read=function() attached=true; return read() end
  assert(require('autobuilder.setup_wizard').run({},e)); eq(settings(e).depot.heading,'east'); eq(e.turtle.calls,0)
end)
test('controller retries discovery when its empty supply chest is not yet connected',function()
  local e=env('controller',{'retry','','','20 64 -9','yes'})
  local names=e.peripheral.getNames; local connected=false; local read=e.read
  e.peripheral.getNames=function() return connected and names() or {'right','stock'} end
  e.read=function() connected=true; return read() end
  assert(require('autobuilder.setup_wizard').run({},e)); eq(settings(e).supply.inventory,'stage')
end)
test('builder retries controller discovery without losing setup',function()
  local e=env('worker',{'retry','east','yes','yes'})
  local receive=e.rednet.receive; local online=false; local read=e.read
  e.rednet.receive=function(protocol) if online then return receive(protocol) end end
  e.read=function() online=true; return read() end
  assert(require('autobuilder.setup_wizard').run({},e)); eq(settings(e).supply.inventory,'stage')
end)
test('builder reads its current pose after retrying a missing depot chest',function()
  local e=env('worker',{'retry','east','yes','yes'})
  local ready=false; local read=e.read
  e.turtle.inspect=function() return ready,ready and {name='minecraft:chest'} or nil end
  e.gps.locate=function() assert(ready,'pose read before hardware was ready'); return 13,64,-9 end
  e.read=function() ready=true; return read() end
  assert(require('autobuilder.setup_wizard').run({},e)); eq(settings(e).depot.x,13); eq(e.turtle.calls,0)
end)
test('cancelling hardware retry leaves saved settings, pose and fuel unchanged',function()
  local e=env('worker',{'cancel'}); local original=e.fs.files['/autobuilder/settings.lua']; local fuel=e.turtle.fuel
  e.turtle.inspect=function() return false end
  e.turtle.refuel=function() error('setup must not consume fuel') end
  eq(require('autobuilder.setup_wizard').run({},e),false)
  eq(e.fs.files['/autobuilder/settings.lua'],original); eq(e.fs.exists('/autobuilder/data/worker.state'),false)
  eq(e.turtle.fuel,fuel); eq(e.turtle.calls,0)
end)
test('menu setup success tells the user it returns to the app',function()
  local e=env('worker',{'east','yes','yes'})
  assert(require('autobuilder.setup_wizard').run({},e,{returnToApp=true}))
  local output=table.concat(e.output,'\n'); assert(output:find('Returning to Autobuilder',1,true))
  assert(not output:find('Run reboot',1,true))
end)
test('saved builder setup loads only enough slot 15 fuel and restores selection',function()
  local e=env('worker',{'east','yes','yes'})
  assert(require('autobuilder.setup_wizard').run({},e))
  eq(e.turtle.fuel,1060); eq(e.turtle.items[15].count,4); eq(e.turtle.selected,3); eq(e.turtle.calls,0)
end)
test('saved builder setup consumes only enough coal blocks to reach its fuel target',function()
  for _,case in ipairs({{before=0,after=1600,left=2},{before=200,after=1000,left=3},{before=1000,after=1000,left=4}}) do
    local e=env('worker',{'east','yes','yes'}); e.turtle.fuel=case.before
    e.turtle.items[15]={name='minecraft:coal_block',count=4}
    e.turtle.items[1]={name='minecraft:oak_planks',count=16}
    e.turtle.items[16]={name='minecraft:coal_block',count=4}
    assert(require('autobuilder.setup_wizard').run({},e))
    eq(e.turtle.fuel,case.after); eq(e.turtle.items[15].count,case.left)
    eq(e.turtle.items[1].count,16); eq(e.turtle.items[16].count,4)
    eq(e.turtle.selected,3); eq(e.turtle.calls,0)
  end
end)
test('setup cancellation never consumes prepared coal',function()
  local e=env('worker',{'east','yes','no'})
  eq(require('autobuilder.setup_wizard').run({},e),false)
  eq(e.turtle.fuel,100); eq(e.turtle.items[15].count,16); eq(e.turtle.selected,3)
end)
test('builder setup does not burn unrelated items or consume fuel once sufficient',function()
  for _,fuel in ipairs({100,1500,'unlimited'}) do
    local e=env('worker',{'east','yes','yes'}); e.turtle.fuel=fuel
    e.turtle.items[15]={name='minecraft:oak_planks',count=16}
    e.turtle.refuel=function() error('should not burn this fuel') end
    assert(require('autobuilder.setup_wizard').run({},e))
    eq(e.turtle.items[15].count,16); eq(e.turtle.fuel,fuel); eq(e.turtle.selected,3)
  end
end)
test('refuel failure after saving preserves settings and restores selection',function()
  local e=env('worker',{'east','yes','yes'})
  e.turtle.refuel=function() error('fuel API unavailable') end
  assert(require('autobuilder.setup_wizard').run({},e))
  eq(settings(e).depot.heading,'east'); eq(e.turtle.selected,3); eq(e.turtle.calls,0)
end)

local function minerEnv(answers)
  local e=env('worker',answers)
  e.turtle.inspectDown=function() return true,{name='minecraft:chest'} end
  e.turtle.inspect=function() return false end
  return e
end

test('miner wizard creates resource-specialized adjacent mines for every heading without moving',function()
  local cases={
    {heading='north',entry={12,64,-10},min={12,64,-17},max={19,66,-10}},
    {heading='south',entry={12,64,-8},min={12,64,-8},max={19,66,-1}},
    {heading='east',entry={13,64,-9},min={13,64,-9},max={20,66,-2}},
    {heading='west',entry={11,64,-9},min={4,64,-9},max={11,66,-2}},
  }
  for _,case in ipairs(cases) do
    local e=minerEnv({case.heading,'','','yes','yes'})
    assert(require('autobuilder.setup_wizard').run({'miner','stone'},e))
    local c=C.load(settings(e)); eq(c.mining.enabled,true); eq(c.mining.resources[1],'minecraft:cobblestone')
    eq(c.automation.enabled,true); eq(c.automation.building,false); eq(c.label,'Keep me'); eq(c.minimumFuelReserve,123)
    eq(c.depot.x,12); eq(c.depot.y,64); eq(c.depot.z,-9); eq(c.depot.heading,case.heading)
    for i,axis in ipairs({'x','y','z'}) do eq(c.mining.entry[axis],case.entry[i]); eq(c.mining.bounds.min[axis],case.min[i]); eq(c.mining.bounds.max[axis],case.max[i]) end
    eq(e.turtle.calls,0); eq(e.turtle.selected,3); eq(e.turtle.fuel,1060)
    local output=table.concat(e.output,'\n'); assert(output:find('STOCK',1,true)); assert(output:find('different',1,true))
  end
end)

test('miner setup without GPS validates resource aliases and manual mine corners',function()
  local e=minerEnv({'12 64 -9','e','bad','sand, clay minecraft:diorite deepslate','13 64 -9','12 66 -2','16 66 -6','yes','yes'})
  e.gps.locate=function() return nil end
  assert(require('autobuilder.setup_wizard').run({'miner'},e))
  local c=C.load(settings(e)); eq(c.mining.resources[1],'minecraft:sand'); eq(c.mining.resources[2],'minecraft:clay_ball')
  eq(c.mining.resources[3],'minecraft:diorite'); eq(c.mining.resources[4],'minecraft:cobbled_deepslate')
  eq(c.mining.bounds.min.x,13); eq(c.mining.bounds.max.x,16); eq(c.mining.bounds.max.z,-6); eq(e.turtle.calls,0)
end)

test('miner setup cancellation leaves settings pose and fuel unchanged',function()
  for _,answers in ipairs({{'cancel'},{'east','cancel'},{'east','','','no'},{'east','','','yes','no'}}) do
    local e=minerEnv(answers); local original=e.fs.files['/autobuilder/settings.lua']
    eq(require('autobuilder.setup_wizard').run({'miner','coal'},e),false)
    eq(e.fs.files['/autobuilder/settings.lua'],original); eq(e.fs.exists('/autobuilder/data/worker.state'),false)
    eq(e.turtle.fuel,100); eq(e.turtle.items[15].count,16); eq(e.turtle.calls,0)
  end
end)

test('miner setup requires deposit chest below and refuses active reservations before prompting',function()
  local e=minerEnv({'cancel'}); e.turtle.inspectDown=function() return false end
  eq(require('autobuilder.setup_wizard').run({'miner','sand'},e),false); eq(e.turtle.calls,0)
  e=minerEnv({}); local original=e.fs.files['/autobuilder/settings.lua']
  assert(CP.new(e.fs,e.textutils,'/autobuilder/data/worker.state'):save({schema=1,id=8,role='worker',boot=1,phase='telemetry',position={known=false},motionReservation={jobId='mine:1'}}))
  assert(not pcall(require('autobuilder.setup_wizard').run,{'miner','sand'},e)); eq(e.fs.files['/autobuilder/settings.lua'],original)
end)

test('miner setup refuses protected entries and leaves fuel intact on failed settings promotion',function()
  local e=minerEnv({'east','','12 64 -8','','yes','yes'})
  e.fs.files['/autobuilder/settings.lua']='return {role="worker",controllerId=1,restrictedAreas={{min={x=13,y=64,z=-9},max={x=13,y=64,z=-9}}}}'
  local original=e.fs.files['/autobuilder/settings.lua']; e.fs.fault.move='/autobuilder/settings.lua'
  local ok,err=pcall(require('autobuilder.setup_wizard').run,{'miner','coal'},e)
  assert(not ok and tostring(err):find('previous settings restored',1,true),tostring(err))
  eq(e.fs.files['/autobuilder/settings.lua'],original); eq(e.turtle.fuel,100); eq(e.turtle.items[15].count,16); eq(e.turtle.calls,0)
end)
test('exploration wizard saves a bounded search area without changing completed work',function()
  local e=env('controller',{'0 64 0','','','','','','-4 60 -4','4 68 4','yes','yes'})
  assert(require('autobuilder.setup_wizard').run({'exploration'},e))
  local c=C.load(settings(e)); assert(c.exploration.enabled); eq(c.exploration.bounds.min.x,-64); eq(c.exploration.bounds.max.y,80)
  eq(c.exploration.baseProtection.min.x,-4)
end)
test('exploration miner setup records clear exit without fuel consumption or movement',function()
  local e=env('worker',{'east','15 64 -9','yes','yes'})
  e.turtle.inspectDown=function() return true,{name='minecraft:chest'} end
  assert(require('autobuilder.setup_wizard').run({'miner','explore'},e))
  local c=C.load(settings(e)); eq(c.mining.mode,'explore'); assert(c.capabilities.explorationV1)
  eq(#c.mining.exitRoute,3); eq(c.mining.exitRoute[3].x,15); eq(e.turtle.calls,0); eq(e.turtle.fuel,100)
end)
test('cancelled exploration wizard leaves existing settings unchanged',function()
  local e=env('controller',{'cancel'}); local original=e.fs.files['/autobuilder/settings.lua']
  eq(require('autobuilder.setup_wizard').run({'exploration'},e),false); eq(e.fs.files['/autobuilder/settings.lua'],original)
end)

test('fuel setup shares controller policy without supply staging and does not move or burn fuel',function()
  local Share=require('autobuilder.setup_share')
  local ce=env('controller',{}); local c=C.load({fuel={enabled=true,low=80,target=160}})
  assert(Share.reply(ce,c,{['8']={}},8,{version=1,type='setup_request',requestId='8:1000'}))
  eq(ce.packet.message.fuel.target,160)
  local we=env('worker',{'yes'})
  we.fs.files['/autobuilder/settings.lua']='return {role="worker",controllerId=1,depot={x=12,y=64,z=-9},label="Keep me"}'
  we.rednet.receive=function() return 1,ce.packet.message end
  local fuel=we.turtle.fuel
  assert(require('autobuilder.setup_wizard').run({'fuel'},we))
  eq(settings(we).fuel.target,160); eq(settings(we).fuel.enabled,true); eq(settings(we).label,'Keep me')
  eq(we.turtle.fuel,fuel); eq(we.turtle.calls,0)
end)

test('setup refuses a frozen fuel recipient even when its original task is idle',function()
  local e=env('worker',{})
  assert(CP.new(e.fs,e.textutils,'/autobuilder/data/worker.state'):save({schema=1,id=8,role='worker',boot=1,phase='telemetry',
    position={known=true,x=12,y=64,z=-9,heading='north'},fuelRecovery={phase='frozen'}}))
  local ok,why=pcall(require('autobuilder.setup_wizard').run,{'fuel'},e)
  assert(not ok and tostring(why):find('fuel recovery',1,true))
end)

test('fuel setup copies only validated profile fields and ignores cyclic unknown data',function()
  local e=env('worker',{}); local fuel=C.load({fuel={enabled=true}}).fuel; fuel.extra=fuel
  e.rednet.receive=function() return 1,{version=1,type='setup_profile',requestId=e.packet.message.requestId,fuel=fuel} end
  local profile=require('autobuilder.setup_share').fetch(e,C.load({role='worker',controllerId=1}))
  eq(profile.fuel.enabled,true); eq(profile.fuel.extra,nil)
end)

test('chunk setup shares only validated assurances and never turns workers into anchors',function()
  local Share=require('autobuilder.setup_share');local ce=env('controller',{})
  local cfg=C.load({chunkLoading={areas={{minX=-2,maxX=1,minZ=-1,maxZ=0}}}})
  assert(Share.reply(ce,cfg,{['8']={}},8,{version=1,type='setup_request',requestId='8:1000'}))
  local we=env('worker',{'yes'});we.rednet.receive=function() return 1,ce.packet.message end
  assert(require('autobuilder.setup_wizard').run({'chunks'},we))
  local c=C.load(settings(we));eq(c.chunkLoading.enabled,true);eq(c.chunkLoading.anchor,false);eq(c.chunkLoading.areas[1].minX,-2)
  eq(we.turtle.calls,0);eq(we.turtle.fuel,100)
  ce.packet.message.chunkLoading.anchor=true;ce.packet.message.chunkLoading.extra=ce.packet.message.chunkLoading
  local p=Share.fetch(we,c);eq(p.chunkLoading.anchor,false);eq(p.chunkLoading.extra,nil)
  ce.packet.message.chunkLoading.areas[1].maxX=-3;ce.packet.message.fuel=nil
  assert(not pcall(Share.fetch,we,c),'invalid loaded area copied')
end)

test('anchor setup requires actual chunky hardware and saves a stationary role without fuel use',function()
  local w=env('worker',{'yes'});local original=w.fs.files['/autobuilder/settings.lua']
  assert(not pcall(require('autobuilder.setup_wizard').run,{'anchor'},w));eq(w.fs.files['/autobuilder/settings.lua'],original)
  local old=w.peripheral.getType;w.peripheral.getType=function(side) return side=='left' and 'chunky' or old(side) end
  assert(require('autobuilder.setup_wizard').run({'anchor'},w));local c=C.load(settings(w))
  eq(c.chunkLoading.anchor,true);eq(c.initialPosition.x,12);eq(c.mining.enabled,false);eq(c.automation.building,false)
  eq(w.turtle.calls,0);eq(w.turtle.fuel,100)
end)

test('fleet profile application uses idle setup persistence without moving refueling or overwriting local paths',function()
 local e=env('worker',{});local p={role='worker',controllerId=1,initialPosition={x=12,y=64,z=-9,heading='east'},depot={x=12,y=64,z=-9},automation={building=true}}
 local W=require('autobuilder.setup_wizard');assert(W.applyFleet(e,p));local c=settings(e)
 eq(c.label,'Keep me');eq(c.minimumFuelReserve,123);eq(c.automation.building,true);eq(e.turtle.calls,0);eq(e.turtle.fuel,100)
 local store=CP.new(e.fs,e.textutils,'/autobuilder/data/worker.state');local state=store:load();eq(state.position.heading,'east')
 state.position.heading='west';assert(store:save(state));assert(W.applyFleet(e,p));eq(store:load().position.heading,'west')
 state=store:load();state.currentTask={id='owned'};assert(store:save(state));local original=e.fs.files['/autobuilder/settings.lua']
 eq(pcall(W.applyFleet,e,p),false);eq(e.fs.files['/autobuilder/settings.lua'],original);eq(store:load().currentTask.id,'owned')
end)

test('fleet partial profiles preserve nested local options and replace collections explicitly',function()
 local e=env('worker',{});local localSettings=settings(e)
 localSettings.supply={inventory='local:chest',side='down',batch=64};localSettings.gps={enabled=true,timeout=7,interval=42}
 localSettings.automation={building=true,courier=true};localSettings.storageInventories={'old:a','old:b'}
 localSettings.protectedBlocks={['minecraft:bedrock']=true,['minecraft:stone']=true}
 e.fs.files['/autobuilder/settings.lua']='return '..e.textutils.serialize(localSettings)
 assert(require('autobuilder.setup_wizard').applyFleet(e,{role='worker',controllerId=1,
  initialPosition={x=12,y=64,z=-9,heading='east'},depot={x=12,y=64,z=-9},
  supply={batch=16},gps={enabled=false},automation={building=false},storageInventories={'new:a'},protectedBlocks={}}))
 local c=settings(e);eq(c.supply.inventory,'local:chest');eq(c.supply.side,'down');eq(c.supply.batch,16)
 eq(c.gps.enabled,false);eq(c.gps.timeout,7);eq(c.gps.interval,42);eq(c.automation.building,false);eq(c.automation.courier,true)
 eq(#c.storageInventories,1);eq(c.storageInventories[1],'new:a');eq(next(c.protectedBlocks),nil)
end)
