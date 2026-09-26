if fs.exists('/.autobuilder-install/transaction') then
  printError('Installation interrupted. Run /.autobuilder-install/transaction/recover.lua (or /installer.lua --recover), then reboot.')
  return
end
package.path='/?.lua;/?/init.lua;'..package.path
local config=require('autobuilder.config').load(require('autobuilder.settings'))
local ok,err=pcall(function() require('autobuilder.core.runtime').run(config) end)
if not ok then
  printError('Autobuilder stopped: '..tostring(err))
  print('Check /autobuilder/logs and /autobuilder/data. State was not reset.')
end
