-- Bounded, digest-checked streaming catalog. baseURL is the directory containing index.json.
-- Three committed cache files: root envelope, current page, current schematic chunk.
local Hash=require('autobuilder.install.sha256')
local Schematic=require('autobuilder.blueprint.schematic')
local M={MAX_BYTES=1024*1024}
local AXES={'x','y','z'}
local function integer(n,low,high)
  return type(n)=='number' and n==math.floor(n) and n>=low and n<=high
end
local function array(value,limit)
  assert(type(value)=='table','expected array')
  local n=0
  for k in pairs(value) do assert(integer(k,1,limit),'invalid array index'); n=n+1 end
  assert(n>0 and n<=limit,'invalid array length')
  for i=1,n do assert(value[i]~=nil,'sparse array') end
  return n
end
local function relative(path)
  assert(type(path)=='string' and #path>0 and #path<=200 and path:match('^[%w_./%-]+$') and path:sub(1,1)~='/' and path:sub(-1)~='/' and not path:find('//',1,true),'unsafe relative path')
  for part in path:gmatch('[^/]+') do assert(part:sub(1,1)~='.','unsafe relative path') end
end
local function descriptor(d)
  assert(type(d)=='table','invalid descriptor'); relative(d.file)
  assert(integer(d.bytes,1,M.MAX_BYTES),'invalid byte count')
  assert(type(d.sha256)=='string' and #d.sha256==64 and d.sha256:match('^[0-9a-f]+$'),'invalid SHA-256')
end
local function dimensions(s,limit)
  assert(type(s)=='table','missing size')
  for _,axis in ipairs(AXES) do assert(integer(s[axis],1,limit),'invalid size '..axis) end
  return s.x*s.y*s.z
end
local function requirements(counts,limit)
  assert(type(counts)=='table','missing requirements')
  local total,n=0,0
  for item,count in pairs(counts) do
    assert(type(item)=='string' and #item<=256 and item:match('^[a-z0-9_.%-]+:[a-z0-9_./%-]+$') and integer(count,1,limit),'invalid requirements')
    n=n+1; assert(n<=4096,'too many requirements'); total=total+count
    assert(total<=limit,'requirements exceed volume')
  end
  return total
end
local function equal(a,b)
  for k,v in pairs(a) do if b[k]~=v then return false end end
  for k,v in pairs(b) do if a[k]~=v then return false end end
  return true
end
local function rootValid(root)
  assert(type(root)=='table' and root.schema==1,'unsupported catalog schema')
  assert(type(root.project)=='string' and #root.project<=64 and root.project:match('^[%w_-]+$'),'invalid project')
  local volume=dimensions(root.size,65535)
  assert(volume<=2147483647,'project volume exceeds limit')
  assert(integer(root.totalBlocks,1,volume),'invalid totalBlocks')
  assert(requirements(root.requirements,volume)==root.totalBlocks,'root requirements mismatch')
  array(root.pages,8192)
  local seen,total={},0
  for _,p in ipairs(root.pages) do
    descriptor(p); assert(not seen[p.file],'duplicate page'); seen[p.file]=true
    assert(integer(p.count,1,128),'invalid page count'); total=total+p.count
  end
  assert(total<=root.totalBlocks and root.totalBlocks<=total*1024,'invalid chunk/block counters')
  return root
end
local function entryValid(entry,root)
  descriptor(entry)
  local volume=dimensions(entry.size,32); assert(entry.size.y==1,'chunk must be one layer')
  assert(type(entry.offset)=='table','missing offset')
  for _,axis in ipairs(AXES) do
    local offset=entry.offset[axis]
    assert(integer(offset,0,65534),'invalid offset')
    if axis~='y' then assert(offset%32==0,'offset must use 32-cell grid') end
    if root then
      assert(offset+entry.size[axis]<=root.size[axis],'chunk outside project bounds')
      if axis~='y' then assert(entry.size[axis]==math.min(32,root.size[axis]-offset),'invalid edge size') end
    end
  end
  assert(integer(entry.blockCount,1,volume),'invalid blockCount')
  assert(requirements(entry.requirements,volume)==entry.blockCount,'entry requirements mismatch')
end
local function before(a,b)
  for _,axis in ipairs({'y','z','x'}) do
    if a[axis]~=b[axis] then return a[axis]<b[axis] end
  end
  return false
end
function M.new(e,baseURL,cacheDir)
  assert(type(baseURL)=='string' and #baseURL<=2048 and baseURL:match('^https://[%w.%-]+/[%w_./%-]+$'),'invalid HTTPS catalog base')
  baseURL=baseURL:gsub('/+$','')
  for part in baseURL:sub(9):gmatch('[^/]+') do assert(part~='.' and part~='..','unsafe catalog base') end
  assert(type(cacheDir)=='string' and #cacheDir>0,'cache directory required')
  local fs,codec=e.fs,e.textutils
  assert(fs and codec,'filesystem and JSON codec required')
  local decode=codec.unserializeJSON or codec.decode
  local encode=codec.serializeJSON or codec.encode
  assert(decode and encode,'JSON codec required')
  local self={}; fs.makeDir(cacheDir)
  local function read(path,limit)
    assert(fs.getSize(path)<=limit,'cached payload exceeds limit')
    local h,err=fs.open(path,'r'); assert(h,err)
    local ok,raw=pcall(h.readAll); h.close(); assert(ok,raw)
    assert(type(raw)=='string' and #raw<=limit,'invalid cached payload'); return raw
  end
  local function recover(path)
    if fs.exists(path..'.bak') then
      if not fs.exists(path) then fs.move(path..'.bak',path) else fs.delete(path..'.bak') end
    end
    if fs.exists(path..'.tmp') then fs.delete(path..'.tmp') end
  end
  local function replace(path,raw)
    recover(path)
    local ok,err=pcall(function()
      local h,why=fs.open(path..'.tmp','w'); assert(h,why)
      local wrote,failure=pcall(h.write,raw); h.close(); assert(wrote,failure)
      assert(read(path..'.tmp',#raw)==raw,'cache write verification failed')
      if fs.exists(path) then fs.move(path,path..'.bak') end
      fs.move(path..'.tmp',path)
    end)
    if not ok then
      if not fs.exists(path) and fs.exists(path..'.bak') then fs.move(path..'.bak',path) end
      if fs.exists(path..'.tmp') then fs.delete(path..'.tmp') end
      error(err,0)
    end
    if fs.exists(path..'.bak') then fs.delete(path..'.bak') end
  end
  local function fetch(file,limit)
    relative(file)
    assert(e.http and type(e.http.get)=='function','HTTP disabled')
    -- Disable redirects: a relative descriptor cannot redirect to another origin.
    local response,err,failure=e.http.get({url=baseURL..'/'..file,binary=true,redirect=false})
    if not response and failure and failure.close then failure.close() end
    assert(response,err or 'HTTP download failed')
    local ok,raw=pcall(function()
      local code=response.getResponseCode and response.getResponseCode() or 200
      assert(code>=200 and code<300,'HTTP status '..code)
      assert(type(response.read)=='function','bounded HTTP read unavailable')
      local parts,total={},0
      while true do
        local part=response.read(math.min(4096,limit-total+1))
        if part==nil or part=='' then break end
        assert(type(part)=='string','invalid HTTP body')
        total=total+#part; assert(total<=limit,'download exceeds size limit')
        parts[#parts+1]=part
      end
      assert(total>0,'empty HTTP download'); return table.concat(parts)
    end)
    response.close(); assert(ok,raw); return raw
  end
  local function verified(raw,d)
    assert(#raw==d.bytes,'size mismatch'); assert(Hash.digest(raw)==d.sha256,'SHA-256 mismatch')
  end
  local function cached(slot,d,validate)
    local path=cacheDir..'/'..slot..'.json'; recover(path)
    if fs.exists(path) then
      local ok,value=pcall(function() local raw=read(path,M.MAX_BYTES); verified(raw,d); return validate(decode(raw)) end)
      if ok then return value,path end
    end
    local raw=fetch(d.file,d.bytes); verified(raw,d)
    local value=validate(decode(raw)); replace(path,raw); return value,path
  end
  function self:root()
    local path=cacheDir..'/root.json'; recover(path)
    if fs.exists(path) then
      local ok,value=pcall(function()
        local envelope=decode(read(path,M.MAX_BYTES*3))
        assert(type(envelope)=='table' and envelope.source==baseURL and type(envelope.body)=='string' and #envelope.body<=M.MAX_BYTES,'invalid root cache')
        assert(Hash.digest(envelope.body)==envelope.sha256,'root cache hash mismatch')
        return rootValid(decode(envelope.body))
      end)
      if ok then return value end
    end
    local raw=fetch('index.json',M.MAX_BYTES); local value=rootValid(decode(raw))
    replace(path,encode({source=baseURL,sha256=Hash.digest(raw),body=raw})); return value
  end
  function self:page(root,pageNumber)
    rootValid(root); assert(integer(pageNumber,1,#root.pages),'invalid page number')
    local d=root.pages[pageNumber]
    local page=cached('page',d,function(value)
      assert(type(value)=='table' and value.schema==1,'unsupported page schema')
      assert(array(value.entries,128)==d.count,'page count mismatch')
      local prior,seen=nil,{}
      for _,entry in ipairs(value.entries) do
        entryValid(entry,root); assert(not seen[entry.file],'duplicate chunk'); seen[entry.file]=true
        assert(not prior or before(prior,entry.offset),'chunk order must ascend Y/Z/X'); prior=entry.offset
      end
      return value
    end)
    return page
  end
  function self:chunk(entry)
    entryValid(entry)
    local _,path=cached('chunk',entry,function(value)
      local valid,err=Schematic.validate(value); assert(valid,err)
      assert(equal(value.size,entry.size),'chunk size mismatch')
      local counts={}; local total=0
      for _,run in ipairs(value.runs) do
        local name=value.palette[run.id].name
        if name~='minecraft:air' and name~='minecraft:cave_air' and name~='minecraft:void_air' then
          counts[name]=(counts[name] or 0)+run.count; total=total+run.count
        end
      end
      assert(total==entry.blockCount,'chunk blockCount mismatch')
      assert(equal(counts,entry.requirements) and equal(counts,value.requirements),'chunk requirements mismatch')
      return value
    end)
    return path
  end
  return self
end
return M
