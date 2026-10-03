local U=require('autobuilder.core.util')
local C=require('autobuilder.config')
local function fixture()
  return {storageInventories={'stock','site','other'},logistics={nodes={
    {id='base',inventory='stock',position={x=0,y=60,z=0},buffers={
      {inventory='pickup',position={x=2,y=61,z=0}},
      {inventory='pickup2',position={x=3,y=61,z=0}}}},
    {id='site',inventory='site',position={x=20,y=60,z=0},buffers={
      {inventory='drop',position={x=22,y=61,z=0}}},targets={['minecraft:stone']=32}},
    {id='other',inventory='other',position={x=40,y=60,z=0},buffers={
      {inventory='other_buffer',position={x=42,y=61,z=0}}}}
  }}}
end
local function held(c)
  local n=require('autobuilder.storage.nodes')
  return {automation={jobs={haul={id='haul',status='queued',logistics={
    source=n.identity(n.get(c,'base')),destination=n.identity(n.get(c,'site')),
    pickup=U.copy(n.get(c,'base').buffers[1]),drop=U.copy(n.get(c,'site').buffers[1])}}}}}
end

test('registered logistics nodes validate and resolve physical endpoints',function()
  local c=C.load(fixture());local n=require('autobuilder.storage.nodes')
  eq(n.get(c,'site').targets['minecraft:stone'],32);eq(n.get(c,'missing'),nil)
  eq(c.logistics.batchSize,64);eq(n.identity(n.get(c,'base')).inventory,'stock')
  for _,edit in ipairs({
    function(o) o.logistics.nodes[1].inventory='missing' end,
    function(o) o.logistics.nodes[2].id='base' end,
    function(o) o.logistics.nodes[2].inventory='stock' end,
    function(o) o.logistics.nodes[1].position.x=0.5 end,
    function(o) o.logistics.nodes[1].buffers={} end,
    function(o) o.logistics.nodes[1].buffers[1].inventory='stock' end,
    function(o) o.logistics.nodes[1].buffers[1].inventory='drop' end,
    function(o) o.logistics.nodes[1].buffers[1].position={x=0,y=61,z=0} end,
    function(o) o.logistics.nodes[2].targets['minecraft:stone']=0 end,
    function(o) o.logistics.nodes[4]=o.logistics.nodes[3];o.logistics.nodes[3]=nil end,
    function(o) o.logistics.batchSize=65 end
  }) do local o=fixture();edit(o);assert(not pcall(C.load,o),'malformed node accepted') end
end)

test('private logistics buffers cannot alias factory fuel supply or legacy endpoints',function()
  C.load(fixture())
  for _,edit in ipairs({
    function(o) o.supply={inventory='pickup'} end,
    function(o) o.furnaces={'pickup'} end,
    function(o) o.craftingStation={input='pickup'} end,
    function(o) o.craftingStations={{id='craft',workerId=3,buffer='pickup',input='ci',output='co'}} end,
    function(o) o.fuel={stations={{id='fuel',inventory='pickup',position={x=5,y=60,z=0},workerId=3,targetItems=2}}} end
  }) do local o=fixture();edit(o);assert(not pcall(C.load,o),'private buffer alias accepted') end
end)

test('held logistics contracts reject node removal rebinding and station takeover after restart',function()
  local c=C.load(fixture());local n=require('autobuilder.storage.nodes');local state=held(c)
  n.validateSaved(c,U.copy(state))
  local changed=fixture();changed.logistics.nodes[3].position.x=45
  changed.logistics.nodes[2].targets['minecraft:stone']=64
  n.validateSaved(C.load(changed),state) -- unrelated nodes and desired counts are not ownership
  for _,edit in ipairs({
    function(o) table.remove(o.logistics.nodes,1) end,
    function(o) o.logistics.nodes[1].position.x=1 end,
    function(o) o.logistics.nodes[1].buffers[1].position.x=5 end,
    function(o) o.logistics.nodes[1].buffers[1].inventory='replacement' end
  }) do
    local o=fixture();edit(o);assert(not pcall(n.validateSaved,C.load(o),U.copy(state)),'owned endpoint changed')
  end
  state.automation.jobs.haul.status='completed'
  local o=fixture();table.remove(o.logistics.nodes,1);n.validateSaved(C.load(o),state)
end)

test('registered and held node containers and turtle stands are protected from excavation',function()
  local c=C.load(fixture());local n=require('autobuilder.storage.nodes');local state=held(c)
  local E=require('autobuilder.resources.exploration');local areas=E.protectedAreas(state,c)
  for _,p in ipairs({{x=0,y=60,z=0},{x=2,y=60,z=0},{x=2,y=61,z=0},{x=22,y=60,z=0},{x=22,y=63,z=0}}) do
    assert(E.protected(p,areas),'registered infrastructure not protected')
  end
  assert(not E.protected({x=10,y=60,z=0},areas),'unrelated terrain protected')
  local empty=C.load({});areas=n.protected(empty,state)
  assert(E.protected({x=2,y=60,z=0},areas),'saved ownership lost its physical protection')
end)

test('node stock cannot double as a machine endpoint and orphan private leases cannot be adopted',function()
  C.load(fixture())
  for _,field in ipairs({'furnaces','supply'}) do
    local o=fixture();o[field]=field=='furnaces' and {'stock'} or {inventory='stock'}
    assert(not pcall(C.load,o),'node stock aliases a shared machine')
  end
  local c=C.load(fixture());local n=require('autobuilder.storage.nodes')
  local state={capacityLedger={leases={old={status='held',nodes={pickup={exclusive=true}}}}}}
  assert(not pcall(n.validateSaved,c,state),'orphan private ownership adopted by node')
  state.capacityLedger.leases.old.status='released';n.validateSaved(c,state)
end)
