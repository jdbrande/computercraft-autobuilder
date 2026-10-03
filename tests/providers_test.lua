local P=require('autobuilder.resources.providers')
local U=require('autobuilder.core.util')
local function mc(s) return 'minecraft:'..s end

test('providers derive copied stable candidates from recipes mining and configured farms',function()
  local c={exploration={enabled=true},treeFarms={{item=mc('oak_log'),base={x=1,y=2,z=3}},{item=mc('oak_log'),base={x=4,y=2,z=3}}}}
  local iron=P.select(mc('raw_iron'),c); eq(iron.type,'exploration'); eq(iron.capability,'explorationV1')
  eq(P.select(mc('glass'),c).type,'smelting'); eq(P.select(mc('stone_bricks'),c).type,'crafting')
  local logs=P.candidates(mc('oak_log'),c); eq(#logs,3); eq(logs[2].type,'tree_farm')
  assert(logs[2].id~=logs[3].id); local id=logs[2].id; logs[2].farm.base.x=99
  eq(P.candidates(mc('oak_log'),c)[2].id,id); eq(c.treeFarms[1].base.x,1)
  eq(P.select(mc('raw_iron'),{}).type,'mining')
end)

test('providers prefer actual sufficient stock and never manufacture a missing provider',function()
  eq(P.select(mc('glass'),{},{available=4,required=4}).type,'storage')
  eq(P.select(mc('glass'),{},{available=3,required=4}).type,'smelting')
  local provider,why=P.select('example:unknown',{},{available=0,required=1})
  eq(provider,nil); assert(why:find('No configured provider',1,true))
  eq(P.select(mc('glass'),{},{acquisitionOnly=true}),nil)
end)

test('provider preferences choose renewable acquisition and fall back to compatible online workers',function()
  local c={farms={{item=mc('sand'),origin={x=0,y=0,z=0}}},providerPreferences={[mc('sand')]={'farm','mining'}}}
  eq(P.select(mc('sand'),c).type,'farm')
  local workers={['1']={online=true,telemetry={capabilities={mining=true},miningResources={mc('sand')}}}}
  eq(P.select(mc('sand'),c,{workers=workers}).type,'mining')
  workers['2']={online=true,telemetry={capabilities={farming=true}}}
  eq(P.select(mc('sand'),c,{workers=workers}).type,'farm')
  workers['2'].online=false; workers['1'].telemetry.miningResources={mc('coal')}
  local p=P.select(mc('sand'),c,{workers=workers}); eq(p.type,'farm'); eq(p.available,false)
  workers['1'].telemetry.miningResources={[1]=mc('sand'),[3]=mc('coal')}
  eq(P.select(mc('sand'),c,{workers=workers}).available,false)
end)

test('provider preferences validate dense known unique types and config preserves explicit ordering',function()
  local C=require('autobuilder.config'); local prefs={[mc('sand')]={'farm','mining'}}
  local c=C.load({providerPreferences=prefs}); eq(c.providerPreferences[mc('sand')][1],'farm')
  prefs[mc('sand')][1]='storage'; eq(c.providerPreferences[mc('sand')][1],'farm')
  for _,value in ipairs({{[mc('sand')]={'unknown'}},{[mc('sand')]={'farm','farm'}},{[mc('sand')]={[2]='farm'}},{['']={'farm'}},{[mc('sand')]='farm'}}) do
    assert(not pcall(C.load,{providerPreferences=value}))
  end
  for _,context in ipairs({{required=0},{required=0/0},{available=-1},{available=math.huge},{workers='bad'}}) do
    assert(not pcall(P.select,mc('sand'),{},context))
  end
  assert(not pcall(P.candidates,'',{}))
end)
