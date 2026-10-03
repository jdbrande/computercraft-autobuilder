local U=require('autobuilder.core.util')
local Materials=require('autobuilder.resources.materials')
local E=require('autobuilder.resources.exploration')
local M={}
local phases={setup=true,travel=true,work=true,['return']=true,unload=true,blocked=true,completed=true}
function M.validate(kind,p)
  if not U.shortString(p.jobId,100) then return false,'invalid job ID' end
  if kind=='mine_assign' then
    if p.returnRequested~=nil and (not p.exploration or type(p.returnRequested)~='boolean') then return false,'invalid return request' end
    if p.exploration and (not E.geometry(p.exploration) or p.quantity>64) then return false,'invalid exploration assignment' end
    if not Materials.validResources(p.miningResources) then return false,'invalid assigned mining resources' end
    if not Materials.get(p.item) or not U.integer(p.quantity) or p.quantity<1 or p.quantity>1000000 then return false,'invalid mining assignment' end
    if p.miningArea then
      if type(p.miningArea)~='table' or not U.position(p.miningArea.min) or not U.position(p.miningArea.max) then return false,'invalid assigned mining area' end
      for _,axis in ipairs({'x','y','z'}) do if p.miningArea.min[axis]>p.miningArea.max[axis] or p.miningArea.max[axis]-p.miningArea.min[axis]>256 then return false,'invalid assigned mining area' end end
    end
  elseif kind=='mine_progress' then
    if p.exploration and (not E.report(p.exploration) or p.phase=='completed' and not p.exploration.result) then return false,'invalid exploration report' end
    if not phases[p.phase] or not U.integer(p.delivered) or p.delivered<0 or p.delivered>1000000
      or not U.integer(p.held) or p.held<0 or p.held>1024 then return false,'invalid mining progress' end
    if p.assignedQuantity~=nil and (not U.integer(p.assignedQuantity) or p.assignedQuantity<1 or p.assignedQuantity>1000000) then return false,'invalid assigned quantity' end
    if p.error~=nil and not U.shortString(p.error,512) then return false,'invalid job error' end
  elseif kind~='mine_ack' and kind~='mine_resume' and kind~='mine_return' then return false,'unsupported message type' end
  return true
end
function M.clean(kind,p)
  local out={jobId=p.jobId}
  if p.exploration then out.exploration=kind=='mine_assign' and E.cleanGeometry(p.exploration) or E.cleanReport(p.exploration) end
  if kind=='mine_assign' then
    out.returnRequested=p.returnRequested; out.item=p.item; out.quantity=p.quantity; out.miningResources=U.copy(p.miningResources)
    if p.miningArea then out.miningArea={min={x=p.miningArea.min.x,y=p.miningArea.min.y,z=p.miningArea.min.z},max={x=p.miningArea.max.x,y=p.miningArea.max.y,z=p.miningArea.max.z}} end
  elseif kind=='mine_progress' then out.phase=p.phase; out.delivered=p.delivered; out.held=p.held; out.error=p.error; out.assignedQuantity=p.assignedQuantity end
  return out
end
return M
