local S=require('autobuilder.blueprint.schematic')
local T=require('autobuilder.blueprint.transforms')
local Cooperate=require('autobuilder.core.cooperate')
local M={}
local air={['minecraft:air']=true,['minecraft:cave_air']=true,['minecraft:void_air']=true}
local aliases={['minecraft:wall_torch']='minecraft:torch',['minecraft:redstone_wall_torch']='minecraft:redstone_torch',['minecraft:soul_wall_torch']='minecraft:soul_torch',['minecraft:redstone_wire']='minecraft:redstone',['minecraft:wheat']='minecraft:wheat_seeds',['minecraft:carrots']='minecraft:carrot',['minecraft:potatoes']='minecraft:potato',['minecraft:beetroots']='minecraft:beetroot_seeds'}
function M.blocks(data,origin,rotation,mirrorX,mirrorZ)
  local valid,err=S.validate(data); assert(valid,err)
  origin=origin or {x=0,y=0,z=0}
  for _,axis in ipairs({'x','y','z'}) do assert(type(origin[axis])=='number' and origin[axis]%1==0 and math.abs(origin[axis])<=30000000,'invalid origin') end
  -- Validate transform even for an entirely empty volume.
  T.state({},rotation,mirrorX,mirrorZ)
  local out,index={},0
  for _,run in ipairs(data.runs) do
    local entry=data.palette[run.id]
    for _=1,run.count do
      if not air[entry.name] then
        local p=T.position({x=index%data.size.x,y=math.floor(index/(data.size.x*data.size.z)),z=math.floor(index/data.size.x)%data.size.z},data.size,rotation,mirrorX,mirrorZ)
        out[#out+1]={x=origin.x+p.x,y=origin.y+p.y,z=origin.z+p.z,name=entry.name,state=T.state(entry.state,rotation,mirrorX,mirrorZ)}
      end
      index=index+1
      Cooperate.every(index)
    end
  end
  return out
end
function M.quantities(data)
  local valid,err=S.validate(data); assert(valid,err)
  local out={}
  for _,run in ipairs(data.runs) do
    local entry=data.palette[run.id]; local name,state=entry.name,entry.state
    local paired=(name:match('_door$') and state.half=='upper') or (name:match('_bed$') and state.part=='head')
    if not air[name] and not paired then
      local item=aliases[name] or name
      local multiplier=(name:match('_slab$') and state.type=='double') and 2 or 1
      out[item]=(out[item] or 0)+run.count*multiplier
    end
  end
  return out
end
local function key(x,y,z) return x..','..y..','..z end
local vectors={north={x=0,z=-1},east={x=1,z=0},south={x=0,z=1},west={x=-1,z=0}}
local function before(a,b)
  if a.y~=b.y then return a.y<b.y end
  if a.z~=b.z then return a.z<b.z end
  return a.x<b.x
end
-- Stable Kahn ordering with a heap keeps large blueprints bounded to O(n log n).
local function ordered(nodes,less)
  local degree,children,heap={},{},{}
  local function push(value)
    local i=#heap+1
    while i>1 do
      local parent=math.floor(i/2)
      if not less(value,heap[parent]) then break end
      heap[i]=heap[parent]; i=parent
    end
    heap[i]=value
  end
  local function pop()
    local out,last=heap[1],table.remove(heap)
    if #heap>0 then
      local i=1
      while i*2<=#heap do
        local child=i*2
        if child<#heap and less(heap[child+1],heap[child]) then child=child+1 end
        if not less(heap[child],last) then break end
        heap[i]=heap[child]; i=child
      end
      heap[i]=last
    end
    return out
  end
  for _,node in ipairs(nodes) do degree[node]=0; children[node]={} end
  for _,node in ipairs(nodes) do
    for dep in pairs(node.deps) do
      degree[node]=degree[node]+1; children[dep][#children[dep]+1]=node
    end
  end
  for _,node in ipairs(nodes) do if degree[node]==0 then push(node) end end
  local result={}
  while #heap>0 do
    local node=pop(); result[#result+1]=node
    Cooperate.every(#result)
    for _,child in ipairs(children[node]) do degree[child]=degree[child]-1; if degree[child]==0 then push(child) end end
  end
  assert(#result==#nodes,'cyclic support dependencies; reduce region size or correct blueprint')
  return result
end
function M.regions(blocks,size)
  size=size or 8
  if type(size)=='number' then size={x=size,y=size,z=size} end
  assert(type(size)=='table','invalid region size')
  for _,axis in ipairs({'x','y','z'}) do assert(type(size[axis])=='number' and size[axis]%1==0 and size[axis]>=1 and size[axis]<=256,'invalid region size') end
  assert(type(blocks)=='table' and #blocks<=S.MAX_BLOCKS,'invalid block list')
  local nodes,cells,regions,groups={},{},{},{}
  for index,b in ipairs(blocks) do
    Cooperate.every(index)
    assert(type(b)=='table' and type(b.name)=='string' and type(b.state)=='table','invalid block')
    for _,axis in ipairs({'x','y','z'}) do assert(type(b[axis])=='number' and b[axis]%1==0 and math.abs(b[axis])<=30000000,'invalid block coordinate') end
    local k=key(b.x,b.y,b.z); assert(not cells[k],'duplicate block coordinate')
    local x,y,z=math.floor(b.x/size.x),math.floor(b.y/size.y),math.floor(b.z/size.z)
    local id=key(x,y,z); local r=groups[id]
    if not r then
      r={id=id,x=x,y=y,z=z,blocks={},deps={},dependencies={},min={x=b.x,y=b.y,z=b.z},max={x=b.x,y=b.y,z=b.z}}
      groups[id]=r; regions[#regions+1]=r
    end
    for _,axis in ipairs({'x','y','z'}) do r.min[axis]=math.min(r.min[axis],b[axis]); r.max[axis]=math.max(r.max[axis],b[axis]) end
    local node={block=b,x=b.x,y=b.y,z=b.z,region=r,deps={}}
    nodes[#nodes+1]=node; cells[k]=node
  end
  local function depend(node,x,y,z)
    local dep=cells[key(x,y,z)]
    if dep and dep~=node then
      node.deps[dep]=true
      if dep.region~=node.region then node.region.deps[dep.region]=true end
    end
  end
  for index,node in ipairs(nodes) do
    Cooperate.every(index)
    local b=node.block; local state=b.state
    depend(node,b.x,b.y-1,b.z)
    local wall=b.name:find('wall_',1,true) or b.name:match(':ladder$') or state.face=='wall' or (b.name:match(':tripwire_hook$'))
    if wall and vectors[state.facing] then
      local v=vectors[state.facing]; depend(node,b.x-v.x,b.y,b.z-v.z)
    elseif state.face=='ceiling' or state.hanging=='true' then
      -- Hanging blocks need the ceiling rather than a block beneath them.
      local below=cells[key(b.x,b.y-1,b.z)]
      if below then node.deps[below]=nil end
      depend(node,b.x,b.y+1,b.z)
    end
    if b.name:match('_bed$') and state.part=='foot' and vectors[state.facing] then
      local v=vectors[state.facing];depend(node,b.x+v.x,b.y-1,b.z+v.z)
    end
    if b.name:match('_bed$') and state.part=='head' and vectors[state.facing] then
      local v=vectors[state.facing]; depend(node,b.x-v.x,b.y,b.z-v.z)
    end
  end
  -- Derive region edges from final block edges (including ceiling overrides).
  for _,r in ipairs(regions) do r.deps={} end
  for _,node in ipairs(nodes) do for dep in pairs(node.deps) do if dep.region~=node.region then node.region.deps[dep.region]=true end end end
  for _,node in ipairs(ordered(nodes,before)) do local r=node.region; r.blocks[#r.blocks+1]=node.block end
  local result=ordered(regions,before)
  for _,r in ipairs(result) do
    for dep in pairs(r.deps) do r.dependencies[#r.dependencies+1]=dep.id end
    table.sort(r.dependencies); r.deps=nil; r.x=nil; r.y=nil; r.z=nil
  end
  return result
end
return M
