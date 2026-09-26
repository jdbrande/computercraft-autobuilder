if fs.exists('/.autobuilder-install/transaction') then
  printError('Installation interrupted. Run /.autobuilder-install/transaction/recover.lua (or /installer.lua --recover), then reboot.')
  return
end
package.path='/?.lua;/?/init.lua;'..package.path
local ok,err=pcall(function()
  while true do
    package.loaded['autobuilder.settings']=nil
    local config=require('autobuilder.config').load(require('autobuilder.settings'))
    local app=require('autobuilder.core.runtime').run(config)
    if app.nextProgram~='setup' then return end
    shell.run('/autobuilder/setup.lua','--menu')
    assert(not fs.exists('/.autobuilder-install/transaction'),'Setup recovery required: run /installer.lua --recover')
  end
end)
if not ok then
  printError('Autobuilder stopped: '..tostring(err))
  print('Check /autobuilder/logs and /autobuilder/data. State was not reset.')
end
