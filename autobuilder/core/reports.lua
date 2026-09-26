-- Transport exact totals with a bounded sample of defects, not hundreds of
-- redundant copies of correctly placed palette states in every heartbeat.
local U=require('autobuilder.core.util')
local M={}
local function short(v,n) return v~=nil and tostring(v):gsub('[%c]',' '):sub(1,n) or nil end
function M.compact(report)
  if not report then return nil end
  local out={counts=U.copy(report.counts or {}),entries={},omittedEntries=report.omittedEntries or 0}
  for _,entry in ipairs(report.entries or {}) do
    if entry.status~='correct' then
      if #out.entries>=16 then out.omittedEntries=out.omittedEntries+1
      else
        local e={x=entry.x,y=entry.y,z=entry.z,index=entry.index,status=short(entry.status,32),reason=short(entry.reason,256)}
        if type(entry.expected)=='table' then e.expected={name=short(entry.expected.name,128)} end
        if type(entry.actual)=='table' then e.actual={name=short(entry.actual.name,128)} end
        e.stateDifferences={}
        for key,value in pairs(type(entry.expected)=='table' and entry.expected.state or {}) do
          local actual=type(entry.actual)=='table' and (entry.actual.state or {})[key]
          if tostring(value)~=tostring(actual) and #e.stateDifferences<8 then e.stateDifferences[#e.stateDifferences+1]={property=short(key,64),expected=short(value,128),actual=short(actual,128)} end
        end
        out.entries[#out.entries+1]=e
      end
    end
  end
  return out
end
return M
