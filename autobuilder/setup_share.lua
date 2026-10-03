-- Read-only discovery. Configuration is only changed by a local setup wizard.
local U=require('autobuilder.core.util')
local M={}
function M.reply(e,config,workers,sender,message)
  if config.role~='controller' or not workers[tostring(sender)] or type(message)~='table'
    or message.version~=1 or message.type~='setup_request' or not U.shortString(message.requestId,64)
    or config.supply.inventory=='' and not config.fuel.enabled then return false,'setup profile unavailable' end
  local fuel=U.copy(config.fuel); fuel.stations={} -- station ownership stays on the controller
  return e.rednet.send(sender,{version=1,type='setup_profile',requestId=message.requestId,
    fuel=fuel,supply=config.supply.inventory~='' and {inventory=config.supply.inventory,side=config.supply.side} or nil},config.protocol..'.setup')
end
function M.fetch(e,config)
  local request=tostring(e.os.getComputerID())..':'..tostring(e.os.epoch('utc'))
  local protocol=config.protocol..'.setup'
  assert(e.rednet.send(config.controllerId,{version=1,type='setup_request',requestId=request},protocol),'Cannot contact controller')
  -- Ignore unrelated replies, but bound both elapsed time and packet count.
  local deadline=e.os.epoch('utc')+5000
  for _=1,16 do
    local remaining=(deadline-e.os.epoch('utc'))/1000; if remaining<=0 then break end
    local sender,m=e.rednet.receive(protocol,remaining)
    if sender==nil then break end
    if sender==config.controllerId and type(m)=='table' and m.version==1 and m.type=='setup_profile' and m.requestId==request
      then
      local fuel
      if m.fuel~=nil then
        local ok=pcall(require('autobuilder.resources.fuel').validate,m.fuel,{})
        if ok and #m.fuel.stations==0 then
          local f=m.fuel
          fuel={enabled=f.enabled,item=f.item,low=f.low,target=f.target,values=U.copy(f.values),returns=U.copy(f.returns),stations={}}
        end
      end
      local supply=type(m.supply)=='table' and U.shortString(m.supply.inventory,128)
        and ({front=true,up=true,down=true})[m.supply.side] and m.supply or nil
      if supply or fuel then return {inventory=supply and supply.inventory,side=supply and supply.side,fuel=fuel} end
    end
  end
  error('Controller '..config.controllerId..' did not provide setup settings. Update it, run setup there first, then reboot it and retry.')
end
return M
