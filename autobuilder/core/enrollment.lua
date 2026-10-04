local U=require('autobuilder.core.util')
local D=require('autobuilder.install.discovery')
local M={}
local allowed={initialPosition=true,depot=true,automation=true,mining=true,supply=true,craftingStation=true,storageInventories=true,
 scanner=true,restrictedAreas=true,allowedMiningBlocks=true,protectedBlocks=true,minimumFuelReserve=true,maxTravelDistance=true,
 turtleFuelReserveItems=true,gps=true,label=true,locations=true}
function M.validate(f)
 assert(type(f)=='table' and type(f.enabled)=='boolean' and type(f.profiles)=='table' and #f.profiles<=128,'invalid fleet enrollment')
 local ids,berths={},{};local count=0
 for i,p in pairs(f.profiles) do
  count=count+1;assert(U.integer(i) and i>=1 and i<=#f.profiles and type(p)=='table','invalid fleet profile list')
  assert(p.workerId==nil or U.integer(p.workerId) and p.workerId>=0 and p.workerId<=2147483647 and not ids[p.workerId],'invalid or duplicate fleet worker ID')
  if p.workerId then ids[p.workerId]=true end
  local settings=D.copy(p.settings);assert(type(settings)=='table','fleet profile settings required')
  for k in pairs(settings) do assert(allowed[k],'unsupported fleet profile key: '..tostring(k)) end
  assert(U.position(settings.initialPosition) and U.heading(settings.initialPosition.heading),'fleet berth requires position and heading')
  local key=settings.initialPosition.x..','..settings.initialPosition.y..','..settings.initialPosition.z
  assert(not berths[key],'duplicate fleet berth');berths[key]=true
  settings.role='worker';settings.controllerId=0
  require('autobuilder.config').load(settings)
 end
 assert(count==#f.profiles,'sparse fleet profile list');return true
end
function M.profile(value,controllerId)
 local p=D.copy(value);assert(type(p)=='table' and p.role=='worker' and p.controllerId==controllerId,'fleet profile identity differs')
 for k in pairs(p) do assert(allowed[k] or k=='role' or k=='controllerId' or k=='protocol' or k=='fuel' or k=='chunkLoading','unsupported received profile key: '..tostring(k)) end
 local c=require('autobuilder.config').load(p)
 local physical=c.mining.enabled
 for _,k in ipairs({'building','crafting','courier','logging','farming'}) do physical=physical or c.automation[k] end
 assert(not physical or U.position(c.initialPosition) and U.heading(c.initialPosition.heading) and U.position(c.depot),'physical fleet profile needs a configured berth and depot')
 return p
end
function M.release(e)
 local Manifest=require('autobuilder.install.manifest');local I=require('autobuilder.install.io')
 local m=e.textutils.unserializeJSON(I.read(e.fs,'/manifest.json'));Manifest.validate(m)
 local base=m.baseUrl
 if e.fs.exists(Manifest.receipt) then
  local r=e.textutils.unserializeJSON(I.read(e.fs,Manifest.receipt));assert(type(r)=='table' and r.version==m.version,'fleet release receipt differs');base=Manifest.base(r.baseUrl)
 end
 return {version=m.version,baseUrl=base}
end
function M.reply(e,config,release,sender,message)
 if config.role~='controller' or not config.fleet.enabled or not release or not U.integer(sender) or sender<0
  or type(message)~='table' or message.version~=1 or message.type~='fleet_discover' or not U.shortString(message.requestId,100)
  or message.purpose~=nil and message.purpose~='configure' and message.purpose~='update'
  or message.position~=nil and not U.position(message.position) then return false,'fleet discovery unavailable' end
 local found
 for _,p in ipairs(config.fleet.profiles) do if p.workerId==sender then found=p;break end end
 if message.purpose~='update' and found and message.position and U.distance(found.settings.initialPosition,message.position)~=0 then return false,'configured berth differs from GPS' end
 if not found and message.position then
  for _,p in ipairs(config.fleet.profiles) do
   if p.workerId==nil and U.distance(p.settings.initialPosition,message.position)==0 then found=p;break end
  end
 end
 local profile=found and D.copy(found.settings) or {automation={enabled=true,building=false,crafting=false,courier=false,logging=false,farming=false},mining={enabled=false},fuel={enabled=false}}
 profile.role='worker';profile.controllerId=e.os.getComputerID();profile.protocol=config.protocol
 if found then
  profile.chunkLoading={enabled=config.chunkLoading.enabled,anchor=false,areas=U.copy(config.chunkLoading.areas)}
  if profile.depot then profile.fuel=U.copy(config.fuel);profile.fuel.stations={} end
 end
 return e.rednet.send(sender,{version=1,type='fleet_offer',requestId=message.requestId,controllerId=profile.controllerId,
  release=release.version,baseUrl=release.baseUrl,profile=profile},D.protocol)
end
return M
