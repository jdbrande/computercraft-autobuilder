-- CPU-only planning must yield on CraftOS. Replay events received while yielding:
-- this may run in the UI coroutine, whose input/network events must not be lost.
-- Never call inside a checkpoint/transaction or between mutation and intent save.
local M={}
function M.every(index)
  if index%1024~=0 or not os or not os.queueEvent or not os.pullEventRaw then return end
  local eventName='autobuilder_planning_yield'
  os.queueEvent(eventName)
  local pending={}
  while true do
    local event=table.pack(os.pullEventRaw())
    if event[1]=='terminate' then error('Terminated',0) end
    if event[1]==eventName then break end
    pending[#pending+1]=event
  end
  for _,event in ipairs(pending) do os.queueEvent(table.unpack(event,1,event.n)) end
end
return M
