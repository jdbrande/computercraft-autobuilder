local U=require('autobuilder.core.util')
local F=require('autobuilder.factory.factory')
local Runtime=require('autobuilder.core.runtime')
local function fixture()
  local f=require('tests.managed_logistics_support').new()
  f.envs={};f.apps={};f.worlds={};f.configs={};f.blocks={};f.owners={};f.active={};f.grants={}
  f.inventories={stock={[1]={name='minecraft:stone',count=12}},home12={},home13={},supply12={},supply13={}}
  local homes={[12]={x=0,y=2,z=-4,heading='north'},[13]={x=18,y=2,z=-4,heading='north'}}
  local buffers,stations={},{}
  for id=12,13 do
    buffers[#buffers+1]={inventory='home'..id,position=U.copy(homes[id])}
    stations[#stations+1]={workerId=id,inventory='supply'..id,position=U.copy(homes[id]),side='front'}
    local h=homes[id];f.blocks[h.x..',1,-4']={name='minecraft:chest',state={}};f.blocks[h.x..',2,-5']={name='minecraft:chest',state={}}
  end
  for x=3,14 do for z=-1,1 do f.blocks[x..',-1,'..z]={name='minecraft:stone',state={}} end end
  for _,x in ipairs({4,13}) do
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
  f.configs[7]=C.load({storageInventories={'stock'},turtleFuelReserveItems={},supplyStations=stations,
    supply={inventory='',batch=2},logistics={nodes={{id='base',inventory='stock',position={x=-4,y=1,z=-4},buffers=buffers}}},
    build={enabled=true,origin={x=4,y=0,z=0},regionSize=2}})
  f.apps[7]=Runtime.new(f.configs[7],env(7))
  for id=12,13 do
    local w=require('tests.build_world').new();f.worlds[id]=w;w.blocks=f.blocks
    w.pose=U.copy(homes[id]);w.pose.known=true;w.fuel=8000
    local t=w.turtle;t.getFuelLevel=function() return w.fuel end;t.getFuelLimit=function() return 20000 end
    for _,action in ipairs({'forward','up','down'}) do local move=t[action];t[action]=function()
      if w.fuel==0 then return false,'out of fuel' end
      local ok,why=move()
      if ok then
        for other,ow in pairs(f.worlds) do if other~=id then assert(U.distance(ow.pose,w.pose)>0,'physical turtle collision') end end
        w.fuel=w.fuel-1
      end
      return ok,why
    end end
    t.getItemSpace=function(slot) return 64-t.getItemCount(slot) end
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
    t.dropDown=function(n)
      assert(U.distance(w.pose,homes[id])==0,'debris dropped outside private home')
      return transfer(w.items,f.inventories['home'..id],w.selected,n)
    end
    t.suck=function(n)
      assert(U.distance(w.pose,homes[id])==0 and w.pose.heading=='north','supply pulled outside private endpoint')
      local inv=f.inventories['supply'..id];local slot=next(inv);if not slot then return false end
      local moved=transfer(inv,w.items,slot,n,w.selected)
      if moved and f.crashPull then f.crashPull=nil;f.crashed=id;error('power lost after registered supply pull') end
      return moved
    end
    f.configs[id]=C.load({role='worker',controllerId=7,automation={building=true},minimumFuelReserve=10,
      depot=U.copy(homes[id]),initialPosition=U.copy(w.pose),supply={inventory='supply'..id,side='front'}})
    local e=env(id);e.turtle=t;f.apps[id]=Runtime.new(f.configs[id],e)
  end
  local ce=f.envs[7]
  ce.fs.files['/fleet.json']=ce.textutils.serialize({schema=1,size={x=10,y=1,z=1},palette={{name='minecraft:stone',state={}}},
    runs={{id=1,count=10}},metadata={},requirements={['minecraft:stone']=10}})
  function f:reboot(id) self.envs[id].packets={};self.apps[id]=Runtime.new(self.configs[id],self.envs[id]) end
  function f:pump()
    for _,id in ipairs({12,13,7}) do
      local e=self.envs[id];local packets=e.packets;e.packets={}
      for _,p in ipairs(packets) do
        if p.m.type=='task_supply' then
          eq(p.m.payload.station.inventory,'supply'..p.to);self.grants[p.to]=true
          if self.loseGrant then self.loseGrant=nil else self.apps[p.to]:receive(p.m.sender,p.m,p.protocol) end
        else self.apps[p.to]:receive(p.m.sender,p.m,p.protocol) end
      end
    end
  end
  function f:cycle()
    self.now=self.now+1;for _,e in pairs(self.envs) do e.now=self.now end
    for _,id in ipairs({12,13}) do self.apps[id]:tick() end;self:pump()
    self.apps[7]:tick();self:pump();self.apps[7]:workStep()
    for _,id in ipairs({12,13}) do self.apps[id]:workStep() end;self:pump()
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
  assert(restarted);eq(p.report.counts.correct,10)
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
