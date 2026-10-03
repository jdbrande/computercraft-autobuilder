local S=require('autobuilder.blueprint.schematic')
local Cooperate=require('autobuilder.core.cooperate')
local M={}
local function field(owner,key,kind)
  local node=owner[key]; assert(node and node.kind==kind,'missing or invalid NBT '..key); return node.value,node
end
local function blockstate(text)
  assert(#text<=4096,'invalid block state length')
  local name,props=text,nil
  if text:find('[',1,true) then name,props=text:match('^([^%[%]]+)%[([^%[%]]+)%]$') end
  assert(name,'invalid block state syntax')
  if not name:find(':',1,true) then name='minecraft:'..name end
  assert(#name<=256 and name:match('^[a-z0-9_.%-]+:[a-z0-9_./%-]+$'),'invalid block state name')
  local state={}; local n=0
  if props then
    assert(props:sub(1,1)~=',' and props:sub(-1)~=',' and not props:find(',,',1,true),'invalid block state properties')
    for property in props:gmatch('[^,]+') do
      local key,value=property:match('^([a-z0-9_]+)=([a-z0-9_.%-]+)$'); n=n+1
      assert(key and #key<=64 and #value<=128 and n<=64 and not state[key],'invalid block state property')
      state[key]=value
    end
  end
  return {name=name,state=state}
end
function M.decode(raw)
  assert(type(raw)=='string' and #raw<=S.MAX_BYTES,'schematic byte limit exceeded')
  if raw:sub(1,2)=='\31\139' then raw=require('autobuilder.blueprint.gzip').decode(raw,S.MAX_BYTES) end
  local root=require('autobuilder.blueprint.nbt').decode(raw).value
  if root.Schematic then root=field(root,'Schematic',10) end
  local version=field(root,'Version',3); assert(version==2 or version==3,'only Sponge versions 2 and 3 are supported')
  local dataVersion=field(root,'DataVersion',3); assert(dataVersion>=0,'invalid DataVersion')
  local size={}
  for axis,key in pairs({x='Width',y='Height',z='Length'}) do
    local n=field(root,key,2)%65536; assert(n>0,'invalid schematic dimension'); size[axis]=n
  end
  local volume=size.x*size.y*size.z; assert(volume<=S.MAX_BLOCKS,'schematic block volume limit exceeded')
  local container=version==3 and field(root,'Blocks',10) or root
  local palette=field(container,'Palette',10); local indexed,indices={},{}
  for text,node in pairs(palette) do
    assert(node.kind==3 and node.value>=0 and not indexed[node.value],'invalid or duplicate palette index')
    assert(#indices<S.MAX_PALETTE,'schematic palette limit exceeded')
    indices[#indices+1]=node.value; indexed[node.value]=blockstate(text); Cooperate.every(#indices)
  end
  assert(#indices>0,'empty schematic palette'); table.sort(indices)
  local entries,remap={},{}
  for i,id in ipairs(indices) do entries[i]=indexed[id]; remap[id]=i end
  local bytes=field(container,version==3 and 'Data' or 'BlockData',7)
  local runs,count,value,shift={},0,0,0
  for i=1,#bytes do
    local byte=bytes:byte(i)
    assert(shift<28 or byte<=7,'block data varint overflow')
    value=value+(byte%128)*2^shift
    if byte>=128 then shift=shift+7
    else
      assert(shift==0 or byte~=0,'block data noncanonical varint')
      local id=remap[value]; assert(id,'block data references unknown palette index')
      count=count+1; assert(count<=volume,'block data exceeds volume')
      local run=runs[#runs]
      if run and run.id==id then run.count=run.count+1 else runs[#runs+1]={id=id,count=1} end
      value=0; shift=0
    end
    Cooperate.every(i)
  end
  assert(shift==0 and count==volume,'truncated block data or volume mismatch')
  local offset={0,0,0}
  if root.Offset then offset=field(root,'Offset',11); assert(#offset==3,'invalid schematic Offset') end
  local issues={}
  for _,spec in ipairs({{root,'Entities','entities'},{container,'BlockEntities','block entities'}}) do
    if spec[1][spec[2]] then
      local _,node=field(spec[1],spec[2],9)
      assert(node.count==0 or node.element==10,'invalid '..spec[2]..' list')
      if node.count>0 then issues[#issues+1]='Unsupported '..spec[3]..': '..node.count..'; entity/NBT data is not restored' end
    end
  end
  if root.Biomes or root.BiomeData then issues[#issues+1]='Unsupported biomes: biome data is not restored' end
  local result={schema=1,size=size,palette=entries,runs=runs,requirements={},metadata={sourceVersion=version,dataVersion=dataVersion,
    offset={x=offset[1],y=offset[2],z=offset[3]},issues=issues}}
  local valid,why=S.validate(result); assert(valid,why)
  result.requirements=require('autobuilder.blueprint.blueprint').quantities(result)
  return result
end
return M
