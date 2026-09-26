local H=require('autobuilder.install.sha256')
local M={}
function M.read(fs,path)
  local h,err=fs.open(path,'rb'); assert(h,err or ('cannot read '..path))
  local ok,value=pcall(h.readAll); h.close(); assert(ok,value)
  assert(type(value)=='string','invalid file contents'); return value
end
function M.write(fs,path,data)
  local dir=fs.getDir(path); if dir~='' then fs.makeDir(dir) end
  local h,err=fs.open(path,'wb'); assert(h,err or ('cannot write '..path))
  local ok,why=pcall(h.write,data); h.close(); assert(ok,why)
  assert(M.read(fs,path)==data,'write verification failed: '..path)
end
function M.fetch(e,url,limit)
  assert(e.http and type(e.http.get)=='function','HTTP is disabled. Enable http.enabled in CC:Tweaked or use an offline bundle.')
  local response,err,failure=e.http.get(url,nil,true)
  if not response and failure and failure.close then failure.close() end
  assert(response,err or ('download failed: '..url))
  local ok,result=pcall(function()
    local code=response.getResponseCode and response.getResponseCode() or 200
    assert(code>=200 and code<300,'HTTP status '..code..' for '..url)
    local body=response.readAll(); assert(type(body)=='string' and #body>0,'empty download: '..url)
    assert(#body<=limit,'download exceeds size limit: '..url); return body
  end)
  response.close(); assert(ok,result); return result
end
function M.verify(data,file)
  assert(#data==file.bytes,'size mismatch: '..file.path)
  assert(H.digest(data)==file.sha256,'SHA-256 mismatch: '..file.path)
  if file.path:match('%.lua$') then
    local fn,err=load(data,'@'..file.path,'t',{})
    assert(fn,'Lua syntax error: '..tostring(err))
  end
end
return M
