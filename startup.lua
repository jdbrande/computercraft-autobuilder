-- Copy to the computer root as /startup.lua. Preserve an existing startup first.
if fs.exists('/.autobuilder-install/transaction') then
  printError('Installation interrupted. Run /.autobuilder-install/transaction/recover.lua (or /installer.lua --recover), then reboot.')
  return
end
if not shell.run('/autobuilder/startup.lua') then
  printError('Autobuilder could not start. Check /autobuilder/settings.lua.')
end
