local function fixture(name)
  local h=assert(io.open('tests/fixtures/native/'..name,'rb')); local data=h:read('*a'); h:close(); return data
end
local function rejects(data,limit,reason)
  local ok,why=pcall(require('autobuilder.blueprint.gzip').decode,data,limit or 200000)
  assert(not ok and tostring(why):find(reason,1,true),'expected '..reason..', got '..tostring(why))
end
local function changed(data,index)
  return data:sub(1,index-1)..string.char((data:byte(index)+1)%256)..data:sub(index+1)
end

test('native gzip decodes stored fixed dynamic optional headers and empty payload',function()
  local G=require('autobuilder.blueprint.gzip'); local payload=fixture('payload.bin')
  for _,name in ipairs({'stored','fixed','dynamic','optional'}) do local data=fixture(name..'.gz'); eq(G.decode(data,math.max(#data,#payload)),payload) end
  eq(G.decode(fixture('empty.gz'),20),'')
end)

test('native gzip rejects header trailer and payload corruption',function()
  local data=fixture('dynamic.gz')
  rejects('not gzip',nil,'gzip'); rejects(changed(data,3),nil,'method')
  rejects(data:sub(1,3)..string.char(32)..data:sub(5),nil,'flags')
  rejects(changed(fixture('optional.gz'),32),nil,'header CRC')
  rejects(changed(data,#data-7),nil,'CRC'); rejects(changed(data,#data-3),nil,'size')
  rejects(data..'x',nil,'trailing'); rejects(data..fixture('empty.gz'),nil,'trailing')
  rejects(data:sub(1,10)..string.char(7)..data:sub(12),nil,'deflate')
end)

test('native gzip bounds expansion while inflating and yields before completion',function()
  local G=require('autobuilder.blueprint.gzip'); local C=require('autobuilder.core.cooperate'); local every=C.every; local yields=0
  C.every=function(n) if n%1024==0 then yields=yields+1 end end
  local ok,why=pcall(function()
    eq(G.decode(fixture('dynamic.gz'),200000),fixture('payload.bin')); assert(yields>0,'inflation did not cooperate')
    yields=0; rejects(fixture('dynamic.gz'),70000,'expanded byte limit'); assert(yields>0,'inflation did not yield before exceeding its bound')
    -- A forged small ISIZE must not bypass the actual inflation bound.
    local data=fixture('dynamic.gz'); rejects(data:sub(1,-5)..'\0\0\0\0',70000,'expanded byte limit')
  end)
  C.every=every; assert(ok,why)
end)

test('native gzip refuses truncated and oversized source before returning bytes',function()
  local data=fixture('optional.gz')
  for _,n in ipairs({0,1,3,9,11,14,23,31,#data-9,#data-1}) do rejects(data:sub(1,n),nil,'gzip') end
  rejects(fixture('stored.gz'),100,'byte limit')
end)
