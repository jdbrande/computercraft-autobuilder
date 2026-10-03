local S=require('tests.native_support')
local function rejects(raw,reason)
  local ok,why=pcall(require('autobuilder.blueprint.sponge').decode,raw)
  assert(not ok and tostring(why):find(reason,1,true),'expected '..reason..', got '..tostring(why))
end

test('native Sponge v2 and v3 retain states air order offsets and material counts',function()
  local P=require('autobuilder.blueprint.sponge')
  for _,version in ipairs({2,3}) do
    local bp=P.decode(S.fixture({version=version,extra={S.tag(11,'Offset',S.uint(3,4)..S.uint(-3,4)..S.uint(4,4)..S.uint(5,4))}}))
    eq(bp.size.x,2); eq(bp.size.y,1); eq(bp.size.z,2); eq(bp.metadata.sourceVersion,version)
    eq(bp.metadata.offset.x,-3); eq(bp.metadata.offset.y,4); eq(bp.metadata.dataVersion,3700)
    eq(bp.palette[2].name,'minecraft:oak_log'); eq(bp.palette[2].state.axis,'x')
    eq(bp.runs[1].id,1); eq(bp.runs[1].count,1); eq(bp.runs[2].id,2); eq(bp.runs[2].count,2); eq(bp.runs[3].id,1)
    eq(bp.requirements['minecraft:oak_log'],2); eq(bp.requirements['minecraft:air'],nil)
  end
  eq(P.decode(S.file('sponge-v3.gz')).metadata.sourceVersion,3)
end)

test('native Sponge remaps sparse palette IDs and reuses paired block and slab quantities',function()
  local bp=require('autobuilder.blueprint.sponge').decode(S.fixture({width=6,length=1,
    palette={{'stone_slab[type=double]',5},{'minecraft:oak_door[half=upper]',127},{'minecraft:oak_door[half=lower]',128},{'minecraft:wall_torch[facing=north]',130}},
    data='\5\5\127\128\1\130\1\130\1'}))
  eq(#bp.palette,4); eq(bp.requirements['minecraft:stone_slab'],4)
  eq(bp.requirements['minecraft:oak_door'],1); eq(bp.requirements['minecraft:torch'],2)
end)

test('native Sponge reports unsupported entity and biome data without silently discarding it',function()
  local bp=require('autobuilder.blueprint.sponge').decode(S.fixture({extra={
    S.tag(9,'Entities','\10'..S.uint(1,4)..'\0'),S.tag(9,'BlockEntities','\10'..S.uint(1,4)..'\0'),S.tag(7,'BiomeData',S.uint(0,4))}}))
  eq(#bp.metadata.issues,3); assert(bp.metadata.issues[1]:find('entities')); assert(bp.metadata.issues[2]:find('block entities'))
  rejects(S.fixture({extra={S.tag(3,'Entities',S.uint(0,4))}}),'Entities')
end)

test('native Sponge rejects wrong NBT field types and invalid dimensions',function()
  rejects(S.fixture({versionKind=2}),'Version'); rejects(S.fixture({widthKind=3}),'Width')
  rejects(S.fixture({version=1}),'versions 2 and 3'); rejects(S.fixture({width=0}),'dimension')
  rejects(S.fixture({width=32767,height=32767}),'block volume')
  rejects(S.fixture({extra={S.tag(9,'Offset','\3'..S.uint(3,4)..S.uint(0,4):rep(3))}}),'Offset')
  local bp=require('autobuilder.blueprint.sponge').decode(S.fixture({width=65535,length=1,data=('\0'):rep(65535)}))
  eq(bp.size.x,65535); eq(bp.runs[1].count,65535)
end)

test('native Sponge rejects malformed palettes states and varints',function()
  rejects(S.fixture({palette={{'stone',0},{'dirt',0}}}),'palette index')
  for _,name in ipairs({'stone[axis=x,axis=y]','stone[]','stone[a=b,]','stone[,a=b]','Stone','stone[a=b=c]'}) do
    rejects(S.fixture({palette={{name,0}}}),'block state')
  end
  for _,data in ipairs({'\2\1\1\0','\128','\128\0\1\1\0','\255\255\255\255\15','\0','\0\0\0\0\0'}) do rejects(S.fixture({data=data}),'block data') end
end)

test('native NBT validates structure lengths nesting and node bounds',function()
  local N=require('autobuilder.blueprint.nbt')
  local function bad(raw,reason)
    local ok,why=pcall(N.decode,raw); assert(not ok and tostring(why):find(reason,1,true),tostring(why))
  end
  bad(S.fixture():sub(1,-2),'truncated'); bad(S.fixture()..'x','trailing')
  bad(S.tag(10,'',S.compound({S.tag(3,'a',S.uint(1,4)),S.tag(3,'a',S.uint(2,4))})),'duplicate')
  bad(S.tag(10,'',S.compound({S.tag(13,'a','')})),'type')
  bad(S.tag(10,'',S.compound({S.tag(7,'a',S.uint(-1,4))})),'length')
  bad(S.tag(10,'',S.compound({S.tag(9,'a','\0'..S.uint(1,4))})),'list')
  local deep='\0'; for _=1,34 do deep=S.tag(10,'nested',deep)..'\0' end
  bad(S.tag(10,'',deep),'nesting')
  bad(S.tag(10,'',S.compound({S.tag(9,'a','\1'..S.uint(1000000,4)..('x'):rep(1000000))})),'node limit')
end)

test('native NBT preserves numeric tag kinds and exact opaque unused numeric bytes',function()
  local fields={S.tag(1,'byte','\255'),S.tag(2,'short',S.uint(-2,2)),S.tag(3,'int',S.uint(-3,4)),
    S.tag(4,'long',('x'):rep(8)),S.tag(5,'float',('y'):rep(4)),S.tag(6,'double',('z'):rep(8)),
    S.tag(12,'longs',S.uint(1,4)..('w'):rep(8))}
  local root=require('autobuilder.blueprint.nbt').decode(S.tag(10,'',S.compound(fields)))
  eq(root.kind,10); eq(root.value.byte.value,-1); eq(root.value.short.value,-2); eq(root.value.int.value,-3)
  eq(root.value.long.value,('x'):rep(8)); eq(root.value.float.value,('y'):rep(4)); eq(root.value.longs.count,1)
end)
