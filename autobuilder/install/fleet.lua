local I=require('autobuilder.install.io')
local Manifest=require('autobuilder.install.manifest')
local Discovery=require('autobuilder.install.discovery')
local Manager=require('autobuilder.install.manager')
local M={}
local pending='/.autobuilder-fleet-profile.json'
function M.run(args,e,base,recovery)
 local opts={};local command=args[1] or 'install';assert(command=='install' or command=='update','Usage: fleet install|update [--controller ID] [--base URL] [--configure] [--no-reboot]')
 local i=2
 while i<=#args do
  local a=args[i]
  if a=='--controller' or a=='--base' then assert(args[i+1],'Missing value for '..a);opts[a=='--controller' and 'controllerId' or 'base']=args[i+1];i=i+1
  elseif a=='--configure' then opts.configure=true
  elseif a=='--no-reboot' then opts.noReboot=true
  else error('Unknown fleet option: '..tostring(a)) end;i=i+1
 end
 assert(e.turtle,'Fleet enrollment runs on a turtle')
 -- Recover old installation transactions before loading settings or state.
 require('autobuilder.install.transaction').new(e.fs,e.textutils):recover()
 local old=e.fs.exists(Manifest.receipt)
 assert(command~='update' or old,'No installation found; use fleet install')
 local cfg
 if e.fs.exists('/autobuilder/settings.lua') then
  cfg=assert(load(I.read(e.fs,'/autobuilder/settings.lua'),'@settings.lua','t',{}))()
  assert(type(cfg)=='table' and cfg.role=='worker','Existing fleet settings must belong to a worker')
  assert(type(cfg.controllerId)=='number' and cfg.controllerId%1==0 and cfg.controllerId>=0,'Invalid saved controller')
  assert(not opts.controllerId or tonumber(opts.controllerId)==cfg.controllerId,'Existing controller differs; migrate explicitly')
  opts.controllerId=cfg.controllerId
  require('autobuilder.core.setup_state').idle(e,{role='worker',dataDir=cfg.dataDir or '/autobuilder/data'})
 end
 local position
 if e.gps and type(e.gps.locate)=='function' then
  local ok,x,y,z=pcall(e.gps.locate,2,false)
  if ok and type(x)=='number' and type(y)=='number' and type(z)=='number' then position={x=x,y=y,z=z} end
 end
 local applying=not cfg or opts.configure or e.fs.exists(pending)
 local offer=Discovery.find(e,{controllerId=opts.controllerId,position=position,purpose=applying and 'configure' or 'update'})
 if applying then
  assert(type(offer.profile)=='table' and offer.profile.role=='worker' and offer.profile.controllerId==offer.controllerId,'Controller did not provide a worker profile')
  I.write(e.fs,pending,e.textutils.serializeJSON(offer.profile))
 end
 local result=Manager.run(e,{mode=old and 'update' or nil,role=not old and 'worker' or nil,controllerId=offer.controllerId,
  base=opts.base or (not old and offer.baseUrl or nil),defaultBase=base,recoverySource=recovery,requiredVersion=offer.release,requiredPaths={'fleet.lua','autobuilder/fleet_apply.lua'}})
 if applying then
  assert(e.shell.run('/autobuilder/fleet_apply.lua',pending),'Fleet profile application failed; retry fleet install after correcting the reported condition')
  e.fs.delete(pending)
 end
 e.print('Fleet '..offer.controllerId..' software verified. Reconnecting with saved worker settings.')
 if not opts.noReboot then e.os.reboot() end
 return result
end
return M
