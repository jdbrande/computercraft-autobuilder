local U=require('autobuilder.core.util')
local function fixture()
 local f={task={id='task:7:9',type='RECOVER_CARGO',source={x=4,y=9,z=2},home={x=0,y=2,z=0},targetWorker=12,item='minecraft:diamond_pickaxe',nbt='tool-tag',quantity=1,recoveryId='recovery:7:1',recoverySequence=1},slots={[15]={name='minecraft:coal',count=3}},fuel=100,drops=0}
 f.nav={pose={x=0,y=2,z=0,heading='north',known=true},goTo=function(self,p) self.pose.x,self.pose.y,self.pose.z=p.x,p.y,p.z;return true end,face=function() return true end}
 f.e={turtle={getItemDetail=function(slot) return U.copy(f.slots[slot]) end,getFuelLevel=function() return f.fuel end,getItemSpace=function(slot) return f.slots[slot] and 64-f.slots[slot].count or 64 end,
 select=function(slot) f.selected=slot;return true end,inspectDown=function() return true,{name=f.nav.pose.x==4 and 'computercraft:turtle_advanced' or 'minecraft:chest'} end,
 dropDown=function(n)
  f.drops=f.drops+1;local i=f.slots[f.selected];local n=math.min(n,f.capacity or 64,i.count);i.count=i.count-n;if i.count==0 then f.slots[f.selected]=nil end
  if f.crash then f.crash=false;error('power loss after deposit') end;return n>0
 end},peripheral={getType=function() return 'turtle' end,call=function(_,method) eq(method,'getID');return f.impostor or 12 end}}
 function f:save() if self.fail then return false,'disk full' end;self.saved=U.copy(self.task);return true end
 function f:boot() self.actor=require('autobuilder.workers.inventory_courier').new(self.task,self.e,{minimumFuelReserve=0,depot=self.task.home},self.nav,function() return self:save() end) end
 function f:arrive() for _=1,10 do self.actor:step();if self.task.recoveryCargo and self.task.recoveryCargo.stage=='receiving' then return end end;error(self.task.error or 'did not arrive') end
 function f:receipt(n) return {jobId=self.task.id,sequence=1,moved=n} end
 f:boot();return f
end
test('inventory courier waits for donor identity and measured receipt then preserves tagged cargo on return',function()
 local f=fixture();f:arrive();eq(f.drops,0);eq(f.task.recoveryCargo.capacity,1)
 f.slots[1]={name=f.task.item,count=1,nbt='tool-tag'};assert(f.actor:received(f:receipt(1)));eq(f.drops,0)
 for _=1,10 do f.actor:step();if f.task.phase=='completed' then break end end
 eq(f.task.phase,'completed');eq(f.task.progress,1);eq(f.drops,1);eq(f.slots[1],nil);eq(f.slots[15].count,3)
 assert(f.actor:received(f:receipt(1)));eq(f.drops,1)
end)
test('inventory courier reconciles donor partial delivery and interrupted storage drop once',function()
 local f=fixture();f.task.item='minecraft:coal';f.task.nbt=nil;f.task.quantity=5;f:arrive()
 f.slots[15].count=5;assert(f.actor:received(f:receipt(2)));f.crash=true;f.actor:step()
 f.task=U.copy(f.saved);f:boot();for _=1,10 do f.actor:step();if f.task.phase=='completed' then break end end
 eq(f.task.phase,'completed');eq(f.task.progress,2);eq(f.slots[15].count,3);eq(f.drops,1)
end)
test('inventory courier refuses false receipts identity changes and unsafe departure fuel',function()
 local f=fixture();f.impostor=99;f.actor:step();eq(f.task.phase,'blocked');eq(f.drops,0)
 f=fixture();f.fuel=0;f.actor:step();eq(f.task.phase,'blocked');eq(f.nav.pose.x,0)
 f=fixture();f:arrive();assert(not f.actor:received(f:receipt(1)));eq(f.drops,0)
 f.slots[1]={name=f.task.item,count=1,nbt='wrong-tag'};assert(not f.actor:received(f:receipt(1)));eq(f.drops,0)
end)
