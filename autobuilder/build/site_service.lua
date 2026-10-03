local U=require('autobuilder.core.util')
local F=require('autobuilder.factory.factory')
local Survey=require('autobuilder.build.site_survey')
local Checkpoint=require('autobuilder.core.checkpoint')
local E=require('autobuilder.resources.exploration')
local M={}
function M.new(app,config,e,queue)
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
  return self
end
return M
