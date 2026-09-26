local U=require('autobuilder.core.util')
local M={}
local defaultBase='https://raw.githubusercontent.com/jdbrande/computercraft-autobuilder/main'
local active={preparing=true,ready=true,building=true,verifying=true,repairing=true,clearing=true}
function M.new(app,config,e,projects,loaderFactory)
  local s=app.state.automation; local self={}; local loader
  local function save() return app:save() end
  local function getLoader(c)
    if not loader then loader=(loaderFactory or require('autobuilder.blueprint.catalog').new)(e,c.url,config.dataDir..'/cathedral-cache') end
    return loader
  end
  local function base()
    if e.fs and e.fs.exists('/autobuilder/.installation.json') then
      local ok,r=pcall(function() return e.textutils.unserializeJSON(require('autobuilder.install.io').read(e.fs,'/autobuilder/.installation.json')) end)
      if ok and type(r)=='table' and r.baseUrl then return r.baseUrl end
    end
    return defaultBase
  end
  function self:command(args)
    local action=args[2] or 'status'; local c=s.cathedral
    if action=='start' then
      assert(not c or c.status=='completed','Cathedral already queued; use cathedral status, pause or resume')
      assert(config.build.enabled,'Run controller setup before starting construction')
      assert(#args==5 or #args==6,'Usage: cathedral start <corner x> <corner y> <corner z> [stream URL]. Needs a clear 416 x 239 site, outside your depot.')
      local origin={x=tonumber(args[3]),y=tonumber(args[4]),z=tonumber(args[5])}
      assert(U.position(origin),'The build corner needs three whole numbers: x y z')
      local candidate={url=args[6] or base()..'/blueprints/classic-cathedral/stream',origin=origin,page=1,entry=1,sequence=0,completedBlocks=0,status='waiting'}
      loader=nil; local root=getLoader(candidate):root()
      assert(origin.y>=-64 and origin.y+root.size.y+1<=319,'Cathedral and turtle clearance exceed Overworld build height (-64..319)')
      candidate.root=U.copy(root); candidate.run=(c and c.run or 0)+1
      s.cathedral=candidate; app.state.view='cathedral'; save()
      return true,'Cathedral queued. Existing projects finish first. Type cathedral to see material workers.'
    end
    assert(c,'Start with: cathedral start <corner x> <corner y> <corner z>. The full site must have clear access; the small-test clearing covers only 8 x 8.')
    app.state.view='cathedral'
    if action=='pause' or action=='resume' then
      c.paused=action=='pause'
      if c.batch then projects:command({'build',action,c.batch}) end
      save(); return true,c.paused and 'Cathedral paused. Assigned miners finish their safe return.' or 'Cathedral resumed'
    end
    assert(action=='status','Use cathedral start|status|pause|resume')
    return true,c.status..': '..c.completedBlocks..'/'..c.root.totalBlocks..' verified blocks'..(c.error and '; '..c.error or '')
  end
  local function advance(c,entry)
    c.completedBlocks=c.completedBlocks+entry.blockCount
    c.entry=c.entry+1; c.batch=nil; c.current=nil; c.status='waiting'; c.error=nil
    if c.entry>c.root.pages[c.page].count then c.entry=1; c.page=c.page+1 end
    if c.page>#c.root.pages then
      assert(c.completedBlocks==c.root.totalBlocks,'Catalog block total changed; completion refused')
      c.status='completed'
    end
    save()
  end
  local function tick()
    local c=s.cathedral
    if not c or c.paused or c.status=='completed' then return end
    if c.batch then
      local p=assert(s.projects[c.batch],'Active cathedral batch is missing; restore controller checkpoint')
      c.status=p.phase
      if p.phase=='built' or p.phase=='verified' then
        local ok,err=projects:retire(c.batch,function() advance(c,c.current) end)
        if not ok then c.error=err; return end
      elseif p.phase=='needs_repair' then c.error='Batch verification failed. Clear the reported obstruction, then build repair '..c.batch
      else
        local r=p.requestId and s.requests[p.requestId]
        c.error=p.error or r and r.error
      end
      return
    end
    for _,p in pairs(s.projects) do
      if active[p.phase] or p.phase=='needs_repair' then c.status='waiting'; c.error='Waiting for existing project '..tostring(p.name or 'pilot')..' to finish'; return end
    end
    if app.state.firstBuild and app.state.firstBuild.autoStart then c.error='Waiting for the small test to finish'; return end
    local page=getLoader(c):page(c.root,c.page); local entry=assert(page.entries[c.entry],'Catalog entry missing')
    assert(entry.size.y==1,'Cathedral chunks must be one layer high')
    for _,axis in ipairs({'x','y','z'}) do
      assert(U.integer(entry.offset[axis]) and entry.offset[axis]>=0 and entry.offset[axis]+entry.size[axis]<=c.root.size[axis],'Chunk lies outside cathedral bounds')
    end
    if c.lastOffset then
      local a,b=entry.offset,c.lastOffset
      assert(a.y>b.y or a.y==b.y and (a.z>b.z or a.z==b.z and a.x>b.x),'Catalog is not in ascending layer order')
    end
    local path=getLoader(c):chunk(entry)
    local name='cathedral_'..c.run..'_'..(c.sequence+1)
    local transform=U.copy(config.build); transform.rotation=0; transform.mirrorX=false; transform.mirrorZ=false
    transform.origin={x=c.origin.x+entry.offset.x,y=c.origin.y+entry.offset.y,z=c.origin.z+entry.offset.z}
    -- A prior interrupted import is harmless: immutable import ownership is
    -- reconciled by the same deterministic name before any production starts.
    if not s.projects[name] then projects:command({'build','import',path,name},transform) end
    c.batch=name; c.current=U.copy(entry); c.sequence=c.sequence+1; c.lastOffset=U.copy(entry.offset); c.error=nil; save()
    projects:command({'build','auto',name}); c.status='preparing'; save()
  end
  function self:tick()
    local ok,err=pcall(tick)
    if not ok and s.cathedral then s.cathedral.error=tostring(err); s.cathedral.status='blocked'; save() end
    -- Recover a checkpoint saved between linking the import and requesting materials.
    local c=s.cathedral; local p=c and c.batch and s.projects[c.batch]
    if p and p.phase=='imported' and not c.paused then
      local good,why=pcall(projects.command,projects,{'build','auto',c.batch})
      if not good then c.error=tostring(why); c.status='blocked'; save() end
    end
  end
  return self
end
return M
