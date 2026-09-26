-- Keep recent detailed replies, and exact sequence intervals for older ACKed
-- work. Archived assignments are refused, never executed a second time.
local M={}
local function split(id) local prefix,n=id:match('^(.*:)(%d+)$'); return prefix,tonumber(n) end
local function base36(n)
  local digits='0123456789abcdefghijklmnopqrstuvwxyz'; local out=''
  repeat local d=n%36; out=digits:sub(d+1,d+1)..out; n=math.floor(n/36) until n==0
  return out
end
local function mine(id)
  local prefix,time,sequence=id:match('^(mine:%d+:)(%d+):(%d+)$')
  if prefix then return prefix,base36(tonumber(time))..','..base36(tonumber(sequence))..';' end
end
local function ranges(text)
  local out={}
  for a,b in (text or ''):gmatch('(%d+)%-(%d+);') do out[#out+1]={tonumber(a),tonumber(b)} end
  return out
end
function M.archived(s,key,id)
  local group,encoded=mine(id); local archive=s[key..'Archive'] or {}
  if group and archive[group] and archive[group]:find(';'..encoded,1,true) then return true end
  local prefix,n=split(id); if not prefix then return false end
  for _,r in ipairs(ranges(archive[prefix])) do if n>=r[1] and n<=r[2] then return true end end
  return false
end
function M.record(s,key,id,value)
  s[key]=s[key] or {}; s[key][id]=value
  local ids={}; for saved in pairs(s[key]) do ids[#ids+1]=saved end
  if #ids<=64 then return end
  table.sort(ids,function(a,b)
    local pa,na=split(a); local pb,nb=split(b)
    if pa and pb and pa==pb then return na<nb end
    return a<b
  end)
  local archive=s[key..'Archive'] or {}; s[key..'Archive']=archive
  for i=1,#ids-64 do
    local old=ids[i]; local prefix,n=split(old)
    local group,encoded=mine(old)
    if group then
      -- Preserve both timestamp and sequence, including after controller backup
      -- recovery, without paying a table-key/envelope cost for every old mine.
      archive[group]=(archive[group] or ';')..encoded; s[key][old]=nil
    elseif prefix then
      local all=ranges(archive[prefix]); all[#all+1]={n,n}
      table.sort(all,function(a,b) return a[1]<b[1] end)
      local merged={}
      for _,r in ipairs(all) do
        local last=merged[#merged]
        if last and r[1]<=last[2]+1 then last[2]=math.max(last[2],r[2]) else merged[#merged+1]=r end
      end
      local parts={}; for _,r in ipairs(merged) do parts[#parts+1]=r[1]..'-'..r[2]..';' end
      archive[prefix]=table.concat(parts); s[key][old]=nil
    end
  end
end
return M
