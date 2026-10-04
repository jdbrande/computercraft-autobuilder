local M={}
M.roles={controller=true,worker=true,miner=true,builder=true,logger=true,courier=true}
M.required={'installer.lua','update.lua','startup.lua','autobuilder/startup.lua','autobuilder/config.lua','autobuilder/core/runtime.lua'}
M.receipt='/autobuilder/.installation.json'
function M.base(url)
  assert(type(url)=='string' and url:match('^https://[%w%.%-]+/[%w%._/%-]+$'),'base URL must be an HTTPS raw repository directory, without query/fragment')
  assert(not url:find('/%.%./') and not url:find('/%./'),'unsafe base URL')
  return (url:gsub('/+$',''))
end
function M.path(path)
  if type(path)~='string' or #path>200 or not path:match('^[%w_%.%/-]+$') or path:sub(1,1)=='/'
    or path:find('//',1,true) or path:sub(-1)=='/' then return false end
  for part in path:gmatch('[^/]+') do if part=='.' or part=='..' or part:sub(1,1)=='.' then return false end end
  if path=='installer.lua' or path=='update.lua' or path=='startup.lua' then return true end
  if not path:match('^autobuilder/.+%.lua$') then return false end
  if path=='autobuilder/settings.lua' or path:match('^autobuilder/data/') or path:match('^autobuilder/logs/') then return false end
  return true
end
local function version(s)
  assert(type(s)=='string','version required')
  local a,b,c=s:match('^(%d+)%.(%d+)%.(%d+)$'); assert(a and #s<=30,'version must be major.minor.patch')
  return {tonumber(a),tonumber(b),tonumber(c)}
end
function M.compare(a,b)
  a,b=version(a),version(b)
  for i=1,3 do if a[i]~=b[i] then return a[i]>b[i] and 1 or -1 end end
  return 0
end
function M.validate(m)
  assert(type(m)=='table' and m.schema==1 and m.project=='autobuilder','unsupported project manifest')
  version(m.version); assert(M.base(m.baseUrl)==m.baseUrl,'manifest base must be normalized')
  assert(type(m.roles)=='table' and type(m.files)=='table' and #m.files>0 and #m.files<=256,'invalid manifest roles/files')
  for role in pairs(M.roles) do
    assert(type(m.roles[role])=='table' and m.roles[role].runtime==(role=='controller' and 'controller' or 'worker'),'invalid role profile '..role)
  end
  local seen={}
  for _,f in ipairs(m.files) do
    assert(type(f)=='table' and M.path(f.path) and not seen[f.path],'unsafe or duplicate manifest path')
    seen[f.path]=true
    assert(f.url==m.baseUrl..'/'..f.path,'file URL outside declared source')
    assert(type(f.sha256)=='string' and #f.sha256==64 and f.sha256:match('^[0-9a-f]+$'),'invalid SHA-256')
    assert(type(f.bytes)=='number' and f.bytes%1==0 and f.bytes>0 and f.bytes<=1048576,'invalid file size')
    version(f.version)
    assert(type(f.roles)=='table' and #f.roles>0,'file roles required')
    for _,role in ipairs(f.roles) do assert(M.roles[role],'unknown file role') end
  end
  return true
end
function M.select(m,role)
  assert(M.roles[role],'unknown installation role')
  local result={}
  for _,f in ipairs(m.files) do for _,r in ipairs(f.roles) do if r==role then result[#result+1]=f; break end end end
  return result
end
return M
