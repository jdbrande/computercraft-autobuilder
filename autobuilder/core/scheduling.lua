local U=require('autobuilder.core.util')
local M={}
function M.valid(n) return U.integer(n) and n>=0 and n<=100 end
function M.priority(state,work)
  local a=state.automation or {};local projects=a.projects or {};local seen={}
  local function resolve(j,depth)
    if type(j)~='table' or seen[j] or depth>16 then return 50 end
    seen[j]=true
    local name=j.project or (j.name and projects[j.name]==j and j.name)
    if not name and type(j.key)=='string' then name=j.key:match('^project:([%w_-]+)') end
    local p=name and projects[name]
    if p then assert(p.priority==nil or M.valid(p.priority),'invalid saved project priority');return p.priority or 50 end
    local request=j.productionRequest or j.consumer
    if not request and type(j.key)=='string' then request=j.key:match('^(request:%d+):') end
    if request and (a.requests or {})[request] then return resolve(a.requests[request],depth+1) end
    if j.exploration then
      local group=((state.exploration or {}).groups or {})[j.exploration.groupId]
      if group then return resolve(group,depth+1) end
    end
    local parent=j.parent
    if not parent and type(j.key)=='string' then parent=j.key:match('^supply:(task:%d+:%d+):') end
    if parent then return resolve((a.jobs or {})[parent] or (state.jobs or {})[parent],depth+1) end
    return 50
  end
  return resolve(work,0)
end
function M.before(state,a,b)
  local pa,pb=M.priority(state,a),M.priority(state,b)
  if pa~=pb then return pa>pb end
  local ca,cb=a.created or 0,b.created or 0
  if ca~=cb then return ca<cb end
  local ia,ib=tostring(a.id or a.name or ''),tostring(b.id or b.name or '')
  local na,nb=tonumber(ia:match(':(%d+)$')),tonumber(ib:match(':(%d+)$'))
  if na and nb and na~=nb then return na<nb end
  return ia<ib
end
function M.set(state,name,value,save)
  assert(M.valid(value),'Project priority must be an integer from 0 to 100')
  local p=assert((state.automation.projects or {})[name],'Unknown project')
  require('autobuilder.factory.factory').commit(p,save,function() p.priority=value end)
  return value
end
return M
