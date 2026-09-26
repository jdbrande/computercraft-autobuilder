local Manifest=require('autobuilder.install.manifest')
local I=require('autobuilder.install.io')
local H=require('autobuilder.install.sha256')
local Transaction=require('autobuilder.install.transaction')
local M={}
local function controllerId(value)
  local n=tonumber(value)
  assert(n and n>=0 and n%1==0 and n<=2147483647,'controller ID must be a nonnegative integer')
  return n
end
local function settings(role,id)
  local runtime=role=='controller' and 'controller' or 'worker'
  local capability=({builder='building',logger='logging',courier='courier'})[role]
  return '-- Local configuration: normal updates preserve this file.\n'..
    '-- Configure GPS/depot/mining bounds before enabling mining.\nreturn {\n  role = '..string.format('%q',runtime)..',\n'..
    (id and ('  controllerId = '..id..',\n') or '')..
    (capability and ('  automation = { '..capability..' = true },\n') or '')..
    '  -- initialPosition = {x=0,y=64,z=0,heading="north"},\n'..
    '  -- depot = {x=0,y=64,z=0},\n}\n'
end
local function receipt(e)
  if not e.fs.exists(Manifest.receipt) then return nil end
  local r=e.textutils.unserializeJSON(I.read(e.fs,Manifest.receipt))
  assert(type(r)=='table' and r.schema==1 and r.project=='autobuilder' and Manifest.roles[r.role]
    and type(r.files)=='table','invalid installation receipt; preserve it and inspect before reinstalling')
  Manifest.compare(r.version,r.version); Manifest.base(r.baseUrl)
  for path,f in pairs(r.files) do
    assert(Manifest.path(path) and type(f)=='table' and type(f.sha256)=='string' and #f.sha256==64,'invalid receipt file')
  end
  return r
end
function M.run(e,opts)
  opts=opts or {}
  local tx=Transaction.new(e.fs,e.textutils)
  local recovered=tx:recover()
  if opts.recover then
    e.print(recovered and 'Interrupted installation recovered. Run reboot.' or 'No interrupted installation found.')
    return {recovered=recovered,changed=0}
  end
  for _,path in ipairs({'/startup','/installer','/update'}) do
    assert(not e.fs.exists(path),'Existing '..path..' shadows the .lua command. Back it up and rename it before installing.')
  end
  local old=receipt(e)
  assert(opts.mode~='update' or old,'No installed version found. Run installer <role> first.')
  local role=opts.role or (old and old.role)
  assert(Manifest.roles[role],'Choose controller, worker, miner, builder, logger, or courier.')
  assert(not old or old.role==role,'Role changes require a separate computer or an explicit manual migration.')
  local base=Manifest.base(opts.base or (old and old.baseUrl) or opts.defaultBase)
  assert(not base:find('/USERNAME/',1,true),'Set the repository URL with --base or generate a release with tools/release.py --base URL.')
  e.print('Checking '..base..'/manifest.json')
  local raw=I.fetch(e,base..'/manifest.json',1048576)
  local m=e.textutils.unserializeJSON(raw); Manifest.validate(m)
  -- --base intentionally rebases paths: a freshly forked repository can be used
  -- before regenerating its manifest. Manifest URLs are still strictly validated.
  assert(not old or Manifest.compare(m.version,old.version)>=0,'Remote version is older than installed version; downgrade refused.')
  local files=Manifest.select(m,role); local selected={}
  for _,f in ipairs(files) do selected[f.path]=true end
  for _,path in ipairs({'installer.lua','update.lua','startup.lua','autobuilder/startup.lua','autobuilder/config.lua','autobuilder/core/runtime.lua'}) do
    assert(selected[path],'Manifest is missing required role file: '..path)
  end
  local newSettings
  if not e.fs.exists('/autobuilder/settings.lua') then
    assert(not old,'Local settings are missing. Restore /autobuilder/settings.lua from backup before updating.')
    local id
    if role~='controller' then
      assert(e.turtle,'Worker profiles require a turtle.')
      if opts.controllerId==nil then e.write('Controller computer ID: '); id=controllerId(e.read())
      else id=controllerId(opts.controllerId) end
    end
    newSettings=settings(role,id)
  elseif opts.mode~='update' then
    local fn,err=load(I.read(e.fs,'/autobuilder/settings.lua'),'@settings.lua','t',{})
    assert(fn,err); local ok,cfg=pcall(fn)
    assert(ok and type(cfg)=='table','Existing settings must return a plain table.')
    assert(cfg.role==(role=='controller' and 'controller' or 'worker'),'Existing settings role conflicts with requested role.')
    if role~='controller' then
      controllerId(cfg.controllerId)
      assert(opts.controllerId==nil or controllerId(opts.controllerId)==cfg.controllerId,'Existing controller ID differs; edit settings.lua explicitly.')
    end
  end
  local nextReceipt={schema=1,project='autobuilder',version=m.version,role=role,baseUrl=base,files={}}
  local changed,preserved=0,0
  tx:begin(opts.recoverySource)
  local ok,err=pcall(function()
    for _,f in ipairs(files) do
      local path='/'..f.path
      assert(not e.fs.exists(path) or not e.fs.isDir(path),'Destination is a directory: '..path)
      local localBody=e.fs.exists(path) and I.read(e.fs,path) or nil
      local localHash=localBody and H.digest(localBody)
      local previous=old and old.files[f.path]
      local keep=f.path=='startup.lua' and previous and localHash and localHash~=previous.sha256
      if f.path=='autobuilder/config.lua' and localHash and localHash~=f.sha256 then
        assert(previous and localHash==previous.sha256,'Local edits to config.lua detected. Move custom values into settings.lua before updating.')
      end
      if keep then
        nextReceipt.files[f.path]=previous; preserved=preserved+1
        e.print('Preserved edited /startup.lua; keep its transaction guard when chaining startup.')
      else
        nextReceipt.files[f.path]={sha256=f.sha256,bytes=f.bytes,version=f.version}
        if localHash~=f.sha256 then
          e.print('Downloading '..f.path)
          local body=I.fetch(e,base..'/'..f.path,1048576); I.verify(body,f)
          if f.path=='startup.lua' and localBody and not old then
            local backup='/startup.pre-autobuilder.lua'
            assert(not e.fs.exists(backup) or I.read(e.fs,backup)==localBody,'Existing startup backup differs; preserve it before installing.')
            if not e.fs.exists(backup) then tx:stage('startup.pre-autobuilder.lua',localBody) end
          end
          tx:stage(f.path,body); changed=changed+1
        end
      end
    end
    if newSettings then tx:stage('autobuilder/settings.lua',newSettings) end
    if not e.fs.exists('/manifest.json') or I.read(e.fs,'/manifest.json')~=raw then tx:stage('manifest.json',raw) end
    local metadataChanged=not old or old.version~=m.version or old.baseUrl~=base
    if not metadataChanged then
      for path,f in pairs(nextReceipt.files) do
        local before=old.files[path]
        if not before or before.sha256~=f.sha256 or before.version~=f.version then metadataChanged=true; break end
      end
      for path in pairs(old.files) do if not nextReceipt.files[path] then metadataChanged=true; break end end
    end
    if metadataChanged then tx:stage('autobuilder/.installation.json',e.textutils.serializeJSON(nextReceipt)) end
    if #tx.entries>0 then tx:commit() else tx:recover() end
  end)
  if not ok then
    local rolled,why=pcall(tx.recover,tx)
    error(tostring(err)..(rolled and '\nWorking files restored.' or '\nRecovery pending: '..tostring(why)..'\nRun /.autobuilder-install/transaction/recover.lua (or /installer.lua --recover) before starting.'),0)
  end
  e.print('Installed '..role..' version '..m.version..': '..changed..' code files changed; '..preserved..' custom startup files preserved.')
  e.print(newSettings and 'Created /autobuilder/settings.lua.' or 'Preserved /autobuilder/settings.lua and saved state.')
  if role=='builder' or role=='logger' or role=='courier' then
    e.print('Configure position, heading, depot and role hardware in settings.lua before assigning work.')
  elseif role=='miner' or role=='worker' then e.print('Mining remains opt-in: configure hardware, position, depot and bounds in settings.lua.') end
  e.print('Run reboot to load the installed version.')
  return {role=role,version=m.version,changed=changed,preserved=preserved,recovered=recovered}
end
return M
