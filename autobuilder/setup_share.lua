-- Read-only discovery. Configuration is only changed by a local setup wizard.
local U=require('autobuilder.core.util')
local M={}
function M.reply(e,config,workers,sender,message)
  if config.role~='controller' or not workers[tostring(sender)] or type(message)~='table'
    or message.version~=1 or message.type~='setup_request' or not U.shortString(message.requestId,64)
    or config.supply.inventory=='' then return false,'setup profile unavailable' end
  return e.rednet.send(sender,{version=1,type='setup_profile',requestId=message.requestId,
    supply={inventory=config.supply.inventory,side=config.supply.side}},config.protocol..'.setup')
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
      and type(m.supply)=='table' and U.shortString(m.supply.inventory,128)
      and ({front=true,up=true,down=true})[m.supply.side] then
      return {inventory=m.supply.inventory,side=m.supply.side}
    end
  end
  error('Controller '..config.controllerId..' did not provide setup settings. Update it, run setup there first, then reboot it and retry.')
end
return M
