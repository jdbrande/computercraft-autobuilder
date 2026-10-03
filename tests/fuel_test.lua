local U=require('autobuilder.core.util')
local Fuel=require('autobuilder.resources.fuel')
local function mc(s) return 'minecraft:'..s end

test('fuel policy validates custom fuels and dedicated station identity',function()
  local C=require('autobuilder.config')
  local c=C.load({fuel={enabled=true,item='mod:fuel',values={['mod:fuel']=120},returns={},
    stations={{id='north',workerId=2,inventory='fuel_chest',position={x=0,y=1,z=0},targetItems=12}}}})
  eq(c.fuel.values['mod:fuel'],120); eq(Fuel.items('mod:fuel',0,1000,c.fuel),9)
  eq(Fuel.items('mod:fuel','unlimited',1000,c.fuel),0)
  for _,change in ipairs({{low=1001},{target=0},{values={['mod:fuel']=0}},
    {returns={['minecraft:unknown']='minecraft:bucket'}},
    {stations={[2]={id='x',workerId=2,inventory='fuel',position={x=0,y=0,z=0}}}}}) do
    assert(not pcall(C.load,{fuel=change}),'malformed fuel policy accepted')
  end
  local station={id='north',workerId=2,inventory='fuel',position={x=0,y=0,z=0}}
  assert(not pcall(C.load,{fuel={stations={station,U.copy(station)}}}))
  assert(not pcall(C.load,{storageInventories={'fuel'},fuel={stations={station}}}))
  eq(C.load().fuel.enabled,false)
end)

test('finite mission fuel budgets include outward work return and reserve',function()
  local b=Fuel.budget(100,20,30,40,20)
  eq(b.required,110); eq(b.shortfall,10); eq(b.allowed,false)
  eq(Fuel.budget(110,20,30,40,20).allowed,true)
  eq(Fuel.budget('unlimited',20,30,40,20).shortfall,0)
  for _,n in ipairs({-1,0/0,math.huge,1.5}) do assert(not pcall(Fuel.budget,100,n,0,0,0)) end
end)

test('native refuel uses configured fuel and retains returned containers until safe depot return',function()
  local level=0; local item={name=mc('lava_bucket'),count=1}; local returned=0; local pulled=0
  local t={getFuelLevel=function() return level end,getFuelLimit=function() return 20000 end,
    getItemCount=function() return item and item.count or 0 end,getItemDetail=function() return item end,
    select=function(slot) eq(slot,15); return true end,
    refuel=function(n) eq(n,1); assert(item.name==mc('lava_bucket')); item={name=mc('bucket'),count=1}; level=level+1000; return true end,
    inspectUp=function() return true,{name=mc('chest')} end,inspectDown=function() return true,{name=mc('chest')} end,
    suckUp=function() pulled=pulled+1; item={name=mc('lava_bucket'),count=1}; return true end,
    dropDown=function(n) eq(item.name,mc('bucket')); returned=returned+n; item=nil; return true end}
  local inv=require('autobuilder.storage.inventory').new(t,{fuel=Fuel.defaults})
  assert(inv:refuel(1000,false)); eq(level,1000); eq(item.name,mc('bucket'))
  assert(not inv:refuel(2000,false)); eq(returned,0); eq(pulled,0)
  assert(inv:refuel(2000,true)); eq(returned,1); eq(pulled,1); eq(level,2000); eq(item.name,mc('bucket'))
end)

test('fuel containers are never dropped without a verified container and NBT fuel is refused',function()
  local item={name=mc('bucket'),count=1}
  local t={getFuelLevel=function() return 0 end,getItemCount=function() return 1 end,getItemDetail=function() return item end,
    inspectDown=function() return false end,select=function() error('must not select unsafe item') end,
    dropDown=function() error('must never world-drop returned container') end,refuel=function() error('must not consume NBT fuel') end}
  local inv=require('autobuilder.storage.inventory').new(t,{fuel=Fuel.defaults})
  assert(not inv:refuel(1000,true))
  item={name=mc('coal'),count=1,nbt='protected'}; assert(not inv:refuel(1000,false))
end)

test('managed station returns the final fuel container before releasing the worker',function()
  local level=0; local item={name=mc('lava_bucket'),count=1}; local returns=0; local chest=false
  local t={getFuelLevel=function() return level end,getFuelLimit=function() return 20000 end,
    getItemCount=function() return item and item.count or 0 end,getItemDetail=function() return item end,
    select=function() return true end,inspectDown=function() return chest,{name=mc('chest')} end,
    refuel=function() item={name=mc('bucket'),count=1}; level=level+1000; return true end,
    dropDown=function() returns=returns+1; item=nil; return true end}
  local inv=require('autobuilder.storage.inventory').new(t,{fuel=Fuel.defaults})
  local ok,why=inv:refuel(1000,true,true)
  assert(not ok and why:find('container'),'returned bucket released without a safe return chest')
  eq(returns,0); chest=true
  assert(inv:refuel(1000,true,true)); eq(returns,1); eq(item,nil); eq(level,1000)
end)
