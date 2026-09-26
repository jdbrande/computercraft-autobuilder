local U=require('autobuilder.core.util')
local P=require('autobuilder.core.pathfinding')
local M={}
function M.new(hw,config,clock)
  local self={}; local cache,nextScan=nil,0
  local side=config.side or 'left'; local slot=config.slot or 16
  local function equipped() return hw.peripheral.getType(side)=='geoScanner' end
  local function swap()
    local t=hw.turtle; local selected=t.getSelectedSlot(); assert(t.select(slot),'cannot select scanner slot')
    local ok,result,err=pcall(side=='left' and t.equipLeft or t.equipRight)
    t.select(selected)
    if not ok then return false,tostring(result) end
    return result,err
  end
  function self:recover()
    if not hw.turtle then return true end -- Also supports stationary scanner adapters.
    local ok,result,err=pcall(function()
      if not equipped() then return true end
      local item=hw.turtle.getItemDetail(slot)
      if not item or item.name~='minecraft:diamond_pickaxe' then return false,'scanner installed but reserved slot has no diamond pickaxe' end
      return swap()
    end)
    if not ok then return false,tostring(result) end
    return result,err
  end
  function self:scan(origin)
    if not U.position(origin) then return nil,'scanner origin unknown' end
    if cache and cache.origin==P.key(origin) and clock()-cache.at<(config.ttl or 15) then return U.copy(cache.blocks) end
    if clock()<nextScan then return nil,'scanner cooldown',nextScan-clock() end
    nextScan=clock()+(config.cooldown or 3)
    local ok,blocks,reason=pcall(function()
      if not equipped() then
        if hw.peripheral.getType(side)=='modem' then return nil,'scanner side holds a modem; configure the pickaxe side' end
        if not hw.turtle then return nil,'Geo Scanner unavailable' end
        local item=hw.turtle.getItemDetail(slot)
        if not item or item.name~='advancedperipherals:geo_scanner' then return nil,'Geo Scanner unavailable in reserved slot' end
        local swapped,err=swap(); if not swapped then return nil,err end
      end
      if hw.peripheral.getMethods then
        local hasCooldown=false
        for _,method in ipairs(hw.peripheral.getMethods(side) or {}) do if method=='getOperationCooldown' then hasCooldown=true end end
        if hasCooldown then
          local remaining=hw.peripheral.call(side,'getOperationCooldown','scanBlocks')
          if not U.finite(remaining) or remaining<0 then return nil,'invalid scanner cooldown' end
          if remaining>0 then
            if remaining/1000>(config.maxWait or 30) or not hw.sleep then return nil,'scanner cooldown exceeds available wait budget' end
            -- Keep scanner installed during this wait: custom AP initial cooldowns can
            -- restart on every equip. The modem stays installed on the other side.
            hw.sleep(remaining/1000+0.05)
          end
        end
      end
      local cost,err=hw.peripheral.call(side,'cost',config.radius or 8)
      if not U.finite(cost) or cost<0 then return nil,err or 'invalid scanner cost' end
      if cost>(config.maxCost or 0) then return nil,'scan exceeds configured fuel budget' end
      local raw,why=hw.peripheral.call(side,'scan',config.radius or 8)
      if type(raw)~='table' then return nil,why or 'scan failed' end
      local result={}
      for _,b in ipairs(raw) do
        if not U.position(b) or not U.shortString(b.name,128) then return nil,'malformed scan result' end
        local radius=config.radius or 8
        if math.abs(b.x)>radius or math.abs(b.y)>radius or math.abs(b.z)>radius then return nil,'scan offset outside radius' end
        result[#result+1]={x=origin.x+b.x,y=origin.y+b.y,z=origin.z+b.z,name=b.name}
      end
      return result
    end)
    local restored,err=self:recover()
    if not restored then return nil,'tool recovery failed: '..tostring(err),nil,'hardware' end
    if not ok then return nil,'scanner error: '..tostring(blocks) end
    if not blocks then return nil,reason or 'scan failed' end
    cache={origin=P.key(origin),at=clock(),blocks=blocks}
    return U.copy(blocks)
  end
  function self:invalidate() cache=nil end
  function self:veins(blocks,requested,origin)
    local remaining={}
    for _,b in ipairs(blocks) do if requested[b.name] then remaining[P.key(b)]=b end end
    local veins={}
    while next(remaining) do
      local key,first=next(remaining); remaining[key]=nil
      local vein={first}; local i=1
      while i<=#vein do
        for _,p in ipairs(P.neighbors(vein[i])) do
          local k=P.key(p); if remaining[k] then vein[#vein+1]=remaining[k]; remaining[k]=nil end
        end
        i=i+1
      end
      table.sort(vein,function(a,b) return U.distance(origin,a)<U.distance(origin,b) end)
      veins[#veins+1]=vein
    end
    table.sort(veins,function(a,b) return U.distance(origin,a[1])<U.distance(origin,b[1]) end)
    return veins
  end
  return self
end
return M
