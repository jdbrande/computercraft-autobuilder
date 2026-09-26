local U=require('autobuilder.core.util')
local M={}
function M.key(p) return p.x..','..p.y..','..p.z end
function M.neighbors(p)
  return {{x=p.x+1,y=p.y,z=p.z},{x=p.x-1,y=p.y,z=p.z},
    {x=p.x,y=p.y+1,z=p.z},{x=p.x,y=p.y-1,z=p.z},
    {x=p.x,y=p.y,z=p.z+1},{x=p.x,y=p.y,z=p.z-1}}
end
function M.inside(p,box)
  return box and p.x>=box.min.x and p.x<=box.max.x and p.y>=box.min.y and p.y<=box.max.y and p.z>=box.min.z and p.z<=box.max.z
end
function M.find(start,goal,passable,budget)
  if not U.position(start) or not U.position(goal) then return nil,'invalid path endpoints' end
  budget=budget or 4096
  local startKey=M.key(start); local goalKey=M.key(goal)
  local open={{p=start,g=0,f=U.distance(start,goal)}}; local best={[startKey]=0}; local parents,points,closed={},{},{}
  points[startKey]=start
  for _=1,budget do
    if #open==0 then return nil,'no safe path' end
    local index=1; for i=2,#open do if open[i].f<open[index].f then index=i end end
    local current=table.remove(open,index); local key=M.key(current.p)
    if key==goalKey then
      local result={}
      while key~=startKey do table.insert(result,1,points[key]); key=parents[key] end
      return result
    end
    if not closed[key] then
      closed[key]=true
      for _,p in ipairs(M.neighbors(current.p)) do
        local k=M.key(p); local g=current.g+1
        if not closed[k] and (not best[k] or g<best[k]) and passable(p) then
          best[k]=g; parents[k]=key; points[k]=p
          open[#open+1]={p=p,g=g,f=g+U.distance(p,goal)}
        end
      end
    end
  end
  return nil,'path search budget exhausted'
end
return M
