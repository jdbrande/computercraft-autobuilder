-- Read-only factory discovery. The caller reviews and persists returned overrides.
local U=require('autobuilder.core.util')
local M={}
local sides={left=true,right=true,front=true,back=true,top=true,bottom=true,up=true,down=true}
local containers={['minecraft:chest']=true,['minecraft:trapped_chest']=true,['minecraft:barrel']=true}
local function discover(e)
  local list,furnaces={},{}; local wired,wireless=false,false
  for _,name in ipairs(e.peripheral.getNames()) do
    local kind=e.peripheral.getType(name)
    if kind=='modem' then
      local ok,value=pcall(e.peripheral.call,name,'isWireless')
      if ok and value==false then wired=true elseif ok and value==true then wireless=true end
    elseif not sides[name] then
      if kind=='minecraft:furnace' then furnaces[#furnaces+1]=name end
      if containers[kind] then
        local ok,methods=pcall(e.peripheral.getMethods,name); local has={}
        if ok and type(methods)=='table' then for _,method in ipairs(methods) do has[method]=true end end
        if has.list and has.pushItems and has.size then
          local good,items=pcall(e.peripheral.call,name,'list')
          if good and type(items)=='table' then list[#list+1]={name=name,items=items} end
        end
      end
    end
  end
  table.sort(list,function(a,b) return a.name<b.name end); table.sort(furnaces)
  return list,furnaces,wired,wireless
end
local function choices(e,list,excluded)
  local out={}
  for _,entry in ipairs(list) do if not excluded[entry.name] then
    out[#out+1]=entry; e.print(#out..') '..entry.name..(next(entry.items) and ' (contains items)' or ' (empty)'))
  end end
  return out
end
local function selectNames(list,value,many,empty,optional)
  if value:lower()=='cancel' then return false end
  if optional and (value:lower()=='none' or value:lower()=='skip') then return {} end
  local names,seen={},{}
  for word in value:gmatch('%S+') do
    local entry=list[tonumber(word) or 0]
    if not entry then for _,candidate in ipairs(list) do if candidate.name==word then entry=candidate; break end end end
    if not entry or seen[entry.name] or empty and next(entry.items) then
      return nil,'Choose distinct listed '..(empty and 'empty ' or '')..'chests by number or wired name; cancel leaves settings unchanged.'
    end
    names[#names+1]=entry.name; seen[entry.name]=true
  end
  if #names==0 or not many and #names~=1 then return nil,'Choose '..(many and 'one or more listed chests.' or 'one listed chest.') end
  return many and names or names[1]
end
local function mergeNames(first,second,excluded)
  local result,seen={},{}
  for _,source in ipairs({first,second}) do for _,name in ipairs(source) do
    if not seen[name] and not excluded[name] then result[#result+1]=name; seen[name]=true end
  end end
  return result
end
function M.locate(e,overrides,config,ask,state)
  local chosen=require('autobuilder.config').overlay(config,overrides)
  local map=U.copy(chosen.inventoryAreas or {})
  local missing=require('autobuilder.core.inventory_geometry').missing(chosen,state)
  if #missing>0 then e.print('Register physical inventory blocks (F3 Targeted Block). Include BOTH halves of double chests and every processor block.') end
  for _,name in ipairs(missing) do
    local bounds=ask(e,name..': x y z OR minX minY minZ maxX maxY maxZ; cancel',function(v)
      if v:lower()=='cancel' then return false end
      local nums={};for word in v:gmatch('%S+') do local n=tonumber(word);if not U.integer(n) then return nil,'Use integer block coordinates.' end;nums[#nums+1]=n end
      if #nums~=3 and #nums~=6 then return nil,'Enter three coordinates for one block, or six for inclusive bounds.' end
      local b={min={x=nums[1],y=nums[2],z=nums[3]},max={x=nums[4] or nums[1],y=nums[5] or nums[2],z=nums[6] or nums[3]}}
      if not require('autobuilder.resources.exploration').box(b) then return nil,'Invalid or reversed inventory bounds.' end
      return b
    end)
    if bounds==false then return nil end;map[name]=bounds
  end
  overrides.inventoryAreas=map;return true
end
function M.configure(e,overrides,config,ask,state)
  local list,found,wired,wireless=discover(e)
  assert(wired,'Connect a wired modem and networking cable to the stock, furnace and crafting chests first.')
  local supply=(overrides.supply or {}).inventory or config.supply.inventory
  local station=U.copy(config.craftingStation)
  for field,value in pairs(overrides.craftingStation or {}) do station[field]=value end
  local furnaces=mergeNames(overrides.furnaces or config.furnaces,found,{})
  local excluded={}; for _,name in ipairs(furnaces) do excluded[name]=true end
  if supply~='' then excluded[supply]=true end
  if config.role=='controller' then
    for _,s in ipairs(config.craftingStations or {}) do for _,field in ipairs({'buffer','input','output'}) do excluded[s[field]]=true end end
    for _,s in ipairs((config.processors or {}).machines or {}) do excluded[s.inventory]=true end
    for _,s in ipairs(config.supplyStations or {}) do excluded[s.inventory]=true end
    for _,s in ipairs((config.fuel or {}).stations or {}) do excluded[s.inventory]=true end
    for _,n in ipairs((config.logistics or {}).nodes or {}) do for _,b in ipairs(n.buffers or {}) do excluded[b.inventory]=true end end
    for _,w in pairs((state or {}).workers or {}) do for _,n in ipairs((w.telemetry or {}).craftingInventories or {}) do excluded[n]=true end end
    if station.input~='' then excluded[station.input]=true end
    if station.output~='' then excluded[station.output]=true end
    e.print('Factory furnaces: '..(#furnaces>0 and table.concat(furnaces,', ') or 'none detected; attach ordinary furnaces to the wired network.'))
    e.print('Additional STOCK deposit chests must be connected to this same wired network.')
    local stocks=choices(e,list,excluded)
    local selected={}
    if #stocks>0 then
      selected=ask(e,'Additional stock chest numbers/names, none, or cancel',function(v) return selectNames(stocks,v,true,false,true) end,'none')
      if selected==false then return nil end
    end
    local staged=U.copy(overrides);staged.furnaces=furnaces
    staged.storageInventories=mergeNames(overrides.storageInventories or config.storageInventories,selected,excluded)
    if not M.locate(e,staged,config,ask,state) then return nil end
    overrides.furnaces=staged.furnaces;overrides.storageInventories=staged.storageInventories;overrides.inventoryAreas=staged.inventoryAreas
    return true
  end
  local turtle=e.turtle
  assert(turtle and type(turtle.craft)=='function','Equip a crafting table upgrade on this turtle before crafter setup.')
  assert(wireless,'Keep a wireless modem equipped for controller messages; use an external wired modem for factory chests.')
  for slot=1,16 do assert(turtle.getItemCount(slot)==0,'Empty all 16 turtle slots before configuring the crafter.') end
  for _,side in ipairs({'Up','Down'}) do
    local ok,foundBlock,block=pcall(turtle['inspect'..side])
    assert(ok and foundBlock and block and containers[block.name],'Place an input chest above and an output chest below this turtle.')
  end
  e.print('Keep this crafter parked: INPUT chest above, OUTPUT chest below; both must be empty.')
  e.print('Enable wired modems on both chests. Match each modem name to the correct physical chest.')
  e.print('Use a crafting table and wireless modem as upgrades, with an external wired modem beside the turtle.')
  local available=choices(e,list,excluded); assert(#available>=3,'Connect separate input, output and stock chests to the wired network.')
  local input=ask(e,'INPUT above: chest number or wired name',function(v) return selectNames(available,v,false,true) end)
  if input==false then return nil end
  excluded[input]=true; available=choices(e,list,excluded)
  local output=ask(e,'OUTPUT below: chest number or wired name',function(v) return selectNames(available,v,false,true) end)
  if output==false then return nil end
  excluded[output]=true; available=choices(e,list,excluded)
  e.print('Choose the same STOCK chests configured on the controller; never choose supply or staging chests.')
  local stocks=ask(e,'STOCK chest numbers or wired names',function(v) return selectNames(available,v,true,false) end)
  if stocks==false then return nil end
  local automation=U.copy(overrides.automation or config.automation)
  automation.enabled=true; automation.crafting=true
  for _,role in ipairs({'building','logging','farming','courier'}) do automation[role]=false end
  local mining=U.copy(overrides.mining or {}); mining.enabled=false
  overrides.automation=automation; overrides.mining=mining; overrides.storageInventories=stocks
  overrides.craftingStation={input=input,output=output,inputSide='up',outputSide='down'}
  return true
end
return M
