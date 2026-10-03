local U=require('autobuilder.core.util')
local F=require('autobuilder.factory.factory')
local Q=require('autobuilder.core.workflows')
local Cargo=require('autobuilder.storage.returns')
local Nodes=require('autobuilder.storage.nodes')
local M={}
function M.new(app,config,e,queue,production)
  local s=queue.state;s.returns=s.returns or {};s.returnSequence=s.returnSequence or 0
  local save=function() return app:save() end
  local capacity=require('autobuilder.storage.capacity').new(app.state,save)
  local self={}
  function self:request(owner,key)
    assert(U.integer(owner) and owner>=0 and app.state.workers[tostring(owner)],'registered return worker required')
    for _,r in pairs(s.returns) do
      if key and r.key==key then assert(r.owner==owner,'changed return request');return r end
      if r.owner==owner and r.status~='completed' then return r end
    end
    local r
    F.commit(s,save,function()
      s.returnSequence=s.returnSequence+1;r={id='return:'..s.returnSequence,owner=owner,key=key,status='queued'};s.returns[r.id]=r
    end)
    return r
  end
  local function eligible(job)
    local w=app.state.workers[tostring(job.preferredWorker)];local t=w and w.telemetry
    assert(w and w.online and t and t.status=='idle' and not t.task and not Q.workerBusy(app.state,w.id,job.id),'waiting for idle return worker')
    assert(t.capabilities and t.capabilities.returnCargoV1 and Cargo.validCargo(t.cargo),'worker needs home cargo telemetry support')
    assert(not t.cargo.error,t.cargo.error)
    assert(t.position and t.position.known and U.position(t.position) and U.position(t.depot),'return requires known worker position and configured depot')
    assert(not job.paused and job.status~='completed','return request paused or completed')
    assert(not Q.factoryActive(app.state),'return waits for active factory inventory operation')
    local busy,why=Q.storageBusy(app.state,true);assert(not busy,why)
    return t
  end
  local function reserve(job)
    if job.returnReady then return end
    local t=eligible(job);local cargo=Cargo.cleanCargo(t.cargo);local home=U.copy(t.depot)
    local node,buffer,lease
    if next(cargo.items) then
      for _,candidate in ipairs(config.logistics.nodes) do for _,b in ipairs(candidate.buffers) do
        if U.distance(b.position,home)==0 then node=candidate;buffer=b end
      end end
      assert(node,'register a private logistics buffer at this worker depot for cargo return')
      assert(not next(F.list(e,buffer.inventory)),'home return buffer is not empty: '..buffer.inventory)
      local why
      lease,why=capacity:preview(job.id,{
        {inventory=buffer.inventory,items=cargo.items,limits=cargo.limits,exclusive=true},
        {inventory=node.inventory,items=cargo.items,limits=cargo.limits}},e)
      assert(lease,why)
    end
    local current=eligible(job)
    assert(F.equal(current.cargo,cargo) and U.distance(current.depot,home)==0,'worker cargo or depot changed during return observation')
    local before=U.copy(job)
    local ok,why=pcall(function()
      job.home=home;job.returnReady=true
      if lease then
        capacity.state.leases[job.id]=lease
        job.returning={node=Nodes.identity(node),buffer=U.copy(buffer),items=U.copy(cargo.items)}
        job.stockInputs={};job.stockOutputs=U.copy(cargo.items);job.returnFlow={collect={}}
        assert(require('autobuilder.storage.ledger').new(app.state,function() return true end):reserve(job.id,{},cargo.items,{}))
      end
      job.status='queued';job.error=nil;assert(save())
    end)
    if not ok then
      capacity.state.leases[job.id]=nil;production.ledger.state.leases[job.id]=nil
      for k in pairs(job) do job[k]=nil end;for k,v in pairs(before) do job[k]=v end;error(why,0)
    end
  end
  local function collect(job)
    local flows=job.returnFlow.collect;local c=job.returning
    for _,flow in pairs(flows) do if flow.intent then return F.reconcileTransfer(flow,e,save) end end
    assert(not Q.factoryActive(app.state),'return collection waits for active factory operation')
    local busy,why=Q.storageBusy(app.state,true);assert(not busy,why)
    local actual={}
    for _,v in pairs(F.list(e,c.buffer.inventory)) do assert(not v.nbt,'home buffer contains NBT cargo');actual[v.name]=(actual[v.name] or 0)+v.count end
    local remaining={};local items={}
    for item,count in pairs(c.items) do
      local n=flows[item] and flows[item].delivered or 0
      assert(n<=count,'home collection exceeds manifest')
      if n<count then remaining[item]=count-n;items[#items+1]=item end
    end
    assert(F.equal(actual,remaining),'home buffer differs from deposited cargo receipt')
    if #items==0 then
      capacity:release(job.id);F.commit(job,save,function() job.status='completed';job.error=nil end);return 'complete'
    end
    table.sort(items);local item=items[1]
    if not flows[item] then F.commit(flows,save,function() flows[item]={delivered=0} end) end
    local flow=flows[item];local offset=flow.delivered;local allocation
    local lease=assert(capacity.state.leases[job.id]);assert(lease.status=='held','home capacity already released')
    for _,a in ipairs(lease.nodes[c.node.inventory].allocations) do if a.item==item then
      if offset<a.count then allocation=a;break end;offset=offset-a.count
    end end
    assert(allocation,'home collection exceeds allocated capacity')
    local source=assert(F.sources(e,{storageInventories={c.buffer.inventory}},item)[1],'home cargo missing')
    local detail=e.peripheral.call(c.buffer.inventory,'getItemDetail',source.slot)
    local to=F.list(e,c.node.inventory)[allocation.slot]
    assert(not to or to.name==item and not to.nbt,'home output slot contaminated')
    local limit=e.peripheral.call(c.node.inventory,'getItemLimit',allocation.slot)
    assert(U.integer(limit) and limit>=0 and detail and U.integer(detail.maxCount) and detail.maxCount>0,'native home output capacity unavailable')
    local room=math.min(limit,detail.maxCount)-(to and to.count or 0);assert(room>0,'home output slot full')
    return F.transfer(flow,e,save,c.buffer.inventory,source.slot,c.node.inventory,allocation.slot,item,
      math.min(source.count,allocation.count-offset,room),c.buffer.inventory,-1,'delivered')
  end
  function self:step()
    local requests={};for _,r in pairs(s.returns) do if r.status~='completed' then requests[#requests+1]=r end end
    table.sort(requests,function(a,b) return a.id<b.id end)
    for _,r in ipairs(requests) do
      local job=r.jobId and s.jobs[r.jobId]
      if not job then
        job=queue:submit('RETURN_HOME',{preferredWorker=r.owner,returnManaged=true,returnRequest=r.id,returnReady=false},{},r.id)
        F.commit(r,save,function() r.jobId=job.id;r.status='running' end)
      end
      if job.status=='completed' then
        local w=app.state.workers[tostring(r.owner)];local t=w and w.telemetry
        if w and w.online and t and not t.task and t.status=='idle' and t.position and t.position.known and U.position(job.home)
          and U.distance(t.position,job.home)==0 and Cargo.validCargo(t.cargo) and not t.cargo.error and not next(t.cargo.items)
          and job.completedAt and w.lastSeen and w.lastSeen>job.completedAt then
          F.commit(r,save,function() r.status='completed';r.error=nil;r.settledAt=w.lastSeen end)
        else r.error='waiting for fresh home position and empty cargo acknowledgement' end
      elseif not job.paused then
        if not job.returnReady or job.workerFinished then
          local status,why=F.protect(function()
            if job.workerFinished then return collect(job) end
            reserve(job);return 'ready'
          end)
          if status=='blocked' then job.error=why;job.status='blocked';r.error=why;assert(save())
          else r.error=nil;production:syncClaims(false);return true end
        end
      end
    end
    return false
  end
  function self:describe()
    local lines={}
    for _,r in pairs(s.returns) do lines[#lines+1]=r.id..' worker='..r.owner..' '..r.status..' '..(r.error or '') end
    table.sort(lines);return #lines>0 and table.concat(lines,'; ') or 'No home returns requested'
  end
  return self
end
return M
