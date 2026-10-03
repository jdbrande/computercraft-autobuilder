-- Only Minecraft hardware is simulated here. All five worker runtimes, mining,
-- inventories, production, messages, projects, supply and placement are real modules.
local U=require('autobuilder.core.util')
local S=require('tests.support')
local Runtime=require('autobuilder.core.runtime')
local Config=require('autobuilder.config')
local function mc(name) return 'minecraft:'..name end
local function fixture(options)
  options=options or {}
  local f={inventories={stock={},stage={},input={},output={},furnace={}},actors={},now=100,
    stats={mined={},deposited={},smelted={},crafts=0,burned=0,pulled={},maxMining=0},assignments={}}
  local function change(inv,slot,item,delta)
    local old=inv[slot]; local count=(old and old.count or 0)+delta
    assert(count>=0 and (not old or old.name==item),'physical inventory underflow/mismatch')
    inv[slot]=count>0 and {name=item,count=count} or nil
  end
  local function move(from,slot,to,target,limit)
    local item=from[slot]; if not item then return 0 end
    if not target then for n=1,27 do if not to[n] or to[n].name==item.name and to[n].count<64 then target=n; break end end end
    if not target or to[target] and to[target].name~=item.name then return 0 end
    local count=math.min(limit or 64,item.count,64-(to[target] and to[target].count or 0)); local name=item.name
    change(from,slot,name,-count); change(to,target,name,count); return count,name
  end
  local peripheral={getNames=function() return {'right','stock','stage','input','output','furnace'} end,
    getType=function(name) return name=='right' and 'modem' or 'inventory' end,
    call=function(name,method,...)
      if name=='right' then assert(method=='isWireless'); return true end
      local inv=assert(f.inventories[name],'unknown inventory '..tostring(name))
      if method=='list' then return U.copy(inv) elseif method=='size' then return 27 end
      assert(method=='pushItems','unexpected inventory call '..method)
      local dest,slot,n,target=...; return move(inv,slot,assert(f.inventories[dest]),target,n)
    end}
  local function actor(id,settings,turtle,peripherals)
    local codec=S.codec(); codec.serializeJSON=codec.serialize; codec.unserializeJSON=codec.unserialize
    local e={fs=require('tests.install_support').fs(),textutils=codec,now=100,packets={},turtle=turtle,peripheral=peripherals or peripheral}
    e.os={getComputerID=function() return id end,epoch=function() return e.now*1000 end}
    e.rednet={isOpen=function() return true end,open=function() end,send=function(to,message,protocol)
      e.packets[#e.packets+1]={to=to,message=U.copy(message),protocol=protocol}; return true
    end}
    local a={id=id,e=e,config=Config.load(settings)}; f.actors[id]=a; a.runtime=Runtime.new(a.config,e); return a
  end
  local common={storageInventories={'stock'},furnaces={'furnace'},turtleFuelReserveItems={},minimumFuelReserve=0,
    craftingStation={input='input',output='output',inputSide='up',outputSide='down'},
    heartbeatInterval=1,registrationInterval=3,workerTimeout=8,gps={enabled=false},
    supply={inventory='stage',side='down',batch=64}}
  local cc=U.copy(common); cc.build={enabled=true,origin={x=2,y=0,z=0}}
  if options.exploration then cc.exploration={enabled=true,base={x=0,y=0,z=0},bounds={min={x=16,y=0,z=0},max={x=103,y=0,z=1}},baseProtection={min={x=-12,y=-1,z=-2},max={x=8,y=3,z=2}},dimensionMinY=-64,dimensionMaxY=319} end
  f.controller=actor(7,cc)
  local sources={{id=21,x=20,item='cobblestone',block='stone',count=4},
    {id=22,x=40,item='sand',block='sand',count=1},{id=23,x=60,item='coal',block='coal_ore',count=2}}
  if options.exploration then sources[#sources+1]={id=26,x=84,item='cobblestone',block='stone',count=4} end
  local sharedBlocks={}
  f.miners={}
  for _,source in ipairs(sources) do
    local w=require('tests.world').new(); w.pose.x=source.x; w.blocks=options.exploration and sharedBlocks or {}
    if options.finiteFuel then w.fuel=1000 end
    w.blocks[source.x..',-1,0']=mc('chest')
    for x=source.x+(options.exploration and 10 or 2),source.x+(options.exploration and 9 or 1)+source.count do w.blocks[x..',0,0']=mc(source.block) end
    local equipped=false; w.items[16]={name='advancedperipherals:geo_scanner',count=1}
    w.turtle.equipLeft=function() equipped=not equipped; w.items[16]={name=equipped and mc('diamond_pickaxe') or 'advancedperipherals:geo_scanner',count=1}; return true end
    w.turtle.dropDown=function()
      assert(w.pose.x==source.x and w.pose.y==0 and w.pose.z==0,'mining deposit must reach its physical depot')
      local n,item=move(w.items,w.selected,f.inventories.stock,nil,64)
      if n>0 then f.stats.deposited[item]=(f.stats.deposited[item] or 0)+n end
      return n>0
    end
    local p={getNames=function() return equipped and {'right','left'} or {'right'} end,
      getType=function(name) if name=='right' then return 'modem' elseif name=='left' and equipped then return 'geoScanner' end end,
      call=function(name,method,arg) if name=='right' then return true end; return w.peripheral.call(name,method,arg) end}
    local wc=U.copy(common); wc.role='worker'; wc.controllerId=7; wc.initialPosition=U.copy(w.pose)
    wc.depot={x=source.x,y=0,z=0}; wc.mining={enabled=true,resources={mc(source.item)},entry={x=source.x+1,y=0,z=0},
      bounds={min={x=source.x+1,y=0,z=-1},max={x=source.x+7,y=0,z=1}},fuelTarget=100}
    if options.exploration then wc.mining.mode='explore'; wc.mining.exitRoute={{x=source.x+1,y=0,z=0}}; wc.mining.bounds=nil; wc.mining.entry=nil end
    if options.scanner==false then p.getType=function(name) if name=='right' then return 'modem' end end; w.items[16]=nil end
    local a=actor(source.id,wc,w.turtle,p); a.world=w; a.source=source; f.miners[#f.miners+1]=a
  end
  local crafty={slots={},selected=1}; local t=S.turtle(); t.getFuelLevel=function() return 'unlimited' end
  t.getItemCount=function(slot) return crafty.slots[slot] and crafty.slots[slot].count or 0 end
  t.getItemDetail=function(slot) return U.copy(crafty.slots[slot]) end
  t.select=function(slot) crafty.selected=slot; return true end
  t.suckUp=function(n) for slot in pairs(f.inventories.input) do return move(f.inventories.input,slot,crafty.slots,crafty.selected,n)>0 end; return false end
  t.dropDown=function(n) return move(crafty.slots,crafty.selected,f.inventories.output,nil,n)>0 end
  t.craft=function(limit)
    eq(limit,1); eq(crafty.selected,13)
    for slot=1,16 do
      if slot==1 or slot==2 or slot==5 or slot==6 then
        assert(crafty.slots[slot] and crafty.slots[slot].name==mc('stone') and crafty.slots[slot].count==1,'stone bricks require four smelted stones in exact grid')
      else assert(not crafty.slots[slot],'non-grid slot must be empty') end
    end
    for _,slot in ipairs({1,2,5,6}) do change(crafty.slots,slot,mc('stone'),-1) end
    change(crafty.slots,13,mc('stone_bricks'),4); f.stats.crafts=f.stats.crafts+1; return true
  end
  local cw=U.copy(common); cw.role='worker'; cw.controllerId=7; cw.initialPosition={x=-10,y=2,z=0,heading='north'}; cw.automation={crafting=true}
  f.craft=actor(24,cw,t); f.craft.slots=crafty.slots
  local w=require('tests.build_world').new(); w.blocks['0,1,0']={name=mc('chest'),state={}}
  w.turtle.getItemSpace=function(slot) return 64-w.turtle.getItemCount(slot) end
  w.turtle.suckDown=function(n)
    assert(w.pose.x==0 and w.pose.y==2 and w.pose.z==0,'builder must physically return for supplies')
    for slot in pairs(f.inventories.stage) do
      local moved,item=move(f.inventories.stage,slot,w.items,w.selected,n)
      f.stats.pulled[item]=(f.stats.pulled[item] or 0)+moved; return moved>0
    end
    return false
  end
  local bw=U.copy(common); bw.role='worker'; bw.controllerId=7; bw.initialPosition=U.copy(w.pose)
  bw.depot={x=0,y=2,z=0}; bw.automation={building=true}
  f.builder=actor(25,bw,w.turtle); f.builder.world=w
  local bp={schema=1,size={x=3,y=1,z=1},palette={{name=mc('stone_bricks'),state={}},{name=mc('glass'),state={}}},
    runs={{id=1,count=2},{id=2,count=1}},metadata={},requirements={[mc('stone_bricks')]=2,[mc('glass')]=1}}
  f.controller.e.fs.files['/chain.json']=f.controller.e.textutils.serialize(bp)
  function f:pump()
    for _=1,15 do
      local any=false
      for _,a in pairs(self.actors) do
        local packets=a.e.packets; a.e.packets={}
        for _,p in ipairs(packets) do
          any=true
          if p.message.type=='mine_assign' then
            self.assignments[p.message.payload.item]=p.to
            self.assignmentOwners=self.assignmentOwners or {}; self.assignmentOwners[p.message.payload.item]=self.assignmentOwners[p.message.payload.item] or {}
            self.assignmentOwners[p.message.payload.item][p.to]=true
          elseif p.message.type=='mine_progress' and p.message.payload.exploration and p.message.payload.phase=='completed' and p.message.payload.delivered==0 then
            self.emptyTrip=true
          end
          assert(self.actors[p.to],'unknown packet recipient')
          self.actors[p.to].runtime:receive(p.message.sender,p.message,p.protocol)
        end
      end
      if not any then return end
    end
    error('network did not quiesce')
  end
  function f:smelt()
    local inv=self.inventories.furnace
    if inv[1] and (inv[2] or (self.burn or 0)>0) then
      local input=inv[1].name; local output=({[mc('sand')]=mc('glass'),[mc('cobblestone')]=mc('stone')})[input]
      assert(output,'unexpected furnace input')
      if (self.burn or 0)==0 then eq(inv[2].name,mc('coal')); change(inv,2,mc('coal'),-1); self.burn=8; self.stats.burned=self.stats.burned+1 end
      change(inv,1,input,-1); change(inv,3,output,1); self.burn=self.burn-1
      self.stats.smelted[output]=(self.stats.smelted[output] or 0)+1
    end
  end
  function f:step()
    self.now=self.now+1
    for _,a in pairs(self.actors) do a.e.now=self.now; if a.world then a.world.time=self.now end; a.runtime:tick() end
    self:pump()
    local active=0
    for _,job in pairs(self.controller.runtime.state.jobs) do if job.workerId and job.status~='completed' and not job.physicalComplete then active=active+1 end end
    self.stats.maxMining=math.max(self.stats.maxMining,active)
    for _,a in pairs(self.actors) do a.runtime:workStep(); self:pump() end
    self:smelt()
  end
  function f:count(name)
    local n=0; for _,stack in pairs(self.inventories.stock) do if stack.name==mc(name) then n=n+stack.count end end; return n
  end
  function f:reboot(a) a.e.packets={}; a.runtime=Runtime.new(a.config,a.e) end
  return f
end

test('autonomous project physically mines different materials in parallel then smelts crafts supplies builds and verifies across reboot',function()
  local f=fixture(); local c=f.controller.runtime
  assert(c:command('build import /chain.json chain')); assert(c:command('build auto chain'))
  eq(next(f.inventories.stock),nil); eq(next(f.builder.world.items),nil)
  local restarted=false
  for _=1,1600 do
    f:step()
    if f.stats.crafts==1 and not restarted then
      assert((f.stats.smelted[mc('stone')] or 0)==4,'crafting ran before smelting finished')
      f:reboot(f.controller); f:reboot(f.craft); restarted=true
    end
    local p=f.controller.runtime.state.automation.projects.chain
    if p.phase=='built' and not f.builder.runtime.state.currentTask and not f.craft.runtime.state.currentTask then break end
  end
  local p=f.controller.runtime.state.automation.projects.chain
  local errors={p.phase,p.error or ''}
  for _,r in pairs(f.controller.runtime.state.automation.requests) do errors[#errors+1]=r.status..':'..tostring(r.error) end
  for id,a in pairs(f.actors) do local task=a.runtime.state.currentTask; if task then errors[#errors+1]=id..':'..task.phase..':'..tostring(task.error) end end
  assert(p.phase=='built',table.concat(errors,'; '))
  assert(restarted); assert(f.stats.maxMining>=2,'different material miners never held concurrent physical jobs')
  eq(f.assignments[mc('cobblestone')],21); eq(f.assignments[mc('sand')],22); eq(f.assignments[mc('coal')],23)
  for _,a in ipairs(f.miners) do
    eq(#a.world.dug,a.source.count); eq(f.stats.deposited[mc(a.source.item)],a.source.count)
    eq(a.runtime.state.currentTask,nil); eq(a.world.pose.x,a.source.x)
  end
  eq(f.stats.crafts,1); eq(f.stats.smelted[mc('stone')],4); eq(f.stats.smelted[mc('glass')],1)
  eq(f:count('cobblestone'),0); eq(f:count('sand'),0); eq(f:count('stone'),0); eq(f:count('stone_bricks'),2); eq(f:count('glass'),0)
  local furnaceCoal=f.inventories.furnace[2] and f.inventories.furnace[2].count or 0
  eq(f:count('coal')+furnaceCoal+f.stats.burned,2)
  eq(f.stats.pulled[mc('stone_bricks')],2); eq(f.stats.pulled[mc('glass')],1)
  eq(f.builder.world.places,3); eq(p.report.counts.correct,3)
  eq(f.builder.world.blocks['2,0,0'].name,mc('stone_bricks')); eq(f.builder.world.blocks['3,0,0'].name,mc('stone_bricks'))
  eq(f.builder.world.blocks['4,0,0'].name,mc('glass')); eq(next(f.inventories.stage),nil); eq(next(f.craft.slots),nil)
end)

for _,scan in ipairs({true,false}) do
  test('exploration fleet discovers shares and builds a schematic with scanner '..tostring(scan),function()
    local f=fixture({exploration=true,scanner=scan,finiteFuel=true}); local c=f.controller.runtime
    assert(c:command('build import /chain.json explore')); assert(c:command('build auto explore'))
    local restarted=false
    for i=1,5000 do
      f:step()
      if not restarted and f.miners[1].runtime.state.currentTask and f.miners[1].runtime.state.currentTask.phase=='work' then
        f:reboot(f.controller); f:reboot(f.miners[1]); restarted=true
      end
      local p=f.controller.runtime.state.automation.projects.explore
      if p.phase=='built' and not f.builder.runtime.state.currentTask and not f.craft.runtime.state.currentTask then break end
    end
    local p=f.controller.runtime.state.automation.projects.explore
    local errors={p.phase,p.error or ''}
    for _,r in pairs(f.controller.runtime.state.automation.requests) do errors[#errors+1]=r.status..':'..tostring(r.error) end
    for id,a in pairs(f.actors) do local t=a.runtime.state.currentTask; if t then errors[#errors+1]=id..':'..t.phase..':'..tostring(t.error) end end
    assert(p.phase=='built',table.concat(errors,'; ')); assert(restarted); assert(f.emptyTrip,'expected automatic advance after an empty sector')
    assert(f.assignmentOwners[mc('cobblestone')][21] and f.assignmentOwners[mc('cobblestone')][26])
    eq(p.report.counts.correct,3); eq(f.builder.world.places,3)
    for _,a in ipairs(f.miners) do eq(a.runtime.state.currentTask,nil); eq(a.world.pose.x,a.source.x) end
  end)
end
