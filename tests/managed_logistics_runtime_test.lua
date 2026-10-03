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
