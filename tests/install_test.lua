local S=require('tests.support')
test('SHA256 matches standard empty and abc vectors',function()
  local hash=require('autobuilder.install.sha256').digest
  eq(hash(''),'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855')
  eq(hash('abc'),'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad')
  eq(hash(string.rep('a',1000)),'41edece42d63e8d9bf515a9ba6932e1c20cbc9f5a5d134645adb5db1b9737ea3')
end)
local function manifest()
  local H=require('autobuilder.install.sha256')
  return {schema=1,project='autobuilder',version='0.2.1',baseUrl='https://raw.githubusercontent.com/user/repo/main',
    roles={controller={runtime='controller'},worker={runtime='worker'},miner={runtime='worker'},builder={runtime='worker'},logger={runtime='worker'},courier={runtime='worker'}},
    files={{path='autobuilder/core/util.lua',url='https://raw.githubusercontent.com/user/repo/main/autobuilder/core/util.lua',roles={'worker','miner'},version='0.2.1',bytes=9,sha256=H.digest('return {}')}}}
end
test('manifest validates safe paths and selects role dependencies',function()
  local M=require('autobuilder.install.manifest'); local m=manifest()
  assert(M.validate(m)); eq(#M.select(m,'miner'),1); eq(#M.select(m,'controller'),0)
  for _,path in ipairs({'../startup.lua','/startup.lua','autobuilder/../config.lua','autobuilder/settings.lua','autobuilder/data/worker.state','autobuilder/logs/a','other.lua','autobuilder/core//x.lua'}) do
    local bad=manifest(); bad.files[1].path=path; bad.files[1].url=bad.baseUrl..'/'..path
    assert(not pcall(M.validate,bad),path)
  end
  m.files[2]=m.files[1]; assert(not pcall(M.validate,m))
end)
test('manifest disallows foreign URLs and version downgrade comparison is numeric',function()
  local M=require('autobuilder.install.manifest'); local m=manifest()
  m.files[1].url='https://other.test/x'; assert(not pcall(M.validate,m))
  assert(M.compare('0.10.0','0.9.9')>0); assert(M.compare('1.0.0','1.0.1')<0)
end)
local IS=require('tests.install_support')
test('transaction stages complete files without touching working files before commit',function()
  local f=IS.fs(); f.makeDir('/autobuilder/core'); f.files['/autobuilder/core/util.lua']='old'
  local tx=require('autobuilder.install.transaction').new(f,IS.codec())
  tx:begin(); tx:stage('autobuilder/core/util.lua','new')
  eq(f.files['/autobuilder/core/util.lua'],'old'); tx:commit()
  eq(f.files['/autobuilder/core/util.lua'],'new'); assert(not f.exists(tx.root))
end)
test('interrupted promotion rolls back all files and can recover without internet',function()
  local f=IS.fs(); f.makeDir('/autobuilder/core'); f.files['/autobuilder/core/util.lua']='old util'; f.files['/startup.lua']='old startup'
  local T=require('autobuilder.install.transaction'); local tx=T.new(f,IS.codec()); tx:begin()
  tx:stage('startup.lua','new guard'); tx:stage('autobuilder/core/util.lua','new util'); tx:stage('update.lua','new updater')
  f.fault.move='/update.lua'; assert(not pcall(tx.commit,tx)); assert(f.exists(tx.root))
  eq(f.files['/autobuilder/core/util.lua'],'new util')
  f.fault.move=nil; local recovered=T.new(f,IS.codec()); assert(recovered:recover())
  eq(f.files['/startup.lua'],'old startup'); eq(f.files['/autobuilder/core/util.lua'],'old util'); eq(f.files['/update.lua'],nil)
end)
test('interrupted rollback retains backups for a second recovery attempt',function()
  local f=IS.fs(); f.files['/startup.lua']='old'; local T=require('autobuilder.install.transaction')
  local tx=T.new(f,IS.codec()); tx:begin(); tx:stage('startup.lua','new'); tx:stage('update.lua','update')
  f.fault.move='/update.lua'; assert(not pcall(tx.commit,tx)); f.fault.move=nil
  f.fault.copy='/startup.lua'; assert(not pcall(tx.recover,tx)); assert(f.exists(tx.root))
  f.fault.copy=nil; assert(tx:recover()); eq(f.files['/startup.lua'],'old')
end)
test('transaction refuses a foreign staging directory or untrusted journal paths',function()
  local f=IS.fs(); local tx=require('autobuilder.install.transaction').new(f,IS.codec())
  f.makeDir(tx.root); f.files[tx.root..'/precious']='user data'
  assert(not pcall(tx.begin,tx)); eq(f.files[tx.root..'/precious'],'user data')
end)
local function installEnv()
  local f=IS.fs(); local codec=IS.codec(); local responses={}; local lines={}; local gets=0
  local e={fs=f,textutils=codec,turtle={},print=function(s) lines[#lines+1]=s end,write=function() end,read=function() return '7' end,
    http={get=function(url)
      gets=gets+1; local data=responses[url]; if not data then return nil,'404 '..url end
      return {readAll=function() return data end,close=function() end,getResponseCode=function() return 200 end}
    end}}
  local m=manifest(); m.files={}
  local files={['installer.lua']='return {}',['update.lua']='return {}',['startup.lua']='return {}',
    ['autobuilder/startup.lua']='return {}',['autobuilder/config.lua']='return {}',['autobuilder/core/runtime.lua']='return {}'}
  local function publish(version)
    m.version=version or m.version; m.files={}
    for path,body in pairs(files) do
      m.files[#m.files+1]={path=path,url=m.baseUrl..'/'..path,roles={'controller','worker','miner','builder','logger','courier'},
        version=m.version,bytes=#body,sha256=require('autobuilder.install.sha256').digest(body)}
      responses[m.baseUrl..'/'..path]=body
    end
    responses[m.baseUrl..'/manifest.json']=codec.serializeJSON(m)
  end
  publish()
  return e,m,files,responses,publish,lines,function() return gets end
end
test('installer configures worker ID and preserves local settings during upgrade',function()
  local e,m,files,_,publish=installEnv(); local Manager=require('autobuilder.install.manager')
  local r=Manager.run(e,{role='worker',base=m.baseUrl,controllerId=12})
  eq(r.role,'worker'); assert(e.fs.files['/autobuilder/settings.lua']:find('12'))
  e.fs.files['/autobuilder/settings.lua']="return {role='worker',controllerId=12,label='My worker',minimumFuelReserve=555}"
  local settings=e.fs.files['/autobuilder/settings.lua']; files['autobuilder/core/runtime.lua']='return {updated=true}'; publish('0.2.2')
  local updated=Manager.run(e,{mode='update'})
  eq(updated.version,'0.2.2'); eq(e.fs.files['/autobuilder/settings.lua'],settings)
  eq(e.fs.files['/autobuilder/core/runtime.lua'],'return {updated=true}')
end)
test('failed download or hash verification never replaces installed files',function()
  local e,m,files,responses,publish=installEnv(); local Manager=require('autobuilder.install.manager')
  Manager.run(e,{role='controller',base=m.baseUrl})
  local old=e.fs.files['/installer.lua']; files['installer.lua']='return {changed=true}'; publish('0.2.2')
  responses[m.baseUrl..'/installer.lua']='bad'
  assert(not pcall(Manager.run,e,{mode='update'})); eq(e.fs.files['/installer.lua'],old)
  eq(e.textutils.unserializeJSON(e.fs.files['/autobuilder/.installation.json']).version,'0.2.1')
end)
test('installer backs up existing startup and updater preserves edited startup',function()
  local e,m,_,_,publish=installEnv(); local Manager=require('autobuilder.install.manager')
  e.fs.files['/startup.lua']='print("original startup")'
  Manager.run(e,{role='controller',base=m.baseUrl})
  eq(e.fs.files['/startup.pre-autobuilder.lua'],'print("original startup")')
  e.fs.files['/startup.lua']='print("custom chain")'; publish('0.2.2')
  Manager.run(e,{mode='update'}); eq(e.fs.files['/startup.lua'],'print("custom chain")')
end)
test('installer prompts for worker controller ID and refuses disabled HTTP clearly',function()
  local e,m=installEnv(); local Manager=require('autobuilder.install.manager')
  Manager.run(e,{role='miner',base=m.baseUrl}); assert(e.fs.files['/autobuilder/settings.lua']:find('7'))
  e.http=nil; local ok,err=pcall(Manager.run,e,{mode='update'}); assert(not ok and tostring(err):find('HTTP'))
end)
test('update checks version, repairs modified code and rejects downgrade',function()
  local e,m,_,_,publish,_,gets=installEnv(); local Manager=require('autobuilder.install.manager')
  Manager.run(e,{role='controller',base=m.baseUrl}); local before=gets()
  local r=Manager.run(e,{mode='update'}); eq(r.changed,0); eq(gets(),before+1)
  e.fs.files['/update.lua']='broken'; Manager.run(e,{mode='update'}); eq(e.fs.files['/update.lua'],'return {}')
  publish('0.1.0'); assert(not pcall(Manager.run,e,{mode='update'}))
end)
test('update refuses modified defaults without changing settings or managed files',function()
  local e,m,files,_,publish=installEnv(); local Manager=require('autobuilder.install.manager')
  Manager.run(e,{role='controller',base=m.baseUrl})
  e.fs.files['/autobuilder/config.lua']='return {minimumFuelReserve=5000}'
  local settings=e.fs.files['/autobuilder/settings.lua']; files['update.lua']='return {new=true}'; publish('0.2.2')
  assert(not pcall(Manager.run,e,{mode='update'}))
  eq(e.fs.files['/update.lua'],'return {}'); eq(e.fs.files['/autobuilder/settings.lua'],settings)
  eq(e.fs.files['/autobuilder/config.lua'],'return {minimumFuelReserve=5000}')
end)
test('manager recovers offline before trying HTTP and leaves no active partial files',function()
  local e=installEnv(); e.http=nil; e.fs.files['/startup.lua']='old startup'
  local tx=require('autobuilder.install.transaction').new(e.fs,e.textutils)
  tx:begin(); tx:stage('startup.lua','new startup'); tx:stage('update.lua','new update')
  e.fs.fault.move='/update.lua'; assert(not pcall(tx.commit,tx)); e.fs.fault.move=nil
  local r=require('autobuilder.install.manager').run(e,{recover=true})
  assert(r.recovered); eq(e.fs.files['/startup.lua'],'old startup'); eq(e.fs.files['/update.lua'],nil)
end)
test('installer uses binary file handles to preserve exact downloaded bytes',function()
  local f=IS.fs(); local open=f.open
  function f.open(path,mode) assert(mode:find('b'),'binary mode required'); return open(path,mode:gsub('b','')) end
  local I=require('autobuilder.install.io'); I.write(f,'/unicode.lua','-- \195\169\nreturn {}')
  eq(I.read(f,'/unicode.lua'),'-- \195\169\nreturn {}')
end)
test('all application entrypoints stop before loading code during an install transaction',function()
  for _,path in ipairs({'startup.lua','autobuilder/startup.lua','autobuilder/controller.lua','autobuilder/workers/worker.lua','autobuilder/pose.lua'}) do
    local h=assert(io.open(path)); local code=h:read('*a'); h:close()
    local env={fs={exists=function(p) return p=='/.autobuilder-install/transaction' end},printError=function() end}
    assert(load(code,'@'..path,'t',env))()
  end
end)
test('installer refuses extensionless startup which would shadow the managed launcher',function()
  local e,m=installEnv(); e.fs.files['/startup']='print("precious")'
  local ok,err=pcall(require('autobuilder.install.manager').run,e,{role='controller',base=m.baseUrl})
  assert(not ok and tostring(err):find('/startup'))
  eq(e.fs.files['/startup'],'print("precious")'); eq(e.fs.files['/installer.lua'],nil)
end)
