local M={}
function M.uint(n,width)
  local out={}; n=n%2^(width*8)
  for i=width,1,-1 do out[i]=string.char(n%256); n=math.floor(n/256) end
  return table.concat(out)
end
function M.string(s) return M.uint(#s,2)..s end
function M.tag(kind,name,payload) return string.char(kind)..M.string(name)..payload end
function M.compound(fields) return table.concat(fields)..'\0' end
function M.fixture(options)
  local o=options or {}; local v=o.version or 2
  local palette={}
  for _,p in ipairs(o.palette or {{'minecraft:air',0},{'minecraft:oak_log[axis=x]',1}}) do palette[#palette+1]=M.tag(3,p[1],M.uint(p[2],4)) end
  local data=o.data or '\0\1\1\0'
  local blocks=M.tag(10,'Palette',M.compound(palette))..M.tag(7,v==3 and 'Data' or 'BlockData',M.uint(#data,4)..data)
  local fields={M.tag(o.versionKind or 3,'Version',M.uint(v,o.versionKind==2 and 2 or 4)),M.tag(3,'DataVersion',M.uint(3700,4)),
    M.tag(o.widthKind or 2,'Width',M.uint(o.width or 2,o.widthKind==3 and 4 or 2)),M.tag(2,'Height',M.uint(o.height or 1,2)),M.tag(2,'Length',M.uint(o.length or 2,2))}
  fields[#fields+1]=v==3 and M.tag(10,'Blocks',blocks..'\0') or blocks
  for _,extra in ipairs(o.extra or {}) do fields[#fields+1]=extra end
  local body=M.compound(fields)
  return v==3 and M.tag(10,'',M.compound({M.tag(10,'Schematic',body)})) or M.tag(10,'Schematic',body)
end
function M.file(name)
  local h=assert(io.open('tests/fixtures/native/'..name,'rb')); local data=h:read('*a'); h:close(); return data
end
return M
