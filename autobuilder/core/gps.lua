local U=require('autobuilder.core.util')
local M={}
function M.heading(a,b)
  if not U.position(a) or not U.position(b) or a.y~=b.y then return nil,'invalid calibration coordinates' end
  local dx,dz=b.x-a.x,b.z-a.z
  if dx==1 and dz==0 then return 'east' elseif dx==-1 and dz==0 then return 'west'
  elseif dz==1 and dx==0 then return 'south' elseif dz==-1 and dx==0 then return 'north' end
  return nil,'calibration requires one forward block'
end
function M.new(api,options)
  local self={}; options=options or {}
  function self:locate()
    if options.enabled==false then return nil,'GPS disabled' end
    if not api or not api.locate then return nil,'GPS API unavailable' end
    local ok,x,y,z=pcall(api.locate,options.timeout or 2,false)
    if not ok then return nil,'GPS error: '..tostring(x) end
    if not U.finite(x) or not U.finite(y) or not U.finite(z) then return nil,'GPS unavailable' end
    local p={x=math.floor(x+0.5),y=math.floor(y+0.5),z=math.floor(z+0.5)}
    if not U.position(p) or math.abs(x-p.x)>0.05 or math.abs(y-p.y)>0.05 or math.abs(z-p.z)>0.05 then return nil,'GPS fix not on block grid' end
    return p
  end
  -- Infer heading from externally recorded fixes; never move as a side effect.
  function self:calibrate(before,after) return M.heading(before,after) end
  return self
end
return M
