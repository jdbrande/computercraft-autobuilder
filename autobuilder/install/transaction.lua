local I=require('autobuilder.install.io')
local H=require('autobuilder.install.sha256')
local Manifest=require('autobuilder.install.manifest')
local M={}
local OWNER='autobuilder transaction v1'
local special={['autobuilder/settings.lua']=true,['autobuilder/.installation.json']=true,
  ['manifest.json']=true,['startup.pre-autobuilder.lua']=true}
local function target(path) return Manifest.path(path) or special[path]==true end
local function priority(path)
  if path=='startup.lua' then return 1 elseif path=='autobuilder/startup.lua' then return 2
  elseif path=='installer.lua' then return 3 elseif path=='autobuilder/.installation.json' then return 99 end
  return 10
end
function M.new(fs,codec)
  local self={root='/.autobuilder-install/transaction',entries={}}; local root=self.root
  local function owned()
    assert(fs.exists(root..'/owner') and I.read(fs,root..'/owner')==OWNER,'foreign/incomplete staging directory; inspect '..root)
  end
  function self:recover()
    if not fs.exists(root) then return false end
    owned()
    if not fs.exists(root..'/journal.json') then fs.delete(root); return true end
    local raw=I.read(fs,root..'/journal.json'); local j=codec.unserializeJSON(raw)
    assert(type(j)=='table' and j.schema==1 and type(j.entries)=='table' and #j.entries<=300,'invalid recovery journal; preserve '..root)
    if fs.exists(root..'/committed') and I.read(fs,root..'/committed')==H.digest(raw) then fs.delete(root); return true end
    local seen={}
    for _,entry in ipairs(j.entries) do
      assert(type(entry)=='table' and target(entry.path) and not seen[entry.path],'unsafe recovery path')
      seen[entry.path]=true
      if entry.oldHash then
        assert(type(entry.oldHash)=='string' and H.digest(I.read(fs,root..'/backup/'..entry.path))==entry.oldHash,'backup integrity failure: '..entry.path)
      end
    end
    -- Restore startup guards LAST. Until then no mixed application can boot.
    for index=#j.entries,1,-1 do
      local entry=j.entries[index]; local path='/'..entry.path
      if fs.exists(path) then assert(not fs.isDir(path),'directory conflicts with recovery '..path); fs.delete(path) end
      if entry.oldHash then fs.makeDir(fs.getDir(path)); fs.copy(root..'/backup/'..entry.path,path) end
    end
    fs.delete(root); return true
  end
  function self:begin(recoverySource)
    self:recover(); fs.makeDir(root); I.write(fs,root..'/owner',OWNER); self.entries={}
    if recoverySource then
      assert(load(recoverySource,'@recover.lua','t',{}),'invalid standalone recovery source')
      I.write(fs,root..'/recover.lua',recoverySource)
    end
  end
  function self:stage(path,data)
    assert(target(path),'unsafe staged path')
    for _,entry in ipairs(self.entries) do assert(entry.path~=path,'duplicate staged path') end
    I.write(fs,root..'/stage/'..path,data)
    self.entries[#self.entries+1]={path=path,newHash=H.digest(data)}
  end
  function self:commit()
    owned()
    table.sort(self.entries,function(a,b)
      local pa,pb=priority(a.path),priority(b.path)
      return pa<pb or (pa==pb and a.path<b.path)
    end)
    for _,entry in ipairs(self.entries) do
      local path='/'..entry.path
      assert(H.digest(I.read(fs,root..'/stage/'..entry.path))==entry.newHash,'staged file changed')
      if fs.exists(path) then
        assert(not fs.isDir(path),'destination is a directory: '..path)
        local data=I.read(fs,path); entry.oldHash=H.digest(data)
        I.write(fs,root..'/backup/'..entry.path,data)
      end
    end
    local raw=codec.serializeJSON({schema=1,entries=self.entries})
    I.write(fs,root..'/journal.tmp',raw); fs.move(root..'/journal.tmp',root..'/journal.json')
    for _,entry in ipairs(self.entries) do
      local path='/'..entry.path; fs.makeDir(fs.getDir(path))
      if fs.exists(path) then fs.delete(path) end
      fs.move(root..'/stage/'..entry.path,path)
      assert(H.digest(I.read(fs,path))==entry.newHash,'promotion verification failed: '..path)
    end
    I.write(fs,root..'/committed',H.digest(raw)); fs.delete(root)
  end
  return self
end
return M
