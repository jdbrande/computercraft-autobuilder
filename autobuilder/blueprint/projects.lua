local U=require('autobuilder.core.util')
local Hash=require('autobuilder.install.sha256')
local IO=require('autobuilder.install.io')
local Cooperate=require('autobuilder.core.cooperate')
local E=require('autobuilder.resources.exploration')
local M={}
function M.new(app,config,e,queue,production)
  local s=queue.state; local cache,sites={},{}; local self={}
  local siteService=require('autobuilder.build.site_service').new(app,config,e,queue,production)
  local function save() return app:save() end
  local function project(name)
    local p=s.projects[name or s.currentProject]; assert(p,'Unknown project; use build import <file.schem|file.json> [name]'); return p
  end
  local function data(p)
    local raw=IO.read(e.fs,p.path); assert(Hash.digest(raw)==p.hash,'Imported blueprint changed; import under a new name')
    local value,err=require('autobuilder.blueprint.schematic').load(e.fs,e.textutils,p.path); assert(value,err); return value
  end
  local function sitePlan(p,verifySource)
    local source=verifySource and data(p) or nil
    if not sites[p.name] then
      local options=U.copy(p.transform.site or config.build.site);options.regionSize=p.transform.regionSize
      sites[p.name]=require('autobuilder.build.site_plan').new(source or data(p),p.transform,p.hash,options)
    end
    return sites[p.name]
  end
  local function ensureSite(p,refresh)
    local plan=sitePlan(p,true)
    if refresh or not p.site or (p.site.projectRun or 0)~=(p.run or 0) then siteService:start(p,plan) end
    assert(p.site.identity==plan.identity,'site geometry changed; finish owned work before importing a new project')
    p.levelAfterSurvey=not p.site.work or nil;p.siteRequired=true;assert(save());return plan
  end
  queue.preparationReady=function(j)
    local p=s.projects[j.project]
    if not p or (p.run or 0)~=(j.projectRun or 0) then return false,'preparation project or run is unavailable' end
    return siteService:readyFor(p,sitePlan(p),j.blocks)
  end
  -- Verification and clearance cover cells with no placement dependency. Visit upper
  -- cells first so an unwanted column can be cleared without digging an access route.
  local function inspectionRegions(blocks)
    local size=config.build.regionSize; local groups,regions={},{}
    for index,b in ipairs(blocks) do
      Cooperate.every(index)
      local x,y,z=math.floor(b.x/size),math.floor(b.y/size),math.floor(b.z/size)
      local id=x..','..y..','..z; local r=groups[id]
      if not r then r={id=id,x=x,y=y,z=z,blocks={},dependencies={}}; groups[id]=r; regions[#regions+1]=r end
      r.blocks[#r.blocks+1]=b
    end
    local function upperFirst(a,b)
      if a.y~=b.y then return a.y>b.y end
      if a.z~=b.z then return a.z<b.z end
      return a.x<b.x
    end
    table.sort(regions,upperFirst)
    for index,r in ipairs(regions) do
      assert(#r.blocks<=512,'inspection region exceeds the task block limit')
      table.sort(r.blocks,upperFirst)
      if index>1 then r.dependencies={regions[index-1].id} end
    end
    return regions
  end
  if (config.exploration or {}).enabled then
    local changed=false
    for _,p in pairs(s.projects) do
      if not p.protectedBounds then p.protectedBounds=E.projectBounds(p.transform,data(p).size); changed=true end
    end
    if changed then assert(save()) end
  end
  local function analysis(p,verifySource)
    -- Commands recheck the immutable import even when its derived arrays are cached.
    local source=verifySource and data(p) or nil
    if cache[p.name] then return cache[p.name] end
    source=source or data(p)
    local bp=require('autobuilder.blueprint.blueprint')
    local transforms=require('autobuilder.blueprint.transforms')
    local states=require('autobuilder.build.blockstates')
    local t=p.transform; local blocks,air,volume={},{},{}; local index=0
    for _,run in ipairs(source.runs) do
      local entry=source.palette[run.id]
      for _=1,run.count do
        local localPosition={x=index%source.size.x,y=math.floor(index/(source.size.x*source.size.z)),z=math.floor(index/source.size.x)%source.size.z}
        local position=transforms.position(localPosition,source.size,t.rotation,t.mirrorX,t.mirrorZ)
        local b={x=t.origin.x+position.x,y=t.origin.y+position.y,z=t.origin.z+position.z,name=entry.name,
          state=transforms.state(entry.state,t.rotation,t.mirrorX,t.mirrorZ)}
        volume[#volume+1]=b
        local list=states.isAir(entry.name) and air or blocks; list[#list+1]=b
        index=index+1
        Cooperate.every(index)
      end
    end
    local counts=bp.quantities(source); local issues={}; local partial=0
    for _,entry in ipairs(source.palette) do
      local status,reason=states.classify(entry.name,entry.state)
      if status=='UNSUPPORTED' or status=='SPECIAL_ACQUISITION' then issues[#issues+1]={name=entry.name,status=status,reason=reason}
      elseif status=='PARTIALLY_SUPPORTED' then partial=partial+1 end
    end
    for _,issue in ipairs((source.metadata or {}).issues or {}) do issues[#issues+1]={name='metadata',status='UNSUPPORTED',reason=tostring(issue)} end
    local regions=bp.regions(blocks,config.build.regionSize)
    local result={blocks=blocks,requirements=counts,regions=regions,issues=issues,partial=partial,clearanceY=t.origin.y+source.size.y+1,
      volume=#volume,airCount=#air,airRegions=inspectionRegions(air),verificationRegions=inspectionRegions(volume)}
    cache[p.name]=result; return result
  end
  local function beginPhase(p,mode,a)
    p.mode=mode; p.phase=mode=='VERIFY' and 'verifying' or mode=='CLEAR' and 'clearing' or mode=='REPAIR' and 'repairing' or 'building'
    p.total=mode=='VERIFY' and a.volume or mode=='CLEAR' and a.airCount or #a.blocks
    p.generation=p.generation+1; p.cursor=1;p.issuedCount=0; p.jobs={}; p.regionJobs={}; p.completed=0; p.report={counts={},entries={}}
  end
  local function linked(p,allRuns)
    local work,requests={},{}
    if p.requestId and (allRuns or p.includeProduction~=false) then requests[p.requestId]=true end
    for id,j in pairs(s.jobs) do
      if j.project==p.name and (allRuns or (j.projectRun or 0)==(p.run or 0)) then
        work[id]=j;local prefix='supply:'..id..':'
        for rid,r in pairs(s.requests) do if r.key and r.key:sub(1,#prefix)==prefix then requests[rid]=true end end
      end
    end
    local function mine(id)
      local j=(app.state.jobs or {})[id]
      while j and not work[j.id] do work[j.id]=j;j=j.childId and app.state.jobs[j.childId] end
    end
    for rid in pairs(requests) do
      local r=s.requests[rid]
      if r then
        for _,id in pairs(r.mines or {}) do mine(id) end
        for _,id in pairs(r.harvests or {}) do if s.jobs[id] then work[id]=s.jobs[id] end end
        for _,gid in pairs(r.acquisitions or {}) do
          local g=(app.state.exploration or {}).groups and app.state.exploration.groups[gid]
          if g then for _,id in ipairs(g.tripIds) do mine(id) end end
        end
      end
      for id,j in pairs(s.jobs) do
        if j.productionRequest==rid or j.key and j.key:sub(1,#rid+1)==rid..':' then work[id]=j end
      end
    end
    return work,requests
  end
  local function actors(p,work)
    p.actors=p.actors or {};local changed=false
    for _,j in pairs(work) do if j.workerId then
      local id=tostring(j.workerId);local a=p.actors[id]
      if not a then a={after=0};p.actors[id]=a;changed=true end
      local after=j.completedAt or j.created or 0
      if after>a.after then a.after=after;a.settled=nil;changed=true end
    end end
    if changed then assert(save()) end
  end
  local function startRun(p,productionLinked)
    p.run=p.run and p.run+1 or (p.phase=='built' or p.phase=='verified') and 1 or 0;p.actors={};p.returnRequests={};p.settlement=nil;p.includeProduction=productionLinked
    p.siteRequired=nil
    p.repairAttempts=nil;p.repairHistory=nil
  end
  local function settle(p,work,requests)
    local why;local active={}
    if app.chunks then app.chunks:reconcile() end
    for rid in pairs(requests) do
      local r=s.requests[rid]
      if r and r.status~='completed' then why=why or 'Waiting for production '..rid end
    end
    for id,j in pairs(work) do
      if j.status~='completed' and not j.physicalComplete then
        why=why or 'Waiting for project task '..id
        if j.workerId then active[tostring(j.workerId)]=true end
      end
      for _,ledger in ipairs({'inventoryLedger','capacityLedger','chunkLedger'}) do
        local lease=(app.state[ledger] or {}).leases and app.state[ledger].leases[id]
        if lease and lease.status=='held' then why=why or 'Waiting for '..ledger..' claim '..id end
      end
      if s.supply and s.supply.owner==j.workerId then why=why or 'Waiting for supply receipt '..tostring(s.supply.jobId) end
    end
    p.returnRequests=p.returnRequests or {}
    for id,a in pairs(p.actors or {}) do if not a.settled then
      local w=app.state.workers[id];local t=w and w.telemetry
      local cargo=t and t.cargo
      local request=p.returnRequests[id] and s.returns[p.returnRequests[id]]
      if request and request.status=='completed' and request.owner==tonumber(id)
        and U.finite(request.settledAt) and request.settledAt>a.after then
        a.settled={at=request.settledAt,returnRequest=request.id};assert(save())
      elseif not w or not w.online or not t or not w.lastSeen or w.lastSeen<=a.after then
        why=why or 'Waiting for fresh acknowledgement from worker '..id
      elseif active[id] then why=why or 'Waiting for project worker '..id
      elseif not require('autobuilder.storage.returns').validCargo(cargo) or cargo.error then
        why=why or 'Worker '..id..' needs supported cargo telemetry: '..tostring(cargo and cargo.error or 'update worker software')
      else
        if request and request.status=='completed' then request=nil end
        local newTask=t.task and (s.jobs[t.task] or (app.state.jobs or {})[t.task])
        local reassigned=newTask and newTask.workerId==w.id and newTask.status~='completed'
          and not newTask.physicalComplete and not work[newTask.id] and not newTask.returnManaged
        if not next(cargo.items) and reassigned and (not request or request.status=='completed'
          or production.returns:releaseToTask(request.id,newTask.id)) then
          a.settled={at=w.lastSeen,reassigned=newTask.id};assert(save())
        elseif not t.task and t.status=='idle' and t.position and t.position.known and U.heading(t.position.heading)
          and U.position(t.depot) and U.distance(t.position,t.depot)==0 and not next(cargo.items)
          and not require('autobuilder.core.workflows').workerBusy(app.state,w.id) then
          a.settled={at=w.lastSeen,home=U.copy(t.depot)};assert(save())
        else
          if not request then
            request=production.returns:request(w.id,'project:'..p.name..':run:'..(p.run or 0)..':worker:'..id..':after:'..a.after)
            p.returnRequests[id]=request.id;assert(save())
          end
          why=why or 'Worker '..id..' return: '..(request.error or request.status)
        end
      end
    end end
    for _,rid in pairs(p.returnRequests) do
      local r=s.returns[rid]
      if not r or r.status~='completed' then why=why or 'Waiting for home return '..rid end
    end
    if why then p.error=why;assert(save());return end
    p.phase=p.settlement.target;p.settlement.completedAt=e.os and e.os.epoch and e.os.epoch('utc')/1000 or 0;p.error=nil;assert(save())
  end
  local function pauseProduction(p,paused)
    for _,rid in pairs(p.returnRequests or {}) do
      local r=s.returns[rid];local j=r and r.jobId and s.jobs[r.jobId]
      if r then r.paused=paused end
      if j and j.status~='completed' then j.paused=paused;if not paused then j.resumeRequested=true end end
    end
    local r=p.requestId and s.requests[p.requestId]; if not r then return end
    r.paused=paused
    for _,id in pairs(r.acquisitions or {}) do app.mining.jobs:setAcquisitionPaused(id,paused) end
    for _,id in pairs(r.mines or {}) do
      local j=(app.state.jobs or {})[id]
      -- Assigned miners return safely; pause prevents claiming a new tunnel.
      local seen={}
      while j and not seen[j.id] do
        seen[j.id]=true; j.paused=paused; j=j.childId and app.state.jobs[j.childId]
      end
    end
    for _,j in pairs(s.jobs) do
      if j.key and j.key:sub(1,#r.id+1)==r.id..':' then
        j.paused=paused; if not paused then j.resumeRequested=true end
      end
    end
  end
  function self:command(args,importTransform)
    local action=args[2]; local name=args[3]
    if action and action:lower():match('%.schem$') then
      assert(#args==2,'Usage: build <file.schem>; configure build origin before starting')
      assert(config.build.enabled,'Set build.enabled=true and configure the build origin first')
      local title=(action:match('([^/]+)$') or ''):gsub('%.[^.]+$','')
      local existing=s.projects[title]
      if existing then
        local source,why,raw=require('autobuilder.blueprint.schematic').load(e.fs,e.textutils,action); assert(source,why)
        assert(existing.sourceHash==Hash.digest(raw),'Schematic source changed or project name is already used; import under a new name')
        if existing.phase~='imported' and existing.phase~='analyzed' then return self:command({'build','status',title}) end
      else self:command({'build','import',action,title},importTransform) end
      return self:command({'build','auto',title})
    end
    if action=='import' then
      assert(name,'Usage: build import <file.schem|file.json> [name]')
      local source,err,snapshot=require('autobuilder.blueprint.schematic').load(e.fs,e.textutils,name); assert(source,err)
      local title=args[4] or (name:match('([^/]+)$') or ''):gsub('%.[^.]+$',''); assert(title and title:match('^[%w_-]+$') and #title<=64,'Invalid project name')
      assert(not s.projects[title],'Project exists; import under a new name')
      local transform=importTransform and require('autobuilder.config').load({build=importTransform}).build or config.build
      local protection=E.projectBounds(transform,source.size)
      assert(not E.conflicts(app.state,protection),'Project conflicts with owned exploration territory; wait for miners to return')
      local raw=snapshot
      if name:lower():match('%.schem$') then
        assert(e.textutils.serializeJSON,'JSON encoder unavailable')
        raw=e.textutils.serializeJSON(source)
        assert(type(raw)=='string' and #raw<=require('autobuilder.blueprint.schematic').MAX_BYTES,'Normalized blueprint byte limit exceeded')
      end
      local path=config.blueprintDir..'/'..title..'.json'
      if e.fs.exists(path) then assert(IO.read(e.fs,path)==raw,'Blueprint destination already exists with different content')
      else IO.write(e.fs,path..'.tmp',raw); e.fs.move(path..'.tmp',path) end
      local transform=importTransform and require('autobuilder.config').load({build=importTransform}).build or config.build
      local p={protectedBounds=protection,name=title,path=path,hash=Hash.digest(raw),sourceHash=Hash.digest(snapshot),phase='imported',transform=U.copy(transform),jobs={},regionJobs={},generation=0}
      s.projects[title]=p; s.currentProject=title; save(); return true,'Imported '..title
    end
    local p=project(name); s.currentProject=p.name
    if action=='status' then return true,p.name..': '..p.phase..' '..(p.completed or 0)..'/'..(p.total or 0)..' positions'..(p.error and '; '..p.error or '') end
    if action=='pause' then
      p.paused=true
      pauseProduction(p,true)
      for _,j in pairs(linked(p)) do if j.status~='completed' then j.paused=true end end
      save(); return true,'Paused '..p.name
    elseif action=='resume' then
      p.paused=false
      pauseProduction(p,false)
      for _,j in pairs(linked(p)) do j.paused=false;j.resumeRequested=true end
      save(); return true,'Resuming '..p.name
    end
    if action=='survey' or action=='level' then
      assert(config.build.enabled,'Set build.enabled=true and configure the build origin first')
      assert(p.phase~='settling','Project still owns worker or inventory settlement')
      for _,id in ipairs(p.jobs) do assert(s.jobs[id].status=='completed','Project still owns unfinished tasks; pause/resume instead') end
      if not p.run or p.phase=='built' or p.phase=='verified' then startRun(p,false) end
      if action=='level' and (p.phase=='surveyed' or p.phase=='survey_blocked') then
        siteService:startWork(p,sitePlan(p,true));return true,'Preparing site '..p.name
      end
      siteService:start(p,sitePlan(p,true))
      if action=='level' then p.levelAfterSurvey=true;assert(save()) end
      return true,'Surveying '..p.name
    end
    local a=analysis(p,true); p.total=p.mode=='VERIFY' and a.volume or p.mode=='CLEAR' and a.airCount or #a.blocks; p.volume=a.volume; p.airCells=a.airCount; p.issues=a.issues; p.requirements=U.copy(a.requirements)
    if action=='analyze' or action=='materials' or action=='simulate' then
      local ok,err=production:refresh(); local stock=ok and app.mining.storage.counts or {}
      p.analysis=require('autobuilder.blueprint.planner').expand(a.requirements,stock,config)
      p.analysis.storageError=not ok and err or nil
      p.analysis.estimatedMovement=#a.blocks*4; p.analysis.estimatedFuel=#a.blocks*4+config.minimumFuelReserve
      p.analysis.partialStrategies=a.partial; p.phase=p.phase=='imported' and 'analyzed' or p.phase
      app.state.view='project'; save()
      return true,p.name..': '..#a.blocks..' blocks, '..#a.regions..' regions, '..#a.issues..' unsupported entries; materials saved in project analysis'
    end
    assert(#a.issues==0,'Unsupported palette or entity data; inspect build analyze before unattended work')
    if action=='prepare' or action=='auto' then
      assert(not ({building=true,clearing=true,verifying=true,repairing=true,settling=true,surveying=true,preparing_site=true})[p.phase],'Project is already active; use pause/resume')
      if not p.run or p.phase=='built' or p.phase=='verified' then startRun(p,true) end
      p.includeProduction=true
      if action=='auto' then p.autoStart=true;ensureSite(p) end
      local message
      if not next(a.requirements) then
        p.preparedEmpty=true;p.requestId=nil;p.phase='ready';message='No materials required'
      else
        local r=production:request(a.requirements,'project:'..p.name,{projectName=p.name});p.requestId=r.id;p.phase='preparing';message=r.id
      end
      if action=='auto' and p.site.status=='surveying' then p.phase='surveying' end
      save();return true,message
    elseif action=='start' or action=='verify' or action=='repair' or action=='clear' then
      assert(config.build.enabled,'Set build.enabled=true and configure the build origin first')
      assert(p.phase~='settling','Project still owns worker or inventory settlement; wait for completion')
      if not p.run or p.phase=='built' or p.phase=='verified' then startRun(p,action=='start' and p.phase~='built' and p.phase~='verified') end
      for _,id in ipairs(p.jobs) do
        local j=s.jobs[id]
        assert(j.status=='completed' or action=='start' and (j.siteWork or j.siteSurvey),'Project still owns unfinished tasks; pause/resume instead')
      end
      if action=='clear' then assert(config.clearSite,'Set clearSite=true before clearing schematic air cells') end
      if action=='start' then
        local r=p.requestId and s.requests[p.requestId]
        assert((p.preparedEmpty and not next(a.requirements)) or (r and r.status=='completed'),'Run build prepare and wait for resources first')
      end
      if action=='start' or action=='repair' then
        if action=='repair' and p.autoStart~='repair' then p.repairAttempts=nil;p.repairHistory=nil end
        ensureSite(p,action=='repair' and p.autoStart~='repair')
        if not p.site.work or (p.site.work.preparedCount or 0)==0 then p.autoStart=action;assert(save());return true,'Waiting for verified site regions' end
      end
      local mode=action=='start' and (config.clearSite and 'REPAIR' or 'BUILD') or action=='verify' and 'VERIFY' or action=='clear' and 'CLEAR' or 'REPAIR'
      p.nextMode=nil; p.afterBuild=nil; p.paused=false
      if config.clearSite and a.airCount>0 and (action=='start' or action=='repair') then p.nextMode=mode; mode='CLEAR' end
      beginPhase(p,mode,a)
      p.autoStart=nil
      save(); return true,p.phase..' '..p.name
    end
    return false,'build import|analyze|materials|survey|level|auto|prepare|start|status|pause|resume|verify|repair|clear [name]'
  end
  function self:tick()
    if s.retiredBlueprints and #s.retiredBlueprints>0 then
      -- Roll the backup forward before deleting imports referenced by the
      -- previous checkpoint. A corrupt primary must not revive a missing file.
      save()
      for _,path in ipairs(s.retiredBlueprints) do if e.fs.exists(path) then e.fs.delete(path) end end
      s.retiredBlueprints=nil; save()
    end
    for _,p in pairs(s.projects) do
      local work,requests=linked(p);actors(p,work)
      if p.site and (p.site.status=='surveying' or p.phase=='surveying') then siteService:tick(p,sitePlan(p)) end
      if p.levelAfterSurvey and not p.paused and p.site and p.site.completed==sitePlan(p).regionCount and not next(p.site.active) then
        siteService:startWork(p,sitePlan(p));p.levelAfterSurvey=nil;assert(save())
      end
      if p.site and p.site.work then siteService:workTick(p,sitePlan(p)) end
      if p.phase=='settling' and not p.paused then settle(p,work,requests) end
      if p.phase=='preparing' and p.requestId and s.requests[p.requestId].status=='completed' then p.phase='ready'; save() end
      if p.autoStart and not p.paused then
        local r=p.requestId and s.requests[p.requestId]
        if (p.autoStart=='repair' or p.preparedEmpty or r and r.status=='completed') and p.site and p.site.work and (p.site.work.preparedCount or 0)>0 then
          local ok,err=pcall(self.command,self,{'build',p.autoStart=='repair' and 'repair' or 'start',p.name})
          if not ok then p.error=tostring(err);save() else p.error=nil end
        end
      end
      if not p.paused and (p.phase=='building' or p.phase=='verifying' or p.phase=='repairing' or p.phase=='clearing') then
        local a=analysis(p); local active,done=0,0
        local regions=p.mode=='VERIFY' and a.verificationRegions or p.mode=='CLEAR' and a.airRegions or a.regions
        for _,id in ipairs(p.jobs) do
          local j=s.jobs[id]
          if j.status~='completed' then active=active+1 end
          done=done+(j.progress or 0)
          if j.status=='completed' and j.report and not j.reportCollected then
            for k,n in pairs(j.report.counts or {}) do p.report.counts[k]=(p.report.counts[k] or 0)+n end
            p.report.omittedEntries=(p.report.omittedEntries or 0)+(j.report.omittedEntries or 0)
            for _,entry in ipairs(j.report.entries or {}) do
              if entry.status~='correct' then
                if #p.report.entries<512 then p.report.entries[#p.report.entries+1]=entry
                else p.report.omittedEntries=p.report.omittedEntries+1 end
              end
            end
            j.reportCollected=true; j.report=nil; j.blocks=nil; save()
          end
        end
        p.completed=done
        -- Only a bounded window of region payloads lives in the checkpoint.
        if p.issuedCount==nil then p.issuedCount=0;for _ in pairs(p.regionJobs) do p.issuedCount=p.issuedCount+1 end end
        if active<4 and p.issuedCount<#regions then
          for _=1,math.min(32,#regions) do
            p.cursor=(p.cursor-1)%#regions+1;local region=regions[p.cursor];p.cursor=p.cursor+1
            if not p.regionJobs[region.id] then
              local deps,ready={},true
              for _,dep in ipairs(region.dependencies or {}) do if not p.regionJobs[dep] then ready=false else deps[#deps+1]=p.regionJobs[dep] end end
              local requiresSite=p.siteRequired and (p.mode~='VERIFY' or p.afterBuild) or nil
              if ready and requiresSite then ready,p.error=siteService:readyFor(p,sitePlan(p),region.blocks) end
              if ready then
                local j=queue:submit(p.mode,{blocks=region.blocks,project=p.name,projectRun=p.run or 0,region=region.id,requiresSite=requiresSite,
                  clearanceY=math.max(a.clearanceY,p.site and p.protectedBounds.max.y or a.clearanceY),deferConnections=p.mode~='VERIFY',stockOnly=p.stockOnly,preferredWorker=p.preferredWorker},deps,p.name..':'..p.generation..':'..region.id)
                p.jobs[#p.jobs+1]=j.id;p.regionJobs[region.id]=j.id;p.issuedCount=p.issuedCount+1;p.error=nil;break
              end
            end
          end
          save()
        elseif active==0 and p.issuedCount==#regions then
          if p.nextMode then
            local mode=p.nextMode; p.nextMode=nil; beginPhase(p,mode,a)
          elseif p.mode~='VERIFY' then
            p.afterBuild=true; beginPhase(p,'VERIFY',a)
          else
            local problems=0; for key,n in pairs(p.report.counts) do if key~='correct' then problems=problems+n end end
            local afterBuild=p.afterBuild;p.afterBuild=nil
            if problems>0 then
              p.phase='needs_repair'
              if afterBuild and (p.repairAttempts or 0)<3 then
                p.repairAttempts=(p.repairAttempts or 0)+1;p.repairHistory=p.repairHistory or {}
                p.repairHistory[#p.repairHistory+1]=require('autobuilder.core.reports').compact(p.report)
                p.autoStart='repair'
                -- Persist the attempt and its fresh survey together. A reboot
                -- continues this generation instead of spending another retry.
                ensureSite(p,true)
              else p.error=afterBuild and 'Defects remain after 3 automatic repair rounds; inspect build status before retrying' or 'Verification found unresolved defects' end
            else p.settlement={target=afterBuild and 'built' or 'verified'};p.phase='settling' end
          end
          save()
        end
      end
    end
  end
  function self:retire(name,advance)
    local p=project(name)
    assert(p.phase=='built' or p.phase=='verified','Only verified projects can be retired')
    local linkedWork,requests=linked(p,true);local remove,returns={},{}
    local prefix='project:'..name..':'
    for id,r in pairs(s.returns or {}) do
      if r.key and r.key:sub(1,#prefix)==prefix then
        if r.status~='completed' then return false,'Waiting for worker home settlement' end
        local shared=false
        for other,q in pairs(s.projects) do if other~=name then
          for _,rid in pairs(q.returnRequests or {}) do if rid==id then shared=true end end
        end end
        if not shared then returns[id]=true;if r.jobId and s.jobs[r.jobId] then linkedWork[r.jobId]=s.jobs[r.jobId] end end
      end
    end
    for id in pairs(requests) do
      if s.requests[id] and s.requests[id].status~='completed' then return false,'Waiting for batch material/fuel production to finish' end
    end
    for id,j in pairs(s.jobs) do
      if linkedWork[id] then
        if j.status~='completed' then return false,'Waiting for batch jobs to finish' end
        if j.workerId then
          local w=app.state.workers[tostring(j.workerId)]
          if not w or not w.online or not j.completedAt or w.lastSeen<=j.completedAt or w.telemetry.task==id then
            return false,'Waiting for turtle '..j.workerId..' to acknowledge its finished batch'
          end
        end
        remove[id]=true
      end
    end
    for id,j in pairs(s.jobs) do
      if not remove[id] then for _,dep in ipairs(j.dependencies or {}) do if remove[dep] then return false,'Another job still depends on this batch' end end end
    end
    if app.chunks then app.chunks:reconcile() end
    for id in pairs(remove) do s.jobs[id]=nil end
    for id in pairs(requests) do s.requests[id]=nil end
    for id in pairs(returns) do s.returns[id]=nil end
    s.projects[name]=nil; cache[name]=nil;sites[name]=nil
    if s.currentProject==name then s.currentProject=nil end
    s.retiredBlueprints=s.retiredBlueprints or {}; s.retiredBlueprints[#s.retiredBlueprints+1]=p.path
    s.retiredBlueprints[#s.retiredBlueprints+1]=config.dataDir..'/sites/'..p.name
    -- Commit the stream cursor and removal in the same checkpoint. Never leave
    -- a cursor pointing to a deleted project if the computer stops here.
    if advance then advance() else save() end
    return true
  end
  return self
end
return M
