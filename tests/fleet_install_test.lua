local IS=require('tests.install_support')
local H=require('autobuilder.install.sha256')
local function fixture()
 local e={fs=IS.fs(),textutils=IS.codec(),turtle={},now=0,prints={},runs={},reboots=0}
 local codec=require('tests.support').codec();e.textutils.serialize=codec.serialize;e.textutils.unserialize=codec.unserialize
 e.print=function(s) e.prints[#e.prints+1]=s end;e.write=function() end;e.read=function() error('fleet install must not prompt') end
 e.os={getComputerID=function() return 12 end,epoch=function() return e.now end,reboot=function() e.reboots=e.reboots+1 end}
 e.peripheral={getNames=function() return {'right'} end,getType=function() return 'modem' end,call=function() return true end}
 e.rednet={isOpen=function() return true end,open=function() end,send=function(id,m) e.request=m;return true end,broadcast=function(m) e.request=m end,
 receive=function(_,timeout)
  e.now=e.now+timeout*1000
  return 7,{version=1,type='fleet_offer',requestId=e.request.requestId,controllerId=7,release='0.30.0',baseUrl='https://example.com/repo',profile={role='worker',controllerId=7,automation={building=false}}}
 end}
 local m={schema=1,project='autobuilder',version='0.30.0',baseUrl='https://example.com/repo',roles={},files={}}
 local responses={};for r in pairs(require('autobuilder.install.manifest').roles) do m.roles[r]={runtime=r=='controller' and 'controller' or 'worker'} end
 local paths={};for _,p in ipairs(require('autobuilder.install.manifest').required) do paths[#paths+1]=p end;paths[#paths+1]='fleet.lua';paths[#paths+1]='autobuilder/fleet_apply.lua'
 for _,path in ipairs(paths) do
  local body='return true';local url=m.baseUrl..'/'..path;responses[url]=body
  m.files[#m.files+1]={path=path,url=url,roles={'worker'},version=m.version,bytes=#body,sha256=H.digest(body)}
 end
 responses[m.baseUrl..'/manifest.json']=e.textutils.serializeJSON(m)
 e.http={get=function(url) e.downloads=(e.downloads or 0)+1;local body=responses[url];assert(body,url);return {readAll=function() return body end,close=function() end} end}
 e.shell={run=function(path,arg) e.runs[#e.runs+1]={path=path,arg=arg};e.profile=e.textutils.unserializeJSON(e.fs.files[arg]);return true end}
 return e
end
test('fleet install discovers downloads through existing transaction applies a profile and reboots',function()
 local e=fixture();require('autobuilder.install.fleet').run({'install'},e,'https://example.com/repo')
 eq(e.reboots,1);eq(#e.runs,1);eq(e.profile.controllerId,7);assert(e.fs.exists('/autobuilder/.installation.json'))
 eq(e.fs.exists('/.autobuilder-install/transaction'),false)
end)
test('fleet repeat install preserves local settings without reapplying a profile',function()
 local e=fixture();local F=require('autobuilder.install.fleet');F.run({'install','--no-reboot'},e,'https://example.com/repo')
 local original=e.fs.files['/autobuilder/settings.lua']..'\n-- local annotation';e.fs.files['/autobuilder/settings.lua']=original
 F.run({'install','--no-reboot'},e,'https://example.com/repo');eq(e.fs.files['/autobuilder/settings.lua'],original);eq(#e.runs,1);eq(e.reboots,0)
end)
test('fleet refuses active or ambiguous recovery before discovery downloads or settings changes',function()
 local e=fixture();local F=require('autobuilder.install.fleet');F.run({'install','--no-reboot'},e,'https://example.com/repo')
 local saved=require('autobuilder.core.checkpoint').new(e.fs,e.textutils,'/autobuilder/data/worker.state')
 assert(saved:save({schema=1,id=12,role='worker',boot=1,phase='telemetry',position={known=false},currentTask={id='owned'}}))
 local before=e.downloads;eq(pcall(F.run,{'install'},e,'https://example.com/repo'),false);eq(e.downloads,before)
end)

test('fleet retries interrupted profile application without forgetting pending enrollment',function()
 local e=fixture();local F=require('autobuilder.install.fleet');local run=e.shell.run
 e.shell.run=function() return false end
 eq(pcall(F.run,{'install','--no-reboot'},e,'https://example.com/repo'),false)
 assert(e.fs.exists('/.autobuilder-fleet-profile.json'));assert(e.fs.exists('/autobuilder/.installation.json'))
 e.shell.run=run;F.run({'install','--no-reboot'},e,'https://example.com/repo');eq(#e.runs,1);eq(e.fs.exists('/.autobuilder-fleet-profile.json'),false)
end)
test('fleet rejects a controller release mismatch before promoting software or enabling roles',function()
 local e=fixture();local receive=e.rednet.receive
 e.rednet.receive=function(...) local id,m=receive(...);m.release='0.31.0';return id,m end
 eq(pcall(require('autobuilder.install.fleet').run,{'install'},e,'https://example.com/repo'),false)
 eq(e.fs.exists('/autobuilder/.installation.json'),false);eq(e.fs.exists('/autobuilder/settings.lua'),false);eq(e.reboots,0)
end)
