-- Compact JSON validation and native Sponge loading. Never trust supplied material counts.
local M={MAX_BLOCKS=262144,MAX_BYTES=32*1024*1024,MAX_PALETTE=65536}
local function integer(v,low,high)
  return type(v)=='number' and v==math.floor(v) and v>=low and v<=high
end
local function array(t,limit)
  if type(t)~='table' then return nil end
  local n=0
  for k in pairs(t) do
    if not integer(k,1,limit) then return nil end
    n=n+1
  end
  if n>limit then return nil end
  for i=1,n do if t[i]==nil then return nil end end
  return n
end
local function name(s)
  return type(s)=='string' and #s<=256 and s:match('^[a-z0-9_.%-]+:[a-z0-9_./%-]+$')
end
function M.validate(d)
  if type(d)~='table' or d.schema~=1 then return nil,'unsupported blueprint schema' end
  local s=d.size
  if type(s)~='table' then return nil,'missing dimensions' end
  for _,axis in ipairs({'x','y','z'}) do
    if not integer(s[axis],1,65535) then return nil,'invalid dimension '..axis end
  end
  local volume=s.x*s.y*s.z
  if volume>M.MAX_BLOCKS then return nil,'blueprint block limit exceeded' end
  local n=array(d.palette,M.MAX_PALETTE)
  if not n or n==0 then return nil,'invalid palette' end
  for _,entry in ipairs(d.palette) do
    if type(entry)~='table' or not name(entry.name) or type(entry.state)~='table' then return nil,'invalid palette entry' end
    local properties=0
    for k,v in pairs(entry.state) do
      properties=properties+1
      if properties>64 or type(k)~='string' or #k>64 or not k:match('^[a-z0-9_]+$') or type(v)~='string' or #v>128 or not v:match('^[a-z0-9_.%-]+$') then return nil,'invalid block property' end
    end
  end
  local nr=array(d.runs,volume)
  if not nr or nr==0 then return nil,'invalid runs' end
  local total=0
  for _,run in ipairs(d.runs) do
    if type(run)~='table' or not integer(run.id,1,n) or not integer(run.count,1,volume) then return nil,'invalid run' end
    total=total+run.count
    if total>volume then return nil,'runs exceed volume' end
  end
  if total~=volume then return nil,'runs do not cover volume' end
  if type(d.metadata)~='table' or type(d.requirements)~='table' then return nil,'missing metadata or requirements' end
  local nodes,seen=0,{}
  local function safe(v,depth)
    nodes=nodes+1
    if nodes>100000 or depth>16 then return false end
    if type(v)=='table' then
      if seen[v] then return false end
      seen[v]=true
      for k,x in pairs(v) do
        if (type(k)~='string' and not integer(k,1,100000)) or not safe(x,depth+1) then return false end
      end
      seen[v]=nil
      return true
    end
    return (type(v)=='string' and #v<=65536) or type(v)=='boolean' or (type(v)=='number' and v==v and math.abs(v)<math.huge)
  end
  if not safe(d.metadata,0) then return nil,'invalid metadata' end
  for item,count in pairs(d.requirements) do
    if not name(item) or not integer(count,0,M.MAX_BLOCKS*2) then return nil,'invalid material requirement' end
  end
  return d
end
function M.load(fs,codec,path)
  local ok,result,err,snapshot=pcall(function()
    if type(path)~='string' or #path==0 then return nil,'invalid blueprint path' end
    if fs.getSize and fs.getSize(path)>M.MAX_BYTES then return nil,'blueprint byte limit exceeded' end
    local h,e=fs.open(path,'rb'); if not h then return nil,e or 'cannot open blueprint' end
    local readOK,raw=pcall(h.readAll); local closeOK,closeErr=pcall(h.close)
    if not readOK then return nil,raw end
    if not closeOK then return nil,closeErr end
    if type(raw)~='string' or #raw>M.MAX_BYTES then return nil,'blueprint byte limit exceeded' end
    if path:lower():match('%.schem$') then return require('autobuilder.blueprint.sponge').decode(raw),nil,raw end
    local decode=codec.unserializeJSON or codec.decode
    if not decode then return nil,'JSON decoder unavailable' end
    local value,why=M.validate(decode(raw)); return value,why,raw
  end)
  if not ok then return nil,tostring(result) end
  return result,err,snapshot
end
return M
