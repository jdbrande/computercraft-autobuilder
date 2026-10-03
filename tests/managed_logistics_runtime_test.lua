local U=require('autobuilder.core.util')
local F=require('autobuilder.factory.factory')
local S=require('tests.support')
local Runtime=require('autobuilder.core.runtime')
local function fixture()
  local f=require('tests.managed_logistics_support').new();f.envs={};f.apps={};f.worlds={};f.maxActive=0
  local inventories={['2,0,0']='a',['4,0,0']='b',['22,0,0']='c',['24,0,0']='d'}
  local function env(id)
    local e={fs=S.fs(),textutils=S.codec(),now=100,packets={}}
    e.os={getComputerID=function() return id end,epoch=function() return e.now*1000 end}
    e.rednet={isOpen=function() return true end,open=function() end,send=function(to,m,p)
      e.packets[#e.packets+1]={to=to,m=U.copy(m),protocol=p};return true
    end}
    e.peripheral={getNames=function() return {'right'} end,getType=function(n) return n=='right' and 'modem' or nil end,
      call=function(n,method,...) if n=='right' and method=='isWireless' then return true end;return f.e.peripheral.call(n,method,...) end}
    f.envs[id]=e;return e
  end
  f.apps[7]=Runtime.new(f.config,env(7));f.configs={[7]=f.config}
  for id=12,13 do
    local w=require('tests.build_world').new();f.worlds[id]=w
    w.pose.x=(id-11)*2;w.pose.y=1;w.pose.z=2;w.fuel=2000
    local t=w.turtle;t.getFuelLevel=function() return w.fuel end;t.getFuelLimit=function() return 20000 end
    for _,action in ipairs({'forward','up','down'}) do local move=t[action];t[action]=function()
      if w.fuel==0 then return false,'out of fuel' end
      local ok,why=move();if ok then w.fuel=w.fuel-1 end;return ok,why
    end end
    for key in pairs(inventories) do w.blocks[key]={name='minecraft:chest',state={}} end
    local function below() return f.inventories[inventories[w.pose.x..','..(w.pose.y-1)..','..w.pose.z]] end
    t.getItemSpace=function(slot) return 64-t.getItemCount(slot) end
    t.suckDown=function(n)
      local inv=below();if not inv then return false end
      local slot,item=next(inv);if not item then return false end
      local held=w.items[w.selected];if held and held.name~=item.name then return false end
      local moved=math.min(n,item.count,64-(held and held.count or 0))
      w.items[w.selected]=held or {name=item.name,count=0};w.items[w.selected].count=w.items[w.selected].count+moved
      item.count=item.count-moved;if item.count==0 then inv[slot]=nil end;return moved>0
    end
    t.dropDown=function(n)
      if f.rejectDrop then return false end
      local inv=below();local item=w.items[w.selected];if not inv or not item then return false end
      if inv[1] and inv[1].name~=item.name then return false end
      local moved=math.min(n,item.count,64-(inv[1] and inv[1].count or 0))
      inv[1]=inv[1] or {name=item.name,count=0};inv[1].count=inv[1].count+moved
      item.count=item.count-moved;if item.count==0 then w.items[w.selected]=nil end;return moved>0
    end
    local c=require('tests.loaded_config').load({role='worker',controllerId=7,gps={enabled=false},minimumFuelReserve=10,
      depot=U.copy(w.pose),initialPosition=U.copy(w.pose),automation={courier=true}})
    f.configs[id]=c;local e=env(id);e.turtle=t;f.apps[id]=Runtime.new(c,e)
  end
  function f:reboot(id) self.envs[id].packets={};self.apps[id]=Runtime.new(self.configs[id],self.envs[id]) end
  function f:pump()
    for _,id in ipairs({12,13,7}) do
      local e=self.envs[id];local packets=e.packets;e.packets={}
      for _,p in ipairs(packets) do
        if p.m.type=='task_ack' and self.loseAck then self.loseAck=false
        else self.apps[p.to]:receive(p.m.sender,p.m,p.protocol) end
      end
    end
  end
  function f:cycle()
    self.now=self.now+1;for _,e in pairs(self.envs) do e.now=self.now end
    for _,id in ipairs({12,13}) do self.apps[id]:tick() end;self:pump()
    self.apps[7]:tick();self:pump();self.apps[7]:workStep()
    for _,id in ipairs({12,13}) do self.apps[id]:workStep() end;self:pump()
    local active=0;for _,j in pairs(self.apps[7].state.automation.jobs) do if j.logistics and j.workerId and j.status~='completed' then active=active+1 end end
    self.maxActive=math.max(self.maxActive,active)
  end
  return f
end

test('real controller and two courier runtimes conserve finite stock through reboots lost ack and full destination recovery',function()
  local f=fixture();local r=f.apps[7].automation.production.logistics:request('minecraft:stone',24,'base','site','runtime')
  local restarted,blocked=false,false;f.rejectDrop=true;f.loseAck=true
  for _=1,1800 do
    f:cycle()
    local t=f.apps[12].state.currentTask
    if not restarted and t and t.cargo and t.cargo.held>0 then f:reboot(7);f:reboot(12);restarted=true end
    for _,id in ipairs({12,13}) do
      local task=f.apps[id].state.currentTask
      if task and task.phase=='blocked' and task.error=='destination container full or unavailable' then
        blocked=true;f.rejectDrop=false
      end
    end
    r=f.apps[7].state.automation.hauls[r.id]
    if r.status=='completed' and not f.apps[12].state.currentTask and not f.apps[13].state.currentTask then break end
  end
  assert(restarted and blocked);eq(r.status,'completed');assert(f.maxActive>=2,'no concurrent couriers')
  eq(F.count(f.inventories.site,'minecraft:stone'),24);eq(F.count(f.inventories.base,'minecraft:stone'),0)
  eq(F.count(f.inventories.base,'minecraft:dirt'),7)
  for _,id in ipairs({12,13}) do assert(not next(f.worlds[id].items));assert(f.worlds[id].fuel<2000 and f.worlds[id].fuel>0) end
  for _,lease in pairs(f.apps[7].state.capacityLedger.leases) do eq(lease.status,'released') end
  for _,lease in pairs(f.apps[7].state.chunkLedger.leases) do eq(lease.status,'released') end
end)

test('operator haul and logistics commands expose managed node progress',function()
  local f=fixture();local app=f.apps[7]
  local ok,why=app:command('haul minecraft:stone 8 base site');assert(ok,why)
  eq(app.state.automation.hauls['haul:1'].quantity,8)
  assert(app:command('logistics'));eq(app.state.view,'logistics');assert(app.state.logisticsLines[1]:find('nodes=2',1,true))
end)

test('native runtime home return settles mixed cargo after drop and collection reboots before acknowledgement',function()
  local f=fixture();local w=f.worlds[12];local t=w.turtle
  w.items={[1]={name='minecraft:stone',count=5},[2]={name='minecraft:dirt',count=3},[15]={name='minecraft:coal',count=2}}
  f.configs[12].depot={x=2,y=1,z=0};f:reboot(12)
  local cutDrop=true;local dropped=0
  t.dropDown=function(n)
    assert(w.pose.x==2 and w.pose.y==1 and w.pose.z==0,'return dropped outside depot')
    local v=w.items[w.selected];local inv=f.inventories.a;local slot
    for i=1,3 do if not inv[i] or inv[i].name==v.name and inv[i].count<64 then slot=i;break end end
    if not slot then return false end
    local moved=math.min(n,v.count,64-(inv[slot] and inv[slot].count or 0));local name=v.name
    inv[slot]=inv[slot] or {name=name,count=0};inv[slot].count=inv[slot].count+moved;v.count=v.count-moved
    if v.count==0 then w.items[w.selected]=nil end;dropped=dropped+moved
    if cutDrop then cutDrop=false;error('power loss after home drop') end;return true
  end
  f:cycle();local ok,id=f.apps[7]:command('worker return 12');assert(ok,id)
  local rebooted,collection=false,false;f.loseAck=true;f.partial=2
  for _=1,600 do
    f:cycle();local task=f.apps[12].state.currentTask
    if not rebooted and task and task.homeCargo and task.homeCargo.intent then
      f:reboot(12);f:reboot(7);rebooted=true;f.crashTransfer=true
    end
    if f.crashed and not collection then f:reboot(7);collection=true end
    local r=f.apps[7].state.automation.returns[id]
    if r.status=='completed' and not f.apps[12].state.currentTask then break end
  end
  local r=f.apps[7].state.automation.returns[id];eq(r.status,'completed');assert(rebooted and collection)
  eq(dropped,8);eq(F.count(f.inventories.base,'minecraft:stone'),29);eq(F.count(f.inventories.base,'minecraft:dirt'),10)
  eq(next(f.inventories.a),nil);eq(w.items[1],nil);eq(w.items[2],nil);eq(w.items[15].count,2)
  eq(w.pose.x,2);eq(w.pose.y,1);eq(w.pose.z,0);assert(w.fuel<2000 and w.fuel>0)
  local j=f.apps[7].state.automation.jobs[r.jobId];eq(j.status,'completed')
  eq(f.apps[7].state.capacityLedger.leases[j.id].status,'released');eq(f.apps[7].state.inventoryLedger.leases[j.id].status,'released')
  local receipt=f.apps[12].state.completedTasks[j.id];eq(receipt.homeReceipt.deposited['minecraft:stone'],5)
end)

test('project completion waits for native worker home return cargo collection and fresh acknowledgement',function()
  local f=fixture();local C=require('tests.loaded_config')
  f.configs[7].build.enabled=true;f.configs[7].build.origin={x=6,y=0,z=5};f.configs[7]=C.load(f.configs[7]);f:reboot(7)
  f.configs[12].automation.building=true;f.configs[12].depot={x=2,y=1,z=0};f.configs[12]=C.load(f.configs[12]);f:reboot(12)
  f.worlds[12].items[1]={name='minecraft:stone',count=4}
  local bp={schema=1,size={x=2,y=1,z=1},palette={{name='minecraft:stone',state={}}},runs={{id=1,count=2}},metadata={},requirements={['minecraft:stone']=2}}
  f.envs[7].textutils.unserializeJSON=f.envs[7].textutils.unserialize
  f.envs[7].fs.files['/settlement.json']=f.envs[7].textutils.serialize(bp)
  local app=f.apps[7];assert(app:command('build import /settlement.json settlement'));assert(app:command('build auto settlement'))
  local settling=false;local rebooted=false;f.rejectDrop=true
  for _=1,600 do
    f:cycle();local p=f.apps[7].state.automation.projects.settlement
    if p.phase=='settling' then settling=true end
    if settling and not rebooted then f:reboot(7);f:reboot(12);rebooted=true end
    local t=f.apps[12].state.currentTask
    if t and t.returning and t.homeRetryable then
      eq(p.phase,'settling');eq(F.count(f.inventories.base,'minecraft:stone'),24);f.rejectDrop=false;f.loseAck=true
    end
    if p.phase=='built' then
      assert(settling,'project declared built before worker settlement');assert(not f.apps[12].state.currentTask)
      break
    end
  end
  local p=f.apps[7].state.automation.projects.settlement;eq(p.phase,'built');assert(rebooted)
  eq(f.worlds[12].pose.x,2);eq(f.worlds[12].pose.z,0);eq(f.worlds[12].items[1],nil)
  eq(F.count(f.inventories.base,'minecraft:stone'),26);eq(next(f.inventories.a),nil);eq(p.report.counts.correct,2)
end)

test('site survey real runtimes retain observed columns through both reboots and lost acknowledgement',function()
  local f=fixture();local C=require('tests.loaded_config')
  f.configs[12].automation.building=true;f.configs[12]=C.load(f.configs[12]);f:reboot(12)
  local w=f.worlds[12];w.blocks['8,0,4']={name='minecraft:dirt',state={}}
  local job=f.apps[7].automation.queue:submit('SURVEY_SITE',{clearanceY=4,bounds={min={x=8,y=0,z=4},max={x=9,y=4,z=4}},
    siteSurvey={identity=string.rep('a',64),region=1,columns={{x=8,z=4,minY=0,clearanceY=4,foundationY=0},{x=9,z=4,minY=0,clearanceY=4,foundationY=0}}}}, {})
  local id=job.id;local rebooted=false;f.loseAck=true
  for _=1,400 do
    f:cycle();local t=f.apps[12].state.currentTask
    if not rebooted and t and t.progress==1 then f:reboot(7);f:reboot(12);rebooted=true end
    job=f.apps[7].state.automation.jobs[id]
    if job.status=='completed' and not f.apps[12].state.currentTask then break end
  end
  assert(rebooted);eq(job.status,'completed');eq(job.progress,2)
  eq(job.siteReport.observations[1].name,'minecraft:dirt');eq(job.siteReport.observations[2].status,'empty')
  eq(w.digs,0);eq(w.places,0);assert(w.fuel<2000 and w.fuel>0)
  eq(#f.apps[12].state.completedTasks[id].siteReport.observations,2)
end)
