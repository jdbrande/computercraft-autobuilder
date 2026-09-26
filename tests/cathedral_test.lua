local U=require('autobuilder.core.util')
local function fixture()
  local s={automation={projects={},requests={},jobs={}},workers={}}
  local app={state=s,save=function() return true end}
  local root={schema=1,project='test',size={x=2,y=2,z=1},totalBlocks=2,pages={{count=2}}}
  local entries={{offset={x=0,y=0,z=0},size={x=1,y=1,z=1},blockCount=1},{offset={x=0,y=1,z=0},size={x=1,y=1,z=1},blockCount=1}}
  local loader={root=function() return root end,page=function() return {entries=entries} end,chunk=function() return '/chunk.json' end}
  local projects={}
  function projects:command(a,t)
    if a[2]=='import' then s.automation.projects[a[4]]={name=a[4],transform=U.copy(t),phase='imported',jobs={}}
    elseif a[2]=='auto' then s.automation.projects[a[3]].phase='preparing'
    elseif a[2]=='pause' then s.automation.projects[a[3]].paused=true
    elseif a[2]=='resume' then s.automation.projects[a[3]].paused=false end
    return true
  end
  function projects:retire(name,advance) s.automation.projects[name]=nil; advance(); return true end
  local config=require('autobuilder.config').load({build={enabled=true}})
  local e={}
  local function new() return require('autobuilder.blueprint.cathedral').new(app,config,e,projects,function() return loader end) end
  return app,new(),new,entries
end
test('cathedral waits for pilot and verifies each layer across pause and restart',function()
  local app,c,reboot=fixture(); local s=app.state.automation
  s.projects.pilot={phase='building'}
  assert(c:command({'cathedral','start','20','60','30'})); c:tick()
  eq(s.cathedral.batch,nil); eq(s.projects.pilot.phase,'building')
  s.projects.pilot.phase='built'; c:tick()
  local first=s.cathedral.batch; assert(first)
  eq(s.projects[first].transform.origin.y,60); eq(s.projects[first].phase,'preparing')
  assert(c:command({'cathedral','pause'})); s.projects[first].phase='built'; c:tick()
  eq(s.cathedral.completedBlocks,0)
  c=reboot(); assert(c:command({'cathedral','resume'})); c:tick(); c:tick()
  eq(s.cathedral.completedBlocks,1); assert(s.cathedral.batch~=first)
  eq(s.projects[s.cathedral.batch].transform.origin.y,61)
  s.projects[s.cathedral.batch].phase='needs_repair'; c:tick()
  eq(s.cathedral.completedBlocks,1); assert(s.cathedral.error:find('verification'))
  s.projects[s.cathedral.batch].phase='built'; c:tick(); c:tick()
  eq(s.cathedral.status,'completed'); eq(s.cathedral.completedBlocks,2)
end)
test('cathedral rejects unsafe height and holds its cursor on a failed download',function()
  local app,c,_,entries=fixture()
  assert(not pcall(c.command,c,{'cathedral','start','0','318','0'}))
  assert(c:command({'cathedral','start','0','60','0'}))
  entries[1].offset.y=-1; c:tick()
  eq(app.state.automation.cathedral.entry,1); eq(app.state.automation.cathedral.batch,nil)
  assert(app.state.automation.cathedral.error)
end)
