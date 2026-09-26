local S=require('tests.support')
test('material registry maps raw iron to normal and deepslate ores',function()
  local M=require('autobuilder.resources.materials')
  assert(M.get('minecraft:raw_iron').blocks['minecraft:iron_ore'])
  assert(M.get('minecraft:raw_iron').blocks['minecraft:deepslate_iron_ore'])
  eq(M.get('minecraft:unobtainium'),nil)
end)
test('A star routes around blocked cells and respects search budget',function()
  local P=require('autobuilder.core.pathfinding')
  local path=assert(P.find({x=0,y=0,z=0},{x=2,y=0,z=0},function(p)
    return p.y==0 and math.abs(p.z)<=1 and p.x>=0 and p.x<=2 and not (p.x==1 and p.z==0)
  end,100))
  eq(#path,4); eq(path[#path].x,2)
  assert(not P.find({x=0,y=0,z=0},{x=20,y=0,z=0},function() return true end,2))
end)
test('scanner converts relative coordinates, caches and groups veins',function()
  local now,calls=0,0
  local p={getType=function() return 'geoScanner' end,call=function(_,method)
    if method=='cost' then return 0 end
    calls=calls+1; return {{name='minecraft:iron_ore',x=1,y=0,z=0},{name='minecraft:iron_ore',x=2,y=0,z=0},{name='minecraft:iron_ore',x=5,y=0,z=0}}
  end}
  local scanner=require('autobuilder.resources.scanner').new({peripheral=p}, {side='left',radius=8,ttl=30,cooldown=3,maxCost=0},function() return now end)
  local origin={x=10,y=64,z=-20}
  local blocks=assert(scanner:scan(origin)); eq(blocks[1].x,11)
  assert(scanner:scan(origin)); eq(calls,1)
  local veins=scanner:veins(blocks,{['minecraft:iron_ore']=true},origin)
  eq(#veins,2); eq(#veins[1],2)
  scanner:invalidate({x=11,y=64,z=-20}); now=4
  assert(scanner:scan(origin)); eq(calls,2)
end)
test('scanner restores pickaxe after scan failure and recovers interrupted swap',function()
  local equipped='pickaxe'; local held='advancedperipherals:geo_scanner'; local selected=1
  local t={getSelectedSlot=function() return selected end,select=function(s) selected=s; return true end,
    getItemDetail=function() return {name=held,count=1} end,
    equipLeft=function() if equipped=='pickaxe' then equipped='scanner'; held='minecraft:diamond_pickaxe' else equipped='pickaxe'; held='advancedperipherals:geo_scanner' end; return true end}
  local p={getType=function() return equipped=='scanner' and 'geoScanner' or nil end,
    call=function(_,method) if method=='cost' then return 0 end; error('disconnected') end}
  local scanner=require('autobuilder.resources.scanner').new({turtle=t,peripheral=p},{side='left',slot=16,radius=8,cooldown=3,maxCost=0},function() return 0 end)
  assert(not scanner:scan({x=0,y=0,z=0})); eq(equipped,'pickaxe'); eq(selected,1)
  equipped='scanner'; held='minecraft:diamond_pickaxe'; assert(scanner:recover()); eq(equipped,'pickaxe')
end)
test('scanner enforces cooldown and refuses paid scans above configured budget',function()
  local calls=0
  local p={getType=function() return 'geoScanner' end,call=function(_,method)
    if method=='cost' then return 5 end; calls=calls+1; return {}
  end}
  local scanner=require('autobuilder.resources.scanner').new({peripheral=p},{radius=8,side='left',maxCost=0,cooldown=3},function() return 0 end)
  assert(not scanner:scan({x=0,y=0,z=0})); eq(calls,0)
end)
test('storage refresh counts inventories and rejects disconnect without serving stale counts',function()
  local broken=false
  local p={call=function(name,method) if broken then error('detached') end; eq(method,'list'); return {[1]={name='minecraft:raw_iron',count=32},[4]={name='minecraft:raw_iron',count=4}} end}
  local storage=require('autobuilder.storage.storage').new(p,{'chest_0','chest_1'})
  assert(storage:refresh()); eq(storage:getCount('minecraft:raw_iron'),72)
  broken=true; assert(not storage:refresh()); eq(storage:getCount('minecraft:raw_iron'),nil)
end)
test('inventory refuses deposit without a real chest and measures partial transfers',function()
  local count=10; local chest=false
  local t={getItemDetail=function(slot) if slot==1 and count>0 then return {name='minecraft:raw_iron',count=count} end end,
    getItemCount=function(slot) return slot==1 and count or 0 end,
    inspectDown=function() return chest,{name=chest and 'minecraft:chest' or 'minecraft:air'} end,
    select=function() return true end,dropDown=function() count=count-3; return true end}
  local inv=require('autobuilder.storage.inventory').new(t,{reservedSlots={15,16}})
  eq(inv:getCount('minecraft:raw_iron'),10); assert(not inv:depositSlot(1))
  eq(count,10); chest=true; eq(inv:depositSlot(1),3); eq(inv:getCount('minecraft:raw_iron'),7)
end)

test('scanner refuses to replace a modem on a misconfigured tool side',function()
  local swaps=0
  local t={getItemDetail=function() return {name='advancedperipherals:geo_scanner',count=1} end,
    getSelectedSlot=function() return 1 end,select=function() return true end,equipLeft=function() swaps=swaps+1; return true end}
  local scanner=require('autobuilder.resources.scanner').new({turtle=t,peripheral={getType=function() return 'modem' end}},{side='left',slot=16},function() return 0 end)
  assert(not scanner:scan({x=0,y=0,z=0})); eq(swaps,0)
end)

test('refuel continues from chest after using a partial reserved fuel stack',function()
  local fuel,count,pulls=0,1,0
  local t={getFuelLevel=function() return fuel end,getItemCount=function() return count end,
    getItemDetail=function() if count>0 then return {name='minecraft:coal',count=count} end end,
    select=function() return true end,inspectUp=function() return true,{name='minecraft:chest'} end,
    suckUp=function() pulls=pulls+1; count=2; return true end,
    refuel=function() count=count-1; fuel=fuel+80; return true end}
  local inv=require('autobuilder.storage.inventory').new(t,{fuelSlot=15})
  assert(inv:refuel(100,true)); eq(pulls,1); eq(fuel,160)
end)

test('refuel preserves explicit item restrictions and does not search other slots',function()
  local items={[1]={name='minecraft:coal_block',count=4},[15]={name='minecraft:coal_block',count=4},[16]={name='minecraft:coal',count=16}}
  local t={getFuelLevel=function() return 0 end,
    getItemCount=function(slot) return items[slot] and items[slot].count or 0 end,
    getItemDetail=function(slot) return items[slot] end,
    select=function() error('must not select unsupported fuel') end,
    refuel=function() error('must not consume unsupported fuel') end}
  local inventory=require('autobuilder.storage.inventory')
  assert(not inventory.new(t,{fuelItems={['minecraft:coal']=true}}):refuel(1000,false))
  items[15]={name='minecraft:oak_planks',count=16}
  assert(not inventory.new(t):refuel(1000,false))
  items[15]=nil
  assert(not inventory.new(t):refuel(1000,false))
  eq(items[1].count,4); eq(items[16].count,16)
end)

test('scanner waits out AP operation cooldown before scanning and restoring tool',function()
  local now,scans=0,0
  local p={getType=function() return 'geoScanner' end,getMethods=function() return {'cost','scan','getOperationCooldown'} end,
    call=function(_,method,argument)
      if method=='cost' then return 0 end
      if method=='getOperationCooldown' then eq(argument,'scanBlocks'); return math.max(0,6000-now*1000) end
      scans=scans+1; if now<6 then return nil,'scanBlocks is on cooldown' end; return {}
    end}
  local scanner=require('autobuilder.resources.scanner').new({peripheral=p,sleep=function(seconds) now=now+seconds end},{radius=8,side='left',maxWait=30},function() return now end)
  assert(scanner:scan({x=0,y=0,z=0})); eq(scans,1); assert(now>=6)
end)
