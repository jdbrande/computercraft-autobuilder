local U=require('autobuilder.core.util')
local M={}
function M.new(peripheral,names)
  local self={counts={},valid=false}
  function self:refresh()
    self.valid=false
    if #names==0 then return false,'no storage inventories configured' end
    local ok,result=pcall(function()
      local counts,seen={},{}
      for _,name in ipairs(names) do
        assert(not seen[name],'duplicate storage inventory'); seen[name]=true
        local items=peripheral.call(name,'list'); assert(type(items)=='table','invalid inventory list')
        for _,item in pairs(items) do
          assert(U.shortString(item.name,128) and U.integer(item.count) and item.count>=0,'invalid inventory item')
          counts[item.name]=(counts[item.name] or 0)+item.count
        end
      end
      return counts
    end)
    if not ok then return false,'storage unavailable: '..tostring(result) end
    self.counts=result; self.valid=true; return true
  end
  function self:getCount(item)
    if not self.valid then return nil,'storage snapshot unavailable' end
    return self.counts[item] or 0
  end
  return self
end
return M
