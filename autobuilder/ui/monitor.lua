local M={}
function M.new(e,config)
 local self={page=0};local last=-math.huge;local rendered
 function self:touch() self.page=self.page+1;last=-math.huge end
 function self:draw(lines,now)
  if config.name=='' then return true end
  if now-last<config.interval then return true end;last=now
  local ok,why=pcall(function()
   local term=assert(e.peripheral.wrap(config.name),'Configured monitor is disconnected')
   if term.setTextScale then term.setTextScale(config.scale) end
   local width,height=term.getSize();assert(width>0 and height>1,'Monitor is too small')
   local rows={};for _,line in ipairs(lines) do
    if line=='' then rows[#rows+1]='' else for i=1,#line,width do rows[#rows+1]=line:sub(i,i+width-1) end end
   end
   local perPage=height-1;local pages=math.max(1,math.ceil(#rows/perPage));self.page=self.page%pages
   local view={};for i=self.page*perPage+1,math.min(#rows,(self.page+1)*perPage) do view[#view+1]=rows[i] end
   for i=#view+1,height-1 do view[i]='' end
   view[height]=('Page '..(self.page+1)..'/'..pages..' | tap next'):sub(1,width)
   local signature=width..':'..height..':'..table.concat(view,'\n')
   if signature~=rendered then
    term.clear();for row,text in pairs(view) do term.setCursorPos(1,row);term.write(text) end
    rendered=signature
   end
  end)
  if not ok then rendered=nil;return false,tostring(why) end
  return true
 end
 return self
end
return M
