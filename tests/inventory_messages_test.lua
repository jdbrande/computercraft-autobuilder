local U=require('autobuilder.core.util')
local V=require('autobuilder.core.task_messages').validate
local contract={jobId='recovery:7:1',position={x=4,y=8,z=2},originalTask='mine:1'}
test('inventory recovery protocol bounds identities snapshots and transfer quantities',function()
 assert(V('task_inventory_freeze',contract))
 local grant={jobId=contract.jobId,sequence=1,slot=16,count=1,courier=13};assert(V('task_inventory_grant',grant))
 local status={jobId=contract.jobId,position=contract.position,originalTask=contract.originalTask,phase='frozen',sequence=0,moved=0,inventory={[16]={name='minecraft:diamond_pickaxe',count=1,nbt='hash'}}}
 assert(V('task_inventory_status',status))
 for _,change in ipairs({function(s) s.inventory[17]={name='stone',count=1} end,function(s) s.inventory[16].count=0 end,
  function(s) s.inventory[16].nbt={} end,function(s) s.sequence=-1 end,function(s) s.position.x='4' end}) do
  local bad=U.copy(status);change(bad);assert(not V('task_inventory_status',bad))
 end
 for _,kind in ipairs({'task_inventory_ack','task_inventory_received'}) do
  assert(V(kind,{jobId=contract.jobId,sequence=1,moved=0}));assert(not V(kind,{jobId=contract.jobId,sequence=1,moved=65}))
 end
 grant.slot=17;assert(not V('task_inventory_grant',grant));contract.originalTask=nil;assert(not V('task_inventory_freeze',contract));contract.originalTask='mine:1'
end)
test('recovery courier assignments and progress carry a bounded custody receipt',function()
 local j={id='task:7:2',type='RECOVER_CARGO',source={x=4,y=9,z=2},home={x=0,y=2,z=0},targetWorker=12,item='minecraft:stone',quantity=5,recoveryId=contract.jobId,recoverySequence=1}
 assert(V('task_assign',{job=j}));j.quantity=65;assert(not V('task_assign',{job=j}));j.quantity=5
 local p={jobId=j.id,phase='work',progress=0,recoveryReceipt={sequence=1,stage='receiving',capacity=5,pickedUp=0,delivered=0}}
 assert(V('task_progress',p));p.recoveryReceipt.pickedUp=6;assert(not V('task_progress',p))
 p.recoveryReceipt.pickedUp=3;p.recoveryReceipt.delivered=4;assert(not V('task_progress',p))
end)
