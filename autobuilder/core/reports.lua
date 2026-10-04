-- Transport exact totals with a bounded sample of defects, not hundreds of
-- redundant copies of correctly placed palette states in every heartbeat.
local U=require('autobuilder.core.util')
local M={}
local function short(v,n) return v~=nil and tostring(v):gsub('[%c]',' '):sub(1,n) or nil end
function M.materialItem(block)
  if not block or type(block.name)~='string' then return nil end
  if block.name:match('_door$') and (block.state or {}).half=='upper' then return nil end
  if block.name:match('_bed$') and (block.state or {}).part=='head' then return nil end
  return require('autobuilder.build.blockstates').item(block)
end
function M.validMaterials(values)
  if type(values)~='table' then return false end
  local total=0
  for item,n in pairs(values) do
    if not U.shortString(item,128) or not U.integer(n) or n<1 or n>512 then return false end
    total=total+n;if total>512 then return false end
  end
  return true
end
function M.materials(report)
  if report.materials then return U.copy(report.materials) end
  local values,correct={},0
  for _,entry in ipairs(report.entries or {}) do if entry.status=='correct' then
    correct=correct+1
    if not entry.expected then return nil end
    local item=M.materialItem(entry.expected);if item then values[item]=(values[item] or 0)+1 end
  end end
  -- Legacy compact reports omitted correct entries. Preserve that uncertainty.
  if correct~=((report.counts or {}).correct or 0) then return nil end
  return values
end
function M.compact(report,kind)
  if not report then return nil end
  local out={counts=U.copy(report.counts or {}),entries={},omittedEntries=report.omittedEntries or 0}
  if kind==nil or ({BUILD=true,REPAIR=true,VERIFY=true,CLEAR=true})[kind] then out.materials=M.materials(report) end
  if report.accessChanges~=nil then out.accessChanges=U.copy(report.accessChanges) end
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
