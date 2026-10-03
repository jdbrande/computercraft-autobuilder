local U=require('autobuilder.core.util')
local S=require('tests.support')
local Courier=require('autobuilder.workers.fuel_courier')
local function fixture()
  local h={slots={},selected=1,stock=2,target=2,received=0,fuel=500}
  local task={id='task:1:1',type='RESCUE',item='minecraft:coal',quantity=2,targetWorker=2,
    source={x=0,y=10,z=0},destination={x=3,y=11,z=0},home={x=0,y=10,z=0},phase='setup'}
  local nav={pose={known=true,x=0,y=10,z=0,heading='north'}}
  nav.face=function() return true end
  nav.goTo=function(_,p) if h.obstructed then return false,'route blocked' end; for _,a in ipairs({'x','y','z'}) do nav.pose[a]=p[a] end; return true end
  local t={getItemDetail=function(i) return U.copy(h.slots[i]) end,getItemCount=function(i) return h.slots[i] and h.slots[i].count or 0 end,
    getItemSpace=function(i) return 64-(h.slots[i] and h.slots[i].count or 0) end,
    select=function(i) h.selected=i; return true end,getFuelLevel=function() return h.fuel end,
    inspect=function() return false end,
    inspectUp=function() return true,{name='minecraft:chest'} end,
    inspectDown=function() return true,{name='computercraft:turtle_advanced'} end,
    suckUp=function(n)
      local used=math.min(n,h.stock); if used==0 then return false end
      h.slots[h.selected]={name='minecraft:coal',count=(h.slots[h.selected] and h.slots[h.selected].count or 0)+used}
      h.stock=h.stock-used; return true
    end,
    dropDown=function(n)
      if h.full then return false end
      local used=math.min(n,h.maxDrop or n); h.received=h.received+used
      local i=h.slots[h.selected]; i.count=i.count-used; if i.count==0 then h.slots[h.selected]=nil end
      if h.crash then h.crash=false; error('power lost after delivery') end
      return true
    end}
  local e={turtle=t,peripheral={getType=function() return 'turtle' end,call=function(side,method) eq(side,'bottom'); eq(method,'getID'); return h.target end}}
  local config=require('autobuilder.config').load({depot=task.home})
  local f={h=h,task=task,nav=nav}
  local function save() f.saved=U.copy(f.task); return true end
  function f:boot() self.c=Courier.new(self.task,e,config,nav,save) end
  function f:finish() for _=1,20 do self.c:step(); if self.task.phase=='completed' then return end end; error(self.task.error or 'courier did not finish') end
  f:boot(); return f
end

test('rescue courier delivers a measured partial batch to the identified turtle then returns home',function()
  local f=fixture(); f.h.maxDrop=1; f:finish()
  eq(f.h.received,2); eq(f.task.fuelDelivered,2); eq(f.nav.pose.x,0); eq(f.nav.pose.y,10); eq(next(f.h.slots),nil)
end)

test('rescue courier reconciles delivery after reboot without giving duplicate fuel',function()
  local f=fixture(); f.h.crash=true
  for _=1,10 do f.c:step(); if f.h.received>0 then break end end
  eq(f.h.received,2); f.task=U.copy(f.saved); f:boot(); f:finish(); eq(f.h.received,2)
end)

test('rescue courier refuses another turtle, full inventory and a blocked route without dropping cargo',function()
  for _,fault in ipairs({'identity','full','route'}) do
    local f=fixture(); if fault=='identity' then f.h.target=99 elseif fault=='full' then f.h.full=true else f.h.obstructed=true end
    for _=1,10 do f.c:step() end
    eq(f.h.received,0); eq(f.task.phase,'blocked'); assert(f.task.error)
  end
end)

test('rescue courier returns beneath an overhead station chest through a side approach',function()
  local f=fixture(); local go=f.nav.goTo
  f.nav.goTo=function(nav,p)
    if p.x==0 and p.z==0 and p.y==10 and nav.pose.x==0 and nav.pose.y>10 then return false,'Movement obstructed: minecraft:chest' end
    return go(nav,p)
  end
  f:finish(); eq(f.h.received,2); eq(f.nav.pose.x,0); eq(f.nav.pose.y,10)
end)
