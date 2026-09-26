-- Trees share the bounded plot executor and its durable harvest/replant/delivery intents.
local Farmer=require('autobuilder.resources.farmer')
local M={}
function M.new(task,e,config,nav,save)
  return Farmer.new(task,e,config,nav,save,true)
end
return M
