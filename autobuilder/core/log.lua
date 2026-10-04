local M={}
local levels={DEBUG=1,INFO=2,WARN=3,ERROR=4}
function M.new(fs,path,options,clock,codec)
  local self={}; options=options or {}; clock=clock or function() return 0 end
  local function append(line)
    local ok,err=pcall(function()
      local dir=fs.getDir(path); if dir~='' then fs.makeDir(dir) end
      local max=options.maxBytes or 65536
      assert(#line<=max,'event exceeds log.maxBytes; record not written')
      if fs.exists(path) and fs.getSize(path)+#line>max then
        local count=options.backups or 3
        if fs.exists(path..'.'..count) then fs.delete(path..'.'..count) end
        for i=count-1,1,-1 do if fs.exists(path..'.'..i) then fs.move(path..'.'..i,path..'.'..(i+1)) end end
        fs.move(path,path..'.1')
      end
      local h,why=fs.open(path,'a'); assert(h,why); h.write(line); h.close()
    end)
    if not ok then return false,'log write failed: '..tostring(err) end
    return true
  end
  function self:write(level,message)
    assert(levels[level],'invalid log level')
    if levels[level] < levels[options.level or 'INFO'] then return true end
    local max=options.maxBytes or 65536
    local line=string.format('%s [%s] %s',tostring(clock()),level,tostring(message):gsub('[\r\n]',' '))
    return append(line:sub(1,max-1)..'\n')
  end
  function self:event(kind,fields)
    local ok,line=pcall(function()
      assert(codec and codec.serializeJSON,'JSON log encoder unavailable')
      assert(require('autobuilder.core.util').shortString(kind,64),'invalid event kind')
      local record=require('autobuilder.core.util').copy(fields or {})
      record.event=kind;record.time=clock()
      return codec.serializeJSON(record)..'\n'
    end)
    if not ok then return false,'event encode failed: '..tostring(line) end
    return append(line)
  end
  return self
end
return M
