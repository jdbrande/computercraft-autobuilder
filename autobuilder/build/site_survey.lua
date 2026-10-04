local U=require('autobuilder.core.util')
local F=require('autobuilder.factory.factory')
local E=require('autobuilder.resources.exploration')
local R=require('autobuilder.workers.resupply')
local M={}
local function dense(t,max)
  if type(t)~='table' then return nil end
  local count=0;for key in pairs(t) do if not U.integer(key) or key<1 or key>max then return nil end;count=count+1 end
  for i=1,count do if not t[i] then return nil end end;return count
end
local function hash(s) return type(s)=='string' and #s==64 and s:match('^[a-f0-9]+$') end
function M.validContract(j)
  if type(j)~='table' or j.type~='SURVEY_SITE' or not E.box(j.bounds) or not U.integer(j.clearanceY) then return false end
  local s=j.siteSurvey;local n=type(s)=='table' and dense(s.columns,64)
  if not n or n==0 or not hash(s.identity) or not U.integer(s.region) or s.region<1 then return false end
  local seen={}
  for _,c in ipairs(s.columns) do
    if type(c)~='table' or not U.integer(c.x) or not U.integer(c.z) or not U.integer(c.minY)
      or c.clearanceY~=j.clearanceY or c.minY>=c.clearanceY or c.clearanceY-c.minY>4096
      or c.x<j.bounds.min.x or c.x>j.bounds.max.x or c.z<j.bounds.min.z or c.z>j.bounds.max.z
      or c.minY<j.bounds.min.y or c.clearanceY>j.bounds.max.y
      or c.substrateY~=nil and (not U.integer(c.substrateY) or c.substrateY~=c.foundationY)
      or c.foundationY~=nil and (not U.integer(c.foundationY) or c.foundationY<c.minY or c.foundationY>=c.clearanceY) then return false end
    local key=c.x..','..c.z;if seen[key] then return false end;seen[key]=true
  end
  return true
end
function M.validSummary(r)
  if type(r)~='table' or not hash(r.identity) or not U.integer(r.region) or r.region<1 or not dense(r.observations,64) then return false end
  for _,o in ipairs(r.observations) do
    if not U.position(o) or not ({surface=true,empty=true,blocked=true,unobserved=true})[o.status] then return false end
    if o.status=='blocked' or o.status=='unobserved' then
      if not U.shortString(o.reason,512) or o.name~=nil and not U.shortString(o.name,128) then return false end
    elseif not U.shortString(o.name,128) or o.status=='empty' and o.name~='minecraft:air' then return false end
  end
  return true
end
function M.validReport(j,r,complete)
  if not M.validContract(j) or not M.validSummary(r) or r.identity~=j.siteSurvey.identity or r.region~=j.siteSurvey.region then return false end
  local n=dense(r.observations,#j.siteSurvey.columns);if not n or complete and n~=#j.siteSurvey.columns then return false end
  for i,o in ipairs(r.observations) do
    local c=j.siteSurvey.columns[i]
    if type(o)~='table' or o.x~=c.x or o.z~=c.z or not U.integer(o.y) or o.y<c.minY or o.y>c.clearanceY then return false end
    if o.status=='blocked' then
      if not U.shortString(o.reason,512) or o.name~=nil and not U.shortString(o.name,128) then return false end
    elseif o.status=='unobserved' then
      if c.substrateY~=o.y or o.name~=nil or not U.shortString(o.reason,512) then return false end
    elseif o.status=='empty' then
      if o.name~='minecraft:air' or o.y~=c.minY then return false end
    elseif o.status=='surface' then
      if not U.shortString(o.name,128) or require('autobuilder.build.blockstates').isAir(o.name) or o.y>=c.clearanceY then return false end
    else return false end
  end
  return true
end
function M.new(task,e,config,nav,save)
  assert(M.validContract(task),'invalid site survey contract')
  local canonical=U.copy({survey=task.siteSurvey,bounds=task.bounds,clearanceY=task.clearanceY})
  task.siteReport=task.siteReport or {identity=task.siteSurvey.identity,region=task.siteSurvey.region,observations={}}
  assert(M.validReport(task,task.siteReport,false),'invalid saved site survey report')
  task.progress=task.progress or 0;task.phase=task.phase or 'work'
  assert(task.progress==#task.siteReport.observations,'survey progress differs from saved observations')
  local self={task=task};local fault
  local function commit(change)
    local ok,why=pcall(F.commit,task,save,change)
    if not ok then fault=tostring(why);error(fault,0) end
  end
  local function block(why,category)
    commit(function() task.phase='blocked';task.error=tostring(why);task.blockedCategory=category end)
    return false,why
  end
  local function record(o)
    commit(function()
      task.siteReport.observations[#task.siteReport.observations+1]=o;task.progress=#task.siteReport.observations
      task.surveyRoute=nil;task.surveyScanning=nil;task.error=nil;task.blockedCategory=nil
      task.phase='work'
    end)
    return true
  end
  local function step()
    if task.paused then return false,'site survey paused' end
    if task.phase=='completed' then return true end
    if task.phase=='blocked' then return false,task.error end
    assert(F.equal(canonical,{survey=task.siteSurvey,bounds=task.bounds,clearanceY=task.clearanceY}),'site survey contract changed')
    local pose=nav.pose
    if not pose.known or pose.pending or pose.uncertain or not U.heading(pose.heading) then return block('trusted pose required for site survey','inaccessible') end
    if task.progress==#task.siteSurvey.columns then
      if pose.y<task.clearanceY then
        local ok,why=nav:up();if not ok then return block(why,'inaccessible') end
        return true
      end
      commit(function() task.phase='completed' end);return true
    end
    local c=task.siteSurvey.columns[task.progress+1]
    if not task.surveyScanning then
      if not task.surveyRoute then
        local points,why=R.overheadPoints(task,nav,e.turtle,config,{x=c.x,y=c.clearanceY,z=c.z},math.max(c.clearanceY,pose.y))
        if not points then return block(why,'inaccessible') end
        commit(function() task.surveyRoute={points=points,index=1} end)
      end
      local route=task.surveyRoute
      while route.index<=#route.points do
        local ok,why=nav:goTo(route.points[route.index])
        if not ok then
          if pose.pending or pose.uncertain or tostring(why):find('reservation',1,true) or tostring(why):find('fuel',1,true) then return block(why,'inaccessible') end
          return record({x=c.x,y=c.clearanceY,z=c.z,status='blocked',reason=tostring(why):sub(1,512)})
        end
        commit(function() task.surveyRoute.index=task.surveyRoute.index+1 end)
      end
      commit(function() task.surveyScanning=true;task.surveyRoute=nil;task.phase='work' end);return true
    end
    if pose.x~=c.x or pose.z~=c.z or pose.y>c.clearanceY or pose.y<=c.minY then return block('survey pose differs from current column','ambiguous') end
    local ok,found,b=pcall(e.turtle.inspectDown)
    if not ok or type(found)~='boolean' or found and (type(b)~='table' or not U.shortString(b.name,128)) then return block('invalid native site inspection','inaccessible') end
    if found then return record({x=c.x,y=pose.y-1,z=c.z,status='surface',name=b.name}) end
    if c.substrateY and pose.y==c.substrateY+2 then
      return record({x=c.x,y=c.substrateY,z=c.z,status='unobserved',reason='plant substrate requires side inspection'})
    end
    if pose.y-1==c.minY then return record({x=c.x,y=c.minY,z=c.z,status='empty',name='minecraft:air'}) end
    local moved,why=nav:down();if not moved then return block(why,'inaccessible') end
    return true
  end
  function self:step()
    if fault then return false,fault end
    local ok,result,why=pcall(step);if ok then return result,why end
    if fault then return false,fault end
    return block(result,'inaccessible')
  end
  function self:resume()
    if fault then return false,fault end
    commit(function() task.phase='work';task.error=nil;task.blockedCategory=nil end);return true
  end
  return self
end
return M
