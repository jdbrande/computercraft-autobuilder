local U=require('autobuilder.core.util')
local F=require('autobuilder.factory.factory')
local Q=require('autobuilder.core.workflows')
local Messages=require('autobuilder.core.task_messages')
local M={}
function M.new(app,config,e,queue,production,network,clock)
  local s=queue.state;s.inventoryRecoveries=s.inventoryRecoveries or {};s.inventoryRecoverySequence=s.inventoryRecoverySequence or 0
  local save=function() return app:save() end
  local capacity=require('autobuilder.storage.capacity').new(app.state,save)
  local self={}
  function self:request(owner)
    assert(U.integer(owner) and owner>=0,'registered recovery worker required')
    for _,r in pairs(s.inventoryRecoveries) do if r.owner==owner then
      if (r.zeroTrips or 0)>=3 then F.commit(r,save,function() r.zeroTrips=0;r.error=nil end) end
      return r
    end end
    local w=app.state.workers[tostring(owner)];local t=w and w.telemetry
    assert(w and w.online and t and t.status=='blocked' and t.capabilities and t.capabilities.inventoryRecoveryV1,
      'recovery requires an online blocked worker with inventory recovery support')
    assert(U.position(t.position) and t.position.known and not t.position.pending and not t.position.uncertain,'confirmed donor position required')
    local j=s.jobs[t.task] or (app.state.jobs or {})[t.task]
    assert(j and j.workerId==owner and j.status=='blocked','blocked owned task required')
    local r
    F.commit(s,save,function()
      s.inventoryRecoverySequence=s.inventoryRecoverySequence+1
      r={id='recovery:'..s.inventoryRecoverySequence,owner=owner,originalTask=j.id,
        position={x=t.position.x,y=t.position.y,z=t.position.z},status='freezing',sequence=0,deposited={}}
      s.inventoryRecoveries[r.id]=r
    end)
    return r
  end
  function self:handle(owner,p)
    if not Messages.validate('task_inventory_status',p) then return false,'invalid donor status' end
    local r=s.inventoryRecoveries[p.jobId]
    if not r or r.owner~=owner or r.originalTask~=p.originalTask or not F.equal(r.position,p.position) then return false,'recovery owner mismatch' end
    if not r.inventory then
      if p.phase=='blocked' then F.commit(r,save,function() r.error=p.error or 'donor cannot freeze; reconcile its task first' end);return true end
      if p.phase~='frozen' or p.sequence~=0 or p.transfer or p.moved~=0 then return false,'initial frozen inventory required' end
      F.commit(r,save,function() r.inventory=U.copy(p.inventory);r.initial=U.copy(p.inventory);r.donor=U.copy(p);r.status='running';r.error=nil end)
      return true
    end
    local g=r.grant
    if p.sequence~=r.sequence then return false,'stale donor sequence' end
    if g then
      if not F.equal(p.transfer,g) then return false,'changed donor transfer' end
      if p.phase=='ready' then
        if r.moved~=nil or p.moved~=0 or not F.equal(p.inventory,r.inventory) then return false,'changed ready inventory' end
      elseif p.phase=='sent' or p.phase=='frozen' then
        if p.moved>g.count or r.moved~=nil and p.moved~=r.moved then return false,'changed delivery receipt' end
        local expected=U.copy(r.before);local item=expected[g.slot];item.count=item.count-p.moved;if item.count==0 then expected[g.slot]=nil end
        if not F.equal(expected,p.inventory) then return false,'donor delta differs from transfer' end
        if p.phase=='frozen' and not r.ackReady then return false,'donor acknowledged before courier receipt' end
      else return false,'invalid donor phase' end
    elseif p.phase~='frozen' or not F.equal(p.inventory,r.inventory) or not F.equal(p.transfer,r.lastGrant) then
      return false,'donor inventory changed outside transfer'
    end
    F.commit(r,save,function()
      r.donor=U.copy(p);r.error=p.error
      if g and (p.phase=='sent' or p.phase=='frozen') then r.moved=p.moved;r.inventory=U.copy(p.inventory) end
    end)
    return true
  end
  local function reserve(r)
    if r.buffer then return end
    local ids={};for id in pairs(app.state.workers) do ids[#ids+1]=tonumber(id) end;table.sort(ids)
    local last='no idle inventory recovery courier with registered empty home buffer'
    for _,id in ipairs(ids) do
      local w=app.state.workers[tostring(id)];local t=w.telemetry
      if id~=r.owner and w.online and t and t.status=='idle' and not t.task and t.capabilities
        and t.capabilities.inventoryRecoveryV1 and t.capabilities.courier
        and require('autobuilder.workers.health').eligible(t,{type='RECOVER_CARGO'}) and not Q.workerBusy(app.state,id)
        and U.position(t.position) and t.position.known and U.position(t.depot) then
        local source={x=r.position.x,y=r.position.y+1,z=r.position.z}
        local fuel=require('autobuilder.workers.fuel_courier').budget(t.position,source,t.depot,t.depot,config.minimumFuelReserve or 100)
        if t.fuel=='unlimited' or type(t.fuel)=='number' and t.fuel>=fuel then
          for _,node in ipairs(config.logistics.nodes) do for _,buffer in ipairs(node.buffers) do
            if U.distance(buffer.position,t.depot)==0 then
              local ok,why=pcall(function()
                assert(not next(F.list(e,buffer.inventory)),'recovery buffer is not empty: '..buffer.inventory)
                local count,limit=0,1;for _,v in pairs(r.initial) do count=count+1;limit=math.max(limit,v.count) end
                local lease,err=capacity:preview(r.id,{{inventory=buffer.inventory,emptySlots=count,minimumSlotLimit=limit,exclusive=true}},e)
                assert(lease,err)
                local current=w.telemetry
                assert(w.online and current and current.status=='idle' and not current.task and not Q.workerBusy(app.state,id)
                  and current.capabilities and current.capabilities.inventoryRecoveryV1 and current.capabilities.courier
                  and require('autobuilder.workers.health').eligible(current,{type='RECOVER_CARGO'})
                  and F.equal(current.position,t.position) and F.equal(current.depot,t.depot)
                  and (current.fuel=='unlimited' or type(current.fuel)=='number' and current.fuel>=fuel),'courier changed during recovery reservation')
                local before=U.copy(r)
                capacity.state.leases[r.id]=lease;r.courier=id;r.node=require('autobuilder.storage.nodes').identity(node);r.buffer=U.copy(buffer)
                local saved,result,err=pcall(save)
                if not saved or not result then
                  capacity.state.leases[r.id]=nil
                  for k in pairs(r) do r[k]=nil end;for k,v in pairs(before) do r[k]=v end
                  error('recovery checkpoint failed: '..tostring(saved and err or result),0)
                end
              end)
              if ok then return end;last=tostring(why)
            end
          end end
        end
      end
    end
    error(last,0)
  end
  local function totals(items)
    local out={}
    for _,v in pairs(items) do if v.count>0 then local key=v.name..'\0'..(v.nbt or '');out[key]=(out[key] or 0)+v.count end end
    return out
  end
  local function advance(r)
    if r.status=='completed' or r.status=='collecting' then return end
    if not r.inventory then
      network:send(r.owner,'task_inventory_freeze',{jobId=r.id,position=r.position,originalTask=r.originalTask});return
    end
    if not next(r.initial) then F.commit(r,save,function() r.status='completed' end);return end
    assert((r.zeroTrips or 0)<3,'repeated empty recovery transfers; check donor/courier inventories then retry worker recover '..r.owner)
    reserve(r)
    local j=r.jobId and s.jobs[r.jobId]
    if not j then
      local slot;for i=1,16 do if r.inventory[i] then slot=i;break end end
      if not slot then
        F.commit(r,save,function() r.status='collecting';r.collection={};r.error=nil end);return
      end
      local v=r.inventory[slot];local seq=r.sequence+1;assert(seq<=4096,'recovery transfer limit reached')
      j=queue:submit('RECOVER_CARGO',{preferredWorker=r.courier,recoveryReady=true,recoveryId=r.id,recoverySequence=seq,
        targetWorker=r.owner,source={x=r.position.x,y=r.position.y+1,z=r.position.z},home=U.copy(r.buffer.position),
        item=v.name,nbt=v.nbt,quantity=math.min(64,v.count),donorSlot=slot},{},r.id..':'..seq)
      F.commit(r,save,function() r.jobId=j.id end)
    end
    local receipt=j.recoveryReceipt
    if receipt and receipt.stage=='receiving' and not r.grant then
      assert(receipt.capacity>0 and receipt.capacity<=j.quantity,'invalid courier receiving capacity')
      F.commit(r,save,function()
        r.sequence=j.recoverySequence;r.before=U.copy(r.inventory)
        r.grant={sequence=r.sequence,slot=j.donorSlot,count=receipt.capacity,courier=r.courier,item=j.item,nbt=j.nbt}
      end)
    end
    if r.grant then
      if r.moved==nil then
        network:send(r.owner,'task_inventory_grant',{jobId=r.id,sequence=r.sequence,slot=r.grant.slot,count=r.grant.count,courier=r.courier})
      else
        if receipt and receipt.stage=='home' then
          assert(receipt.pickedUp==r.moved,'courier receipt differs from donor delivery')
          if not r.ackReady then F.commit(r,save,function() r.ackReady=true end) end
          network:send(r.owner,'task_inventory_ack',{jobId=r.id,sequence=r.sequence,moved=r.moved})
        else network:send(r.courier,'task_inventory_received',{jobId=j.id,sequence=r.sequence,moved=r.moved}) end
      end
    end
    if j.workerFinished and j.status~='completed' then
      assert(r.ackReady and receipt and receipt.delivered==r.moved,'recovery delivery lacks custody receipt')
      local expected=U.copy(r.deposited);expected[j.id]={name=j.item,nbt=j.nbt,count=r.moved}
      assert(F.equal(totals(F.list(e,r.buffer.inventory)),totals(expected)),'recovery buffer differs from measured delivery')
      F.commit(r,save,function() r.deposited=expected end)
      F.commit(j,save,function() j.status='completed';j.error=nil end)
    end
    if j.status=='completed' and r.donor.phase=='frozen' and r.donor.sequence==r.sequence then
      local w=app.state.workers[tostring(r.courier)];local t=w and w.telemetry
      if w and w.online and t and t.status=='idle' and not t.task then
        F.commit(r,save,function()
          r.zeroTrips=r.moved==0 and (r.zeroTrips or 0)+1 or 0
          r.jobId=nil;r.lastGrant=r.grant;r.grant=nil;r.before=nil;r.moved=nil;r.ackReady=nil;r.error=nil
        end)
      end
    end
  end
  local function collect(r)
    for _,flow in pairs(r.collection) do if flow.intent then return F.reconcileTransfer(flow,e,save) end end
    local remaining=U.copy(r.deposited);local items,limits={},{}
    for _,v in pairs(r.deposited) do if not v.nbt then
      items[v.name]=(items[v.name] or 0)+v.count;limits[v.name]=math.max(limits[v.name] or 1,v.count)
    end end
    local expected=totals(remaining);local pending={}
    for item,count in pairs(items) do
      local done=r.collection[item] and r.collection[item].delivered or 0
      assert(done<=count,'recovery collection exceeds deposited stock')
      local key=item..'\0';expected[key]=expected[key]-done;if expected[key]==0 then expected[key]=nil end
      if done<count then pending[#pending+1]=item end
    end
    assert(F.equal(expected,totals(F.list(e,r.buffer.inventory))),'recovery buffer differs from collected stock receipt')
    local stockId=r.id..':stock'
    if #pending==0 then
      if capacity.state.leases[stockId] then capacity:release(stockId) end
      capacity:release(r.id);F.commit(r,save,function() r.status='completed';r.error=nil end);return 'completed'
    end
    local lease,why=capacity:reserve(stockId,{{inventory=r.node.inventory,items=items,limits=limits}},e);assert(lease,why)
    table.sort(pending);local item=pending[1]
    if not r.collection[item] then F.commit(r.collection,save,function() r.collection[item]={delivered=0} end) end
    local flow=r.collection[item];local offset=flow.delivered;local allocation
    for _,a in ipairs(lease.nodes[r.node.inventory].allocations) do if a.item==item then
      if offset<a.count then allocation=a;break end;offset=offset-a.count
    end end
    assert(allocation,'recovery stock exceeds allocated capacity')
    local source=assert(F.sources(e,{storageInventories={r.buffer.inventory}},item)[1],'plain recovered stock missing')
    local detail=e.peripheral.call(r.buffer.inventory,'getItemDetail',source.slot)
    local to=F.list(e,r.node.inventory)[allocation.slot]
    assert(not to or to.name==item and not to.nbt,'recovery stock output contaminated')
    local limit=e.peripheral.call(r.node.inventory,'getItemLimit',allocation.slot)
    assert(U.integer(limit) and limit>=0 and detail and U.integer(detail.maxCount) and detail.maxCount>0,'native recovery stock capacity unavailable')
    local room=math.min(limit,detail.maxCount)-(to and to.count or 0);assert(room>0,'recovery stock output full')
    return F.transfer(flow,e,save,r.buffer.inventory,source.slot,r.node.inventory,allocation.slot,item,
      math.min(source.count,allocation.count-offset,room),r.buffer.inventory,-1,'delivered',nil,nil,true)
  end
  function self:step()
    for _,r in pairs(s.inventoryRecoveries) do if r.status=='collecting' then
      local status,why=F.protect(function() return collect(r) end)
      if status=='blocked' then r.error=why;assert(save()) else production:syncClaims(false) end
      return true
    end end
    return false
  end
  function self:tick()
    local ids={};for id in pairs(s.inventoryRecoveries) do ids[#ids+1]=id end;table.sort(ids)
    for _,id in ipairs(ids) do local r=s.inventoryRecoveries[id]
      if r.status~='completed' then
        local ok,why=pcall(advance,r)
        if not ok then r.error=tostring(why);assert(save()) end
      end
    end
  end
  function self:describe()
    local lines={};for _,r in pairs(s.inventoryRecoveries) do lines[#lines+1]=r.id..' worker='..r.owner..' '..r.status..' '..(r.error or '') end
    table.sort(lines);return #lines>0 and table.concat(lines,'; ') or 'No inventory recovery requested'
  end
  return self
end
return M
