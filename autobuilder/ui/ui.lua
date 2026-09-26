local M={}
local function position(p)
  if not p or not p.known then return 'position unknown' end
  return string.format('%d,%d,%d %s %s',p.x,p.y,p.z,p.heading or '?',p.source or 'local')
end
function M.draw(term,state,agent,page,input)
  local width,height=term.getSize(); local lines={}
  local function line(s) lines[#lines+1]=tostring(s) end
  line('AUTOBUILDER | '..state.role..' '..state.id)
  if state.role=='controller' and state.view=='project' then
    local a=state.automation or {}; local p=a.projects and a.projects[a.currentProject]
    if p then
      line(p.name..' | '..p.phase..(p.paused and ' [PAUSED]' or ''))
      line(string.format('Progress %d/%d (%.1f%%)',p.completed or 0,p.total or 0,(p.total or 0)>0 and (p.completed or 0)/p.total*100 or 0))
    else line('No imported project | request <item> <count>') end
    local details={}
    local infrastructure=a.infrastructure
    if infrastructure and infrastructure.status~='idle' then
      details[#details+1]='Depot expansion: '..infrastructure.status..' '..(infrastructure.error or '')
    end
    if p then
      for _,issue in ipairs(p.issues or {}) do details[#details+1]=issue.status..' '..issue.name..': '..issue.reason end
      local plan=p.analysis
      if plan then
        local items={}; for item in pairs(p.requirements or {}) do items[#items+1]=item end; table.sort(items)
        for _,item in ipairs(items) do details[#details+1]=item..' need '..p.requirements[item]..' stored '..((state.resourceCounts or {})[item] or 0) end
        for item,n in pairs(plan.missing or {}) do details[#details+1]='Acquire '..item..' '..n end
      end
      for result,n in pairs((p.report or {}).counts or {}) do details[#details+1]='Verify '..result..': '..n end
    end
    for _,r in pairs(a.requests or {}) do if r.status~='completed' then details[#details+1]=r.id..' '..r.status..' '..(r.error or '') end end
    for _,j in pairs(a.jobs or {}) do if j.status~='completed' then details[#details+1]=j.id..' '..j.type..' '..j.status..' '..(j.error or j.supplyError or '') end end
    local perPage=math.max(1,height-7); local pages=math.max(1,math.ceil(#details/perPage)); page=(page or 0)%pages
    line('Details '..(page+1)..'/'..pages)
    for i=page*perPage+1,math.min(#details,(page+1)*perPage) do line(details[i]) end
  elseif state.role=='controller' and state.view=='jobs' then
    local jobs={}; for _,job in pairs(state.jobs or {}) do jobs[#jobs+1]=job end
    for _,job in pairs((state.automation or {}).jobs or {}) do jobs[#jobs+1]=job end
    table.sort(jobs,function(a,b) return a.id<b.id end)
    local perPage=math.max(1,math.floor((height-5)/3)); local pages=math.max(1,math.ceil(#jobs/perPage)); page=(page or 0)%pages
    line('Jobs '..#jobs..' | page '..(page+1)..'/'..pages)
    for i=page*perPage+1,math.min(#jobs,(page+1)*perPage) do
      local job=jobs[i]
      line(job.id..' '..job.status)
      local progress=type(job.progress)=='table' and job.progress.delivered or job.progress or 0
      line((job.item or job.type)..' '..progress..'/'..(job.quantity or #(job.blocks or {}))..' worker '..tostring(job.workerId or '-'))
      line(job.error or ('Target '..tostring(job.target or job.project or '-')))
    end
  elseif state.role=='controller' and state.view=='resources' then
    line('Storage: '..(state.storageError or 'available'))
    local names={}; for name in pairs(state.resourceCounts or {}) do names[#names+1]=name end; table.sort(names)
    local perPage=math.max(1,height-5); local pages=math.max(1,math.ceil(#names/perPage)); page=(page or 0)%pages
    for i=page*perPage+1,math.min(#names,(page+1)*perPage) do line(names[i]..' '..state.resourceCounts[names[i]]) end
  elseif state.role=='controller' then
    local ids={}; local online=0
    for id,w in pairs(state.workers) do ids[#ids+1]=id; if w.online then online=online+1 end end
    table.sort(ids,function(a,b) return tonumber(a)<tonumber(b) end)
    local perPage=math.max(1,math.floor((height-5)/3)); local pages=math.max(1,math.ceil(#ids/perPage)); page=(page or 0)%pages
    line('Workers '..online..'/'..#ids..' online | page '..(page+1)..'/'..pages)
    for i=page*perPage+1,math.min(#ids,(page+1)*perPage) do
      local w=state.workers[ids[i]]; local t=w.telemetry
      line(ids[i]..' '..t.label..' ['..(w.online and 'ONLINE' or 'OFFLINE')..'] '..t.status)
      line('  '..position(t.position))
      line('  fuel '..tostring(t.fuel)..' | slots '..t.inventory.used..'/16 | '..(t.task or 'idle'))
    end
    if #ids==0 then line('Waiting for worker registration...') end
  else
    line('Controller '..state.controllerId..' | '..(agent.connected and 'connected' or 'reconnecting'))
    line('Status: '..state.status); line(position(state.position))
    if state.telemetry then line('Fuel '..state.telemetry.fuel..' | slots '..state.telemetry.inventory.used..'/16') end
    line('GPS: '..(state.gpsError or 'fix available'))
    local task=state.currentTask
    if task then
      line(task.id); line((task.item or task.type or 'task')..' progress '..(tonumber(task.progress) or task.delivered or 0)..'/'..(task.quantity or #(task.blocks or {})))
      line(task.error or ('Phase: '..tostring(task.phase)))
    else line('No active job') end
    line('Last error: '..(state.lastError or 'none'))
  end
  term.clear()
  for y=1,math.min(#lines,math.max(1,height-3)) do term.setCursorPos(1,y); term.write(lines[y]:sub(1,width)) end
  local footer={state.commandResult or 'build status | request <item> <count>','Q save/quit | Shift N/P pages | Enter command','> '..(input or '')}
  for i=1,3 do if height-3+i>=1 then term.setCursorPos(1,height-3+i); term.write(footer[i]:sub(1,width)) end end
end
return M
