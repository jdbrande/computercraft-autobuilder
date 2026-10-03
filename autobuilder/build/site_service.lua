local U=require('autobuilder.core.util')
local F=require('autobuilder.factory.factory')
local Survey=require('autobuilder.build.site_survey')
local Checkpoint=require('autobuilder.core.checkpoint')
local E=require('autobuilder.resources.exploration')
local Access=require('autobuilder.build.site_access')
local M={}
function M.new(app,config,e,queue,production)
  local self={};local s=queue.state
  local function save() return app:save() end
  local function contract(plan,region,height)
    local job=plan:survey(region,1,64)
    job.clearanceY=height;job.bounds.max.y=height
    for _,c in ipairs(job.siteSurvey.columns) do c.clearanceY=height end
    return job
  end
  local function store(p,plan,region)
    assert(p.site and p.site.identity==plan.identity,'site geometry changed during preparation')
    assert(U.integer(region) and region>=1 and region<=plan.regionCount,'invalid site evidence region')
    local path=config.dataDir..'/sites/'..p.name..'/'..plan.identity..'/'..p.site.generation..'/'..region
    return Checkpoint.new(e.fs,e.textutils,path),path
  end
  function self:evidence(p,plan,region)
    local cp,path=store(p,plan,region);local record,why=cp:load()
    if not record then return nil,why end
    if record.identity~=plan.identity or record.region~=region or not U.shortString(record.jobId,160)
      or not U.integer(record.clearanceY) or record.clearanceY<plan.bounds.max.y or record.clearanceY>plan.maxY
      or not Survey.validReport(contract(plan,region,record.clearanceY),record.report,true) then return nil,'invalid site evidence' end
    local w=record.preparation
    if record.recovery~=nil and (not U.integer(record.recovery) or record.recovery<0) then return nil,'invalid site recovery generation' end
    if record.preparationRetries~=nil and (not U.integer(record.preparationRetries) or record.preparationRetries<0 or record.preparationRetries>3)
      or record.retryPending~=nil and type(record.retryPending)~='boolean'
      or record.fluidRechecked~=nil and type(record.fluidRechecked)~='boolean'
      or record.containmentRechecked~=nil and type(record.containmentRechecked)~='boolean'
      or record.retryHistory~=nil and (type(record.retryHistory)~='table' or #record.retryHistory>3) then return nil,'invalid preparation retry evidence' end
    if record.retryPending and (type(w)~='table' or w.status~='blocked' or w.stage~='verified' or not record.preparationRetries or record.preparationRetries<1) then
      return nil,'invalid pending preparation retry'
    end
    if w~=nil then
      if type(w)~='table' or not ({working=true,prepared=true,blocked=true})[w.status]
        or not ({clear=true,seal=true,fill=true,verify_fill=true,verify_clear=true,verified=true})[w.stage]
        or not U.integer(w.sequence) or w.sequence<1 or not U.integer(w.cursor) or w.cursor<0 or w.cursor>262145
        or not U.integer(w.failed) or w.failed<0 or type(w.defects)~='table' or #w.defects>64
        or w.epoch~=nil and (not U.integer(w.epoch) or w.epoch<0)
        or w.jobId~=nil and not U.shortString(w.jobId,160)
        or w.nextCursor~=nil and (not U.integer(w.nextCursor) or w.nextCursor<1 or w.nextCursor>262145)
        or w.status=='prepared' and (w.stage~='verified' or w.failed~=0 or w.verifiedFill~=true or w.verifiedClear~=true)
        or w.status=='working' and w.stage=='verified' then return nil,'invalid preparation evidence' end
      if not Access.valid(w,plan,region,record.clearanceY) then return nil,'invalid foundation access evidence' end
      if w.status=='prepared' and (w.access or w.accessPending and #w.accessPending>0) then return nil,'unfinished foundation access' end
    end
    return record,path
  end
  function self:start(p,plan)
    assert(not p.site or not p.site.barrier or p.site.barrier.status~='working','site still owns retaining barrier work')
    assert(not p.site or not next(p.site.active),'site still owns active survey work')
    assert(not p.site or not p.site.work or not next(p.site.work.active),'site still owns active preparation work')
    assert(not E.conflicts(app.state,plan.bounds),'Site overlaps owned exploration territory; wait for miners to return')
    local protection=U.copy(plan.bounds)
    if p.site and p.site.identity==plan.identity and p.site.barrier and E.box(p.protectedBounds) then
      for _,axis in ipairs({'x','y','z'}) do
        protection.min[axis]=math.min(protection.min[axis],p.protectedBounds.min[axis])
        protection.max[axis]=math.max(protection.max[axis],p.protectedBounds.max[axis])
      end
    end
    F.commit(p,save,function()
      p.generation=p.generation+1
      p.site={identity=plan.identity,generation=p.generation,projectRun=p.run or 0,cursor=1,completed=0,blocked=0,active={},status='surveying'}
      p.protectedBounds=protection;p.phase='surveying';p.completed=0;p.total=plan.columnCount;p.error=nil
    end)
  end
  function self:tick(p,plan)
    local site=p.site;assert(site and site.identity==plan.identity,'site geometry changed during preparation')
    if p.paused or not (site.status=='surveying' or not site.status and p.phase=='surveying') then return end
    for key,a in pairs(site.active) do
      local j=a.jobId and s.jobs[a.jobId]
      if j and j.status=='completed' then
        local record=self:evidence(p,plan,a.region)
        if not record or record.jobId~=j.id then
          assert(Survey.validReport(j,j.siteReport,true),'completed survey lacks valid observations')
          record={identity=plan.identity,region=a.region,jobId=j.id,clearanceY=j.clearanceY,report=U.copy(j.siteReport)}
          assert(store(p,plan,a.region):save(record))
        end
        local blocked=false;for _,o in ipairs(record.report.observations) do if o.status=='blocked' then blocked=true end end
        F.commit(p,save,function()
          if blocked and a.clearanceY<plan.maxY then
            site.active[key]={region=a.region,attempt=a.attempt+1,clearanceY=math.min(plan.maxY,a.clearanceY+8)}
          else
            site.completed=site.completed+1;site.blocked=site.blocked+(blocked and 1 or 0)
            p.completed=p.completed+#record.report.observations;site.active[key]=nil
          end
        end)
        -- External evidence commits before shrinking the root checkpoint. Old
        -- completion packets are still acknowledged through the retained job ID.
        j.siteReport=nil;j.siteSurvey.columns=nil;assert(save())
        break
      end
    end
    local active=0;for _ in pairs(site.active) do active=active+1 end
    if active<require('autobuilder.core.scaling').window(app.state,config,'clearing') and site.cursor<=plan.regionCount then
      F.commit(p,save,function()
        local region=site.cursor;site.active[tostring(region)]={region=region,attempt=1,clearanceY=plan.bounds.max.y};site.cursor=region+1
      end)
    end
    for _,a in pairs(site.active) do if not a.jobId then
      local payload=contract(plan,a.region,a.clearanceY)
      local expanded=U.copy(p.protectedBounds);expanded.max.y=math.max(expanded.max.y,a.clearanceY)
      if E.conflicts(app.state,expanded) then p.error='Higher survey access overlaps an owned mining route';assert(save());return end
      if expanded.max.y~=p.protectedBounds.max.y then F.commit(p,save,function() p.protectedBounds=expanded end) end
      payload.project=p.name;payload.projectRun=p.run or 0;payload.preferredWorker=p.preferredWorker
      local j=queue:submit('SURVEY_SITE',payload,{},p.name..':site:'..site.generation..':'..a.region..':'..a.attempt)
      F.commit(p,save,function() a.jobId=j.id end)
      return
    end end
    if site.cursor>plan.regionCount and not next(site.active) then
      F.commit(p,save,function()
        site.status=site.blocked>0 and 'survey_blocked' or 'surveyed'
        if p.phase=='surveying' then p.phase=site.status end
        p.error=site.blocked>0 and (site.blocked..' site regions remain inaccessible; inspect saved region observations') or nil
      end)
    end
  end
  local function fillMaterial(required)
    local counts=app.mining and app.mining.storage.counts or {};local best,bestCount,bestAvailable
    for _,item in ipairs(require('autobuilder.build.site_work').fillMaterials) do
      local available=production.ledger:view(item,counts).available
      local provider=require('autobuilder.resources.providers').select(item,config,{available=available,required=math.max(1,required),workers=app.state.workers})
      local useful=available>=required or provider and provider.available
      if not best or useful and not bestAvailable or useful==bestAvailable and available>bestCount then best,bestCount,bestAvailable=item,available,useful end
    end
    return best
  end
  function self:startWork(p,plan)
    assert(production,'preparation requires production and cargo return services')
    assert(p.site and p.site.identity==plan.identity and p.site.completed==plan.regionCount and not next(p.site.active),'survey all site regions first')
    assert(not p.site.work,'site preparation already started')
    F.commit(p,save,function()
      p.site.work={cursor=1,completed=0,blocked=0,preparedCount=0,active={},status='working'};p.returnRequests=p.returnRequests or {};p.phase='preparing_site';p.error=nil
    end)
  end
  function self:prepared(p,plan,region)
    if p.site and p.site.barrier and p.site.barrier.status=='working' then return false,'retaining barrier is not verified' end
    if p.site and p.site.accessLease and E.overlaps(p.site.accessLease.bounds,plan:region(region).bounds) then return false,'foundation access restoration remains owned' end
    local record,why=self:evidence(p,plan,region)
    if not record then return false,why end
    local work=record.preparation
    return work and work.status=='prepared' and work.stage=='verified' and work.verifiedFill==true and work.verifiedClear==true or false
  end
  function self:readyFor(p,plan,blocks)
    if p.site and p.site.barrier and p.site.barrier.status=='working' then return false,'retaining barrier is not verified' end
    if not p.site or p.site.identity~=plan.identity or not p.site.work then return false,'site preparation has not started' end
    for _,region in ipairs(plan:requiredRegions(blocks)) do
      local lease=p.site.accessLease
      if lease and E.overlaps(lease.bounds,plan:region(region).bounds) then return false,'foundation access restoration owns preparation region '..region end
      local record,why=self:evidence(p,plan,region)
      if not record or p.site.work.status=='completed' and (not record.preparation or record.preparation.status=='working') then
        local w=p.site.work
        F.commit(p,save,function()
          if not w.rechecking then
            w.cursor=1;w.completed=0;w.blocked=0;w.preparedCount=0;w.firstDefect=nil;w.fluidBlocked=0;w.rechecking=true
            for _,a in pairs(w.active) do a.countInAudit=false end
          end
          w.status='working'
          local active=0;for _ in pairs(w.active) do active=active+1 end
          if not w.active[tostring(region)] and active<require('autobuilder.core.scaling').window(app.state,config,'clearing') then w.active[tostring(region)]={region=region,countInAudit=false} end
        end)
        return false,'preparation region '..region..' needs evidence recovery: '..tostring(record and 'unfinished backup' or why)
      end
      if not record.preparation or record.preparation.status~='prepared' then return false,'preparation region '..region..' is not verified' end
    end
    return true
  end
  local function collectDefects(work,report)
    work.defects=work.defects or {}
    for _,entry in ipairs(report.entries or {}) do if entry.status~='correct' then
      if #work.defects<64 then work.defects[#work.defects+1]=U.copy(entry) else work.omitted=(work.omitted or 0)+1 end
    end end
    work.omitted=(work.omitted or 0)+(report.omittedEntries or 0)
  end
  local function cargoSettled(p,j,a)
    if j.workerId then
      local returnId=p.returnRequests['site:'..j.id];local r=returnId and s.returns[returnId]
      if not (r and r.status=='completed' and r.owner==j.workerId and U.finite(r.settledAt) and r.settledAt>(j.completedAt or 0)) then
        local worker=app.state.workers[tostring(j.workerId)];local t=worker and worker.telemetry
        if not worker or not worker.online or not worker.lastSeen or worker.lastSeen<=(j.completedAt or 0) or not t
          or t.task==j.id or not require('autobuilder.storage.returns').validCargo(t.cargo) or t.cargo.error then a.error='Waiting for fresh preparation cargo receipt';return false end
        if next(t.cargo.items) then
          if not r then
            r=production.returns:request(j.workerId,'project:'..p.name..':site:'..j.id)
            F.commit(p,save,function() p.returnRequests['site:'..j.id]=r.id end)
          end
          a.error='Waiting for preparation debris return '..r.id;return false
        end
      end
    end
    return true
  end
  local function recoverEvidence(p,plan,a,prior)
    local prefix=p.name..':site:'..p.site.generation..':'..a.region..':work:'
    local owners={};local epoch=a.recoveries or 0
    for _,j in pairs(s.jobs) do if j.key and j.key:sub(1,#prefix)==prefix then
      epoch=math.max(epoch,tonumber(j.key:sub(#prefix+1):match('^(%d+):')) or 0)
      if j.status~='completed' then a.error='Missing site evidence; retaining physical owner of '..j.id;return false end
      if j.workerId and (not owners[j.workerId] or (j.completedAt or 0)>(owners[j.workerId].completedAt or 0)) then owners[j.workerId]=j end
    end end
    for _,j in pairs(owners) do if not cargoSettled(p,j,a) then return false end end
    if not a.recovery then
      F.commit(p,save,function()
        a.recoveries=epoch+1;a.recovery={attempt=1,clearanceY=p.protectedBounds.max.y}
      end);return true
    end
    local recovery=a.recovery;local j=recovery.jobId and s.jobs[recovery.jobId]
    if not j then
      local payload=contract(plan,a.region,recovery.clearanceY);payload.project=p.name;payload.projectRun=p.run or 0;payload.preferredWorker=p.preferredWorker
      j=queue:submit('SURVEY_SITE',payload,{},p.name..':site:'..p.site.generation..':'..a.region..':resurvey:'..a.recoveries..':'..recovery.attempt)
      F.commit(p,save,function() recovery.jobId=j.id end);return true
    end
    if j.status~='completed' then a.error='Re-surveying missing evidence with '..j.id;return false end
    if not j.siteReport then
      F.commit(p,save,function() recovery.attempt=recovery.attempt+1;recovery.jobId=nil end);return true
    end
    assert(Survey.validReport(j,j.siteReport,true),'recovery survey lacks valid observations')
    local blocked=false;for _,o in ipairs(j.siteReport.observations) do if o.status=='blocked' then blocked=true end end
    if blocked and recovery.clearanceY<plan.maxY then
      local expanded=U.copy(p.protectedBounds);expanded.max.y=math.min(plan.maxY,recovery.clearanceY+8)
      if E.conflicts(app.state,expanded) then a.error='Higher recovery survey overlaps owned mining territory';return false end
      F.commit(p,save,function()
        p.protectedBounds=expanded;recovery.clearanceY=expanded.max.y;recovery.attempt=recovery.attempt+1;recovery.jobId=nil
      end);j.siteReport=nil;j.siteSurvey.columns=nil;assert(save());return true
    end
    local record={identity=plan.identity,region=a.region,jobId=j.id,clearanceY=j.clearanceY,report=U.copy(j.siteReport),recovery=a.recoveries}
    record.preparationRetries=math.max(a.preparationRetries or 0,prior and prior.preparationRetries or 0)
    record.retryHistory=U.copy(prior and prior.retryHistory or {})
    record.fluidRechecked=a.fluidRechecked or prior and prior.fluidRechecked or nil
    record.containmentRechecked=a.containmentRechecked or p.site.work.containmentRecheck or prior and prior.containmentRechecked or nil
    local orphanJobs={}
    for _,old in pairs(s.jobs) do if old.key and old.key:sub(1,#prefix)==prefix and old.siteAccess then orphanJobs[#orphanJobs+1]=old end end
    if #orphanJobs>0 then
      record.preparation=Access.recover(plan,a.region,j.clearanceY,orphanJobs,fillMaterial(1),a.recoveries)
    end
    local cp=store(p,plan,a.region);assert(cp:save(record));assert(cp:save(record))
    F.commit(p,save,function() a.recovery=nil;a.fluidRetry=nil;a.error=nil end)
    j.siteReport=nil;j.siteSurvey.columns=nil
    for _,old in pairs(s.jobs) do if old.key and old.key:sub(1,#prefix)==prefix and not old.siteAccess then old.blocks=nil;old.report=nil end end
    assert(save());return true
  end
  local function workRegion(p,plan,a)
    local record,why=self:evidence(p,plan,a.region)
    if not record then a.error='Site evidence unavailable: '..tostring(why);return recoverEvidence(p,plan,a) end
    local cp=store(p,plan,a.region)
    if a.fluidRetry then
      if a.recovery and record.recovery and record.recovery>=(a.recoveries or 0) then
        F.commit(p,save,function() a.recovery=nil;a.fluidRetry=nil;a.error=nil end);return true
      end
      return recoverEvidence(p,plan,a)
    end
    if p.site.work.containmentRecheck and record.preparation and record.preparation.status=='blocked'
      and record.preparation.fluids and not record.containmentRechecked then
      F.commit(p,save,function() a.fluidRetry=true;a.fluidRechecked=true;a.containmentRechecked=true;a.preparationRetries=0 end);return true
    end
    if p.site.work.fluidRecheck and record.preparation and record.preparation.status=='blocked'
      and record.preparation.fluids and not record.fluidRechecked then
      F.commit(p,save,function() a.fluidRetry=true;a.fluidRechecked=true;a.preparationRetries=0 end);return true
    end
    if record.retryPending then
      if (a.preparationRetries or 0)<record.preparationRetries then
        F.commit(p,save,function() a.preparationRetries=record.preparationRetries end);return true
      end
      return recoverEvidence(p,plan,a,record)
    end
    -- Region evidence can commit before its older root acknowledges the survey.
    if a.recovery and record.recovery and record.recovery>=(a.recoveries or 0) then
      F.commit(p,save,function() a.recovery=nil;a.error=nil end);return true
    end
    if not record.preparation then
      record.preparation={status='working',stage='clear',cursor=1,sequence=1,epoch=record.recovery or 0,defects={},failed=0}
      for _,o in ipairs(record.report.observations) do if o.status=='blocked' then
        record.preparation.status='blocked';record.preparation.defects[#record.preparation.defects+1]=U.copy(o)
      end end
      assert(cp:save(record));return true
    end
    local work=record.preparation
    assert(({working=true,prepared=true,blocked=true})[work.status] and U.integer(work.sequence) and work.sequence>=1,'invalid saved preparation state')
    local retired=work.lastJob and s.jobs[work.lastJob]
    if retired and retired.status~='completed' then
      local receipt=work.lastReceipt;local w=receipt and app.state.workers[tostring(receipt.owner)];local t=w and w.telemetry
      if not receipt or not U.integer(receipt.owner) or not U.finite(receipt.at) or not U.integer(receipt.progress)
        or receipt.progress<0 or receipt.progress>512 or retired.workerId and retired.workerId~=receipt.owner
        or not w or not w.online or not t or t.task==retired.id or not w.lastSeen or w.lastSeen<=receipt.at then
        a.error='Waiting for preparation receipt reconciliation '..retired.id;return false
      end
      F.commit(retired,save,function()
        retired.workerId=receipt.owner;retired.status='completed';retired.phase='completed';retired.progress=receipt.progress;retired.completedAt=receipt.at
      end)
    end
    if retired and not retired.siteAccess and (retired.blocks or retired.report) then
      -- A failed prior promotion may leave only the primary advanced. Make the
      -- backup contain consumed evidence before deleting the worker's report.
      assert(cp:save(record));retired.blocks=nil;retired.report=nil;retired.siteAccess=nil;assert(save())
    end
    if work.accessRetired then
      assert(cp:save(record))
      for _,id in ipairs(work.accessRetired) do
        local old=s.jobs[id];if old then old.blocks=nil;old.report=nil;old.siteAccess=nil end
      end
      assert(save());work.accessRetired=nil;assert(cp:save(record))
      if p.site.accessLease and p.site.accessLease.region==a.region then F.commit(p,save,function() p.site.accessLease=nil end) end
      return true
    end
    if p.site.accessLease and p.site.accessLease.region==a.region and not work.access and not (work.accessPending and #work.accessPending>0) then
      F.commit(p,save,function() p.site.accessLease=nil end);return true
    end
    if work.status=='blocked' and work.access then
      a.error='Foundation access restoration requires recovery; region remains owned';return false
    end
    if work.status~='working' then
      -- Both sidecar generations must contain terminal proof before the root
      -- stops advancing this region. Older unfinished backups still reconcile
      -- through readyFor when restored against a completed root.
      assert(cp:save(record))
      F.commit(p,save,function()
        if a.countInAudit~=false then
          p.site.work.completed=p.site.work.completed+1;p.site.work.blocked=p.site.work.blocked+(work.status=='blocked' and 1 or 0)
          p.site.work.preparedCount=(p.site.work.preparedCount or 0)+(work.status=='prepared' and 1 or 0)
          if work.status=='blocked' and not p.site.work.firstDefect then p.site.work.firstDefect=U.copy(work.defects[1]) end
          if work.status=='blocked' and work.fluids then
            p.site.work.needsFluidRecheck=true;p.site.work.fluidBlocked=(p.site.work.fluidBlocked or 0)+1
          end
        end
        p.site.work.active[tostring(a.region)]=nil
      end);return true
    end
    if not work.fill and work.stage~='clear' then
      -- This bounds possible demand without crediting unseen support. Selection
      -- may prefer replenishable stock; actual supply still follows inspection.
      local _,_,required=plan:work(a.region,record,work.stage=='seal' and 'seal' or 'fill',1,1,'minecraft:cobblestone')
      work.fill=fillMaterial(required);assert(cp:save(record));return true
    end
    if work.jobId then
      local j=assert(s.jobs[work.jobId],'preparation task ownership missing')
      if j.status~='completed' then return false end
      assert(j.report and type(j.report.counts)=='table','preparation task lacks durable inspection receipt')
      if j.siteWork.stage~='verify' and not cargoSettled(p,j,a) then return false end
      local failed=0;for status,n in pairs(j.report.counts) do if status~='correct' then failed=failed+n end end
      if j.siteWork.stage=='clear' then
        for _,entry in ipairs(j.report.entries or {}) do
          if entry.actual and require('autobuilder.build.site_work').fluid(entry.actual.name) then work.fluids=true end
        end
      end
      if failed>0 then collectDefects(work,j.report);work.failed=work.failed+failed end
      if j.siteAccess then Access.consume(work,j.report,failed)
      elseif work.stage=='fill' then Access.discover(work,plan,a.region,record.clearanceY,j.report) end
      local retry=j.report.counts.inventory_full and j.report.counts.inventory_full>0
      work.lastJob=j.id;work.lastReceipt={owner=j.workerId,at=j.completedAt or 0,progress=j.progress};work.jobId=nil;work.sequence=work.sequence+1
      if not retry and not j.siteAccess then work.cursor=work.nextCursor or 0 end
      work.nextCursor=nil
      -- The next tick rolls this evidence into the backup before root pruning.
      assert(cp:save(record));return true
    end
    local lease=p.site.accessLease
    if lease and lease.region~=a.region and E.overlaps(lease.bounds,plan:region(a.region).bounds) then
      a.error='Waiting for foundation access restoration in region '..lease.region;return false
    end
    if work.access or work.accessPending and #work.accessPending>0 then
      -- ponytail: one project access lease; independent access leases can replace
      -- this when measured preparation throughput warrants the extra ownership.
      if lease and lease.region~=a.region then a.error='Waiting for another foundation access owner';return false end
      if not lease then
        local route=work.access and work.access.route or assert(plan:access(a.region,work.accessPending[1],record.clearanceY))
        F.commit(p,save,function() p.site.accessLease={region=a.region,target=U.copy(route.target),bounds=U.copy(route.bounds or plan:region(a.region).bounds)} end)
        return true
      end
      for _,other in pairs(s.jobs) do if other.workerId and other.status~='completed' and other.bounds and E.overlaps(lease.bounds,other.bounds) then
        a.error='Waiting for existing task '..other.id..' to leave the foundation access envelope';return false
      end end
      local payload=Access.payload(work,plan,a.region,record.clearanceY)
      if payload then
        payload.project=p.name;payload.projectRun=p.run or 0;payload.preferredWorker=p.preferredWorker
        local j=queue:submit('PREPARE_REGION',payload,{},p.name..':site:'..p.site.generation..':'..a.region..':work:'..(work.epoch or 0)..':'..work.sequence..':access:'..work.access.phase..':'..work.access.cursor)
        work.jobId=j.id;work.access.jobs[#work.access.jobs+1]=j.id
      end
      assert(cp:save(record));return true
    end
    if work.cursor==0 then
      if work.stage=='clear' then work.stage=work.fluids and not work.sealed and 'seal' or 'fill'
      elseif work.stage=='seal' then work.sealed=true;work.stage='clear'
      elseif work.stage=='fill' then work.stage='verify_fill';work.failed=0;work.defects={};work.omitted=nil
      elseif work.stage=='verify_fill' then work.verifiedFill=work.failed==0;work.stage='verify_clear'
      elseif work.stage=='verify_clear' then
        work.verifiedClear=work.failed==0;work.stage='verified';work.status=work.verifiedFill and work.verifiedClear and 'prepared' or 'blocked'
        local retryable=false
        for _,defect in ipairs(work.defects) do
          local actual=defect.actual
          if not actual or require('autobuilder.build.site_work').drops(actual,config)
            or require('autobuilder.build.site_work').fluid(actual.name) then retryable=true end
        end
        if work.status=='blocked' and retryable and math.max(record.preparationRetries or 0,a.preparationRetries or 0)<3 then
          record.preparationRetries=math.max(record.preparationRetries or 0,a.preparationRetries or 0)+1
          record.retryHistory=record.retryHistory or {}
          record.retryHistory[#record.retryHistory+1]={failed=work.failed,defect=U.copy(work.defects[1])}
          record.retryPending=true
        end
      else error('unknown preparation stage') end
      work.cursor=1;assert(cp:save(record));return true
    end
    local payload,nextCursor=plan:work(a.region,record,work.stage,work.cursor,8,work.fill)
    if not payload then work.cursor=0;assert(cp:save(record));return true end
    if work.stage=='fill' or work.stage=='verify_fill' then
      for i=#payload.blocks,1,-1 do if Access.covered(work,payload.blocks[i]) then table.remove(payload.blocks,i) end end
      if #payload.blocks==0 then work.cursor=nextCursor or 0;assert(cp:save(record));return true end
    end
    payload.project=p.name;payload.projectRun=p.run or 0;payload.preferredWorker=p.preferredWorker
    local j=queue:submit('PREPARE_REGION',payload,{},p.name..':site:'..p.site.generation..':'..a.region..':work:'..(work.epoch or 0)..':'..work.sequence)
    work.jobId=j.id;work.nextCursor=nextCursor;assert(cp:save(record))
    a.error=nil;return true
  end
  local function barrierTick(p,plan)
    local b=p.site.barrier
    if b.lastJob then
      local old=s.jobs[b.lastJob]
      if old and old.report then assert(save());old.report=nil;old.blocks=nil;assert(save()) end
    end
    if b.jobId then
      local j=assert(s.jobs[b.jobId],'retaining barrier ownership missing')
      if j.status~='completed' then return end
      assert(j.report and j.report.counts,'retaining barrier lacks physical receipt')
      local waiting={}
      if j.siteWork.stage~='verify' and not cargoSettled(p,j,waiting) then p.error=waiting.error;assert(save());return end
      F.commit(p,save,function()
        for status,n in pairs(j.report.counts) do if status~='correct' then b.failed=b.failed+n end end
        collectDefects(b,j.report)
        b.lastJob=j.id;b.jobId=nil;b.sequence=b.sequence+1
        if not j.report.counts.inventory_full or j.report.counts.inventory_full==0 then b.cursor=b.nextCursor or 0 end
        b.nextCursor=nil;p.error=nil
      end);return
    end
    if b.cursor==0 then
      F.commit(p,save,function()
        if b.stage=='fill' then b.stage='verify';b.cursor=1;b.failed=0;b.defects={};b.omitted=nil
        else
          b.status=b.failed==0 and 'verified' or 'blocked'
          if b.status=='verified' then
            local w=p.site.work;w.containmentRecheck=true;w.cursor=1;w.completed=0;w.blocked=0;w.preparedCount=0;w.firstDefect=nil;w.fluidBlocked=0
          else p.site.work.firstDefect=U.copy(b.defects[1]) end
        end
      end);return
    end
    local payload,nextCursor=plan:barrier(b.height,b.cursor,8,b.fill,b.stage=='verify',1)
    payload.project=p.name;payload.projectRun=p.run or 0;payload.preferredWorker=p.preferredWorker
    local j=queue:submit('PREPARE_REGION',payload,{},p.name..':site:'..p.site.generation..':barrier:'..b.sequence)
    F.commit(p,save,function() b.jobId=j.id;b.nextCursor=nextCursor end)
  end
  function self:workTick(p,plan)
    assert(p.site and p.site.identity==plan.identity and p.site.work,'preparation geometry missing or changed')
    if p.paused or p.site.work.status=='completed' then return end
    if p.site.barrier and p.site.barrier.status=='working' then barrierTick(p,plan);return end
    local work=p.site.work;local active=0;for _ in pairs(work.active) do active=active+1 end
    if not p.site.accessLease then
      for _,a in pairs(work.active) do
        local record=self:evidence(p,plan,a.region);local access=record and record.preparation and record.preparation.access
        if access then
          F.commit(p,save,function() p.site.accessLease={region=a.region,target=U.copy(access.route.target),bounds=U.copy(access.route.bounds or plan:region(a.region).bounds)} end)
          return
        end
      end
    end
    if work.cursor<=plan.regionCount and (active<require('autobuilder.core.scaling').window(app.state,config,'clearing') or work.active[tostring(work.cursor)]) then
      F.commit(p,save,function()
        local key=tostring(work.cursor);work.active[key]=work.active[key] or {region=work.cursor};work.active[key].countInAudit=true;work.cursor=work.cursor+1
      end)
    end
    for _,a in pairs(work.active) do if workRegion(p,plan,a) then return end end
    local waiting;for _,a in pairs(work.active) do waiting=waiting or a.error end
    if waiting~=p.error then p.error=waiting;assert(save()) end
    if work.cursor>plan.regionCount and not next(work.active) then
      -- A slow neighboring region may remove inflow only after an early region
      -- exhausted its retries. Reconsider wet failures once after all owners
      -- drain, using the same bounded census and fresh-survey recovery path.
      if work.needsFluidRecheck and not work.fluidRecheck then
        F.commit(p,save,function()
          work.fluidRecheck=true;work.fluidFirstDefect=U.copy(work.firstDefect)
          work.cursor=1;work.completed=0;work.blocked=0;work.preparedCount=0;work.firstDefect=nil;work.fluidBlocked=0
        end);return
      end
      if work.fluidRecheck and (work.fluidBlocked or 0)>0 and not p.site.barrier then
        local payload,_,required=plan:barrier(p.protectedBounds.max.y,1,1,'minecraft:cobblestone',false,1)
        if E.conflicts(app.state,payload.bounds) then p.error='Retaining barrier overlaps owned mining territory; waiting for return';assert(save());return end
        local fill=fillMaterial(required)
        F.commit(p,save,function()
          p.protectedBounds=U.copy(payload.bounds)
          p.site.barrier={status='working',stage='fill',cursor=1,sequence=1,height=payload.clearanceY,fill=fill,failed=0,defects={}}
        end);return
      end
      F.commit(p,save,function()
        work.status='completed';work.rechecking=nil
        if p.phase=='preparing_site' then p.phase=work.blocked==0 and 'site_ready' or 'site_blocked' end
        p.error=work.blocked>0 and (work.blocked..' preparation regions have unresolved defects') or nil
        local d=work.firstDefect
        if d then p.error=p.error..': '..d.x..','..d.y..','..d.z..' '..tostring(d.actual and d.actual.name or d.name or 'unknown block')..': '..tostring(d.reason) end
      end)
    end
  end
  return self
end
return M
