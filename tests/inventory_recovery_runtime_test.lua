local U=require('autobuilder.core.util')
local S=require('tests.support')
local R=require('autobuilder.core.runtime')
local C=require('tests.loaded_config')
test('real recovery runtimes preserve tagged cargo donor ownership and receipts across interrupted drop and reboot',function()
 local f=require('tests.managed_logistics_support').new();local now=100;local apps,envs,configs,packets={},{},{},{}
 local slots={[12]={[1]={name='minecraft:stone',count=5},[16]={name='minecraft:diamond_pickaxe',count=1,nbt='tool-tag'}},[13]={[15]={name='minecraft:coal',count=3}}}
 local drops=0;local crash=true
 local function transfer(from,slot,to,n)
  local v=from[slot];if not v then return false end
  local target;for i=1,16 do if not to[i] or to[i].name==v.name and to[i].nbt==v.nbt and to[i].count<64 then target=i;break end end
  if not target then return false end
  n=math.min(n,v.count,64-(to[target] and to[target].count or 0));to[target]=to[target] or {name=v.name,nbt=v.nbt,count=0}
  to[target].count=to[target].count+n;v.count=v.count-n;if v.count==0 then from[slot]=nil end;return true
 end
 for _,id in ipairs({7,12,13}) do
  local e={fs=S.fs(),textutils=S.codec(),turtle=S.turtle(),gps={locate=function() return nil end}}
  e.os={getComputerID=function() return id end,epoch=function() return now*1000 end}
  e.rednet={isOpen=function() return true end,open=function() end,send=function(to,m,p) packets[#packets+1]={to=to,m=U.copy(m),p=p};return true end}
  e.peripheral={getNames=function() return {'left'} end,getType=function(side) return (side=='top' or side=='bottom') and 'turtle' or 'modem' end,
   call=function(name,method,...) if method=='isWireless' then return true end;if method=='getID' then return id==12 and 13 or 12 end;return f.e.peripheral.call(name,method,...) end}
  e.turtle.fuel=id==12 and 0 or 2000
  if id~=7 then
   local selected=1;local t=e.turtle
   t.getItemDetail=function(slot) return U.copy(slots[id][slot]) end;t.getItemCount=function(slot) return slots[id][slot] and slots[id][slot].count or 0 end
   t.getItemSpace=function(slot) return 64-t.getItemCount(slot) end;t.getSelectedSlot=function() return selected end
   t.select=function(slot) selected=slot;return true end
   t.inspect=function() return false end
   t.inspectUp=function() local a,b=apps[12].state.position,apps[13].state.position;return a.x==b.x and a.z==b.z and a.y+1==b.y,{name='computercraft:turtle_advanced'} end
   t.inspectDown=function() local p=apps[id].state.position;return true,{name=p.x==2 and p.z==2 and 'computercraft:turtle_advanced' or 'minecraft:chest'} end
   t.dropUp=function(n)
    assert(id==12 and t.inspectUp());drops=drops+1;local moved=transfer(slots[id],selected,slots[13],n)
    if crash then crash=false;error('power lost after donor drop') end;return moved
   end
   t.dropDown=function(n) local p=apps[id].state.position;assert(id==13 and p.x==4 and p.y==1 and p.z==0);return transfer(slots[id],selected,f.inventories.b,n) end
  end
  local opts={role=id==7 and 'controller' or 'worker',controllerId=7,automation={enabled=true,courier=id==13},minimumFuelReserve=0,
   depot={x=id==13 and 4 or 2,y=1,z=id==13 and 0 or 2},initialPosition={x=id==13 and 4 or 2,y=1,z=id==13 and 0 or 2,heading='north'},
   storageInventories={'base','site'},turtleFuelReserveItems={},logistics=U.copy(f.config.logistics)}
  configs[id]=C.load(opts);envs[id]=e;apps[id]=R.new(configs[id],e)
 end
 local c,d,w=apps[7],apps[12],apps[13]
 d.state.currentTask={id='mine:7:1',type='MINE',phase='blocked',error='return obstructed'};d.state.status='blocked';assert(d:save())
 c.state.jobs['mine:7:1']={id='mine:7:1',type='MINE',workerId=12,status='blocked',item='minecraft:stone',quantity=5,delivered=0};assert(c:save())
 local function pump()
  for _=1,100 do if #packets==0 then return end;local p=table.remove(packets,1);assert(apps[p.to],'unknown recipient');apps[p.to]:receive(p.m.sender,p.m,p.p) end
  error('packet loop')
 end
 for _,id in ipairs({12,13,7}) do apps[id]:tick();pump() end
 assert(c:command('worker recover 12'));local restarted=false;local r
 for i=1,800 do
  now=now+5
  for _,id in ipairs({12,13,7}) do apps[id]:tick();pump() end
  for _,id in ipairs({12,13,7}) do apps[id]:workStep();pump() end
  if not crash and not restarted then
   for _,id in ipairs({7,12,13}) do apps[id]=R.new(configs[id],envs[id]) end
   c,d,w=apps[7],apps[12],apps[13];restarted=true
  end
  for _,request in pairs(c.state.automation.inventoryRecoveries) do r=request end
  if r and r.status=='completed' then break end
 end
 assert(r and r.status=='completed',r and (r.error or r.status) or 'no recovery')
 assert(restarted);eq(drops,2);eq(next(slots[12]),nil);eq(slots[13][15].count,3)
 eq(f.inventories.b[1],nil);eq(f.inventories.base[2].count,29)
 eq(f.inventories.b[2].nbt,'tool-tag');eq(f.inventories.b[2].count,1)
 eq(d.state.status,'quarantined');eq(d.state.currentTask.id,'mine:7:1');eq(c.state.jobs['mine:7:1'].workerId,12)
 eq(w.state.currentTask,nil);eq(w.state.status,'idle');assert(envs[13].turtle.fuel<2000);eq(envs[12].turtle.calls,0)
 assert(not d.automation:handle(7,{boot=c.state.boot,sequence=999999,type='task_resume',payload={jobId='mine:7:1'}}))
 assert(not d.mining:handle(7,{type='mine_resume',payload={jobId='mine:7:1'}}));d:workStep();eq(envs[12].turtle.calls,0)
end)
