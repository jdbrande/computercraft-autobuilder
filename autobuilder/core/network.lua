local U=require('autobuilder.core.util')
local M={}
local MiningMessages=require('autobuilder.core.mining_messages')
local TaskMessages=require('autobuilder.core.task_messages')
local short=U.shortString
local Chunks=require('autobuilder.core.chunks')
local E=require('autobuilder.resources.exploration')
local function telemetry(p)
  if not short(p.label) or not short(p.status) then return false end
  if p.controllerBoot~=nil and (not U.integer(p.controllerBoot) or p.controllerBoot<1 or p.controllerBoot>9007199254740991) then return false end
  for _,field in ipairs({'fuelRequired','fuelLimit'}) do
    if p[field]~=nil and (not U.integer(p[field]) or p[field]<1 or p[field]>100000000) then return false end
  end
  if p.fuelBudget~=nil and not require('autobuilder.resources.fuel_budget').valid(p.fuelBudget,p.task,p.fuel) then return false end
  if p.fuelBudgetError~=nil and (not short(p.fuelBudgetError,512) or not short(p.task,128) or p.fuelBudget~=nil) then return false end
  if p.chunkAnchor~=nil and not Chunks.validAnchor(p.chunkAnchor) then return false end
  if p.poseRecovery~=nil and (not TaskMessages.validPoseReport(p.poseRecovery)
    or p.poseRecovery.stage~='settled' and p.poseRecovery.jobId~=p.task) then return false end
  if p.cargo~=nil and not require('autobuilder.storage.returns').validCargo(p.cargo) then return false end
  if p.depot~=nil and (not U.position(p.depot) or p.depot.heading~=nil and not U.heading(p.depot.heading)) then return false end
  if p.explorationHome~=nil and not E.home(p.explorationHome) then return false end
  local pos=p.position
  if type(pos)~='table' or type(pos.known)~='boolean' then return false end
  if pos.known and not U.position(pos) then return false end
  if pos.heading~=nil and not U.heading(pos.heading) then return false end
  if pos.source~=nil and not short(pos.source) then return false end
  if p.fuel~='unlimited' and (not U.finite(p.fuel) or p.fuel<0) then return false end
  local inv=p.inventory
  if type(inv)~='table' or inv.slots~=16 or not U.integer(inv.used) or inv.used<0 or inv.used>16 then return false end
  if type(p.capabilities)~='table' then return false end
  local count=0
  for k,v in pairs(p.capabilities) do count=count+1; if count>32 or not short(k) or type(v)~='boolean' then return false end end
  if p.task~=nil and not short(p.task,128) then return false end
  if not require('autobuilder.resources.materials').validResources(p.miningResources) then return false end
  if p.miningArea~=nil then
    if type(p.miningArea)~='table' or not U.position(p.miningArea.min) or not U.position(p.miningArea.max) then return false end
    for _,axis in ipairs({'x','y','z'}) do if p.miningArea.max[axis]<p.miningArea.min[axis] or p.miningArea.max[axis]-p.miningArea.min[axis]>256 then return false end end
  end
  if p.miningRoute~=nil and (type(p.miningRoute)~='table' or not U.position(p.miningRoute.entry)
    or p.miningRoute.fuelTarget~=nil and (not U.integer(p.miningRoute.fuelTarget) or p.miningRoute.fuelTarget<1 or p.miningRoute.fuelTarget>100000000)) then return false end
  return true
end
function M.validate(sender,m)
  if not U.integer(sender) or sender<0 or type(m)~='table' then return false,'invalid sender/envelope' end
  if m.version~=1 or m.sender~=sender then return false,'version or sender mismatch' end
  if not U.integer(m.boot) or m.boot<1 or not U.integer(m.sequence) or m.sequence<1 then return false,'invalid sequence' end
  if m.id~=tostring(sender)..':'..m.boot..':'..m.sequence then return false,'invalid message ID' end
  if type(m.payload)~='table' then return false,'invalid payload' end
  if m.type=='register' or m.type=='heartbeat' then
    if not telemetry(m.payload) then return false,'invalid telemetry' end
  elseif m.type=='ack' then
    if not short(m.payload.requestId,100) then return false,'invalid acknowledgement' end
  elseif m.type=='register_required' then
    if not short(m.payload.reason,128) then return false,'invalid registration request' end
  elseif type(m.type)=='string' and m.type:sub(1,5)=='task_' then return TaskMessages.validate(m.type,m.payload)
  else return MiningMessages.validate(m.type,m.payload) end
  return true
end
function M.new(hw,config,id,boot)
  assert(U.integer(id) and id>=0 and U.integer(boot) and boot>=1,'invalid local identity')
  local self={}; local sequence=0; local seen,queue={},{}
  function self:open()
    local ok,result=pcall(function()
      local found=false
      for _,name in ipairs(hw.peripheral.getNames()) do
        if hw.peripheral.getType(name)=='modem' and hw.peripheral.call(name,'isWireless') then
          if not hw.rednet.isOpen(name) then hw.rednet.open(name) end
          found=true
        end
      end
      return found
    end)
    if not ok then return false,'modem error: '..tostring(result) end
    if not result then return false,'wireless modem unavailable' end
    return true
  end
  function self:send(recipient,kind,payload)
    if not U.integer(recipient) or recipient<0 then return false,'invalid recipient' end
    local ready,err=self:open(); if not ready then return false,err end
    sequence=sequence+1
    local m={version=1,id=id..':'..boot..':'..sequence,sender=id,boot=boot,sequence=sequence,type=kind,payload=payload}
    local valid,why=M.validate(id,m); if not valid then return false,why end
    local ok,sent=pcall(hw.rednet.send,recipient,m,config.protocol)
    if not ok or not sent then return false,'rednet send failed: '..tostring(sent) end
    return true,m.id
  end
  function self:accept(sender,message,protocol,now)
    if protocol~=config.protocol then return nil,'different protocol' end
    local ok,err=M.validate(sender,message); if not ok then return nil,err end
    while #queue>0 and now-queue[1].at>(config.dedupTTL or 120) do
      local old=table.remove(queue,1); seen[old.id]=nil
    end
    if seen[message.id] then return nil,'duplicate message' end
    while #queue>=(config.dedupLimit or 512) do
      local old=table.remove(queue,1); seen[old.id]=nil
    end
    seen[message.id]=true; queue[#queue+1]={id=message.id,at=now}
    -- Copy only validated fields: ignore unknown, potentially cyclic network data.
    local p=message.payload; local clean={}
    if message.type=='register' or message.type=='heartbeat' then
      clean={controllerBoot=p.controllerBoot,label=p.label,status=p.status,fuel=p.fuel,task=p.task,fuelRequired=p.fuelRequired,fuelLimit=p.fuelLimit,
        fuelBudget=require('autobuilder.resources.fuel_budget').clean(p.fuelBudget),fuelBudgetError=p.fuelBudgetError,
        inventory={used=p.inventory.used,slots=16},capabilities=U.copy(p.capabilities),
        position={known=p.position.known,heading=p.position.heading,source=p.position.source}}
      if p.position.known then clean.position.x,clean.position.y,clean.position.z=p.position.x,p.position.y,p.position.z end
      if p.chunkAnchor then clean.chunkAnchor={provider=p.chunkAnchor.provider,x=p.chunkAnchor.x,z=p.chunkAnchor.z} end
      clean.poseRecovery=TaskMessages.poseReport(p.poseRecovery)
      clean.cargo=require('autobuilder.storage.returns').cleanCargo(p.cargo)
      if p.depot then clean.depot={x=p.depot.x,y=p.depot.y,z=p.depot.z,heading=p.depot.heading} end
      clean.miningResources=U.copy(p.miningResources)
      if p.miningRoute then clean.miningRoute={entry={x=p.miningRoute.entry.x,y=p.miningRoute.entry.y,z=p.miningRoute.entry.z},fuelTarget=p.miningRoute.fuelTarget} end
      if p.explorationHome then clean.explorationHome=E.cleanHome(p.explorationHome) end
      if p.miningArea then clean.miningArea={min={x=p.miningArea.min.x,y=p.miningArea.min.y,z=p.miningArea.min.z},max={x=p.miningArea.max.x,y=p.miningArea.max.y,z=p.miningArea.max.z}} end
    elseif message.type=='ack' then clean.requestId=p.requestId
    elseif message.type=='register_required' then clean.reason=p.reason
    elseif message.type:sub(1,5)=='task_' then clean=TaskMessages.clean(message.type,p)
    else clean=MiningMessages.clean(message.type,p) end
    return {version=1,id=message.id,sender=sender,boot=message.boot,sequence=message.sequence,type=message.type,payload=clean}
  end
  function self:cacheSize() return #queue end
  return self
end
return M
