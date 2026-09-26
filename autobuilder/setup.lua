if fs.exists('/.autobuilder-install/transaction') then
  printError('Interrupted installation or setup. Run /installer.lua --recover, then reboot.')
  return
end
package.path='/?.lua;/?/init.lua;'..package.path
local args={...}
local ok,err=pcall(function() return require('autobuilder.setup_wizard').run(args,_G) end)
if not ok then printError('Setup stopped: '..tostring(err)) end
