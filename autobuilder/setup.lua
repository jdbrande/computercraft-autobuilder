if fs.exists('/.autobuilder-install/transaction') then
  printError('Interrupted installation or setup. Run /installer.lua --recover, then reboot.')
  return
end
package.path='/?.lua;/?/init.lua;'..package.path
local args={...}
local options={}
if args[1]=='--menu' then table.remove(args,1); options.returnToApp=true end
local ok,err=pcall(function() return require('autobuilder.setup_wizard').run(args,_G,options) end)
if not ok then printError('Setup stopped: '..tostring(err)) end
if not ok and options.returnToApp then print('Press Enter to return to Autobuilder.'); read() end
