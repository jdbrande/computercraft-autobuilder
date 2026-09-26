local M = {}
function M.finite(n) return type(n)=='number' and n==n and n~=math.huge and n~=-math.huge end
function M.shortString(s,limit)
  return type(s)=='string' and #s>0 and #s<=(limit or 64) and not s:find('[%c]')
end
function M.integer(n) return M.finite(n) and n%1==0 end
function M.position(p)
  return type(p)=='table' and M.integer(p.x) and M.integer(p.y) and M.integer(p.z)
    and math.abs(p.x)<=30000000 and math.abs(p.z)<=30000000 and math.abs(p.y)<=30000000
end
function M.copy(v)
  if type(v)~='table' then return v end
  local out={}; for k,x in pairs(v) do out[k]=M.copy(x) end; return out
end
function M.distance(a,b) return math.abs(a.x-b.x)+math.abs(a.y-b.y)+math.abs(a.z-b.z) end
function M.heading(h) return h=='north' or h=='east' or h=='south' or h=='west' end
return M
