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
  if role=='worker' then e.turtle=S.turtle(); e.turtle.inspect=function() return true,{name='minecraft:chest'} end end
  return e
end
local function settings(e) return assert(load(e.fs.files['/autobuilder/settings.lua'],'settings','t',{}))() end
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
test('wizard refuses a controller with queued production and a builder without a supply chest',function()
  local e=env('controller',{})
  assert(CP.new(e.fs,e.textutils,'/autobuilder/data/controller.state'):save({schema=1,id=1,role='controller',boot=1,
    phase='telemetry',automation={jobs={},requests={r={status='pending'}}}}))
  assert(not pcall(require('autobuilder.setup_wizard').run,{},e))
  e=env('worker',{'north','yes'}); e.turtle.inspect=function() return false end
  local original=e.fs.files['/autobuilder/settings.lua']
  assert(not pcall(require('autobuilder.setup_wizard').run,{},e)); eq(e.fs.files['/autobuilder/settings.lua'],original)
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
