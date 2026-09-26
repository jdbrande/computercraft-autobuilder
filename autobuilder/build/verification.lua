local Builder=require('autobuilder.build.builder')
local Placement=require('autobuilder.build.placement')
local M={compare=Placement.compare}
function M.new(task,e,config,nav,save) return Builder.new(task,e,config,nav,save,'verify') end
return M
