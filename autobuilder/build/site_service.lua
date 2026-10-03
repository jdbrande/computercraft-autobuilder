local U=require('autobuilder.core.util')
local F=require('autobuilder.factory.factory')
local Survey=require('autobuilder.build.site_survey')
local Checkpoint=require('autobuilder.core.checkpoint')
local E=require('autobuilder.resources.exploration')
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
    if w~=nil then
      if type(w)~='table' or not ({working=true,prepared=true,blocked=true})[w.status]
        or not ({clear=true,fill=true,verify_fill=true,verify_clear=true,verified=true})[w.stage]
        or not U.integer(w.sequence) or w.sequence<1 or not U.integer(w.cursor) or w.cursor<0 or w.cursor>262145
        or not U.integer(w.failed) or w.failed<0 or type(w.defects)~='table' or #w.defects>64
        or w.epoch~=nil and (not U.integer(w.epoch) or w.epoch<0)
        or w.jobId~=nil and not U.shortString(w.jobId,160)
        or w.nextCursor~=nil and (not U.integer(w.nextCursor) or w.nextCursor<1 or w.nextCursor>262145)
        or w.status=='prepared' and (w.stage~='verified' or w.failed~=0 or w.verifiedFill~=true or w.verifiedClear~=true)
        or w.status=='working' and w.stage=='verified' then return nil,'invalid preparation evidence' end
    end
    return record,path
  end
  function self:start(p,plan)
    assert(not p.site or not next(p.site.active),'site still owns active survey work')
    assert(not E.conflicts(app.state,plan.bounds),'Site overlaps owned exploration territory; wait for miners to return')
    F.commit(p,save,function()
      p.generation=p.generation+1
      p.site={identity=plan.identity,generation=p.generation,cursor=1,completed=0,blocked=0,active={}}
      p.protectedBounds=U.copy(plan.bounds);p.phase='surveying';p.completed=0;p.total=plan.columnCount;p.error=nil
    end)
  end
  function self:tick(p,plan)
    local site=p.site;assert(site and site.identity==plan.identity,'site geometry changed during preparation')
    if p.paused or p.phase~='surveying' then return end
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
    if active<4 and site.cursor<=plan.regionCount then
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
      F.commit(p,save,function() a.jobId=j.id;p.jobs[#p.jobs+1]=j.id end)
      return
    end end
    if site.cursor>plan.regionCount and not next(site.active) then
      F.commit(p,save,function()
        p.phase=site.blocked>0 and 'survey_blocked' or 'surveyed'
        p.error=site.blocked>0 and (site.blocked..' site regions remain inaccessible; inspect saved region observations') or nil
      end)
    end
  end
  local function fillMaterial()
    local counts=app.mining and app.mining.storage.counts or {};local best,bestCount,bestAvailable
    for _,item in ipairs({'minecraft:cobblestone','minecraft:dirt','minecraft:cobbled_deepslate','minecraft:netherrack','minecraft:andesite','minecraft:diorite','minecraft:granite','minecraft:stone'}) do
      local available=production.ledger:view(item,counts).available
      local provider=require('autobuilder.resources.providers').select(item,config,{available=available,workers=app.state.workers})
      local useful=available>0 or provider and provider.available
      if not best or useful and not bestAvailable or useful==bestAvailable and available>bestCount then best,bestCount,bestAvailable=item,available,useful end
    end
    return best
  end
  function self:startWork(p,plan)
    assert(production,'preparation requires production and cargo return services')
    assert(p.site and p.site.identity==plan.identity and p.site.completed==plan.regionCount and not next(p.site.active),'survey all site regions first')
    assert(not p.site.work,'site preparation already started')
    F.commit(p,save,function()
      p.site.work={cursor=1,completed=0,blocked=0,active={}};p.returnRequests=p.returnRequests or {};p.phase='preparing_site';p.error=nil
    end)
  end
  function self:prepared(p,plan,region)
    local record,why=self:evidence(p,plan,region)
    if not record then return false,why end
    local work=record.preparation
    return work and work.status=='prepared' and work.stage=='verified' and work.verifiedFill==true and work.verifiedClear==true or false
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
  local function recoverEvidence(p,plan,a)
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
      F.commit(p,save,function() recovery.jobId=j.id;p.jobs[#p.jobs+1]=j.id end);return true
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
    local cp=store(p,plan,a.region);assert(cp:save(record));assert(cp:save(record))
    F.commit(p,save,function() a.recovery=nil;a.error=nil end)
    j.siteReport=nil;j.siteSurvey.columns=nil
    for _,old in pairs(s.jobs) do if old.key and old.key:sub(1,#prefix)==prefix then old.blocks=nil;old.report=nil end end
    assert(save());return true
  end
  local function workRegion(p,plan,a)
    local record,why=self:evidence(p,plan,a.region)
    if not record then a.error='Site evidence unavailable: '..tostring(why);return recoverEvidence(p,plan,a) end
    local cp=store(p,plan,a.region)
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
    if retired and (retired.blocks or retired.report) then
      -- A failed prior promotion may leave only the primary advanced. Make the
      -- backup contain consumed evidence before deleting the worker's report.
      assert(cp:save(record));retired.blocks=nil;retired.report=nil;assert(save())
    end
    if work.status~='working' then
      F.commit(p,save,function()
        p.site.work.completed=p.site.work.completed+1;p.site.work.blocked=p.site.work.blocked+(work.status=='blocked' and 1 or 0)
        if work.status=='blocked' and not p.site.work.firstDefect then p.site.work.firstDefect=U.copy(work.defects[1]) end
        p.site.work.active[tostring(a.region)]=nil
      end);return true
    end
    if not work.fill and work.stage~='clear' then work.fill=fillMaterial();assert(cp:save(record));return true end
    if work.jobId then
      local j=assert(s.jobs[work.jobId],'preparation task ownership missing')
      if j.status~='completed' then return false end
      assert(j.report and type(j.report.counts)=='table','preparation task lacks durable inspection receipt')
      if j.siteWork.stage~='verify' and not cargoSettled(p,j,a) then return false end
      local failed=0;for status,n in pairs(j.report.counts) do if status~='correct' then failed=failed+n end end
      if failed>0 then collectDefects(work,j.report);work.failed=work.failed+failed end
      local retry=j.report.counts.inventory_full and j.report.counts.inventory_full>0
      work.lastJob=j.id;work.lastReceipt={owner=j.workerId,at=j.completedAt or 0,progress=j.progress};work.jobId=nil;work.sequence=work.sequence+1
      if not retry then work.cursor=work.nextCursor or 0 end
      work.nextCursor=nil
      -- The next tick rolls this evidence into the backup before root pruning.
      assert(cp:save(record));return true
    end
    if work.cursor==0 then
      if work.stage=='clear' then work.stage='fill'
      elseif work.stage=='fill' then work.stage='verify_fill';work.failed=0;work.defects={};work.omitted=nil
      elseif work.stage=='verify_fill' then work.verifiedFill=work.failed==0;work.stage='verify_clear'
      elseif work.stage=='verify_clear' then
        work.verifiedClear=work.failed==0;work.stage='verified';work.status=work.verifiedFill and work.verifiedClear and 'prepared' or 'blocked'
      else error('unknown preparation stage') end
      work.cursor=1;assert(cp:save(record));return true
    end
    local payload,nextCursor=plan:work(a.region,record,work.stage,work.cursor,8,work.fill)
    if not payload then work.cursor=0;assert(cp:save(record));return true end
    payload.project=p.name;payload.projectRun=p.run or 0;payload.preferredWorker=p.preferredWorker
    local j=queue:submit('PREPARE_REGION',payload,{},p.name..':site:'..p.site.generation..':'..a.region..':work:'..(work.epoch or 0)..':'..work.sequence)
    work.jobId=j.id;work.nextCursor=nextCursor;assert(cp:save(record))
    local linked=false;for _,id in ipairs(p.jobs) do if id==j.id then linked=true end end
    if not linked then F.commit(p,save,function() p.jobs[#p.jobs+1]=j.id end) end
    a.error=nil;return true
  end
  function self:workTick(p,plan)
    assert(p.site and p.site.identity==plan.identity and p.site.work,'preparation geometry missing or changed')
    if p.paused then return end
    local work=p.site.work;local active=0;for _ in pairs(work.active) do active=active+1 end
    if active<4 and work.cursor<=plan.regionCount then
      F.commit(p,save,function() work.active[tostring(work.cursor)]={region=work.cursor};work.cursor=work.cursor+1 end)
    end
    for _,a in pairs(work.active) do if workRegion(p,plan,a) then return end end
    local waiting;for _,a in pairs(work.active) do waiting=waiting or a.error end
    if waiting~=p.error then p.error=waiting;assert(save()) end
    if work.cursor>plan.regionCount and not next(work.active) then
      F.commit(p,save,function()
        p.phase=work.blocked==0 and 'site_ready' or 'site_blocked'
        p.error=work.blocked>0 and (work.blocked..' preparation regions have unresolved defects') or nil
        local d=work.firstDefect
        if d then p.error=p.error..': '..d.x..','..d.y..','..d.z..' '..tostring(d.actual and d.actual.name or d.name or 'unknown block')..': '..tostring(d.reason) end
      end)
    end
  end
  return self
end
return M
