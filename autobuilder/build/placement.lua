local C=require('autobuilder.build.blockstates')
local U=require('autobuilder.core.util')
local M={}
local vectors={north={0,-1},east={1,0},south={0,1},west={-1,0}}
local opposite={north='south',south='north',east='west',west='east'}
function M.plan(block)
  if type(block)~='table' or not U.position(block) then return nil,'invalid block coordinates' end
  local status,reason=C.classify(block.name,block.state)
  if status=='UNSUPPORTED' or status=='SPECIAL_ACQUISITION' then return nil,reason,status end
  local state=block.state or {}; local family=C.family(block.name)
  local p={stand={x=block.x,y=block.y+1,z=block.z},direction='down',heading='north',item=C.item(block),status=status}
  local function vertical(top)
    p.stand.y=block.y+(top and -1 or 1); p.direction=top and 'up' or 'down'
    p.support={direction=p.direction,heading=p.heading}
  end
  local function horizontal(heading)
    local v=vectors[heading]; p.heading=heading; p.direction='forward'
    p.stand={x=block.x-v[1],y=block.y,z=block.z-v[2]}
    p.support={direction='forward',heading=heading}
  end
  if family=='log' then
    if state.axis=='x' then horizontal('east') elseif state.axis=='z' then horizontal('south') else vertical(false) end
  elseif family=='slab' then vertical(state.type=='top')
  elseif family=='stairs' then p.heading=state.facing or 'north'; vertical(state.half=='top')
  elseif family=='torch' or family=='gravity' or family=='carpet' or family=='pane' or family=='fence' then vertical(false)
  elseif family=='wall_torch' or family=='ladder' then horizontal(opposite[state.facing or 'north'])
  elseif family=='lantern' then vertical(tostring(state.hanging)=='true')
  elseif family=='control' then
    if state.face=='wall' then horizontal(opposite[state.facing]) else p.heading=state.facing;vertical(state.face=='ceiling') end
  elseif family=='rail' then p.heading=state.shape=='east_west' and 'east' or 'north';vertical(false)
  elseif family=='repeater' or family=='comparator' then p.heading=opposite[state.facing];vertical(false)
  elseif family=='wire' or family=='redstone_torch' then vertical(false)
  elseif family=='redstone_wall_torch' then horizontal(opposite[state.facing])
  elseif family=='bed' then
    p.heading=state.facing;vertical(false);p.observeOnly=state.part=='head'
    local v=vectors[state.facing];local sign=p.observeOnly and -1 or 1
    local pairState=U.copy(state);pairState.part=p.observeOnly and 'foot' or 'head'
    p.pair={x=block.x+v[1]*sign,y=block.y,z=block.z+v[2]*sign,name=block.name,state=pairState}
  elseif family=='door' then
    horizontal(state.facing)
    p.support={direction='down',heading=p.heading}; p.observeOnly=state.half=='upper'
    local pairState=U.copy(state); pairState.half=p.observeOnly and 'lower' or 'upper'
    p.pair={x=block.x,y=block.y+(p.observeOnly and -1 or 1),z=block.z,name=block.name,state=pairState}
  end
  p.connected=C.connected(family)
  return p
end
function M.suffix(direction) return direction=='up' and 'Up' or direction=='down' and 'Down' or '' end
function M.compare(block,present,actual,ignoreConnections)
  if C.isAir(block.name) then return not present, present and 'expected air' or nil end
  if not present then return false,'missing block' end
  if type(actual)~='table' or actual.name~=block.name then return false,'wrong block name' end
  for key,value in pairs(block.state or {}) do
    local got=(actual.state or {})[key]
    local connection=key=='north' or key=='east' or key=='south' or key=='west' or key=='powered' or key=='power' or key=='lit' or key=='locked' or key=='shape' and C.family(block.name)=='rail'
    if not (ignoreConnections and connection) and (got==nil or tostring(got)~=tostring(value)) then return false,'wrong state '..key end
  end
  return true
end
return M
