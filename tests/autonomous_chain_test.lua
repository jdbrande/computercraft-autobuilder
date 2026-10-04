-- Only Minecraft hardware is simulated here. All five worker runtimes, mining,
-- inventories, production, messages, projects, supply and placement are real modules.
local U=require('autobuilder.core.util')
local S=require('tests.support')
local Runtime=require('autobuilder.core.runtime')
local Config=require('tests.loaded_config')
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
    local a={id=id,e=e,config=Config.load(settings),enabled=id~=options.delayedMiner}; f.actors[id]=a; a.runtime=Runtime.new(a.config,e); return a
  end
  local common={storageInventories={'stock'},furnaces={'furnace'},turtleFuelReserveItems={},minimumFuelReserve=0,
    craftingStation={input='input',output='output',inputSide='up',outputSide='down'},
    heartbeatInterval=1,registrationInterval=3,workerTimeout=8,gps={enabled=false},
    supply={inventory='stage',side='down',batch=64}}
  local cc=U.copy(common); cc.build={enabled=true,origin={x=2,y=0,z=0},regionSize=options.parallelBuilders and 2 or 8}
  if options.parallelBuilders then
    f.inventories.stage2={}
    cc.supply={inventory='',batch=2}
    cc.supplyStations={{workerId=25,inventory='stage',position={x=0,y=2,z=0},side='down'},
      {workerId=28,inventory='stage2',position={x=12,y=2,z=0},side='down'}}
  end
  cc.scaling={roles={mining={min=options.scaling and 0 or (options.exploration and 4 or 3)}}}
  if options.parallelBuilders then cc.scaling.roles.building={min=2};cc.scaling.roles.clearing={min=2} end
  if options.exploration then cc.exploration={enabled=true,base={x=0,y=0,z=0},bounds={min={x=16,y=0,z=0},max={x=103,y=0,z=1}},baseProtection={min={x=-12,y=-1,z=-2},max={x=8,y=3,z=2}},dimensionMinY=-64,dimensionMaxY=319} end
  f.controller=actor(7,cc)
  local sources={{id=21,x=20,item='cobblestone',block='stone',count=options.fill and 5 or 4},
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
  local cw=U.copy(common); cw.role='worker'; cw.controllerId=7; cw.initialPosition={x=-10,y=2,z=0,heading='north'}; cw.depot=U.copy(cw.initialPosition); cw.automation={crafting=true}
  f.craft=actor(24,cw,t); f.craft.slots=crafty.slots
  local builderBlocks={['0,1,0']={name=mc('chest'),state={}}}
  -- Solid prepared support; terrain mutations have separate exact-yield fixtures.
  for x=2,4 do builderBlocks[x..','..(options.fill and x==3 and -2 or -1)..',0']={name=mc('stone'),state={}} end
  if options.parallelBuilders then for x=1,9 do for z=-1,1 do builderBlocks[x..',-1,'..z]={name=mc('stone'),state={}} end end end
  f.builders={}
  for _,id in ipairs(options.parallelBuilders and {25,28} or {25}) do
    local w=require('tests.build_world').new();w.blocks=builderBlocks
    local home={x=id==25 and 0 or 12,y=2,z=0,heading='north'};w.pose=U.copy(home);w.pose.known=true
    local inventory=id==25 and 'stage' or 'stage2';builderBlocks[home.x..',1,0']={name=mc('chest'),state={}}
    w.turtle.getItemSpace=function(slot) return 64-w.turtle.getItemCount(slot) end
    w.turtle.suckDown=function(n)
      assert(U.distance(w.pose,home)==0,'builder must physically return for supplies')
      for slot in pairs(f.inventories[inventory]) do
        local moved,item=move(f.inventories[inventory],slot,w.items,w.selected,n)
        f.stats.pulled[item]=(f.stats.pulled[item] or 0)+moved; return moved>0
      end
      return false
    end
    if options.parallelBuilders then
      for _,action in ipairs({'place','placeUp','placeDown'}) do local original=w.turtle[action];w.turtle[action]=function(...)
        local ok,why=original(...)
        if ok then
          for _,miner in ipairs(f.miners) do
            local task=miner.runtime.state.currentTask
            if task and task.phase~='completed' and not task.paused and U.distance(miner.world.pose,miner.config.depot)>0 then
              f.stats.overlapPlacement={builder=id,miner=miner.id,task=task.id,at=f.now}
            end
          end
        end
        return ok,why
      end end
      w.fuel=8000;w.turtle.getFuelLevel=function() return w.fuel end
      for _,action in ipairs({'forward','up','down'}) do local original=w.turtle[action];w.turtle[action]=function()
        if w.fuel==0 then return false,'out of fuel' end
        local ok,why=original()
        if ok then
          for _,other in ipairs(f.builders) do if other.id~=id then assert(U.distance(other.world.pose,w.pose)>0,'physical builder collision') end end
          w.fuel=w.fuel-1
        end
        return ok,why
      end end
    end
    local bw=U.copy(common);bw.role='worker';bw.controllerId=7;bw.initialPosition=U.copy(home)
    bw.depot=U.copy(home);bw.automation={building=true};bw.supply.inventory=inventory
    local builder=actor(id,bw,w.turtle);builder.world=w;f.builders[#f.builders+1]=builder
    if id==25 then f.builder=builder end
  end
  local bp={schema=1,size={x=3,y=1,z=1},palette={{name=mc('stone_bricks'),state={}},{name=mc('glass'),state={}}},
    runs={{id=1,count=2},{id=2,count=1}},metadata={},requirements={[mc('stone_bricks')]=2,[mc('glass')]=1}}
  if options.parallelBuilders then
    -- Independent building regions have a real gap beyond traffic exclusion.
    bp.size.x=7;bp.palette[3]={name=mc('air'),state={}};bp.runs={{id=1,count=2},{id=3,count=4},{id=2,count=1}}
  end
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
    for _,a in pairs(self.actors) do a.e.now=self.now; if a.world then a.world.time=self.now end;if a.enabled then a.runtime:tick() end end
    self:pump()
    local active=0
    for _,job in pairs(self.controller.runtime.state.jobs) do if job.workerId and job.status~='completed' and not job.physicalComplete then active=active+1 end end
    self.stats.maxMining=math.max(self.stats.maxMining,active)
    for _,a in pairs(self.actors) do if a.enabled then a.runtime:workStep(); self:pump() end end
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
    local delivered,clear,observations={},0,0
    for _,record in pairs(f.controller.runtime.state.exploration.sectors) do
      for item,h in pairs(record.outcomes or {}) do delivered[item]=(delivered[item] or 0)+h.delivered end
      for _,v in ipairs(record.evidence or {}) do if v.kind=='clear' then clear=clear+1 end end
      observations=observations+#record.observations
    end
    for item,count in pairs(f.stats.deposited) do eq(delivered[item],count) end
    assert(clear>0 and observations>0,'physical learning did not survive runtime restarts')
    for _,a in ipairs(f.miners) do eq(a.runtime.state.currentTask,nil); eq(a.world.pose.x,a.source.x) end
  end)
end


test('automatic preparation acquires additional foundation fill while structural production drains raw stock',function()
  local f=fixture({fill=true,finiteFuel=true});local c=f.controller.runtime
  assert(c:command('build import /chain.json fill_shortage'));assert(c:command('build auto fill_shortage'))
  eq(next(f.inventories.stock),nil);eq(next(f.builder.world.items),nil)
  for _=1,6000 do
    f:step();local p=f.controller.runtime.state.automation.projects.fill_shortage
    if p.phase=='built' and not f.builder.runtime.state.currentTask then break end
  end
  local p=f.controller.runtime.state.automation.projects.fill_shortage
  local errors={p.phase,tostring(p.error)}
  for _,r in pairs(f.controller.runtime.state.automation.requests) do errors[#errors+1]=r.status..':'..tostring(r.error) end
  for id,a in pairs(f.actors) do local t=a.runtime.state.currentTask;if t then errors[#errors+1]=id..':'..t.phase..':'..tostring(t.error) end end
  assert(p.phase=='built',table.concat(errors,'; '))
  eq(f.stats.deposited[mc('cobblestone')],5);eq(f.stats.smelted[mc('stone')],4)
  eq(f.stats.pulled[mc('cobblestone')],1);eq(f.builder.world.blocks['3,-1,0'].name,mc('cobblestone'))
  eq(f.builder.world.places,4);eq(p.report.counts.correct,3)
  for _,a in ipairs(f.miners) do assert(a.world.fuel>0 and a.world.fuel<1000) end
end)


test('late registered miner joins costly shared demand automatically and the fleet drains across restart',function()
  local f=fixture({exploration=true,scanner=false,finiteFuel=true,scaling=true,delayedMiner=26})
  local ok,id=f.controller.runtime:command('request minecraft:cobblestone 8');assert(ok,id)
  local joined,restarted=false,false
  for _=1,6000 do
    f:step()
    if not joined and f.emptyTrip then
      assert(not f.controller.runtime.state.workers['26']);f.actors[26].enabled=true;joined=true
    end
    if not restarted and f.stats.maxMining>=2 then f:reboot(f.controller);restarted=true end
    local r=f.controller.runtime.state.automation.requests[id]
    local busy=false;for _,a in ipairs(f.miners) do busy=busy or a.runtime.state.currentTask~=nil end
    if r.status=='completed' and not busy then break end
  end
  local c=f.controller.runtime;local r=c.state.automation.requests[id]
  assert(r.status=='completed',tostring(r.error));assert(joined and restarted)
  assert(f.assignmentOwners[mc('cobblestone')][21] and f.assignmentOwners[mc('cobblestone')][26])
  eq(f:count('cobblestone'),8);eq(f.stats.deposited[mc('cobblestone')],8)
  for _,a in ipairs(f.miners) do assert(not a.runtime.state.currentTask);eq(a.world.pose.x,a.source.x);assert(a.world.fuel>0) end
  for _=1,5 do f:step() end
  local view=require('autobuilder.core.scaling').snapshot(c.state,c.config,c.mining.storage.counts,f.now)
  eq(view.mining.active,0);eq(view.mining.desired,0)
  assert(c.state.fleet.metrics.mining.count>1);assert(#c.state.fleet.decisions>0)
end)

test('early builder top-up launches real exploration while its last held block remains across restarts',function()
  local f=fixture({exploration=true,scanner=false,finiteFuel=true})
  f.builder.world.items[1]={name=mc('cobblestone'),count=1}
  local q=f.controller.runtime.automation.queue
  local job=q:submit('BUILD',{clearanceY=2,blocks={{x=2,y=0,z=0,name=mc('cobblestone'),state={}}, {x=3,y=0,z=0,name=mc('cobblestone'),state={}}}},{})
  local early,restarted=false,false
  for _=1,5000 do
    f:step()
    local active=false
    for _,a in ipairs(f.miners) do
      local task=a.runtime.state.currentTask
      if task and task.phase=='work' then active=true end
    end
    if active and not early then
      eq(f.builder.world.places,0);eq(f.builder.world.turtle.getItemCount(1),1);early=true
      f:reboot(f.controller);f:reboot(f.builder);restarted=true
    end
    local complete=f.controller.runtime.state.automation.jobs[job.id].status=='completed'
    local busy=false;for _,a in ipairs(f.miners) do busy=busy or a.runtime.state.currentTask~=nil end
    local settled=true;for _,r in pairs(f.controller.runtime.state.automation.requests) do if r.status~='completed' then settled=false end end
    if complete and settled and not busy and not f.builder.runtime.state.currentTask then break end
  end
  assert(early and restarted,'exploration did not begin before the last held block was spent')
  local c=f.controller.runtime;eq(c.state.automation.jobs[job.id].status,'completed')
  eq(f.builder.world.places,2)
  assert(f.stats.deposited[mc('cobblestone')]==1, f.controller.e.textutils.serialize({deposited=f.stats.deposited,pulled=f.stats.pulled,requests=c.state.automation.requests,groups=c.state.exploration.groups,jobs=c.state.jobs}))
  eq(f.stats.pulled[mc('cobblestone')],1)
  eq(f:count('cobblestone'),0);eq(next(f.inventories.stage),nil);eq(next(f.builder.world.items),nil)
  eq(f.builder.world.blocks['2,0,0'].name,mc('cobblestone'));eq(f.builder.world.blocks['3,0,0'].name,mc('cobblestone'))
  for _,r in pairs(c.state.automation.requests) do eq(r.status,'completed') end
  for _,a in ipairs(f.miners) do eq(a.runtime.state.currentTask,nil);eq(a.world.pose.x,a.source.x);assert(a.world.fuel>0) end
end)


test('automatic pipeline overlaps finite production with multiple prepared-region builders across restart',function()
  local f=fixture({parallelBuilders=true,finiteFuel=true});local c=f.controller.runtime
  assert(c:command('build import /chain.json pipeline'))
  -- Make both independent regions eligible before measuring production overlap.
  -- Ordinary automatic terrain admission is covered by the other runtime cases.
  assert(c:command('build level pipeline'))
  for _=1,2000 do f:step();if c.state.automation.projects.pipeline.phase=='site_ready' then break end end
  eq(c.state.automation.projects.pipeline.phase,'site_ready');eq(next(f.inventories.stock),nil)
  assert(c:command('build auto pipeline'))
  eq(c.state.automation.projects.pipeline.requestId,nil)
  local overlap,restarted=false,false;local buildOwners={}
  for _=1,5000 do
    f:step()
    for _,b in ipairs(f.builders) do local t=b.runtime.state.currentTask;if t and t.type=='BUILD' then buildOwners[b.id]=true end end
    if f.stats.overlapPlacement then
      overlap=true
      if not restarted then f:reboot(f.controller);for _,b in ipairs(f.builders) do f:reboot(b) end;restarted=true end
    end
    local p=f.controller.runtime.state.automation.projects.pipeline
    if p.phase=='built' then break end
  end
  local s=f.controller.runtime.state;local p=s.automation.projects.pipeline
  assert(overlap,'no measured placement while later production remained active');assert(restarted)
  assert(buildOwners[25] and buildOwners[28],'construction did not use both builders')
  assert(p.phase=='built',p.phase..':'..tostring(p.error));eq(p.report.counts.correct,7)
  for _,b in ipairs(f.builders) do eq(b.runtime.state.currentTask,nil);eq(next(b.world.items),nil);eq(U.distance(b.world.pose,b.config.depot),0);assert(b.world.fuel>0 and b.world.fuel<8000) end
  for _,a in ipairs(f.miners) do eq(a.runtime.state.currentTask,nil);eq(a.world.pose.x,a.source.x) end
  for _,r in pairs(s.automation.requests) do eq(r.status,'completed');assert(r.key:sub(1,8)~='project:') end
  eq(s.automation.supply,nil);eq(next(f.inventories.stage),nil);eq(next(f.inventories.stage2),nil)
  eq(f.stats.crafts,1);eq(f.stats.smelted[mc('stone')],4);eq(f.stats.smelted[mc('glass')],1)
  eq(f.stats.deposited[mc('cobblestone')],4);eq(f.stats.deposited[mc('sand')],1)
  eq(f.stats.pulled[mc('stone_bricks')],2);eq(f.stats.pulled[mc('glass')],1);eq(f:count('stone_bricks'),2)
end)

test('streaming project pause retains active exploration groups across restart and resumes same demand',function()
  local f=fixture({exploration=true,scanner=false,finiteFuel=true});local c=f.controller.runtime
  assert(c:command('build import /chain.json paused_pipeline'));assert(c:command('build auto paused_pipeline'))
  local request,group
  for _=1,2000 do
    f:step()
    for _,r in pairs(c.state.automation.requests) do for _,id in pairs(r.acquisitions or {}) do
      local g=c.state.exploration.groups[id]
      if g and #g.tripIds>0 then request=r;group=g end
    end end
    if group then break end
  end
  assert(group);local rid,gid=request.id,group.id;local sequence=c.state.jobSequence
  assert(c:command('build pause paused_pipeline'));eq(request.paused,true);eq(group.paused,true)
  f:reboot(f.controller);c=f.controller.runtime
  for _=1,50 do f:step() end
  eq(c.state.exploration.groups[gid].paused,true);eq(c.state.jobSequence,sequence)
  eq(c.state.automation.requests[rid].paused,true);eq(f.builder.world.places,0)
  for _,j in pairs(c.state.automation.jobs) do assert(j.type~='CRAFT' and j.type~='SMELT','paused acquisition created factory work') end
  assert(c:command('build resume paused_pipeline'));eq(c.state.exploration.groups[gid].paused,false);eq(c.state.automation.requests[rid].paused,false)
end)
