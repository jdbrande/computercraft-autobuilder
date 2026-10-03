local M={}
-- Adler-32 uses exact integer arithmetic even on Lua's double-number runtime.
local function checksum(s)
  local a,b=1,0
  -- Batch reductions without yielding inside a transaction. Even the largest
  -- intermediate sum stays below 2^32, exactly representable by Lua doubles.
  for start=1,#s,4096 do
    for i=start,math.min(start+4095,#s) do a=a+s:byte(i);b=b+a end
    a=a%65521;b=b%65521
  end
  return b*65536+a
end
function M.new(fs,codec,path)
  assert(type(path)=='string' and #path>0,'checkpoint path required')
  local self={}
  local function read(p)
    if not fs.exists(p) then return nil,'missing' end
    local ok,result=pcall(function()
      local h,err=fs.open(p,'r'); assert(h,err)
      local raw=h.readAll(); h.close()
      local e=codec.unserialize(raw)
      assert(type(e)=='table' and e.version==1 and type(e.payload)=='string','invalid envelope')
      assert(e.checksum==checksum(e.payload),'checksum mismatch')
      local value=codec.unserialize(e.payload); assert(type(value)=='table','invalid payload')
      return value
    end)
    if ok then return result end
    return nil,tostring(result)
  end
  function self:load()
    local value,err=read(path); if value then return value,'primary' end
    local backup,berr=read(path..'.bak'); if backup then return backup,'backup (primary: '..err..')' end
    if err=='missing' and berr=='missing' and not fs.exists(path..'.tmp') then return nil,'missing' end
    return nil,'No valid checkpoint: '..err..'; backup: '..berr..'. Preserve files and investigate.'
  end
  function self:save(value)
    local ok,err=pcall(function()
      assert(type(value)=='table','checkpoint must be a table')
      local dir=fs.getDir(path); if dir~='' then fs.makeDir(dir) end
      local payload=codec.serialize(value,{compact=true})
      local raw=codec.serialize({version=1,payload=payload,checksum=checksum(payload)},{compact=true})
      local h,why=fs.open(path..'.tmp','w'); assert(h,why)
      h.write(raw); h.close()
      assert(read(path..'.tmp'),'temporary checkpoint did not validate')
      -- Do not replace a good backup with a damaged primary during recovery.
      if read(path) then
        if fs.exists(path..'.bak') then fs.delete(path..'.bak') end
        fs.move(path,path..'.bak')
      elseif fs.exists(path) then fs.delete(path) end
      fs.move(path..'.tmp',path)
    end)
    if not ok then return false,'checkpoint save failed: '..tostring(err) end
    return true
  end
  return self
end
return M
