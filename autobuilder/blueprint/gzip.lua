-- Strict single-member RFC1952 wrapper around the pinned bounded inflater.
local Cooperate=require('autobuilder.core.cooperate')
local M={}
local crcTable={}
for n=0,255 do
  local c=n
  for _=1,8 do c=c%2==1 and bit32.bxor(bit32.rshift(c,1),0xedb88320) or bit32.rshift(c,1) end
  crcTable[n]=c
end
local function crc32(data)
  local crc=0xffffffff
  for i=1,#data do
    crc=bit32.bxor(bit32.rshift(crc,8),crcTable[bit32.band(bit32.bxor(crc,data:byte(i)),255)])
    Cooperate.every(i)
  end
  return bit32.bxor(crc,0xffffffff)
end
function M.decode(data,maxBytes)
  assert(type(data)=='string','invalid gzip source')
  assert(type(maxBytes)=='number' and maxBytes%1==0 and maxBytes>=1 and maxBytes<=32*1024*1024,'invalid gzip byte limit')
  assert(#data<=maxBytes,'gzip source byte limit exceeded')
  assert(#data>=18 and data:sub(1,2)=='\31\139','invalid or truncated gzip header')
  assert(data:byte(3)==8,'unsupported gzip method')
  local flags=data:byte(4); assert(flags<32,'invalid gzip flags')
  local pos=11
  local function take(n)
    assert(n>=0 and pos+n-1<=#data-8,'truncated gzip header')
    local value=data:sub(pos,pos+n-1); pos=pos+n; return value
  end
  local function little(raw)
    local n=0; for i=#raw,1,-1 do n=n*256+raw:byte(i) end; return n
  end
  if bit32.band(flags,4)~=0 then take(little(take(2))) end
  for _,flag in ipairs({8,16}) do
    if bit32.band(flags,flag)~=0 then
      local n=0
      repeat n=n+1; Cooperate.every(n) until take(1)=='\0'
    end
  end
  if bit32.band(flags,2)~=0 then
    local expected=bit32.band(crc32(data:sub(1,pos-1)),65535)
    assert(little(take(2))==expected,'gzip header CRC mismatch')
  end
  assert(pos<=#data-8,'truncated gzip deflate stream')
  local raw,remaining=require('autobuilder.vendor.libdeflate'):DecompressDeflateBounded(data:sub(pos),maxBytes,function() Cooperate.every(1024) end)
  assert(raw,'invalid gzip deflate stream')
  assert(remaining==8,'gzip trailing or truncated member data')
  assert(little(data:sub(-8,-5))==crc32(raw),'gzip data CRC mismatch')
  assert(little(data:sub(-4))==#raw,'gzip expanded size mismatch')
  return raw
end
return M
