local U=require('autobuilder.core.util')
local function fixture()
 local f={app={state={id=12,position={x=4,y=8,z=2,known=true,heading='north'},currentTask={id='mine:1',type='MINE',phase='blocked',error='return obstructed'}}},slots={[1]={name='minecraft:stone',count=5},[16]={name='minecraft:diamond_pickaxe',count=1,nbt='tagged-tool'}},drops=0,receiver=13}
 function f.app:save() if self.fail then return false,'disk full' end;self.saved=U.copy(self.state);return true end
 f.e={turtle={getItemDetail=function(slot) return U.copy(f.slots[slot]) end,select=function(slot) f.selected=slot;return true end,
  inspectUp=function() return true,{name='computercraft:turtle_advanced'} end,
  dropUp=function(n)
   local i=f.slots[f.selected];n=math.min(n,i.count,f.capacity or 64);i.count=i.count-n;if i.count==0 then f.slots[f.selected]=nil end;f.drops=f.drops+1
   if f.crash then f.crash=false;error('power lost after drop') end;return n>0
  end},peripheral={getType=function() return 'turtle' end,call=function(_,method) eq(method,'getID');return f.receiver end}}
 f.contract={jobId='recovery:7:1',position={x=4,y=8,z=2},originalTask='mine:1'}
 function f:boot() self.r=require('autobuilder.workers.inventory_donor').new(self.app,self.e) end
 function f:grant(sequence,slot,count) return {jobId=self.contract.jobId,sequence=sequence,slot=slot,count=count,courier=13} end
 f:boot();return f
end
test('inventory donor quarantine preserves original task and controls never transfer items',function()
 local f=fixture();assert(f.r:freeze(f.contract));assert(f.r:active());eq(f.app.state.currentTask.id,'mine:1')
 assert(f.r:grant(f:grant(1,16,1)));eq(f.drops,0);f.app.busy=true;assert(f.r:step());f.app.busy=false;eq(f.drops,1);eq(f.slots[16],nil)
 local r=f.r:status();eq(r.phase,'sent');eq(r.moved,1);eq(r.transfer.item,'minecraft:diamond_pickaxe');eq(r.transfer.nbt,'tagged-tool')
 assert(f.r:ack({jobId=f.contract.jobId,sequence=1,moved=1}));assert(f.r:active());eq(f.r:status().phase,'frozen');eq(f.app.state.currentTask.phase,'blocked')
 assert(f.r:grant(f:grant(1,16,1)));assert(f.r:step());eq(f.drops,1)
end)
test('inventory donor partial transfer and after-effect reboot cannot repeat a physical drop',function()
 local f=fixture();assert(f.r:freeze(f.contract));assert(f.r:grant(f:grant(1,1,5)));f.capacity=2;f.crash=true;f.r:step()
 f.app.state=U.copy(f.app.saved);f:boot();assert(f.r:step());eq(f.r:status().moved,2);eq(f.drops,1);eq(f.slots[1].count,3)
 assert(not f.r:ack({jobId=f.contract.jobId,sequence=1,moved=5}));assert(f.r:ack({jobId=f.contract.jobId,sequence=1,moved=2}))
 assert(f.r:grant(f:grant(2,1,3)));f.capacity=64;assert(f.r:step());eq(f.drops,2);eq(f.slots[1],nil)
end)
test('inventory donor refuses wrong identity uncertain poses journals and changed grants',function()
 for _,kind in ipairs({'pose','busy','intent','pendingMove','nested','fuel'}) do
  local f=fixture()
  if kind=='pose' then f.app.state.position.pending={} elseif kind=='busy' then f.app.busy=true elseif kind=='nested' then f.app.state.currentTask.homeCargo={intent={}}
  elseif kind=='fuel' then f.app.state.fuelRecovery={} else f.app.state.currentTask[kind]={} end
  assert(not f.r:freeze(f.contract),kind);eq(f.drops,0)
 end
 local f=fixture();assert(f.r:freeze(f.contract));assert(f.r:grant(f:grant(1,1,5)))
 local bad=f:grant(1,1,4);assert(not f.r:grant(bad));f.receiver=99;assert(not f.r:step());eq(f.drops,0)
 f.receiver=13;f.slots[2]={name='minecraft:dirt',count=1};assert(not f.r:step());eq(f.drops,0)
end)
test('inventory donor failed checkpoints prevent side effects and retain quarantine',function()
 local f=fixture();f.app.fail=true;assert(not pcall(f.r.freeze,f.r,f.contract));assert(not f.r:active())
 f.app.fail=nil;assert(f.r:freeze(f.contract));assert(f.r:grant(f:grant(1,1,5)));f.app.fail=true
 assert(not f.r:step());eq(f.drops,0);assert(f.r:active())
end)
test('donor refuses unsettled supply acknowledgements and nested recovery cargo journals',function()
 local f=fixture();f.app.state.pendingSupplyAcks={['mine:1:supply:1']='mine:1'};assert(not f.r:freeze(f.contract))
 f=fixture();f.app.state.currentTask.recoveryCargo={intent={}};assert(not f.r:freeze(f.contract))
end)
