local U=require('autobuilder.core.util')
local F=require('autobuilder.factory.factory')
local Runtime=require('autobuilder.core.runtime')
local function fixture(options)
  options=options or {};local width=options.width or 10;local lastWorker=11+(options.workers or 2)
  local f=require('tests.managed_logistics_support').new()
  f.workerIds={};for id=12,lastWorker do f.workerIds[#f.workerIds+1]=id end
  f.envs={};f.apps={};f.worlds={};f.configs={};f.blocks={};f.owners={};f.active={};f.grants={};f.moves={};f.denials={};f.holds={}
  f.inventories={stock={[1]={name='minecraft:stone',count=width+2}},home12={},home13={},supply12={},supply13={}}
  local homes={}
  for id=12,lastWorker do
    homes[id]=U.copy((options.homes or {})[id] or {x=(id-12)*18,y=2,z=-4,heading='north'})
    f.inventories['home'..id]={};f.inventories['supply'..id]={}
  end
  local buffers,stations={},{}
  for id=12,lastWorker do
    buffers[#buffers+1]={inventory='home'..id,position=U.copy(homes[id])}
    stations[#stations+1]={workerId=id,inventory='supply'..id,position=U.copy(homes[id]),side='front'}
    local h=homes[id];f.blocks[h.x..','..(h.y-1)..','..h.z]={name='minecraft:chest',state={}}
    f.blocks[h.x..','..h.y..','..(h.z-1)]={name='minecraft:chest',state={}}
  end
  for x=3,width+4 do for z=-1,1 do f.blocks[x..',-1,'..z]={name='minecraft:stone',state={}} end end
  for _,x in ipairs({4,width+3}) do
    f.blocks[x..',0,0']={name='minecraft:dirt',state={}}
    f.blocks[x..',-1,0']=nil;f.blocks[x..',-2,0']={name='minecraft:stone',state={}}
  end
  local function env(id)
    local codec=require('tests.support').codec();codec.serializeJSON=codec.serialize;codec.unserializeJSON=codec.unserialize
    local e={fs=require('tests.install_support').fs(),textutils=codec,now=100,packets={}}
    e.os={getComputerID=function() return id end,epoch=function() return e.now*1000 end}
    e.rednet={isOpen=function() return true end,open=function() end,send=function(to,m,p)
      e.packets[#e.packets+1]={to=to,m=U.copy(m),protocol=p};return true
    end}
    e.peripheral={getNames=function() return {'right'} end,getType=function(n) return n=='right' and 'modem' or nil end,
      call=function(n,method,...) if n=='right' and method=='isWireless' then return true end;return f.e.peripheral.call(n,method,...) end}
    f.envs[id]=e;return e
  end
  local C=require('tests.loaded_config')
  local controllerSettings={storageInventories={'stock'},turtleFuelReserveItems={},supplyStations=stations,
    supply={inventory='',batch=2},logistics={nodes={{id='base',inventory='stock',position={x=-4,y=1,z=-4},buffers=buffers}}},
    build={enabled=true,origin={x=4,y=0,z=0},regionSize=2},
    scaling={roles={building={min=options.scaling and 0 or 2},clearing={min=options.scaling and 0 or 2}}}}
  if options.configure then options.configure(f,controllerSettings,homes) end
  f.configs[7]=C.load(controllerSettings)
  f.apps[7]=Runtime.new(f.configs[7],env(7))
  for id=12,lastWorker do
    local w=require('tests.build_world').new();f.worlds[id]=w;w.blocks=f.blocks
    w.pose=U.copy((options.starts or {})[id] or homes[id]);w.pose.known=true;w.fuel=8000
    local t=w.turtle;t.getFuelLevel=function() return w.fuel end;t.getFuelLimit=function() return 20000 end
    for _,action in ipairs({'forward','up','down'}) do local move=t[action];t[action]=function()
      if w.fuel==0 then return false,'out of fuel' end
      local from=options.traffic and U.copy(w.pose);local ok,why=move()
      if ok then
        if options.traffic then
          local task=assert(f.apps[id].state.currentTask);local key=require('autobuilder.core.pathfinding').key(w.pose)
          local cell=assert(f.apps[7].state.automation.cells[key],'physical move without a controller reservation')
          eq(cell.owner,id);eq(cell.jobId,task.id);f.moves[#f.moves+1]={worker=id,kind=task.type,from=from,to=U.copy(w.pose)}
        end
        for other,ow in pairs(f.worlds) do if other~=id then assert(U.distance(ow.pose,w.pose)>0,'physical turtle collision') end end
        w.fuel=w.fuel-1
      end
      return ok,why
    end end
    t.getItemSpace=function(slot) return 64-t.getItemCount(slot) end
    t.getSelectedSlot=function() return w.selected end
    local function transfer(from,to,slot,n,target)
      local item=from[slot];if not item then return false end
      for s=target or 1,target or 3 do
        if not to[s] or to[s].name==item.name and to[s].count<64 then
          local amount=math.min(n,item.count,64-(to[s] and to[s].count or 0))
          to[s]=to[s] or {name=item.name,count=0};to[s].count=to[s].count+amount
          item.count=item.count-amount;if item.count==0 then from[slot]=nil end;return amount>0
        end
      end
      return false
    end
    local function underfoot()
      local name=(f.containers or {})[require('autobuilder.core.pathfinding').key(w.pose)]
      if name then return f.inventories[name] end
      assert(U.distance(w.pose,homes[id])==0,'cargo transferred outside a physical endpoint')
      return f.inventories['home'..id]
    end
    t.dropDown=function(n) return transfer(w.items,underfoot(),w.selected,n or t.getItemCount(w.selected)) end
    t.suckDown=function(n)
      local inv=underfoot();local slot=next(inv);if not slot then return false end
      return transfer(inv,w.items,slot,n or 64,w.selected)
    end
    t.suck=function(n)
      assert(U.distance(w.pose,homes[id])==0 and w.pose.heading=='north','supply pulled outside private endpoint')
      local inv=f.inventories['supply'..id];local slot=next(inv);if not slot then return false end
      local moved=transfer(inv,w.items,slot,n,w.selected)
      if moved and f.crashPull then f.crashPull=nil;f.crashed=id;error('power lost after registered supply pull') end
      return moved
    end
    local settings={role='worker',controllerId=7,automation={building=true},minimumFuelReserve=10,
      depot=U.copy(homes[id]),initialPosition=U.copy(w.pose),supply={inventory='supply'..id,side='front'}}
    for key,value in pairs((options.workerSettings or {})[id] or {}) do settings[key]=U.copy(value) end
    f.configs[id]=C.load(settings)
    local e=env(id);e.turtle=t;f.apps[id]=Runtime.new(f.configs[id],e)
  end
  local ce=f.envs[7]
  ce.fs.files['/fleet.json']=ce.textutils.serialize({schema=1,size={x=width,y=1,z=1},palette={{name='minecraft:stone',state={}}},
    runs={{id=1,count=width}},metadata={},requirements={['minecraft:stone']=width}})
  f.enabled={};for _,id in ipairs(f.workerIds) do f.enabled[id]=id==12 or not options.joinLater end;f.buildOverlapExercised=options.scaling or nil
  function f:reboot(id) self.envs[id].packets={};self.apps[id]=Runtime.new(self.configs[id],self.envs[id]) end
  function f:pump()
    local order=U.copy(self.workerIds);order[#order+1]=7
    for _,id in ipairs(order) do
      local e=self.envs[id];local packets=e.packets;e.packets={}
      for _,p in ipairs(packets) do
        if options.traffic and (not self.enabled[id] and id~=7 or not self.enabled[p.to] and p.to~=7) then
          -- An offline computer cannot receive or transmit queued packets.
        elseif p.m.type=='task_supply' then
          eq(p.m.payload.station.inventory,'supply'..p.to);self.grants[p.to]=true
          if self.loseGrant then self.loseGrant=nil else self.apps[p.to]:receive(p.m.sender,p.m,p.protocol) end
        else
          if options.traffic and p.m.type=='task_grant' and not p.m.payload.granted then self.denials[#self.denials+1]=U.copy(p.m.payload) end
          self.apps[p.to]:receive(p.m.sender,p.m,p.protocol)
        end
      end
    end
  end
  function f:cycle()
    self.now=self.now+1;for _,e in pairs(self.envs) do e.now=self.now end
    for _,id in ipairs(self.workerIds) do if self.enabled[id] then self.apps[id]:tick() end end;self:pump()
    self.apps[7]:tick();self:pump();self.apps[7]:workStep()
    -- A two-block batch can finish before another region becomes ready. Model
    -- one slow departure after supply settles at its private home, so overlap
    -- admission is deterministic without obstructing the preparation workspace
    -- or retaining the shared supply lease.
    local held,builders=self.heldBuilder,0
    if not self.buildOverlapExercised then
      for _,id in ipairs(self.workerIds) do
        local task=self.apps[id].state.currentTask
        if task and task.type=='BUILD' then
          builders=builders+1
          if not held and U.distance(self.worlds[id].pose,homes[id])==0 and not task.supplyRequest
            and not self.apps[7].state.automation.supply and F.count(self.worlds[id].items,'minecraft:stone')>0 then held=id end
        end
      end
      if builders==2 then self.buildOverlapExercised=true;held=nil end
    end
    self.heldBuilder=held
    for _,id in ipairs(self.workerIds) do if self.enabled[id] and id~=held and not self.holds[id] then self.apps[id]:workStep() end end;self:pump()
    local active={}
    for _,j in pairs(self.apps[7].state.automation.jobs) do
      if j.workerId then self.owners[j.type]=self.owners[j.type] or {};self.owners[j.type][j.workerId]=true end
      if j.workerId and j.status~='completed' then active[j.type]=(active[j.type] or 0)+1 end
    end
    for kind,n in pairs(active) do self.active[kind]=math.max(self.active[kind] or 0,n) end
  end
  return f
end

test('two construction workers prepare and build through private supplies with lost grants and a physical pull reboot',function()
  local f=fixture();f.crashPull=true;f.loseGrant=true
  assert(f.apps[7]:command('build import /fleet.json fleet'));assert(f.apps[7]:command('build auto fleet'))
  local restarted=false
  for _=1,6500 do
    f:cycle()
    if f.crashed and not restarted then f:reboot(f.crashed);f:reboot(7);restarted=true end
    if f.apps[7].state.automation.projects.fleet.phase=='built' then break end
  end
  local p=f.apps[7].state.automation.projects.fleet
  assert(p.phase=='built',f.envs[7].textutils.serialize({project=p,workers={f.apps[12].state.currentTask,f.apps[13].state.currentTask},jobs=f.apps[7].state.automation.jobs}))
  assert(restarted);assert(f.buildOverlapExercised,'second builder was never admitted beside a slow first builder');eq(p.report.counts.correct,10)
  for _,kind in ipairs({'SURVEY_SITE','PREPARE_REGION','BUILD'}) do
    assert(f.owners[kind][12] and f.owners[kind][13],'both workers did not participate in '..kind)
  end
  assert(f.active.PREPARE_REGION>=2,'preparation did not overlap');assert(f.active.BUILD>=2,'construction did not overlap')
  for x=4,13 do eq(f.blocks[x..',0,0'].name,'minecraft:stone');eq(f.blocks[x..',-1,0'].name,'minecraft:stone') end
  eq(F.count(f.inventories.stock,'minecraft:dirt'),2);eq(F.count(f.inventories.stock,'minecraft:stone'),0)
  eq(f.apps[7].state.automation.supply,nil)
  for id=12,13 do
    assert(f.grants[id]);assert(not f.apps[id].state.currentTask);assert(not next(f.worlds[id].items))
    assert(not next(f.inventories['home'..id]));assert(not next(f.inventories['supply'..id]))
    assert(f.worlds[id].fuel>0 and f.worlds[id].fuel<8000)
  end
end)


test('late registered construction workers automatically ramp preparation and building then drain to idle',function()
  local f=fixture({width=48,workers=4,scaling=true,joinLater=true})
  assert(f.apps[7]:command('build import /fleet.json growing'));assert(f.apps[7]:command('build auto growing'))
  local joined,restarted=false,false
  for i=1,16000 do
    f:cycle()
    if not joined and f.apps[12].state.currentTask and f.apps[12].state.currentTask.type=='SURVEY_SITE' then
      assert(not f.apps[7].state.workers['13']);for _,id in ipairs(f.workerIds) do f.enabled[id]=true end;joined=true
    end
    if not restarted and (f.active.PREPARE_REGION or 0)>=2 then f:reboot(7);restarted=true end
    if f.apps[7].state.automation.projects.growing.phase=='built' then break end
  end
  local c=f.apps[7];local p=c.state.automation.projects.growing
  assert(p.phase=='built',f.envs[7].textutils.serialize({project=p,workers={f.apps[12].state.currentTask,f.apps[13].state.currentTask},jobs=c.state.automation.jobs}))
  assert(joined and restarted);eq(p.report.counts.correct,48)
  assert(f.active.PREPARE_REGION>=2,'heavy preparation did not scale');assert(f.active.BUILD>=2,'heavy construction did not scale')
  for _,kind in ipairs({'PREPARE_REGION','BUILD'}) do
    local count=0;for _ in pairs(f.owners[kind] or {}) do count=count+1 end;assert(count>=2,kind..' did not use additional workers')
  end
  for x=4,51 do eq(f.blocks[x..',0,0'].name,'minecraft:stone');eq(f.blocks[x..',-1,0'].name,'minecraft:stone') end
  for _=1,10 do f:cycle() end
  local view=require('autobuilder.core.scaling').snapshot(c.state,c.config,f.inventories.stock,f.now)
  eq(view.clearing.active,0);eq(view.clearing.desired,0);eq(view.building.active,0);eq(view.building.desired,0)
  eq(c.state.automation.supply,nil)
  for _,id in ipairs(f.workerIds) do
    assert(not f.apps[id].state.currentTask and not next(f.worlds[id].items));assert(f.worlds[id].fuel>0)
    assert(not next(f.inventories['home'..id]) and not next(f.inventories['supply'..id]))
  end
end)


test('an idle construction worker vacates a verifier destination through a managed home return',function()
  local f=fixture({width=1,scaling=true});local blocker=f.worlds[13]
  for axis,value in pairs({x=4,y=1,z=0}) do blocker.pose[axis]=value;f.apps[13].state.position[axis]=value end
  f.blocks['4,0,0']={name='minecraft:stone',state={}}
  local j=f.apps[7].automation.queue:submit('VERIFY',{preferredWorker=12,clearanceY=2,
    blocks={{x=4,y=0,z=0,name='minecraft:stone',state={}}}},{})
  for _=1,500 do
    f:cycle()
    if j.status=='completed' and not f.apps[12].state.currentTask and not f.apps[13].state.currentTask
      and U.distance(blocker.pose,f.configs[13].depot)==0 then break end
  end
  eq(j.status,'completed');eq(j.report.counts.correct,1)
  eq(U.distance(blocker.pose,f.configs[13].depot),0);assert(not f.apps[13].state.currentTask)
  local returns=0;for _,r in pairs(f.apps[7].state.automation.returns) do returns=returns+1;eq(r.owner,13) end
  eq(returns,1);eq(f.blocks['4,0,0'].name,'minecraft:stone')
end)


test('construction travel detours another active preparation region without entering or changing it',function()
  local f=fixture({width=1,scaling=true});local q=f.apps[7].automation.queue
  f.blocks['4,0,0']={name='minecraft:stone',state={}}
  q.state.jobs.other={id='other',type='SURVEY_SITE',siteSurvey={columns={}},status='running',workerId=99,
    bounds={min={x=2,y=1,z=-4},max={x=2,y=2,z=-4}},clearanceY=3}
  local j=q:submit('VERIFY',{preferredWorker=12,clearanceY=2,
    blocks={{x=4,y=0,z=0,name='minecraft:stone',state={}}}},{})
  local denied=false
  for _=1,400 do
    f:cycle()
    local r=f.apps[12].state.motionReservation
    if r and r.reason and r.reason:find('active preparation region owned by ',1,true)==1 then denied=true end
    assert(not require('autobuilder.core.pathfinding').inside(f.worlds[12].pose,q.state.jobs.other.bounds))
    if j.status=='completed' then break end
  end
  assert(denied,'fixture did not encounter the protected region');eq(j.status,'completed')
  eq(j.report.counts.correct,1);eq(q.state.jobs.other.workerId,99);eq(q.state.jobs.other.status,'running')
  eq(f.blocks['4,0,0'].name,'minecraft:stone')
end)


test('opposing construction workers pass one another without synchronized detour deadlock',function()
  local f=fixture({width=20,scaling=true});assert(f.apps[7]:command('fleet limit building 2 4'))
  for id,x in pairs({[12]=10,[13]=11}) do
    for axis,value in pairs({x=x,y=2,z=0}) do f.worlds[id].pose[axis]=value;f.apps[id].state.position[axis]=value end
  end
  for x=0,20 do f.blocks[x..',0,2']={name='minecraft:stone',state={}} end
  local q=f.apps[7].automation.queue;local jobs={}
  for id,x in pairs({[12]=20,[13]=0}) do jobs[#jobs+1]=q:submit('VERIFY',{preferredWorker=id,clearanceY=2,
    blocks={{x=x,y=0,z=2,name='minecraft:stone',state={}}}},{}) end
  f.heldBuilder=12
  for _=1,30 do f:cycle();if jobs[1].workerId and jobs[2].workerId then break end end
  f.heldBuilder=nil
  for _=1,800 do f:cycle();if jobs[1].status=='completed' and jobs[2].status=='completed' then break end end
  assert((f.active.VERIFY or 0)>=2,'fixture did not run opposing workers concurrently')
  for _,j in ipairs(jobs) do eq(j.status,'completed');eq(j.report.counts.correct,1) end
  for x=0,20 do eq(f.blocks[x..',0,2'].name,'minecraft:stone') end
end)

test('opposing construction detours recover physical station obstructions without digging',function()
  local f=fixture({width=20,scaling=true});assert(f.apps[7]:command('fleet limit building 2 4'))
  for id,x in pairs({[12]=10,[13]=11}) do
    for axis,value in pairs({x=x,y=2,z=0}) do f.worlds[id].pose[axis]=value;f.apps[id].state.position[axis]=value end
  end
  for x=0,20 do f.blocks[x..',0,2']={name='minecraft:stone',state={}} end
  f.blocks['10,2,1']={name='minecraft:chest',state={}};f.blocks['11,2,-1']={name='minecraft:chest',state={}}
  local q=f.apps[7].automation.queue;local jobs={}
  for id,x in pairs({[12]=20,[13]=0}) do jobs[#jobs+1]=q:submit('VERIFY',{preferredWorker=id,clearanceY=2,
    blocks={{x=x,y=0,z=2,name='minecraft:stone',state={}}}},{}) end
  f.heldBuilder=12
  for _=1,30 do f:cycle();if jobs[1].workerId and jobs[2].workerId then break end end
  f.heldBuilder=nil
  for _=1,800 do f:cycle();if jobs[1].status=='completed' and jobs[2].status=='completed' then break end end
  assert((f.active.VERIFY or 0)>=2,'fixture did not run opposing workers concurrently')
  for _,j in ipairs(jobs) do eq(j.status,'completed');eq(j.report.counts.correct,1) end
  for x=0,20 do eq(f.blocks[x..',0,2'].name,'minecraft:stone') end
  eq(f.blocks['10,2,1'].name,'minecraft:chest');eq(f.blocks['11,2,-1'].name,'minecraft:chest')
end)

test('concurrent project priorities survive handover reboot and exact shared-stock construction',function()
 local f=fixture({width=2,workers=1,scaling=true});f.inventories.stock={[1]={name='minecraft:stone',count=4}}
 for _,z0 in ipairs({0,8}) do for x=3,6 do for z=z0-1,z0+1 do
  f.blocks[x..',-1,'..z]={name='minecraft:stone',state={}};f.blocks[x..',0,'..z]=nil
 end end end
 local c=f.apps[7];assert(c:command('build import /fleet.json alpha'))
 f.configs[7].build.origin.z=8;assert(c:command('build import /fleet.json beta'))
 assert(c:command('build priority alpha 20'));assert(c:command('build priority beta 80'))
 assert(c:command('build auto alpha'));assert(c:command('build auto beta'))
 local switched,owned,nextProject=false,nil,nil
 for _=1,6000 do
  f:cycle();c=f.apps[7];local a=c.state.automation;local task=f.apps[12].state.currentTask
  if not switched and task and task.project then
   eq(task.project,'beta');owned=task.id;assert(c:command('build priority alpha 100'))
   eq(a.jobs[owned].workerId,12);assert(a.jobs[owned].status~='completed')
   assert(not f.apps[12].state.position.pending);f:reboot(12);f:reboot(7);switched=true
  elseif switched and task and task.project and task.id~=owned and not nextProject then nextProject=task.project end
  a=f.apps[7].state.automation
  if a.projects.alpha.phase=='built' and a.projects.beta.phase=='built' and not f.apps[12].state.currentTask then break end
 end
 local a=f.apps[7].state.automation;assert(switched);eq(nextProject,'alpha');eq(a.projects.alpha.priority,100)
 for _,name in ipairs({'alpha','beta'}) do eq(a.projects[name].phase,'built');eq(a.projects[name].report.counts.correct,2) end
 for _,z in ipairs({0,8}) do for x=4,5 do eq(f.blocks[x..',0,'..z].name,'minecraft:stone') end end
 eq(F.count(f.inventories.stock,'minecraft:stone'),0);eq(next(f.inventories.home12),nil);eq(next(f.inventories.supply12),nil)
 eq(next(f.worlds[12].items),nil);eq(a.supply,nil);eq(f.apps[12].state.status,'idle')
 for _,j in pairs(a.jobs) do eq(j.status,'completed') end
end)


test('roofed one cell opposing corridor retains ownership and actionable blockage across restart',function()
 local f=fixture({width=20,scaling=true,traffic=true,starts={
  [12]={x=10,y=2,z=0,heading='east'},[13]={x=11,y=2,z=0,heading='west'}}})
 assert(f.apps[7]:command('fleet limit building 2 4'))
 for x=1,19 do for _,p in ipairs({{x=x,y=1,z=0},{x=x,y=3,z=0},{x=x,y=2,z=-1},{x=x,y=2,z=1}}) do
  f.blocks[require('autobuilder.core.pathfinding').key(p)]={name='minecraft:stone',state={}}
 end end
 local before=U.copy(f.blocks);local ids={}
 for id,x in pairs({[12]=20,[13]=0}) do
  f.blocks[x..',0,0']={name='minecraft:stone',state={}}
  local j=f.apps[7].automation.queue:submit('VERIFY',{preferredWorker=id,clearanceY=2,blocks={{x=x,y=0,z=0,name='minecraft:stone',state={}}}},{})
  ids[id]=j.id
 end
 f.holds[12]=true;f.holds[13]=true
 for _=1,30 do f:cycle();if f.apps[12].state.currentTask and f.apps[13].state.currentTask then break end end
 f.holds={}
 local witnessed=false
 for _=1,300 do f:cycle()
  for _,j in pairs(f.apps[7].state.automation.jobs) do if j.trafficWait and j.trafficWait.blocker then witnessed=true end end
 end
 assert(witnessed,'opposing workers did not contend for a physical cell')
 for id,job in pairs(ids) do eq(f.apps[id].state.currentTask.id,job) end
 f:reboot(7);f:reboot(12);f:reboot(13)
 for _=1,100 do f:cycle() end
 for id,job in pairs(ids) do
  local j=f.apps[7].state.automation.jobs[job];eq(j.workerId,id);assert(j.status~='completed')
  assert(j.trafficWait or j.lastRouteFailure,'corridor has no persisted explanation')
  local text=table.concat(require('autobuilder.ui.dashboard').lines(f.apps[7].state,{},f.now,{},id),'\n')
  assert(text:find('passing bay',1,true) or text:find('Inspect worker',1,true),'corridor remedy missing')
  assert(text:find(job,1,true) and text:find('Position ',1,true),'affected task or known position missing')
  eq(f.worlds[id].digs,0);eq(f.apps[id].state.currentTask.id,job)
 end
 for key,value in pairs(before) do assert(F.equal(value,f.blocks[key]),'corridor changed: '..key) end
end)

test('offline destination retains its physical owner while independent verification finishes and reconnect clears it',function()
 local f=fixture({width=1,workers=3,scaling=true,traffic=true,starts={[13]={x=4,y=1,z=0,heading='north'}}})
 assert(f.apps[7]:command('fleet limit building 2 4'))
 for _=1,3 do f:cycle() end;f.enabled[13]=false
 for _=1,40 do f:cycle() end;eq(f.apps[7].state.workers['13'].online,false)
 f.blocks['4,0,0']={name='minecraft:stone',state={}};f.blocks['22,0,8']={name='minecraft:stone',state={}}
 local q=f.apps[7].automation.queue
 local blocked=q:submit('VERIFY',{preferredWorker=12,clearanceY=2,blocks={{x=4,y=0,z=0,name='minecraft:stone',state={}}}},{})
 local free=q:submit('VERIFY',{preferredWorker=14,clearanceY=2,blocks={{x=22,y=0,z=8,name='minecraft:stone',state={}}}},{})
 for _=1,350 do f:cycle();if free.status=='completed' and blocked.trafficWait then break end end
 eq(free.status,'completed');eq(free.report.counts.correct,1);eq(blocked.workerId,12);assert(blocked.trafficWait)
 eq(blocked.trafficWait.blocker,13);eq(f.worlds[13].pose.x,4);eq(f.worlds[13].pose.y,1)
 f:reboot(7);for _=1,40 do f:cycle() end
 blocked=f.apps[7].state.automation.jobs[blocked.id];eq(blocked.workerId,12);assert(blocked.status~='completed');eq(f.worlds[13].pose.x,4)
 f.enabled[13]=true
 for _=1,600 do f:cycle();if blocked.status=='completed' and not f.apps[13].state.currentTask and U.distance(f.worlds[13].pose,f.configs[13].depot)==0 then break end end
 eq(blocked.status,'completed');eq(blocked.report.counts.correct,1);eq(U.distance(f.worlds[13].pose,f.configs[13].depot),0)
 local returns=0;for _,r in pairs(f.apps[7].state.automation.returns) do if r.owner==13 then returns=returns+1 end end;eq(returns,1)
 for _,id in ipairs(f.workerIds) do eq(f.worlds[id].digs,0) end
end)


test('four fleet roles share one physical intersection with granted motion and exact cargo',function()
 local f=fixture({width=1,workers=4,scaling=true,traffic=true,
  homes={[13]={x=10,y=2,z=4,heading='north'},[14]={x=4,y=2,z=10,heading='north'},[15]={x=10,y=4,z=18,heading='north'}},
  starts={[12]={x=4,y=4,z=10,heading='east'},[14]={x=14,y=2,z=10,heading='west'}},
  workerSettings={[13]={automation={building=false,courier=true}},[14]={automation={building=false}},
   [15]={automation={building=false},mining={enabled=true,resources={'minecraft:cobblestone'},entry={x=10,y=4,z=16},
    bounds={min={x=10,y=4,z=6},max={x=11,y=4,z=16}},fuelTarget=100}}},
  configure=function(f,c,homes)
   f.containers={['10,2,4']='pickup',['10,2,16']='delivery',['10,4,18']='home15'}
   f.inventories.pickup={[1]={name='minecraft:dirt',count=1}};f.inventories.delivery={}
   f.blocks['10,1,4']={name='minecraft:chest',state={}};f.blocks['10,1,16']={name='minecraft:chest',state={}}
   f.blocks['10,4,17']=nil;f.blocks['11,4,6']={name='minecraft:cobblestone',state={}}
   c.storageInventories={'stock','home15'};c.scaling.roles.mining={min=1};c.scaling.roles.hauling={min=1}
   c.inventoryAreas={home15={min={x=10,y=3,z=18},max={x=10,y=3,z=18}},pickup={min={x=10,y=1,z=4},max={x=10,y=1,z=4}},delivery={min={x=10,y=1,z=16},max={x=10,y=1,z=16}}}
   for i=#c.supplyStations,1,-1 do if c.supplyStations[i].workerId==15 then table.remove(c.supplyStations,i) end end
   local buffers=c.logistics.nodes[1].buffers;for i=#buffers,1,-1 do if buffers[i].inventory=='home15' then table.remove(buffers,i) end end
  end})
 f.blocks['16,2,10']={name='minecraft:stone',state={}}
 for _,id in ipairs(f.workerIds) do f.holds[id]=true end
 for _=1,3 do f:cycle() end
 local c=f.apps[7];local q=c.automation.queue
 local home=c.automation.production.returns:request(14)
 for _=1,30 do f:cycle();if f.apps[14].state.currentTask then break end end
 assert(f.apps[14].state.currentTask and f.apps[14].state.currentTask.type=='RETURN_HOME')
 local verify=q:submit('VERIFY',{preferredWorker=12,clearanceY=4,blocks={{x=16,y=2,z=10,name='minecraft:stone',state={}}}},{})
 local haul=q:submit('TRANSPORT',{preferredWorker=13,item='minecraft:dirt',quantity=1,source={x=10,y=2,z=4},destination={x=10,y=2,z=16}},{})
 local mine=assert(c.mining.jobs:submit('minecraft:cobblestone',1,0))
 for _=1,40 do f:cycle();if verify.workerId and haul.workerId and mine.workerId then break end end
 eq(verify.workerId,12);eq(haul.workerId,13);eq(mine.workerId,15);f.holds={}
 for _=1,1600 do f:cycle();if verify.status=='completed' and haul.status=='completed' and home.status=='completed' and mine.status=='completed' then break end end
 assert(verify.status=='completed' and haul.status=='completed' and home.status=='completed' and mine.status=='completed',f.envs[7].textutils.serialize({verify=verify,haul=haul,home=home,mine=mine}))
 eq(verify.report.counts.correct,1);eq(F.count(f.inventories.delivery,'minecraft:dirt'),1);eq(next(f.inventories.pickup),nil)
 eq(F.count(f.inventories.home15,'minecraft:cobblestone'),1);eq(f.worlds[15].digs,1);eq(U.distance(f.worlds[15].pose,f.configs[15].depot),0)
 local roles={};for _,m in ipairs(f.moves) do if m.to.y==4 and math.abs(m.to.x-10)<=1 and math.abs(m.to.z-10)<=1 then roles[m.kind]=true end end
 for _,kind in ipairs({'VERIFY','TRANSPORT','RETURN_HOME','MINE'}) do assert(roles[kind],kind..' did not physically traverse intersection') end
 local contention=false
 for _,d in ipairs(f.denials) do if d.target.y==4 and math.abs(d.target.x-10)<=2 and math.abs(d.target.z-10)<=2
  and d.reason and (d.reason:find('worker',1,true) or d.reason:find('reservation',1,true)) then contention=true end end
 assert(contention,'no cross-role intersection denial '..f.envs[7].textutils.serialize(f.denials))
 for _=1,20 do f:cycle() end
 for _,id in ipairs(f.workerIds) do assert(not f.apps[id].state.currentTask);assert(not next(f.worlds[id].items));assert(f.worlds[id].fuel>0) end
 for id=12,14 do eq(f.worlds[id].digs,0) end
 eq(f.blocks['10,1,4'].name,'minecraft:chest');eq(f.blocks['10,1,16'].name,'minecraft:chest');eq(f.blocks['16,2,10'].name,'minecraft:stone')
end)
