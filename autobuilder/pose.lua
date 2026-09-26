-- Operator-only recovery command; does not move the turtle.
if fs.exists('/.autobuilder-install/transaction') then
  printError('Installation interrupted. Run /.autobuilder-install/transaction/recover.lua (or /installer.lua --recover), then reboot.')
  return
end
package.path='/?.lua;/?/init.lua;'..package.path
local args={...}
local fix={x=tonumber(args[1]),y=tonumber(args[2]),z=tonumber(args[3])}
local U=require('autobuilder.core.util')
assert(#args==4 and U.position(fix) and U.heading(args[4]),'Usage: /autobuilder/pose.lua x y z north|east|south|west')
local config=require('autobuilder.config').load(require('autobuilder.settings'))
assert(config.role=='worker','Pose confirmation is for workers only')
local app=require('autobuilder.core.runtime').new(config,_G)
local ok,err=app:confirmPose(fix,args[4]); assert(ok,err)
print('Position and heading saved. Run /autobuilder/startup.lua to reconnect.')
