-- Bounded big-endian NBT. Keep tag kinds at the format boundary. Unused long,
-- floating-point and long-array values remain exact bytes, never rounded doubles.
local Cooperate=require('autobuilder.core.cooperate')
local M={}
function M.decode(data)
  assert(type(data)=='string' and #data<=32*1024*1024,'NBT byte limit exceeded')
  local pos,nodes=1,0
  local function take(n)
    assert(n>=0 and n<=#data-pos+1,'truncated NBT value')
    local raw=data:sub(pos,pos+n-1); pos=pos+n; return raw
  end
  local function number(width,signed)
    local raw=take(width); local n=0
    for i=1,width do n=n*256+raw:byte(i) end
    if signed and n>=2^(width*8-1) then n=n-2^(width*8) end
    return n
  end
  local function stringValue() return take(number(2)) end
  local function count()
    local n=number(4,true); assert(n>=0 and n<=#data,'invalid NBT collection length'); return n
  end
  local payload
  payload=function(kind,depth)
    nodes=nodes+1; assert(nodes<=1000000,'NBT node limit exceeded'); assert(depth<=32,'NBT nesting limit exceeded')
    Cooperate.every(nodes)
    local node={kind=kind}
    if kind>=1 and kind<=3 then node.value=number(({1,2,4})[kind],true)
    elseif kind>=4 and kind<=6 then node.value=take(({[4]=8,[5]=4,[6]=8})[kind])
    elseif kind==7 then node.count=count(); node.value=take(node.count)
    elseif kind==8 then node.value=stringValue()
    elseif kind==9 then
      local element,n=number(1),count()
      assert(element<=12 and (element~=0 or n==0),'invalid NBT list type')
      assert(nodes+n<=1000000,'NBT node limit exceeded')
      node.element=element; node.count=n; node.value={}
      for i=1,n do node.value[i]=payload(element,depth+1) end
    elseif kind==10 then
      node.value={}
      while true do
        local child=number(1); if child==0 then break end
        assert(child<=12,'unknown NBT tag type')
        local name=stringValue(); assert(node.value[name]==nil,'duplicate NBT compound key')
        node.value[name]=payload(child,depth+1)
      end
    elseif kind==11 or kind==12 then
      local n=count(); assert(nodes+n<=1000000,'NBT node limit exceeded')
      node.count=n
      if kind==12 then node.value=take(n*8); nodes=nodes+n
      else
        assert(n*4<=#data-pos+1,'truncated NBT int array'); node.value={}
        for i=1,n do node.value[i]=number(4,true); nodes=nodes+1; Cooperate.every(nodes) end
      end
    else error('unknown NBT tag type',0) end
    return node
  end
  assert(number(1)==10,'NBT root must be compound'); stringValue()
  local root=payload(10,0); assert(pos==#data+1,'trailing NBT data'); return root
end
return M
