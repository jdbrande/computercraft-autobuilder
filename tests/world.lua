local U=require('autobuilder.core.util')
local P=require('autobuilder.core.pathfinding')
local M={}
function M.new()
  local w={pose={x=0,y=0,z=0,heading='east',known=true},blocks={},items={},stock={},fuel=10000,capacity=10000,selected=1,dug={},time=0}
  local vec={north={0,-1},east={1,0},south={0,1},west={-1,0}}
  local function target(direction)
    local p=U.copy(w.pose)
    if direction=='up' then p.y=p.y+1 elseif direction=='down' then p.y=p.y-1
    else local v=vec[p.heading]; p.x=p.x+v[1]*(direction=='back' and -1 or 1); p.z=p.z+v[2]*(direction=='back' and -1 or 1) end
    return p
  end
  local t={}; w.turtle=t
  t.getFuelLevel=function() return w.fuel end
  t.getSelectedSlot=function() return w.selected end
  t.select=function(s) w.selected=s; return true end
  t.getItemDetail=function(s) return U.copy(w.items[s or w.selected]) end
  t.getItemCount=function(s) local item=w.items[s or w.selected]; return item and item.count or 0 end
  t.refuel=function(n) local item=w.items[w.selected]; if not item or item.name~='minecraft:coal' then return false end; item.count=item.count-n; w.fuel=w.fuel+n*80; if item.count==0 then w.items[w.selected]=nil end; return true end
  t.suckUp=function() return false end
  for _,direction in ipairs({'forward','back','up','down'}) do
    t[direction]=function()
      local p=target(direction)
      if w.blocks[P.key(p)] then return false,'Movement obstructed' end
      w.pose.x,w.pose.y,w.pose.z=p.x,p.y,p.z; w.fuel=w.fuel-1; return true
    end
  end
  local order={'north','east','south','west'}; local idx={north=1,east=2,south=3,west=4}
  t.turnRight=function() w.pose.heading=order[idx[w.pose.heading]%4+1]; return true end
  t.turnLeft=function() w.pose.heading=order[(idx[w.pose.heading]-2)%4+1]; return true end
  local drops={['minecraft:iron_ore']='minecraft:raw_iron',['minecraft:deepslate_iron_ore']='minecraft:raw_iron',['minecraft:coal_ore']='minecraft:coal',['minecraft:stone']='minecraft:cobblestone'}
  for suffix,direction in pairs({['']='forward',Up='up',Down='down'}) do
    t['inspect'..suffix]=function()
      local name=w.blocks[P.key(target(direction))]
      if not name then return false,'No block to inspect' end
      return true,{name=name,state={}}
    end
    t['dig'..suffix]=function()
      local p=target(direction); local key=P.key(p); local name=w.blocks[key]
      if not name then return false,'Nothing to dig' end
      local item=drops[name] or name; local slot
      for i=1,14 do if not w.items[i] or (w.items[i].name==item and w.items[i].count<64) then slot=i; break end end
      if not slot then return false,'No space' end
      w.items[slot]=w.items[slot] or {name=item,count=0}; w.items[slot].count=w.items[slot].count+1
      w.blocks[key]=nil; w.dug[#w.dug+1]=name; return true
    end
  end
  t.dropDown=function()
    local item=w.items[w.selected]; if not item then return false end
    local moved=math.min(item.count,w.capacity); if moved==0 then return false,'No space for items' end
    w.stock[item.name]=(w.stock[item.name] or 0)+moved; item.count=item.count-moved; w.capacity=w.capacity-moved
    if item.count==0 then w.items[w.selected]=nil end
    return true
  end
  w.blocks['0,-1,0']='minecraft:chest'
  w.peripheral={getType=function() return 'geoScanner' end,call=function(_,method,radius)
    if method=='cost' then return 0 end
    local result={}
    for key,name in pairs(w.blocks) do
      local x,y,z=key:match('([^,]+),([^,]+),([^,]+)'); x,y,z=tonumber(x)-w.pose.x,tonumber(y)-w.pose.y,tonumber(z)-w.pose.z
      if math.max(math.abs(x),math.abs(y),math.abs(z))<=radius then result[#result+1]={name=name,x=x,y=y,z=z} end
    end
    return result
  end}
  return w
end
return M
