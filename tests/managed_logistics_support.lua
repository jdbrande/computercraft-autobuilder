local U=require('autobuilder.core.util')
local F=require('autobuilder.factory.factory')
local M={}
function M.new()
  local f={inventories={base={[1]={name='minecraft:dirt',count=7},[2]={name='minecraft:stone',count=24}},site={},a={},b={},c={},d={}},transfers=0,now=100}
  f.config=require('tests.loaded_config').load({storageInventories={'base','site'},turtleFuelReserveItems={},logistics={batchSize=8,nodes={
    {id='base',inventory='base',position={x=0,y=0,z=0},buffers={{inventory='a',position={x=2,y=1,z=0}},{inventory='b',position={x=4,y=1,z=0}}}},
    {id='site',inventory='site',position={x=20,y=0,z=0},buffers={{inventory='c',position={x=22,y=1,z=0}},{inventory='d',position={x=24,y=1,z=0}}}}
  }}})
  f.e={os={epoch=function() return f.now*1000 end},peripheral={call=function(name,method,...)
    assert(name~=f.offline,'inventory disconnected: '..name)
    local inv=assert(f.inventories[name],'missing inventory '..name)
    if method=='list' then return U.copy(inv) end
    if method=='size' then return f.size or 3 end
    if method=='getItemLimit' then return 64 end
    if method=='getItemDetail' then local slot=...;local v=U.copy(inv[slot]);if v then v.maxCount=f.maxCount or 64 end;return v end
    assert(method=='pushItems','unexpected '..method)
    local destination,slot,limit,target=...;assert(destination~=f.offline,'destination disconnected')
    local to=assert(f.inventories[destination]);local item=inv[slot]
    if not item then return 0 end
    if not target then for i=1,f.size or 3 do if not to[i] or to[i].name==item.name and to[i].count<64 then target=i;break end end end
    if not target or to[target] and to[target].name~=item.name then return 0 end
    local n=math.min(limit,item.count,64-(to[target] and to[target].count or 0),f.partial or 64)
    if n==0 then return 0 end
    to[target]=to[target] or {name=item.name,count=0};to[target].count=to[target].count+n
    item.count=item.count-n;if item.count==0 then inv[slot]=nil end
    f.transfers=f.transfers+1
    if f.crashTransfer then f.crashTransfer=false;f.crashed=true;error('power loss after transfer') end
    return n
  end}}
  function f:boot(restart)
    self.crashed=false
    self.app={state=restart and U.copy(self.saved) or {workers={},jobs={}}}
    for id=12,13 do if not restart then self.app.state.workers[tostring(id)]={id=id,online=true,telemetry={status='idle',fuel=2000,
      position={x=id-10,y=1,z=2,known=true},capabilities={courier=true,logisticsV1=true,chunkCoverageV1=true}}} end end
    function self.app:save()
      if f.crashed then return false,'power lost' end
      f.saved=U.copy(self.state);return true
    end
    self.app.mining={storage=require('autobuilder.storage.storage').new(self.e.peripheral,self.config.storageInventories)}
    function self.app.mining:refresh() return self.storage:refresh() end
    self.queue=require('autobuilder.core.workflows').new(self.app.state,function() return self.app:save() end,function() return self.now end,7)
    self.production=require('autobuilder.core.production_service').new(self.app,self.config,self.e,self.queue)
    self.service=assert(self.production.logistics,'managed logistics service missing')
  end
  function f:step(n)
    for _=1,n or 1 do self.now=self.now+1;self.production:syncClaims();self.production:step() end
  end
  function f:jobs()
    local result={};for _,j in pairs(self.queue.state.jobs) do if j.logistics then result[#result+1]=j end end
    table.sort(result,function(a,b) return a.id<b.id end);return result
  end
  function f:deliver(j)
    assert(j.logisticsReady);j.workerId=j.preferredWorker;j.status='running'
    local from,to=self.inventories[j.logistics.pickup.inventory],self.inventories[j.logistics.drop.inventory]
    assert(not next(to));for k,v in pairs(from) do to[k]=v;from[k]=nil end
    assert(self.queue:progress(j.workerId,{jobId=j.id,phase='completed',progress=j.quantity,
      transportReceipt={sequence=2,pickedUp=j.quantity,delivered=j.quantity}}))
  end
  f:boot();return f
end
return M
