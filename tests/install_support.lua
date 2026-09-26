local S=require('tests.support')
local M={}
function M.fs()
  local f=S.fs(); local dirs={['/']=true,['']=true}; local oldExists=f.exists; local oldOpen=f.open
  function f.exists(p) return oldExists(p) or dirs[p]~=nil end
  function f.isDir(p) return dirs[p]~=nil end
  function f.makeDir(p)
    if p=='' or p=='/' then return end
    f.makeDir(f.getDir(p)); dirs[p]=true
  end
  function f.delete(p)
    for key in pairs(f.files) do if key==p or key:sub(1,#p+1)==p..'/' then f.files[key]=nil end end
    for key in pairs(dirs) do if key==p or key:sub(1,#p+1)==p..'/' then dirs[key]=nil end end
  end
  function f.copy(a,b)
    if f.fault.copy==b then error('copy failure') end
    assert(f.files[a] and not f.exists(b),'invalid copy'); f.files[b]=f.files[a]
  end
  function f.open(p,mode)
    mode=mode:gsub('b','')
    if mode~='r' then assert(f.isDir(f.getDir(p)),'parent directory missing: '..p) end
    return oldOpen(p,mode)
  end
  return f
end
function M.codec()
  local c=S.codec(); return {serializeJSON=c.serialize,unserializeJSON=c.unserialize}
end
return M
