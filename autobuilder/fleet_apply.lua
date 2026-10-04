-- Invoked by the standalone fleet installer after verified code promotion.
assert(not fs.exists('/.autobuilder-install/transaction'),'Recover interrupted installation before enrollment')
package.path='/?.lua;/?/init.lua;'..package.path
local path=...
assert(path=='/.autobuilder-fleet-profile.json','Invalid enrollment profile path')
local raw=require('autobuilder.install.io').read(fs,path)
assert(#raw<=65536,'Fleet profile too large')
return require('autobuilder.setup_wizard').applyFleet(_G,textutils.unserializeJSON(raw))
