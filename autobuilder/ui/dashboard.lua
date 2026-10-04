-- Projection only: never refresh inventories, analyze blueprints or mutate state.
local M={}
local function keys(t)
 local out={};for k in pairs(t or {}) do out[#out+1]=k end;table.sort(out,function(a,b) return tostring(a)<tostring(b) end);return out
end
local function v(n) return n==nil and 'unknown' or tostring(n) end
function M.lines(state,forecasts,now,io,workerId)
 local lines={};local function add(s) lines[#lines+1]=s end
 local a=state.automation or {};local jobs={}
 for _,list in ipairs({state.jobs or {},a.jobs or {}}) do for id,j in pairs(list) do jobs[id]=j end end
 local function worker(w)
  local t=w.telemetry or {};local p=t.position or {};local cargo=t.inventory or {}
  add('Worker '..w.id..' '..(w.online and 'ONLINE' or 'OFFLINE')..' '..(t.status or 'unknown'))
  add('Fuel '..v(t.fuel)..' | Cargo '..v(cargo.used)..'/'..v(cargo.slots))
  add('Heartbeat '..math.max(0,math.floor(now-(w.lastSeen or now)))..'s | '..(t.task or 'idle'))
  if p.known then add('Position '..p.x..','..p.y..','..p.z..' '..(p.heading or '?')) end
  if t.health then add(require('autobuilder.workers.health').describe(t.health)) end
  for _,id in ipairs(keys(jobs)) do local j=jobs[id];if j.workerId==w.id and j.status~='completed' then
   local n=type(j.progress)=='table' and j.progress.delivered or j.progress or 0
   add(id..' '..(j.type or 'MINE')..' '..j.status..' '..v(n)..'/'..v(j.quantity or j.total or j.blocks and #j.blocks))
   if j.project then add('Project '..j.project) end
   if j.exploration then add('Sector '..v(j.exploration.sectorId)) end
   if j.error or j.coverageError then add(j.error or j.coverageError) end
  end end
 end
 add('FLEET '..state.id)
 if workerId then
  local w=(state.workers or {})[tostring(workerId)]
  if w then worker(w) else add('Unknown worker '..workerId) end
 else
  for _,name in ipairs(keys(a.projects)) do local p=a.projects[name]
   add(name..' | '..p.phase..(p.paused and ' PAUSED' or '')..' | priority '..(p.priority or 50))
   local verified=(p.mode=='VERIFY' or p.phase=='verifying' or p.phase=='built' or p.phase=='verified') and (p.report or {}).counts
   add('Placement '..v(p.completed or 0)..'/'..v(p.total)..' | Verified '..v(verified and verified.correct or nil)..'/'..v(p.total))
   if p.error then add(p.error) end
   local f=(forecasts or {})[name]
   if f then
    if f.materialUnknown then add('Material progress partly unknown') end
    for _,item in ipairs(keys(f.items)) do local r=f.items[item]
     add(item..' need '..r.required..' stored '..v(r.stored)..' deficit~ '..v(r.deficit))
     add('  held '..v(r.held)..' reserved '..v(r.reserved)..' transit '..v(r.inTransit))
     add('  mining~ '..v(r.mining)..' harvest~ '..v(r.harvesting)..' craft~ '..v(r.crafting)..' process~ '..v(r.processing))
    end
   else add('Materials not analyzed') end
  end
  if not next(a.projects or {}) then add('No project imported') end
  for _,role in ipairs(keys((state.fleet or {}).status)) do local r=state.fleet.status[role]
   add(role..' active '..v(r.active)..' target '..v(r.desired)..' | '..(r.bottleneck or ''))
  end
  for _,id in ipairs(keys(state.workers)) do worker(state.workers[id]) end
 end
 for _,id in ipairs(keys(jobs)) do local j=jobs[id]
  if j.status~='completed' and (not workerId or j.workerId==workerId) then
   if j.trafficWait then local w=j.trafficWait;local p=w.target
    add(id..' waiting '..math.max(0,math.floor(now-w.since))..'s at '..p.x..','..p.y..','..p.z)
    add(w.reason or 'reservation pending');add(w.remedy)
   elseif j.error or j.stockError or j.coverageError then
    add(id..': '..(j.error or j.stockError or j.coverageError))
    if j.lastRouteFailure then
     add('Last route failure: '..j.lastRouteFailure)
     add('Inspect the corridor; provide a passing bay or clear alternate route, then resume. Ownership retained.')
    end
   end
  end
 end
 for _,id in ipairs(keys(a.requests)) do local r=a.requests[id];if r.status~='completed' and r.error then add(id..': '..r.error) end end
 if state.storageError then add('Storage UNKNOWN: '..state.storageError) end
 if state.eventLogError then add('Event log: '..state.eventLogError) end
 if state.lastError then add('Last warning: '..state.lastError) end
 io=io or {};add('Queues network '..(io.networkPending or 0)..' input '..(io.operatorPending or 0)..' | dropped '..(io.networkDropped or 0)..'/'..(io.operatorDropped or 0))
 return lines
end
return M
