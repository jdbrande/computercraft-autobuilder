local U=require('autobuilder.core.util')
local function fixture(role)
  local inventories={['minecraft:chest_1']={},['minecraft:chest_2']={},['minecraft:barrel_3']={},['minecraft:furnace_1']={}}
  local types={['minecraft:chest_1']='minecraft:chest',['minecraft:chest_2']='minecraft:chest',['minecraft:barrel_3']='minecraft:barrel',['minecraft:furnace_1']='minecraft:furnace',left='modem',front='modem',top='minecraft:chest',bottom='minecraft:chest'}
  local e={prints={},items={}}
  e.print=function(s) e.prints[#e.prints+1]=s end
  e.peripheral={getNames=function() local a={}; for k in pairs(types) do a[#a+1]=k end; return a end,
    getType=function(name) return types[name] end,
    getMethods=function(name) return inventories[name] and {'list','pushItems','size'} or {} end,
    call=function(name,method)
      if method=='isWireless' then return name=='left' end
      if method=='list' then return U.copy(assert(inventories[name])) end
      error('Unexpected peripheral call '..method)
    end}
  e.turtle={craft=function() error('Must never craft during setup') end,
    getItemCount=function(slot) return e.items[slot] or 0 end,
    inspectUp=function() return true,{name='minecraft:chest'} end,
    inspectDown=function() return true,{name='minecraft:chest'} end}
  local config=require('autobuilder.config').load(role=='worker' and {role='worker',controllerId=1} or {})
  local function askAnswers(answers)
    local index=0
    return function(_,_,validate,default)
      index=index+1; local value=answers[index]; assert(value~=nil,'unexpected extra prompt')
      if value=='' then value=default or '' end
      local got,err=validate(value); assert(got~=nil,err); return got
    end
  end
  return e,config,types,inventories,askAnswers
end
test('controller factory setup discovers furnace lanes and adds stock without including reserved inventories or side aliases',function()
  local e,config,types,inventories,answers=fixture('controller')
  config.storageInventories={'old_stock'}; config.supply.inventory='minecraft:chest_1'
  config.craftingStation.output='minecraft:chest_2'; config.furnaces={'detached_furnace'}
  local overrides={protocol='custom'}
  assert(require('autobuilder.factory_setup').configure(e,overrides,config,answers({'1'})))
  eq(overrides.furnaces[1],'detached_furnace'); eq(overrides.furnaces[2],'minecraft:furnace_1')
  eq(#overrides.storageInventories,2); eq(overrides.storageInventories[1],'old_stock')
  eq(overrides.storageInventories[2],'minecraft:barrel_3'); eq(overrides.protocol,'custom')
  eq(#config.furnaces,1); eq(#config.storageInventories,1)
end)
test('crafter setup maps physical chest names explicitly and enables a stationary crafting worker',function()
  local e,config,types,inventories,answers=fixture('worker'); local overrides={automation={logging=true},mining={enabled=true}}
  assert(require('autobuilder.factory_setup').configure(e,overrides,config,answers({'minecraft:chest_1','minecraft:chest_2','1'})))
  eq(overrides.craftingStation.input,'minecraft:chest_1'); eq(overrides.craftingStation.output,'minecraft:chest_2')
  eq(overrides.craftingStation.inputSide,'up'); eq(overrides.craftingStation.outputSide,'down')
  eq(overrides.storageInventories[1],'minecraft:barrel_3')
  eq(overrides.automation.crafting,true); eq(overrides.automation.building,false); eq(overrides.mining.enabled,false)
  eq(overrides.automation.logging,false); eq(config.automation.crafting,false)
end)
test('crafter setup refuses occupied slots missing hardware and contaminated staging before changing overrides',function()
  local variants={
    function(e) e.items[16]=1 end,
    function(e) e.turtle.craft=nil end,
    function(e) e.turtle.inspectUp=function() return false end end,
    function(e,types) types.front=nil end,
    function(e,types) types.left=nil end,
    function(e,types,inventories) inventories['minecraft:chest_1'][1]={name='minecraft:dirt',count=1} end,
  }
  for _,change in ipairs(variants) do
    local e,config,types,inventories,answers=fixture('worker'); change(e,types,inventories)
    local overrides={protocol='untouched'}
    local ok=pcall(require('autobuilder.factory_setup').configure,e,overrides,config,answers({'minecraft:chest_1','minecraft:chest_2','1'}))
    assert(not ok); eq(overrides.protocol,'untouched'); eq(overrides.automation,nil); eq(overrides.craftingStation,nil)
  end
end)
test('factory setup cancellation does not alter existing overrides',function()
  local e,config,types,inventories,answers=fixture('worker'); local overrides={automation={building=true}}
  eq(require('autobuilder.factory_setup').configure(e,overrides,config,answers({'cancel'})),nil)
  eq(overrides.automation.building,true); eq(overrides.automation.crafting,nil); eq(overrides.storageInventories,nil)
end)
test('factory setup rejects side aliases duplicate staging and reserved stock choices',function()
  local e,config,types,inventories=fixture('worker'); local prompts=0; local overrides={}
  local function ask(_,_,validate)
    prompts=prompts+1
    if prompts==1 then eq(validate('top'),nil); return assert(validate('minecraft:chest_1')) end
    if prompts==2 then eq(validate('minecraft:chest_1'),nil); return assert(validate('minecraft:chest_2')) end
    eq(validate('minecraft:furnace_1'),nil); eq(validate('minecraft:chest_1'),nil)
    return assert(validate('minecraft:barrel_3'))
  end
  assert(require('autobuilder.factory_setup').configure(e,overrides,config,ask)); eq(prompts,3)
end)
test('factory setup respects partially overridden staging and does not drop the configured output reservation',function()
  local e,config,types,inventories,answers=fixture('controller')
  config.craftingStation.output='minecraft:chest_2'
  local overrides={craftingStation={input='minecraft:chest_1'}}
  assert(require('autobuilder.factory_setup').configure(e,overrides,config,answers({'1'})))
  eq(#overrides.storageInventories,1); eq(overrides.storageInventories[1],'minecraft:barrel_3')
end)
