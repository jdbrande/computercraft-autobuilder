local U=require('autobuilder.core.util')
local P=require('autobuilder.core.pathfinding')
local function world()
  local w={pose={x=0,y=2,z=0,heading='north',known=true},blocks={},items={},selected=1,places=0,digs=0}
  local vectors={north={0,-1},east={1,0},south={0,1},west={-1,0}}
  local order={'north','east','south','west'}; local index={north=1,east=2,south=3,west=4}
  local function target(suffix)
    local p=U.copy(w.pose)
    if suffix=='Up' then p.y=p.y+1 elseif suffix=='Down' then p.y=p.y-1
    else local v=vectors[p.heading]; p.x=p.x+v[1]; p.z=p.z+v[2] end
    return p
  end
  local t={}; w.turtle=t
  t.getFuelLevel=function() return 'unlimited' end
  t.select=function(s) w.selected=s; return true end
  t.getItemDetail=function(s) return U.copy(w.items[s or w.selected]) end
  t.getItemCount=function(s) local i=w.items[s or w.selected]; return i and i.count or 0 end
  for _,suffix in ipairs({'','Up','Down'}) do
    t['inspect'..suffix]=function() local b=w.blocks[P.key(target(suffix))]; return b~=nil,b and U.copy(b) or 'No block to inspect' end
    t['place'..suffix]=function()
      w.places=w.places+1
      local p=target(suffix); local key=P.key(p); local item=w.items[w.selected]
      if w.blocks[key] or not item or w.failPlace then return false,'cannot place' end
      local state={}; local name=item.name
      if name:match('_log$') then state.axis=suffix~='' and 'y' or (w.pose.heading=='east' or w.pose.heading=='west') and 'x' or 'z' end
      if name:match('_slab$') or name:match('_stairs$') then
        local support=U.copy(p); support.y=support.y+(suffix=='Down' and -1 or 1)
        local far=w.blocks[P.key(support)]~=nil
        local half=(suffix=='Down' and far or suffix=='Up' and not far) and 'bottom' or 'top'
        state.waterlogged=false
        if name:match('_slab$') then state.type=half else state.half=half; state.facing=w.pose.heading; state.shape='straight' end
      end
      w.blocks[key]={name=name,state=state}; item.count=item.count-1
      if item.count==0 then w.items[w.selected]=nil end
      if w.crashPlace then w.crashPlace=false; error('power lost after placement') end
      return true
    end
    t['dig'..suffix]=function()
      local key=P.key(target(suffix)); local b=w.blocks[key]; if not b then return false end
      local slot
      for n=1,14 do if not w.items[n] then slot=n; break end end
      if not slot then return false,'inventory full' end
      w.items[slot]={name=b.name,count=1}; w.blocks[key]=nil; w.digs=w.digs+1
      if w.crashDig then w.crashDig=false; error('power lost after dig') end
      return true
    end
  end
  for action,suffix in pairs({forward='',up='Up',down='Down'}) do
    t[action]=function() local p=target(suffix); if w.blocks[P.key(p)] then return false,'blocked' end; w.pose.x,w.pose.y,w.pose.z=p.x,p.y,p.z; return true end
  end
  t.turnRight=function() w.pose.heading=order[index[w.pose.heading]%4+1]; return true end
  t.turnLeft=function() w.pose.heading=order[(index[w.pose.heading]-2)%4+1]; return true end
  return w
end
return {new=world}
