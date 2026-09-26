local Builder=require('autobuilder.build.builder')
local M={}
function M.new(task,e,config,nav,save) return Builder.new(task,e,config,nav,save,'repair') end
return M
