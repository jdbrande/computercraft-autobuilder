-- These hardware simulations keep their complete small terrain in memory. Declare
-- that guarantee explicitly; production defaults and chunk-specific tests stay strict.
local U=require('autobuilder.core.util')
local C=require('autobuilder.config')
local M={}
function M.load(overrides)
  local settings=U.copy(overrides or {})
  settings.chunkLoading=settings.chunkLoading or {enabled=true,anchor=false,areas={{minX=-64,maxX=64,minZ=-64,maxZ=64}}}
  return C.load(settings)
end
return M
