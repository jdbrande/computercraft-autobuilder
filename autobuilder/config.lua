local U=require('autobuilder.core.util')
local M={}
M.defaults={
  role='controller', protocol='autobuilder.v1',
  heartbeatInterval=5, registrationInterval=15, workerTimeout=30,
  checkpointInterval=5, gps={enabled=true,timeout=2,interval=30},
  dataDir='/autobuilder/data', logDir='/autobuilder/logs',
  log={level='INFO',maxBytes=65536,backups=3},
  minimumFuelReserve=100, movementRetries=2, maxTravelDistance=1024,
  restrictedAreas={}, locations={}, capabilities={telemetry=true},
  maxWorkers=128, dedupLimit=512, dedupTTL=120,
  chunkLoading={enabled=true,anchor=false,areas={}},
  storageInventories={}, providerPreferences={}, fuel=require('autobuilder.resources.fuel').defaults,
  furnaces={}, smeltingFuelItem='minecraft:coal', smeltingWaitSteps=600, turtleFuelReserveItems={['minecraft:coal']=64},
  craftingStation={buffer='',input='',output='',inputSide='up',outputSide='down'},
  craftingStations={},craftingBatchSize=2,
  logistics={batchSize=64,nodes={}},
  automation={enabled=true,building=false,crafting=false,courier=false,logging=false,farming=false},
  build={enabled=false,autoSite=false,origin={x=0,y=64,z=0},rotation=0,mirrorX=false,mirrorZ=false,regionSize=8},
  blueprintDir='/autobuilder/blueprints', clearSite=false,
  supply={inventory='',side='front',batch=64}, treeFarms={}, farms={}, depotExpansion={}, farmRetrySeconds=60,
  autoDepotExpansion={enabled=false,freeSlots=2},
  scanner={side='left',slot=16,radius=8,ttl=15,cooldown=3,maxCost=0,maxWait=30},
  exploration={enabled=false,revision=0,base={},bounds={},baseProtection={},dimensionMinY=-64,dimensionMaxY=319},
  mining={mode='fixed',exitRoute={},enabled=false,resources={},fallback=true,maxSurveySteps=256,pathBudget=4096,returnMargin=8,fuelTarget=1000},
  allowedMiningBlocks={['minecraft:stone']=true,['minecraft:deepslate']=true,
    ['minecraft:cobblestone']=true,['minecraft:cobbled_deepslate']=true,
    ['minecraft:granite']=true,['minecraft:diorite']=true,['minecraft:andesite']=true,
    ['minecraft:tuff']=true,['minecraft:dirt']=true,['minecraft:gravel']=true},
  protectedBlocks={['minecraft:bedrock']=true},
}
for _,material in pairs(require('autobuilder.resources.materials').all()) do
  for block in pairs(material.blocks) do M.defaults.allowedMiningBlocks[block]=true end
end
local function merge(dst,src)
  for k,v in pairs(src) do
    assert(dst[k]~=nil or k=='controllerId' or k=='initialPosition' or k=='depot' or k=='label' or k=='entry' or k=='bounds' or k=='x' or k=='y' or k=='z' or k=='min' or k=='max', 'Unknown config key: '..tostring(k))
    if type(v)=='table' and type(dst[k])=='table' then
      -- These maps/lists are user-defined rather than schema objects.
      if k=='nodes' or k=='areas' or k=='values' or k=='returns' or k=='stations' or k=='providerPreferences' or k=='exitRoute' or k=='resources' or k=='locations' or k=='capabilities' or k=='restrictedAreas' or k=='storageInventories' or k=='allowedMiningBlocks' or k=='protectedBlocks'
        or k=='craftingStations' or k=='furnaces' or k=='turtleFuelReserveItems' or k=='treeFarms' or k=='farms' or k=='depotExpansion' then dst[k]=U.copy(v)
      else merge(dst[k],v) end
    else dst[k]=U.copy(v) end
  end
end
function M.load(overrides)
  local c=U.copy(M.defaults); merge(c,overrides or {})
  require('autobuilder.core.chunks').validate(c)
  assert(require('autobuilder.resources.providers').validatePreferences(c.providerPreferences))
  assert(require('autobuilder.resources.fuel').validate(c.fuel,c))
  assert(c.role=='controller' or c.role=='worker','role must be controller or worker')
  if c.role=='worker' then assert(U.integer(c.controllerId) and c.controllerId>=0,'worker requires controllerId') end
  assert(type(c.protocol)=='string' and #c.protocol>0 and #c.protocol<=64,'invalid protocol')
  for _,k in ipairs({'heartbeatInterval','registrationInterval','workerTimeout','checkpointInterval','maxWorkers','dedupLimit','dedupTTL','maxTravelDistance'}) do
    assert(U.finite(c[k]) and c[k]>0,k..' must be positive')
  end
  assert(c.workerTimeout>c.heartbeatInterval*2,'workerTimeout must exceed two heartbeats')
  assert(U.finite(c.minimumFuelReserve) and c.minimumFuelReserve>=0,'invalid fuel reserve')
  assert(U.integer(c.movementRetries) and c.movementRetries>=1 and c.movementRetries<=10,'movementRetries must be 1..10')
  assert(type(c.gps.enabled)=='boolean' and U.finite(c.gps.timeout) and c.gps.timeout>0 and U.finite(c.gps.interval) and c.gps.interval>0,'invalid GPS config')
  for _,k in ipairs({'dataDir','logDir'}) do assert(type(c[k])=='string' and c[k]:sub(1,1)=='/',k..' must be absolute') end
  assert(({DEBUG=true,INFO=true,WARN=true,ERROR=true})[c.log.level],'invalid log level')
  assert(U.integer(c.log.maxBytes) and c.log.maxBytes>=40 and U.integer(c.log.backups) and c.log.backups>=1 and c.log.backups<=10,'invalid log limits')
  for _,k in ipairs({'depot','initialPosition'}) do
    if c[k] then assert(U.position(c[k]),'invalid '..k); assert(not c[k].heading or U.heading(c[k].heading),'invalid heading') end
  end
  for name,p in pairs(c.locations) do assert(type(name)=='string' and U.position(p),'invalid named location') end
  for _,area in ipairs(c.restrictedAreas) do
    assert(U.position(area.min) and U.position(area.max),'invalid restricted area')
    for _,axis in ipairs({'x','y','z'}) do assert(area.min[axis]<=area.max[axis],'reversed restricted area') end
  end
  if c.label~=nil then assert(U.shortString(c.label),'invalid label') end
  for _,map in ipairs({c.allowedMiningBlocks,c.protectedBlocks}) do
    for k,v in pairs(map) do assert(U.shortString(k,128) and type(v)=='boolean','invalid block rule') end
  end
  local seen={}
  for _,name in ipairs(c.storageInventories) do assert(U.shortString(name,128) and not seen[name],'invalid/duplicate storage inventory'); seen[name]=true end
  assert(c.scanner.side=='left' or c.scanner.side=='right','invalid scanner side')
  assert(c.scanner.slot==16,'scanner slot must be 16 in Milestone 2')
  for _,k in ipairs({'radius','ttl','cooldown','maxCost','maxWait'}) do assert(U.finite(c.scanner[k]) and c.scanner[k]>=0,'invalid scanner '..k) end
  assert(U.integer(c.scanner.radius) and c.scanner.radius>=1 and c.scanner.radius<=16,'scanner radius must be 1..16')
  assert(c.scanner.maxCost==0,'Milestone 2 uses free scans to preserve return fuel')
  assert(type(c.mining.enabled)=='boolean' and type(c.mining.fallback)=='boolean','invalid mining mode')
  assert(require('autobuilder.resources.materials').validResources(c.mining.resources),'invalid mining resources')
  for _,k in ipairs({'maxSurveySteps','pathBudget','returnMargin','fuelTarget'}) do assert(U.integer(c.mining[k]) and c.mining[k]>0,'invalid mining '..k) end
  assert(c.mining.mode=='fixed' or c.mining.mode=='explore','invalid mining mode')
  assert(require('autobuilder.resources.exploration').validate(c.exploration))
  if c.mining.enabled and c.mining.mode=='explore' then
    assert(c.depot and U.position(c.depot),'exploration requires depot')
    local previous=c.depot
    for _,p in ipairs(c.mining.exitRoute) do assert(U.position(p) and U.distance(previous,p)==1,'invalid clear exit route'); previous=p end
  end
  if c.mining.enabled and c.mining.mode=='fixed' then
    assert(c.depot and U.position(c.mining.entry),'mining requires depot and entry coordinates')
    local b=c.mining.bounds
    assert(type(b)=='table' and U.position(b.min) and U.position(b.max),'mining bounds required')
    for _,axis in ipairs({'x','y','z'}) do assert(b.max[axis]>=b.min[axis] and b.max[axis]-b.min[axis]<=256,'mining bounds must span 0..256 blocks per axis') end
    assert(require('autobuilder.core.pathfinding').inside(c.mining.entry,b),'entry must be inside mining bounds')
    assert(U.distance(c.depot,c.mining.entry)<=c.maxTravelDistance,'mine entry too far from depot')
  end
  c.capabilities.mining=c.mining.enabled and true or nil
  c.capabilities.explorationV1=c.mining.enabled and c.mining.mode=='explore' and true or nil
  for k,v in pairs(c.automation) do assert(type(v)=='boolean','invalid automation flag '..k) end
  for _,k in ipairs({'building','crafting','courier','logging','farming'}) do c.capabilities[k]=c.automation.enabled and c.automation[k] or nil end
  c.capabilities.logisticsV1=c.capabilities.courier and true or nil
  c.capabilities.sitePreparation=c.capabilities.building and true or nil
  require('autobuilder.factory.stations').validate(c)
  require('autobuilder.storage.nodes').validate(c)
  c.capabilities.isolatedCraftingV1=c.capabilities.crafting and c.craftingStation.buffer~='' and true or nil
  assert(U.position(c.build.origin) and ({[0]=true,[90]=true,[180]=true,[270]=true})[c.build.rotation],'invalid build transform')
  assert(type(c.build.enabled)=='boolean' and type(c.build.autoSite)=='boolean' and type(c.build.mirrorX)=='boolean' and type(c.build.mirrorZ)=='boolean','invalid build flags')
  assert(U.integer(c.build.regionSize) and c.build.regionSize>=1 and c.build.regionSize<=8,'regionSize must be 1..8')
  assert(type(c.clearSite)=='boolean' and type(c.blueprintDir)=='string' and c.blueprintDir:sub(1,1)=='/','invalid blueprint/clearing config')
  assert(({front=true,up=true,down=true})[c.supply.side] and U.integer(c.supply.batch) and c.supply.batch>=1 and c.supply.batch<=64,'invalid supply station')
  assert(type(c.supply.inventory)=='string','supply inventory must be a wired peripheral name')
  for _,name in ipairs(c.furnaces) do assert(U.shortString(name,128),'invalid furnace peripheral') end
  for item,n in pairs(c.turtleFuelReserveItems) do assert(U.shortString(item,128) and U.integer(n) and n>=0,'invalid reserved fuel') end
  assert(U.shortString(c.smeltingFuelItem,128),'invalid smelting fuel item')
  assert(U.integer(c.smeltingWaitSteps) and c.smeltingWaitSteps>0,'invalid furnace wait budget')
  assert(U.finite(c.farmRetrySeconds) and c.farmRetrySeconds>=5,'farmRetrySeconds must be at least 5')
  assert(type(c.autoDepotExpansion.enabled)=='boolean' and U.integer(c.autoDepotExpansion.freeSlots) and c.autoDepotExpansion.freeSlots>=0,'invalid automatic depot expansion settings')
  for _,field in ipairs({'input','output'}) do assert(type(c.craftingStation[field])=='string','invalid crafting station') end
  for _,field in ipairs({'inputSide','outputSide'}) do assert(({up=true,down=true,front=true})[c.craftingStation[field]],'invalid crafting station side') end
  local capabilityCount=0
  for k,v in pairs(c.capabilities) do
    capabilityCount=capabilityCount+1
    assert(U.shortString(k) and type(v)=='boolean','invalid capability')
  end
  assert(capabilityCount<=32,'at most 32 capabilities allowed')
  return c
end
return M
