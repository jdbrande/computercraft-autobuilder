if fs.exists('/.autobuilder-install/transaction') then
  printError('Installation interrupted. Run /.autobuilder-install/transaction/recover.lua (or /installer.lua --recover), then reboot.')
  return
end
package.path='/?.lua;/?/init.lua;'..package.path
local config=require('autobuilder.config').load(require('autobuilder.settings'))
assert(config.role=='worker','Set role="worker" and controllerId in /autobuilder/settings.lua')
return require('autobuilder.core.runtime').run(config)
