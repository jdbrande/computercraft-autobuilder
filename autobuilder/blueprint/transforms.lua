local M={}
local dirs={'north','east','south','west'}
local indices={north=0,east=1,south=2,west=3}
local function turns(rotation,mx,mz)
  rotation=rotation or 0
  assert(rotation==0 or rotation==90 or rotation==180 or rotation==270,'rotation must be 0, 90, 180 or 270')
  assert(mx==nil or type(mx)=='boolean','mirrorX must be boolean')
  assert(mz==nil or type(mz)=='boolean','mirrorZ must be boolean')
  return rotation/90
end
local function facing(value,t,mx,mz)
  local i=indices[value]; if i==nil then return value end
  if mx then i=(-i)%4 end
  if mz then i=(2-i)%4 end
  return dirs[(i+t)%4+1]
end
function M.position(p,size,rotation,mx,mz)
  local t=turns(rotation,mx,mz)
  local x,z,w,d=p.x,p.z,size.x,size.z
  if mx then x=w-1-x end
  if mz then z=d-1-z end
  for _=1,t do x,z,w,d=d-1-z,x,d,w end
  return {x=x,y=p.y,z=z}
end
function M.state(state,rotation,mx,mz)
  local t=turns(rotation,mx,mz)
  local out={}
  for k,v in pairs(state or {}) do out[facing(k,t,mx,mz)]=v end
  if state and state.facing then out.facing=facing(state.facing,t,mx,mz) end
  if out.axis and t%2==1 then
    if out.axis=='x' then out.axis='z' elseif out.axis=='z' then out.axis='x' end
  end
  if out.rotation then
    local n=tonumber(out.rotation); assert(n and n%1==0 and n>=0 and n<16,'invalid rotation state')
    if mx then n=(-n)%16 end
    if mz then n=(8-n)%16 end
    out.rotation=tostring((n+t*4)%16)
  end
  local reflected=(mx and not mz) or (mz and not mx)
  if reflected then
    if out.hinge=='left' then out.hinge='right' elseif out.hinge=='right' then out.hinge='left' end
    if out.type=='left' then out.type='right' elseif out.type=='right' then out.type='left' end
    if out.shape then
      out.shape=out.shape:gsub('_left$','_RIGHT'):gsub('_right$','_left'):gsub('_RIGHT$','_right')
    end
  end
  local shape=out.shape
  if shape then
    local ascending=shape:match('^ascending_(.+)$')
    if ascending then out.shape='ascending_'..facing(ascending,t,mx,mz)
    elseif shape=='north_south' or shape=='east_west' then
      local direction=facing(shape:match('^([^_]+)'),t,mx,mz)
      out.shape=(direction=='north' or direction=='south') and 'north_south' or 'east_west'
    else
      local a,b=shape:match('^(%a+)_(%a+)$')
      if indices[a] and indices[b] then
        a,b=facing(a,t,mx,mz),facing(b,t,mx,mz)
        if a=='east' or a=='west' then a,b=b,a end
        out.shape=a..'_'..b
      end
    end
  end
  return out
end
return M
