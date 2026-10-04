local Manifest=require('autobuilder.install.manifest')
local M={protocol='autobuilder.fleet.v1'}
-- Enrollment carries configuration data, never code. Bound before schema loading.
function M.copy(value)
  local seen,nodes,bytes={},0,0
  local function copy(v,depth)
    nodes=nodes+1;assert(nodes<=4096 and depth<=12,'fleet profile too large')
    local kind=type(v)
    if kind=='nil' or kind=='boolean' then return v end
    if kind=='number' then assert(v==v and math.abs(v)<math.huge,'invalid profile number');return v end
    if kind=='string' then bytes=bytes+#v;assert(#v<=2048 and bytes<=65536,'fleet profile too large');return v end
    assert(kind=='table' and not seen[v],'fleet profile must be acyclic data')
    seen[v]=true;local result={}
    for k,x in pairs(v) do
      assert(type(k)=='string' and #k<=128 or type(k)=='number' and k%1==0 and k>=1 and k<=4096,'invalid profile key')
      result[copy(k,depth+1)]=copy(x,depth+1)
    end
    seen[v]=nil;return result
  end
  return copy(value,0)
end
local function id(n) return type(n)=='number' and n%1==0 and n>=0 and n<=2147483647 end
local sequence=0
function M.find(e,opts)
  opts=opts or {};local selected=opts.controllerId and tonumber(opts.controllerId)
  assert(opts.controllerId==nil or id(selected),'invalid controller ID')
  local opened=false
  for _,name in ipairs(e.peripheral.getNames()) do
    if e.peripheral.getType(name)=='modem' and e.peripheral.call(name,'isWireless') then
      if not e.rednet.isOpen(name) then e.rednet.open(name) end;opened=true
    end
  end
  assert(opened,'Attach a wireless modem for fleet discovery')
  sequence=sequence+1
  local request={version=1,type='fleet_discover',requestId=e.os.getComputerID()..':'..e.os.epoch('utc')..':'..sequence}
  request.purpose=opts.purpose or 'configure'
  if opts.position then request.position=M.copy(opts.position) end
  if selected then assert(e.rednet.send(selected,request,M.protocol),'Cannot contact controller')
  else e.rednet.broadcast(request,M.protocol) end
  local deadline=e.os.epoch('utc')+3000;local offers={};local exhausted=true
  for _=1,32 do
    local remaining=(deadline-e.os.epoch('utc'))/1000;if remaining<=0 then exhausted=false;break end
    local sender,m=e.rednet.receive(M.protocol,remaining);if sender==nil then exhausted=false;break end
    if id(sender) and (not selected or sender==selected) and type(m)=='table' and m.version==1 and m.type=='fleet_offer'
      and m.requestId==request.requestId and m.controllerId==sender then
      local ok,offer=pcall(function()
        Manifest.compare(m.release,m.release)
        return {controllerId=sender,release=m.release,baseUrl=Manifest.base(m.baseUrl),profile=M.copy(m.profile)}
      end)
      if ok then offers[sender]=offer end
    end
  end
  assert(selected or not exhausted or e.os.epoch('utc')>=deadline,'Discovery packet limit reached; retry or use --controller ID')
  local result
  for _,offer in pairs(offers) do assert(not result,'Found multiple controllers; use --controller ID');result=offer end
  assert(result,'No enabled fleet controller replied');return result
end
return M
