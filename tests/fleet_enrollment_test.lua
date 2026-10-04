local C=require('autobuilder.config')
local E=require('autobuilder.core.enrollment')
local function environment()
 local e={sent={}};e.os={getComputerID=function() return 7 end}
 e.rednet={send=function(id,m,p) e.sent[#e.sent+1]={id=id,message=m,protocol=p};return true end}
 return e
end
local function config()
 return C.load({fleet={enabled=true,profiles={{workerId=12,settings={initialPosition={x=1,y=64,z=2,heading='north'},depot={x=1,y=64,z=2},automation={building=true}}},
  {settings={initialPosition={x=3,y=64,z=4,heading='east'},depot={x=3,y=64,z=4},automation={courier=true}}}}}})
end
local release={version='0.30.0',baseUrl='https://example.com/repo'}
test('fleet enrollment shares only an enabled nonce bound profile by ID or configured GPS berth',function()
 local e=environment();local c=config();local request={version=1,type='fleet_discover',requestId='12:1:1'}
 assert(E.reply(e,c,release,12,request));local offer=e.sent[1].message;eq(offer.controllerId,7);eq(offer.profile.automation.building,true);eq(offer.profile.controllerId,7)
 request.position={x=3,y=64,z=4};assert(E.reply(e,c,release,13,request));eq(e.sent[2].message.profile.automation.courier,true)
 c.fleet.enabled=false;eq(E.reply(e,c,release,12,request),false);eq(#e.sent,2)
end)
test('unmatched fleet enrollment retains telemetry without inventing movement roles',function()
 local e=environment();assert(E.reply(e,config(),release,99,{version=1,type='fleet_discover',requestId='99:1'}))
 local c=C.load(e.sent[1].message.profile);eq(c.role,'worker');assert(not c.capabilities.building);eq(c.mining.enabled,false);eq(c.initialPosition,nil)
end)
test('fleet profiles reject duplicate berths unsafe paths nested enrollment and conflicting GPS',function()
 for _,settings in ipairs({{dataDir='/elsewhere'},{fleet={enabled=true}},{role='controller'},{automation={building=true}}}) do
  eq(pcall(C.load,{fleet={enabled=true,profiles={{workerId=12,settings=settings}}}}),false)
 end
 local c=config();c.fleet.profiles[2].settings.initialPosition=c.fleet.profiles[1].settings.initialPosition
 eq(pcall(E.validate,c.fleet),false)
 local e=environment();eq(E.reply(e,config(),release,12,{version=1,type='fleet_discover',requestId='x',position={x=90,y=64,z=2}}),false);eq(#e.sent,0)
end)

test('received profiles cannot redirect local state paths or advertise physical roles without a real berth',function()
 for _,p in ipairs({{role='worker',controllerId=7,dataDir='/elsewhere'}, {role='controller',controllerId=7},
  {role='worker',controllerId=7,automation={building=true}}, {role='worker',controllerId=8}}) do
  eq(pcall(E.profile,p,7),false)
 end
 local p=E.profile({role='worker',controllerId=7,protocol='fleet.test',automation={building=false}},7)
 eq(p.controllerId,7);eq(p.protocol,'fleet.test')
end)
