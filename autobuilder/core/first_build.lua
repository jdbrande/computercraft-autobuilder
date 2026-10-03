-- Beginner entry point; all physical work still uses the existing durable queues.
local U=require('autobuilder.core.util')
local IO=require('autobuilder.install.io')
local Hash=require('autobuilder.install.sha256')
local Pilot=require('autobuilder.blueprint.pilot')
local M={}
local NAME='first_cathedral_test'
local function friendly(item) return item:gsub('minecraft:',''):gsub('_',' ') end
local function sameTransform(a,b)
  return a and b and a.origin and b.origin and U.distance(a.origin,b.origin)==0
    and a.rotation==b.rotation and a.mirrorX==b.mirrorX and a.mirrorZ==b.mirrorZ and (a.autoSite==true)==(b.autoSite==true)
end
function M.new(app,config,e)
  local s=app.state; local a=s.automation; local self={}; local lastCheck=-math.huge
  local function project() return a.projects[NAME] end
  local function save() return app:save() end
  local function siteJob() return s.firstBuild and s.firstBuild.siteJob and a.jobs[s.firstBuild.siteJob] end
  local function siteSafe(plan,owner)
    for _,point in ipairs(plan.points) do
      for _,area in ipairs(config.restrictedAreas) do
        if point.x>=area.min.x and point.x<=area.max.x and point.y>=area.min.y and point.y<=area.max.y and point.z>=area.min.z and point.z<=area.max.z then
          return false,'Automatic site crosses a protected area. Move the depot and run setup again.'
        end
      end
      for _,w in pairs(s.workers) do
        local pose=w.telemetry and w.telemetry.position
        if w.id~=owner and pose and pose.known and U.distance(point,pose)==0 then
          return false,'Move turtle '..w.id..' out of the area behind the builder, then try again.'
        end
      end
    end
    return true
  end
  local function execute(action,...)
    local ok,why=app.automation.projects:command({'build',action,...}); assert(ok,why); return why
  end
  local function otherWork()
    for _,j in pairs(s.jobs or {}) do if j.status~='completed' then return true end end
    for _,j in pairs(a.jobs) do if j.status~='completed' and j.project~=NAME then return true end end
    local p=project()
    for id,r in pairs(a.requests) do if r.status~='completed' and (not p or id~=p.requestId) then return true end end
    for name,pj in pairs(a.projects) do
      if name~=NAME and ({building=true,verifying=true,repairing=true,clearing=true,preparing=true})[pj.phase] then return true end
    end
    return false
  end
  function self:check()
    local issues={}; local function issue(text) issues[#issues+1]=text end
    if not config.build.enabled or #config.storageInventories==0 or config.supply.inventory=='' then
      issue('On this controller, type setup. Choose the two chests and the test corner.')
    end
    if not config.automation.enabled then issue('Automation is off. Type setup on this controller.') end
    if config.clearSite or config.build.rotation~=0 or config.build.mirrorX or config.build.mirrorZ then
      issue('The first test needs clearing OFF and no rotation/mirrors. Type setup here.')
    end
    if s.assignmentRecovery then issue('Waiting for saved workers to reconnect after recovery. Keep all workers powered on.') end
    if otherWork() then issue('Other work is still queued or running. Finish it first; type jobs to see it.') end
    if a.supply then issue('A supply delivery is unfinished. Leave its chest contents alone and keep its worker running.') end
    local ok=app.mining:refresh()
    if not ok then issue('Stock chest is not readable. Check its wired modem and cable, then type 1 again.')
    else
      local items={}; for item in pairs(Pilot.requirements) do items[#items+1]=item end; table.sort(items)
      for _,item in ipairs(items) do
        local need=Pilot.requirements[item]+(config.turtleFuelReserveItems[item] or 0)
        local have=app.mining.storage.counts[item] or 0
        if have<need then issue('Put '..(need-have)..' more '..friendly(item)..' in the STOCK chest ('..have..'/'..need..').') end
      end
    end
    if config.supply.inventory~='' then
      for _,name in ipairs(config.storageInventories) do
        if name==config.supply.inventory then issue('Stock and supply must be different chests. Type setup here.') end
      end
      local good,contents=pcall(e.peripheral.call,config.supply.inventory,'list')
      if not good or type(contents)~='table' then issue('Supply chest is not readable. Enable its wired modem and check its cable.')
      elseif next(contents) and not a.supply then issue('Empty the SUPPLY chest. Put the building blocks in the STOCK chest.') end
    end
    local ready,builders,selected=0,0,nil
    local builderProblems,problemId
    for _,w in pairs(s.workers) do
      local t=w.telemetry
      if w.online and t.capabilities.building and (not s.firstBuild or w.id==s.firstBuild.workerId) then
        builders=builders+1
        local problems={}; local prefix='Turtle '..w.id..': '
        if config.build.autoSite and not t.capabilities.sitePreparation then problems[#problems+1]=prefix..'needs the update for automatic clearing. Press Q on it, run /update.lua, then reboot.' end
        if t.status~='idle' or t.task then problems[#problems+1]=prefix..'finish its current job first.' end
        if not t.position.known or not U.heading(t.position.heading) then problems[#problems+1]=prefix..'type setup on it to save its position and facing.' end
        local fuelNeeded=siteJob() and siteJob().status=='completed' and 500 or 1000
        if t.fuel~='unlimited' and t.fuel<fuelNeeded then problems[#problems+1]=prefix..'only '..t.fuel..' fuel. Put 16 coal/charcoal or 2 coal blocks in slot 15, then type setup on it.' end
        if t.inventory.used>14 then problems[#problems+1]=prefix..'needs two empty inventory slots. Move extra cargo into STOCK before starting.' end
        if not config.build.autoSite and t.position.known and U.distance(t.position,config.build.origin)>64 then problems[#problems+1]=prefix..'is too far away. Choose a test corner within 64 blocks of its depot in controller setup.' end
        if config.build.autoSite and not s.firstBuild and t.position.known and U.heading(t.position.heading) then
          local safe,why=siteSafe(require('autobuilder.build.site').plan(t.position),w.id)
          if not safe then problems[#problems+1]=why end
        end
        if #problems==0 then ready=ready+1; if not selected or w.id<selected then selected=w.id end
        elseif not problemId or w.id<problemId then problemId=w.id; builderProblems=problems end
      end
    end
    if ready==0 then
      if builders==0 then issue('On ONE turtle, type setup and finish it. Leave that turtle running, then type 1 here.')
      else for _,problem in ipairs(builderProblems or {}) do issue(problem) end end
    end
    return #issues==0,issues,selected
  end
  function self:guide(force)
    local now=e.os.epoch('utc')/1000
    if not force and now-lastCheck<5 then return end
    lastCheck=now
    local lines={'FIRST TEST: 28 blocks in an 8 x 8 area.','This is a sample, not the whole cathedral.'}
    local f=s.firstBuild; local p=project()
    if f then
      lines[#lines+1]='Builder: turtle '..tostring(f.workerId)..'. Keep this turtle online.'
      if f.paused or p and p.paused then lines[#lines+1]='PAUSED. Type 4 to continue.'
      elseif p and (p.phase=='built' or p.phase=='verified') then
        lines[#lines+1]='TEST FINISHED. Check the blocks in your world.'
        lines[#lines+1]='Verified cells: '..tostring((p.report.counts or {}).correct or 0)..'/64.'
      elseif p and p.phase=='needs_repair' then lines[#lines+1]='Test found a problem. Type errors for details; leave checkpoints intact.'
      elseif siteJob() and siteJob().status~='completed' then
        local j=siteJob()
        lines[#lines+1]='Clearing test space: '..tostring(j.progress or 0)..'/'..#f.sitePlan.points..' steps.'
        lines[#lines+1]='Keep players and other turtles away from the builder.'
      else
        lines[#lines+1]='Test: '..(p and p.phase or 'preparing')..'. Keep the controller and turtle running.'
        if p then lines[#lines+1]='Progress: '..tostring(p.completed or 0)..'/'..tostring(p.total or 28)..' cells in this phase.' end
      end
      if f.error then lines[#lines+1]='Needs attention: '..f.error end
      if p and p.requestId and a.requests[p.requestId] and a.requests[p.requestId].error then
        lines[#lines+1]='Needs attention: '..a.requests[p.requestId].error
      end
      for _,j in pairs(a.jobs) do
        if j.project==NAME and j.status~='completed' and (j.error or j.supplyError) then
          lines[#lines+1]='Worker '..tostring(j.workerId or '?')..': '..tostring(j.error or j.supplyError)
          lines[#lines+1]='After fixing the cause, type 4 to continue.'; break
        end
      end
    else
      local ok,issues=self:check()
      if ok then
        lines[#lines+1]='Software checks passed.'
        lines[#lines+1]=config.build.autoSite and 'AUTO: clears an 8 x 8 site behind the builder, then builds. Type 2 to start.'
          or 'Check the site is empty and the route/space above the turtle is clear. Type 2 to start.'
      else for _,issue in ipairs(issues) do lines[#lines+1]=issue end end
    end
    s.guideLines=lines
  end
  function self:command(line)
    if line=='guide' or line=='help' or line=='1' then s.view='guide'; app.page=0; self:guide(true); return true,'Choose a number, then press Enter.' end
    local action=({['2']='start',['3']='pause',['4']='resume'})[line] or line:match('^pilot%s+(%w+)$')
    if line=='pilot' then action='status' end
    if not action then return nil end
    s.view='guide'; app.page=0
    if action=='status' then self:guide(true); return true,'First test status' end
    local f=s.firstBuild; local p=project()
    if action=='start' then
      if f then
        if f.paused or p and p.paused then return false,'Test is paused. Type 4 to continue.' end
        self:guide(true); return true,p and (p.phase=='built' or p.phase=='verified') and 'Test already finished. No second copy started.' or 'Test already requested. No duplicate work started.'
      end
      assert(not p,'A project already uses first_cathedral_test. Preserve it; use the normal build commands for that project.')
      local ready,issues,workerId=self:check(); if not ready then self:guide(true); return false,issues[1] end
      local raw=e.textutils.serializeJSON(U.copy(Pilot))
      local transform=U.copy(config.build)
      local plan=config.build.autoSite and require('autobuilder.build.site').plan(s.workers[tostring(workerId)].telemetry.position) or nil
      if plan then transform.origin=U.copy(plan.origin) end
      s.firstBuild={name=NAME,workerId=workerId,raw=raw,hash=Hash.digest(raw),settings=U.copy(config.build),transform=transform,sitePlan=plan,autoStart=true}
      save(); self:guide(true); return true,'Test requested. Import, preparation, building and verification run automatically.'
    elseif action=='pause' or action=='resume' then
      if not f then return false,'No first test yet. Type 1 to check setup.' end
      if p and (p.phase=='built' or p.phase=='verified' or p.phase=='needs_repair') then return false,'Test already finished. Type errors to inspect any problems.' end
      f.paused=action=='pause'
      local j=siteJob()
      if j and j.status~='completed' then j.paused=f.paused; j.resumeRequested=not f.paused end
      if p then
        execute(action,NAME)
        if p.requestId and a.requests[p.requestId] then a.requests[p.requestId].paused=f.paused end
      end
      save(); self:guide(true); return true,f.paused and 'Pause requested. A current physical step may finish first.' or 'Continuing the saved test.'
    end
    return false,'Use pilot start, pilot pause, pilot resume, or guide.'
  end
  function self:tick()
    local f=s.firstBuild
    if f and f.autoStart and not f.paused and not s.assignmentRecovery then
      local ok,err=pcall(function()
        assert(config.build.enabled and config.automation.enabled and not config.clearSite and sameTransform(f.settings or f.transform,config.build),
          'Build settings changed. Restore the original test corner/settings before continuing.')
        assert(not otherWork(),'Waiting for other queued work to finish.')
        if f.sitePlan then
          if not f.siteJob then
            local safe,why=siteSafe(f.sitePlan,f.workerId); assert(safe,why)
            local j=app.automation.queue:submit('PREPARE_SITE',{sitePlan=f.sitePlan,bounds=f.sitePlan.bounds,project=NAME,
              preferredWorker=f.workerId,stockOnly=true},{},NAME..':site')
            f.siteJob=j.id; save()
          end
          if siteJob().status~='completed' then return end
        end
        local p=project()
        if not p then
          local path=config.blueprintDir..'/'..NAME..'.json'
          if e.fs.exists(path) then assert(Hash.digest(IO.read(e.fs,path))==f.hash,'Existing test file differs; preserve it before continuing.')
          else IO.write(e.fs,path..'.tmp',f.raw); e.fs.move(path..'.tmp',path) end
          local imported,why=app.automation.projects:command({'build','import',path,NAME},f.transform)
          assert(imported,why); p=project()
        end
        assert(p.hash==f.hash and Hash.digest(IO.read(e.fs,p.path))==f.hash and sameTransform(p.transform,f.transform),
          'Test blueprint or coordinates changed. Restore the saved source before continuing.')
        -- A direct advanced pause command must also prevent this shortcut from starting.
        if p.paused then return end
        if p.phase=='imported' or p.phase=='analyzed' then
          local ready,issues=self:check(); assert(ready,issues[1])
          execute('analyze',NAME); s.view='guide'
          p.preferredWorker=f.workerId
          app.automation.production:request(p.requirements,'project:'..NAME,{stockOnly=true,projectName=NAME})
        elseif p.phase=='ready' then
          local ready,issues=self:check(); assert(ready,issues[1])
          execute('start',NAME); s.view='guide'
          f.autoStart=false;f.raw=nil;save()
        elseif p.phase=='building' or p.phase=='verifying' or p.phase=='built' or p.phase=='verified' or p.phase=='needs_repair' then
          f.autoStart=false; f.raw=nil; save()
        end
      end)
      local message=not ok and tostring(err) or nil
      if f.error~=message then f.error=message; save() end
    end
    if s.view=='guide' then self:guide(false) end
  end
  return self
end
return M
