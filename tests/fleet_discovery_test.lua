local D=require('autobuilder.install.discovery')
local function env(offers)
 local e={now=0,sent={},opened={}}
 e.os={getComputerID=function() return 12 end,epoch=function() return e.now end}
 e.peripheral={getNames=function() return {'right'} end,getType=function() return 'modem' end,call=function() return true end}
 e.rednet={open=function(name) e.opened[name]=true end,isOpen=function() return false end,
  broadcast=function(m,p) e.sent[#e.sent+1]={message=m,protocol=p};return true end,
  send=function(id,m,p) e.sent[#e.sent+1]={id=id,message=m,protocol=p};return true end,
  receive=function(protocol,timeout)
   local v=table.remove(offers,1);if not v then e.now=e.now+timeout*1000;return nil end
   return v.id,{version=1,type='fleet_offer',requestId=v.nonce or e.sent[1].message.requestId,controllerId=v.id,
    release='0.30.0',baseUrl='https://example.com/repo',profile=v.profile}
  end}
 return e
end
test('fleet discovery selects one nonce bound controller and preserves bounded profile data',function()
 local e=env({{id=7,nonce='old'},{id=7,profile={automation={building=true}}},{id=7,profile={automation={building=true}}}})
 local result=D.find(e,{});eq(result.controllerId,7);eq(result.profile.automation.building,true);eq(e.opened.right,true)
end)
test('fleet discovery refuses ambiguity and an explicit controller filters other offers',function()
 local ok,err=pcall(D.find,env({{id=7},{id=8}}),{});eq(ok,false);assert(tostring(err):find('multiple'))
 eq(D.find(env({{id=8},{id=7}}),{controllerId=7}).controllerId,7)
end)
test('fleet discovery rejects cyclic oversized or executable profile values and times out',function()
 local cycle={};cycle.a=cycle
 for _,p in ipairs({cycle,{callback=function() end},{text=string.rep('x',65537)}}) do
  eq(pcall(D.find,env({{id=7,profile=p}}),{}),false)
 end
 eq(pcall(D.find,env({}),{}),false)
end)

test('fleet discovery packet exhaustion cannot silently select the first fleet',function()
 for _,stale in ipairs({false,true}) do
  local offers={};for i=1,32 do offers[i]={id=7,nonce=stale and i>1 and 'stale' or nil} end;offers[33]={id=8}
  local e=env(offers);local ok,why=pcall(D.find,e,{})
  eq(ok,false);assert(tostring(why):find('controller'));eq(e.now,0);eq(#offers,1)
 end
 local offers={};for i=1,33 do offers[i]={id=7} end
 eq(D.find(env(offers),{controllerId=7}).controllerId,7)
end)
