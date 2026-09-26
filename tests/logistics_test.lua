local U=require('autobuilder.core.util')
test('building resupply stays inside the cleared overhead plane',function()
  local w=require('tests.build_world').new(); local depot=U.copy(w.pose)
  w.pose.x=3; w.pose.y=3
  for x=0,3 do w.blocks[x..',5,0']={name='minecraft:stone',state={}} end
  local nav=require('autobuilder.core.navigation').new(w.turtle,U.copy(w.pose),{minimumFuelReserve=0},function() return true end)
  local ok,err=require('autobuilder.workers.resupply').travel({},
    {type='BUILD',clearanceY=4,blocks={{x=3,y=2,z=0}}},nav,depot,function() return true end)
  assert(ok,err); eq(w.pose.x,0); eq(w.pose.y,2)
end)
local function wired()
  local w={inventories={stock={[1]={name='minecraft:stone',count=100}},stage={}},capacity=64,transfers=0}
  w.peripheral={call=function(name,method,...)
    local inv=assert(w.inventories[name],'disconnected inventory')
    if method=='list' then return U.copy(inv) end
    if method=='pushItems' then
      local dest,slot,limit=...; local item=inv[slot]; local target=w.inventories[dest]; assert(target,'disconnected destination')
      local count=target[1] and target[1].count or 0; local moved=math.min(item and item.count or 0,limit,w.capacity-count)
      if moved>0 then target[1]=target[1] or {name=item.name,count=0}; target[1].count=target[1].count+moved; item.count=item.count-moved; if item.count==0 then inv[slot]=nil end end
      w.transfers=w.transfers+1
      if w.crash then w.crash=false; error('power lost after transfer') end
      return moved
    end
    error('unexpected method')
  end}
  return w
end
local function supply(w,state,overrides)
  local saved; local c={supply={inventory='stage',batch=64},storageInventories={'stock'},turtleFuelReserveItems={['minecraft:coal']=64}}
  for k,v in pairs(overrides or {}) do c[k]=v end
  local ex=require('autobuilder.storage.supply').new(state,c,{peripheral=w.peripheral},function() saved=U.copy(state); return true end)
  return ex,function() return saved end
end
local function carrier()
  local w={pose={x=0,y=1,z=0,heading='east',known=true},items={},chests={['0,0,0']={name='minecraft:chest',items={name='minecraft:stone',count=32}},['3,0,0']={name='minecraft:chest'}},selected=1,sucks=0,drops=0,capacity=128}
  local key=function(p) return p.x..','..p.y..','..p.z end
  local dirs={north={0,-1},east={1,0},south={0,1},west={-1,0}}
  local function target(s)
    local p=U.copy(w.pose)
    if s=='Down' then p.y=p.y-1 elseif s=='Up' then p.y=p.y+1 else local v=dirs[p.heading]; p.x=p.x+v[1]; p.z=p.z+v[2] end
    return key(p)
  end
  local t={}; w.turtle=t
  t.getFuelLevel=function() return 'unlimited' end
  t.getItemCount=function(s) local i=w.items[s or w.selected]; return i and i.count or 0 end
  t.getItemDetail=function(s) return U.copy(w.items[s or w.selected]) end
  t.getItemSpace=function(s) return 64-t.getItemCount(s) end
  t.select=function(s) w.selected=s; return true end
  for _,s in ipairs({'','Up','Down'}) do
    t['inspect'..s]=function() local c=w.chests[target(s)]; return c~=nil,c and {name=c.name} or 'No block to inspect' end
    t['suck'..s]=function(n)
      local c=w.chests[target(s)]; if not c or not c.items then return false end
      local item=w.items[w.selected]; if item and item.name~=c.items.name then return false end
      local moved=math.min(n,64-(item and item.count or 0),c.items.count)
      if moved<=0 then return false end
      w.items[w.selected]=item or {name=c.items.name,count=0}; w.items[w.selected].count=w.items[w.selected].count+moved
      c.items.count=c.items.count-moved; if c.items.count==0 then c.items=nil end; w.sucks=w.sucks+1
      if w.crashSuck then w.crashSuck=false; error('power lost after pull') end
      return true
    end
    t['drop'..s]=function(n)
      local c=w.chests[target(s)]; local item=w.items[w.selected]; if not c or not item then return false end
      local held=c.items and c.items.count or 0; local moved=math.min(n,item.count,w.capacity-held)
      if moved<=0 then return false,'full chest' end
      c.items=c.items or {name=item.name,count=0}; c.items.count=c.items.count+moved; item.count=item.count-moved; if item.count==0 then w.items[w.selected]=nil end
      w.drops=w.drops+1; if w.crashDrop then w.crashDrop=false; error('power lost after drop') end; return true
    end
  end
  local order={'north','east','south','west'}; local idx={north=1,east=2,south=3,west=4}
  t.turnRight=function() w.pose.heading=order[idx[w.pose.heading]%4+1]; return true end
  t.turnLeft=function() w.pose.heading=order[(idx[w.pose.heading]-2)%4+1]; return true end
  for a,s in pairs({forward='',up='Up',down='Down'}) do
    t[a]=function()
      local k=target(s); if w.chests[k] then return false,'obstruction' end
      local x,y,z=k:match('([^,]+),([^,]+),([^,]+)'); w.pose.x,w.pose.y,w.pose.z=tonumber(x),tonumber(y),tonumber(z); return true
    end
  end
  return w
end
local function worker(w,task,kind,c)
  c=c or {depot={x=0,y=1,z=0,heading='east'},supply={side='down'},minimumFuelReserve=0}
  local saved; local function save() saved=U.copy(task); return true end
  local nav=require('autobuilder.core.navigation').new(w.turtle,U.copy(w.pose),c,save)
  local ex=require('autobuilder.workers.'..kind).new(task,{turtle=w.turtle},c,nav,save)
  return ex,function() return saved end
end
local function finish(ex,task,resupply)
  for _=1,100 do
    local ok,err=ex:step()
    if resupply and ok then return true end
    if not resupply and (task.phase=='blocked' or task.phase=='completed') then return task.phase=='completed',err end
    if resupply and err and err~='resupply in progress' then return false,err end
  end
  error('logistics did not terminate')
end

test('supply stages bounded stock behind one durable exclusive owner',function()
  local w=wired(); local state={}; local ex=supply(w,state)
  eq(ex:offer('j1',7,'minecraft:stone',100),64); eq(w.inventories.stage[1].count,64); eq(w.inventories.stock[1].count,36)
  eq(ex:offer('j2',8,'minecraft:stone',1),nil); eq(w.transfers,1)
  eq(ex:offer('j1',7,'minecraft:stone',100),64); eq(w.transfers,1)
  assert(not ex:release('j1')); w.inventories.stage={}; assert(ex:release('j1')); eq(ex:offer('j2',8,'minecraft:stone',1),1)
end)
test('supply reconciles transfer crash and preserves protected fuel reserve',function()
  local w=wired(); w.crash=true; local ex,saved=supply(w,{})
  pcall(function() ex:offer('j',7,'minecraft:stone',20) end); local state=saved(); assert(state.supply.intent)
  ex=supply(w,state); eq(ex:offer('j',7,'minecraft:stone',20),20); eq(w.transfers,1); eq(w.inventories.stock[1].count,80)
  w=wired(); w.inventories.stock={[1]={name='minecraft:coal',count=70}}; ex=supply(w,{})
  eq(ex:offer('coal',7,'minecraft:coal',20),6); eq(w.inventories.stock[1].count,64)
end)
test('supply refuses foreign stage contents and reconciles partial capacity',function()
  local w=wired(); w.inventories.stage[1]={name='minecraft:dirt',count=1}; local ex=supply(w,{})
  eq(ex:offer('j',1,'minecraft:stone',4),nil); eq(w.transfers,0)
  w=wired(); w.capacity=3; ex=supply(w,{}); eq(ex:offer('j',1,'minecraft:stone',10),3); eq(w.inventories.stock[1].count,97)
end)
test('resupply waits for grant then pulls exact amount without changing owner phase',function()
  local w=carrier(); local task={phase='blocked',position={x=9,y=2,z=4},supplyRequest={item='minecraft:stone',count=5,granted=false}}
  local ex=worker(w,task,'resupply'); assert(not ex:step()); eq(w.sucks,0)
  task.supplyRequest.granted=true; task.supplyRequest.amount=5
  assert(finish(ex,task,true)); eq(task.phase,'blocked'); eq(task.position.x,9); eq(task.supplyRequest,nil); eq(task.lastSupply.count,5); eq(w.items[1].count,5); eq(w.chests['0,0,0'].items.count,27)
end)
test('resupply restart accounts a completed pull once',function()
  local w=carrier(); w.crashSuck=true
  local task={phase='blocked',supplyRequest={item='minecraft:stone',count=3,amount=3,granted=true}}
  local ex,saved=worker(w,task,'resupply'); pcall(function() finish(ex,task,true) end)
  task=saved(); assert(task.resupply.intent); ex=worker(w,task,'resupply'); assert(finish(ex,task,true)); eq(w.items[1].count,3); eq(w.chests['0,0,0'].items.count,29)
end)
test('resupply rejects wrong containers and full inventory without pulling',function()
  for _,full in ipairs({true,false}) do
    local w=carrier(); if full then for s=1,14 do w.items[s]={name='minecraft:dirt',count=64} end else w.chests['0,0,0'].name='minecraft:stone' end
    local task={supplyRequest={item='minecraft:stone',count=2,amount=2,granted=true}}; local ex=worker(w,task,'resupply')
    assert(not finish(ex,task,true)); eq(w.sucks,0)
  end
end)
test('courier delivers exact cargo and preserves unrelated held items',function()
  local w=carrier(); w.items[2]={name='minecraft:dirt',count=2}
  local task={source={x=0,y=1,z=0},destination={x=3,y=1,z=0},item='minecraft:stone',quantity=10}
  local ex=worker(w,task,'courier'); assert(finish(ex,task)); eq(task.delivered,10); eq(w.chests['3,0,0'].items.count,10); eq(w.chests['0,0,0'].items.count,22); eq(w.items[2].count,2)
end)
test('courier recovers interrupted delivery and blocks a full destination',function()
  local w=carrier(); w.crashDrop=true; local task={source={x=0,y=1,z=0},destination={x=3,y=1,z=0},item='minecraft:stone',quantity=5}
  local ex,saved=worker(w,task,'courier'); pcall(function() finish(ex,task) end)
  task=saved(); assert(task.cargo.intent); task.phase='work'; ex=worker(w,task,'courier'); assert(finish(ex,task)); eq(task.delivered,5); eq(w.chests['3,0,0'].items.count,5)
  w=carrier(); w.capacity=0; task={source={x=0,y=1,z=0},destination={x=3,y=1,z=0},item='minecraft:stone',quantity=5}; ex=worker(w,task,'courier')
  assert(not finish(ex,task)); eq(task.delivered,0); assert(w.items[1]); eq(w.drops,0)
end)
test('unowned matching supply stock is refused and a consumed grant is not restaged',function()
  local w=wired(); w.inventories.stage[1]={name='minecraft:stone',count=2}; local ex=supply(w,{})
  eq(ex:offer('j',1,'minecraft:stone',2),nil); eq(w.transfers,0)
  w=wired(); ex=supply(w,{}); eq(ex:offer('j',1,'minecraft:stone',5),5); w.inventories.stage={}
  eq(ex:offer('j',1,'minecraft:stone',5),5); eq(w.transfers,1)
end)
test('resupply keeps a fixed overhead route while reservations yield each movement',function()
  local w=carrier(); w.pose.x=3; local task={supplyRequest={item='minecraft:stone',count=2,amount=2,granted=true}}
  local config={depot={x=0,y=1,z=0},supply={side='down'},minimumFuelReserve=0}
  local nav=require('autobuilder.core.navigation').new(w.turtle,U.copy(w.pose),config,function() return true end)
  local original=nav.goTo; local grant=false; local maxY=0
  function nav:goTo(target)
    maxY=math.max(maxY,target.y)
    if not grant then grant=true; return false,'movement reservation pending' end
    grant=false; return original(self,target)
  end
  local ex=require('autobuilder.workers.resupply').new(task,{turtle=w.turtle},config,nav,function() return true end)
  for _=1,20 do if ex:step() then break end end
  eq(task.supplyRequest,nil); eq(maxY,3); eq(task.lastSupply.count,2)
end)
test('foreign incoming supply is retained with an unresolved intent and no success',function()
  local w=carrier(); w.chests['0,0,0'].items={name='minecraft:dirt',count=4}
  local task={supplyRequest={item='minecraft:stone',count=2,amount=2,granted=true}}; local ex=worker(w,task,'resupply')
  assert(not finish(ex,task,true)); assert(task.resupply.intent); eq(task.lastSupply,nil); eq(w.items[1].name,'minecraft:dirt')
end)
test('courier makes multiple trips and resumes after destination capacity returns',function()
  local w=carrier(); w.chests['0,0,0'].items.count=90
  local task={source={x=0,y=1,z=0},destination={x=3,y=1,z=0},item='minecraft:stone',quantity=70}
  local ex=worker(w,task,'courier'); assert(finish(ex,task)); eq(task.delivered,70); eq(w.chests['3,0,0'].items.count,70); eq(w.chests['0,0,0'].items.count,20)
  w=carrier(); w.capacity=0; task={source={x=0,y=1,z=0},destination={x=3,y=1,z=0},item='minecraft:stone',quantity=4}; ex=worker(w,task,'courier')
  assert(not finish(ex,task)); w.capacity=10; assert(ex:resume()); assert(finish(ex,task)); eq(task.delivered,4)
end)
test('resupply grant cannot exceed the amount originally requested',function()
  local w=carrier(); local task={supplyRequest={item='minecraft:stone',count=1,amount=5,granted=true}}; local ex=worker(w,task,'resupply')
  assert(not finish(ex,task,true)); eq(w.sucks,0)
end)
