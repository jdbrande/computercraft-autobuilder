-- CraftOS resolves `update` to this file when run from the computer root.
local args={...}
if not fs.exists('/installer.lua') and fs.exists('/.autobuilder-install/transaction/recover.lua') then
  if not shell.run('/.autobuilder-install/transaction/recover.lua') then error('Recovery failed; preserve the transaction directory.',0) end
  print('Recovery finished. Retry update to install the release.')
  return
end
if not fs.exists('/installer.lua') then error('Missing /installer.lua. Run the online installer first.',0) end
if not shell.run('/installer.lua','update',table.unpack(args)) then error('Update failed; inspect the message above.',0) end
