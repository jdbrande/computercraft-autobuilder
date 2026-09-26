local U=require('autobuilder.core.util')
local IS=require('tests.install_support')
local function fixture(options)
  options=options or {}
  local w=require('tests.build_world').new(); w.items[1]={name='minecraft:stone',count=8}
  local function env(id)
    local codec=require('tests.support').codec(); codec.unserializeJSON=codec.unserialize; codec.serializeJSON=codec.serialize
    local e={fs=IS.fs(),textutils=codec,now=100,packets={}}
    e.os={getComputerID=function() return id end,epoch=function() return e.now*1000 end}
    e.rednet={isOpen=function() return true end,open=function() end,send=function(to,m,p) e.packets[#e.packets+1]={to=to,m=U.copy(m),protocol=p}; return true end}
    e.peripheral={getNames=function() return {'right'} end,getType=function() return 'modem' end,
      call=function(name,method) if method=='isWireless' then return true end; if method=='size' then return 1 end; assert(method=='list'); return {[1]={name='minecraft:stone',count=8}} end}
    return e
  end
  local ce,we=env(7),env(12); we.turtle=w.turtle
  local C=require('autobuilder.config'); local cc=C.load({storageInventories={'stock'},turtleFuelReserveItems={},clearSite=options.clearSite or false,build={enabled=true,origin={x=2,y=0,z=0},rotation=options.rotation or 0,mirrorX=options.mirrorX or false},autoDepotExpansion={enabled=options.expansion~=nil,freeSlots=0},depotExpansion=options.expansion or {}})
  local wc=C.load({role='worker',controllerId=7,automation={building=true},clearSite=options.clearSite or false,minimumFuelReserve=0,initialPosition=U.copy(w.pose)})
  local R=require('autobuilder.core.runtime'); local c,b=R.new(cc,ce),R.new(wc,we)
  local blueprint={schema=1,size={x=2,y=1,z=1},palette={{name='minecraft:stone',state={}}},runs={{id=1,count=2}},metadata={},requirements={['minecraft:stone']=2}}
  ce.fs.files['/example.json']=ce.textutils.serialize(options.blueprint or blueprint)
  local function pump(from,to)
    local packets=from.packets; from.packets={}
    for _,p in ipairs(packets) do to:receive(p.m.sender,p.m,p.protocol) end
  end
  local function step()
    ce.now=ce.now+1; we.now=ce.now
    b:tick(); pump(we,c); c:tick(); pump(ce,b); b:workStep(); pump(we,c); pump(ce,b)
  end
  return w,ce,we,c,b,step,function() c=R.new(cc,ce); b=R.new(wc,we); return c,b end
end
test('full storage automatically builds and verifies configured depot footprint across runtime restart',function()
  local plan={{x=2,y=0,z=0,name='minecraft:stone',state={}},{x=3,y=0,z=0,name='minecraft:stone',state={}}}
  local w,ce,we,c,b,step,reboot=fixture({expansion=plan})
  local restarted=false
  for _=1,350 do
    step()
    if not restarted and w.places==1 then c,b=reboot(); restarted=true end
    if c.state.automation.infrastructure.status=='completed' and not b.state.currentTask then break end
  end
  assert(restarted); eq(w.places,2); eq(c.state.automation.infrastructure.status,'completed')
  eq(c.state.automation.infrastructure.report.counts.correct,2)
  local count=0; for _ in pairs(c.state.automation.jobs) do count=count+1 end; eq(count,2)
end)
test('build import analyze prepare start verify repair run through real controller and worker',function()
  local w,ce,we,c,b,step,reboot=fixture()
  assert(c:command('build import /example.json sample')); assert(c:command('build analyze sample'))
  eq(w.places,0); eq(c.state.automation.projects.sample.total,2)
  assert(c:command('build prepare sample')); for _=1,3 do step() end
  eq(c.state.automation.projects.sample.phase,'ready'); assert(c:command('build start sample'))
  local restarted=false
  for i=1,250 do
    step()
    if not restarted and w.places==1 then c,b=reboot(); restarted=true end
    if c.state.automation.projects.sample.phase=='built' and not b.state.currentTask then break end
  end
  assert(restarted); eq(c.state.automation.projects.sample.phase,'built'); eq(w.places,2)
  assert(c:command('build verify sample'))
  for _=1,250 do step(); if c.state.automation.projects.sample.phase=='verified' and not b.state.currentTask then break end end
  eq(c.state.automation.projects.sample.report.counts.correct,2)
  w.blocks['2,0,0']=nil
  assert(c:command('build repair sample'))
  for _=1,250 do step(); if c.state.automation.projects.sample.phase=='built' and not b.state.currentTask then break end end
  eq(w.blocks['2,0,0'].name,'minecraft:stone'); eq(w.places,3)
end)
test('build commands reject unsupported palette and modified imported data before placement',function()
  local w,ce,_,c=fixture()
  assert(c:command('build import /example.json sample'))
  ce.fs.files['/autobuilder/blueprints/sample.json']='corrupted'
  assert(not c:command('build prepare sample')); eq(w.places,0)
  assert(not c:command('request minecraft:stone nope')); assert(not c:command('request minecraft:stone -1'))
end)
test('build auto prepares stock and resumes through reboot without a separate start command',function()
  local w,ce,we,c,b,step,reboot=fixture()
  assert(c:command('build import /example.json automatic'))
  assert(c:command('build auto automatic'))
  local p=c.state.automation.projects.automatic
  assert(p.autoStart and not p.stockOnly)
  assert(c:command('build pause automatic'))
  for _=1,5 do step() end
  eq(w.places,0)
  assert(c.state.automation.requests[p.requestId].paused)
  c,b=reboot(); assert(c:command('build resume automatic'))
  for _=1,300 do step(); if c.state.automation.projects.automatic.phase=='built' and not b.state.currentTask then break end end
  eq(c.state.automation.projects.automatic.phase,'built'); eq(w.places,2)
  assert(not c.state.automation.projects.automatic.autoStart)
end)
local function airBlueprint()
  return {schema=1,size={x=2,y=1,z=1},palette={{name='minecraft:stone',state={}},{name='minecraft:air',state={}}},runs={{id=1,count=1},{id=2,count=1}},metadata={},requirements={['minecraft:stone']=1}}
end
local function awaitProject(c,b,step,phase)
  for _=1,350 do
    step()
    if c.state.automation.projects.air.phase==phase and not b.state.currentTask then return end
  end
  eq(c.state.automation.projects.air.phase,phase)
end
test('air-only projects prepare without production and clear then verify the volume',function()
  local bp=airBlueprint(); bp.runs={{id=2,count=2}}; bp.requirements={}
  local w,ce,we,c,b,step=fixture({blueprint=bp,clearSite=true})
  w.blocks['2,0,0']={name='minecraft:dirt',state={}}
  assert(c:command('build import /example.json air'))
  assert(not c:command('build start air'))
  assert(c:command('build prepare air'))
  eq(c.state.automation.projects.air.phase,'ready')
  eq(next(c.state.automation.requests),nil)
  assert(c:command('build start air')); awaitProject(c,b,step,'built')
  eq(w.digs,1); eq(w.places,0); eq(c.state.automation.projects.air.report.counts.correct,2)
end)
test('project verification includes occupied schematic air while analysis and gated repair preserve terrain',function()
  local w,ce,we,c,b,step=fixture({blueprint=airBlueprint()})
  w.blocks['2,0,0']={name='minecraft:stone',state={}}; w.blocks['3,0,0']={name='minecraft:dirt',state={}}
  assert(c:command('build import /example.json air')); assert(c:command('build analyze air')); eq(w.digs,0); eq(w.places,0)
  assert(c:command('build verify air')); assert(c:command('build analyze air')); eq(c.state.automation.projects.air.total,2); awaitProject(c,b,step,'needs_repair')
  eq(c.state.automation.projects.air.report.counts.wrong,1); eq(c.state.automation.projects.air.report.counts.correct,1)
  eq(#c.state.automation.projects.air.report.entries,1); eq(c.state.automation.projects.air.report.entries[1].status,'wrong')
  assert(c:command('build repair air')); awaitProject(c,b,step,'needs_repair')
  eq(w.digs,0); eq(w.blocks['3,0,0'].name,'minecraft:dirt'); assert(not c:command('build clear air'))
end)
test('project clearSite repair clears schematic air and verifies every cell',function()
  local w,ce,we,c,b,step=fixture({blueprint=airBlueprint(),clearSite=true})
  w.blocks['2,0,0']={name='minecraft:stone',state={}}; w.blocks['3,0,0']={name='minecraft:dirt',state={}}
  assert(c:command('build import /example.json air')); assert(c:command('build repair air')); awaitProject(c,b,step,'built')
  eq(w.digs,1); eq(w.blocks['3,0,0'],nil); eq(c.state.automation.projects.air.report.counts.correct,2)
end)
test('project start with site clearing repairs wrong wanted cells and survives clearing restart',function()
  local w,ce,we,c,b,step,reboot=fixture({blueprint=airBlueprint(),clearSite=true})
  w.blocks['2,0,0']={name='minecraft:dirt',state={}}; w.blocks['3,0,0']={name='minecraft:dirt',state={}}
  assert(c:command('build import /example.json air')); assert(c:command('build prepare air')); for _=1,3 do step() end
  assert(c:command('build start air')); local restarted=false
  for _=1,500 do
    step()
    if not restarted and w.digs==1 then c,b=reboot(); restarted=true end
    if c.state.automation.projects.air.phase=='built' and not b.state.currentTask then break end
  end
  assert(restarted); eq(c.state.automation.projects.air.phase,'built'); eq(w.digs,2); eq(w.places,1)
  eq(w.blocks['2,0,0'].name,'minecraft:stone'); eq(w.blocks['3,0,0'],nil)
  eq(c.state.automation.projects.air.report.counts.correct,2)
end)
test('explicit project clear respects transformed air coordinates and leaves wanted cells intact',function()
  local w,ce,we,c,b,step=fixture({blueprint=airBlueprint(),clearSite=true,rotation=90,mirrorX=true})
  -- Mirror sends original x=1 air to x=0; rotation puts it at local z=0.
  w.blocks['2,0,0']={name='minecraft:dirt',state={}}; w.blocks['2,0,1']={name='minecraft:stone',state={}}
  assert(c:command('build import /example.json air')); assert(c:command('build clear air')); awaitProject(c,b,step,'built')
  eq(w.digs,1); eq(w.blocks['2,0,0'],nil); eq(w.blocks['2,0,1'].name,'minecraft:stone')
end)
test('project air clear refuses containers without mutating the site',function()
  local w,ce,we,c,b,step=fixture({blueprint=airBlueprint(),clearSite=true})
  w.blocks['2,0,0']={name='minecraft:stone',state={}}; w.blocks['3,0,0']={name='minecraft:chest',state={}}
  assert(c:command('build import /example.json air')); assert(c:command('build clear air'))
  for _=1,100 do step(); if b.state.currentTask and b.state.currentTask.phase=='blocked' and not tostring(b.state.currentTask.error):find('reservation',1,true) then break end end
  assert(b.state.currentTask); eq(b.state.currentTask.phase,'blocked'); eq(w.digs,0); eq(w.blocks['3,0,0'].name,'minecraft:chest')
  assert(c.state.automation.projects.air.phase~='built')
end)
test('project air regions stay bounded while the full volume remains outside checkpoints',function()
  local volume=40*8*8
  local bp={schema=1,size={x=40,y=8,z=8},palette={{name='minecraft:air',state={}}},runs={{id=1,count=volume}},metadata={},requirements={}}
  local w,ce,we,c=fixture({blueprint=bp,clearSite=true})
  assert(c:command('build import /example.json air')); assert(c:command('build verify air'))
  for _=1,10 do ce.now=ce.now+1; c:tick() end
  local p=c.state.automation.projects.air; eq(p.volume,volume); eq(p.total,volume); eq(p.blocks,nil); eq(p.airRegions,nil); eq(p.verificationRegions,nil)
  local queued,cells=0,0
  for _,job in pairs(c.state.automation.jobs) do
    queued=queued+1; assert(#job.blocks<=512); cells=cells+#job.blocks
    for _,b in ipairs(job.blocks) do eq(b.name,'minecraft:air') end
  end
  eq(queued,4); assert(cells<volume); eq(w.digs,0); eq(w.places,0)
end)
test('cached project analysis does not bypass the imported blueprint content hash',function()
  local w,ce,we,c=fixture({blueprint=airBlueprint()})
  assert(c:command('build import /example.json air')); assert(c:command('build analyze air'))
  ce.fs.files['/autobuilder/blueprints/air.json']='modified after analysis'
  assert(not c:command('build prepare air')); eq(w.digs,0); eq(w.places,0)
end)
test('retired stream imports remain available until checkpoint backup no longer references them',function()
  local w,ce,we,c=fixture()
  assert(c:command('build import /example.json old_batch'))
  local p=c.state.automation.projects.old_batch; p.phase='built'; c:save()
  c.state.automation.jobs['old-job']={id='old-job',project=p.name,status='completed'}
  c.state.automation.requests['request:99']={id='request:99',key='supply:old-job:minecraft:coal',status='completed'}
  c.state.automation.jobs['fuel-factory']={id='fuel-factory',key='request:99:op:1',status='completed'}
  local path=p.path
  assert(c.automation.projects:retire(p.name))
  eq(c.state.automation.requests['request:99'],nil); eq(c.state.automation.jobs['fuel-factory'],nil)
  assert(ce.fs.exists(path),'backup still needs this import')
  c.automation.projects:tick()
  assert(not ce.fs.exists(path))
  local statePath='/autobuilder/data/controller.state'
  ce.fs.files[statePath]='corrupt primary'
  local recovered,source=require('autobuilder.core.checkpoint').new(ce.fs,ce.textutils,statePath):load()
  assert(source:find('backup')); eq(recovered.automation.projects.old_batch,nil)
end)
test('project build without clearing finishes with an air-cell defect report',function()
  local w,ce,we,c,b,step=fixture({blueprint=airBlueprint()})
  w.blocks['3,0,0']={name='minecraft:dirt',state={}}
  assert(c:command('build import /example.json air')); assert(c:command('build prepare air')); for _=1,3 do step() end
  assert(c:command('build start air')); awaitProject(c,b,step,'needs_repair')
  eq(w.places,1); eq(w.digs,0); eq(c.state.automation.projects.air.report.counts.wrong,1)
end)
test('project aggregation keeps exact report counts and omitted issue totals without correct-cell details',function()
  local w,ce,we,c=fixture({blueprint=airBlueprint()})
  assert(c:command('build import /example.json air')); assert(c:command('build verify air')); c:tick()
  local p=c.state.automation.projects.air; local j=c.state.automation.jobs[p.jobs[1]]
  j.status='completed'; j.progress=1
  j.report={counts={correct=1,wrong=1},entries={{status='correct',x=2,y=0,z=0},{status='wrong',x=3,y=0,z=0}},omittedEntries=7}
  c:tick(); eq(p.report.counts.correct,1); eq(p.report.counts.wrong,1)
  eq(#p.report.entries,1); eq(p.report.entries[1].status,'wrong'); eq(p.report.omittedEntries,7)
end)
test('project clears air columns from the top and honors project pause before scheduling',function()
  local bp={schema=1,size={x=1,y=2,z=1},palette={{name='minecraft:air',state={}}},runs={{id=1,count=2}},metadata={},requirements={}}
  local w,ce,we,c,b,step=fixture({blueprint=bp,clearSite=true})
  w.blocks['2,0,0']={name='minecraft:dirt',state={}}; w.blocks['2,1,0']={name='minecraft:dirt',state={}}
  assert(c:command('build import /example.json air')); assert(c:command('build clear air')); assert(c:command('build pause air'))
  for _=1,10 do step() end
  eq(w.digs,0); eq(#c.state.automation.projects.air.jobs,0)
  assert(c:command('build resume air')); awaitProject(c,b,step,'built')
  eq(w.digs,2); eq(w.blocks['2,0,0'],nil); eq(w.blocks['2,1,0'],nil)
  eq(c.state.automation.projects.air.report.counts.correct,2)
end)
test('cathedral real runtimes prepare stocked materials build verify retire and continue the next layer after reboot',function()
  local prior=package.loaded['autobuilder.blueprint.catalog']
  local env
  local entries={
    {offset={x=0,y=0,z=0},size={x=1,y=1,z=1},blockCount=1},
    {offset={x=0,y=1,z=0},size={x=1,y=1,z=1},blockCount=1}}
  package.loaded['autobuilder.blueprint.catalog']={new=function()
    return {root=function() return {schema=1,size={x=1,y=2,z=1},totalBlocks=2,pages={{count=2}}} end,
      page=function() return {entries=entries} end,chunk=function()
        env.fs.files['/chunk.json']=env.textutils.serialize({schema=1,size={x=1,y=1,z=1},
          palette={{name='minecraft:stone',state={}}},runs={{id=1,count=1}},metadata={},requirements={['minecraft:stone']=1}})
        return '/chunk.json'
      end}
  end}
  local ok,err=pcall(function()
    local w,ce,we,c,b,step,reboot=fixture(); env=ce
    assert(c:command('cathedral start 2 0 0'))
    local restarted=false
    for _=1,700 do
      step()
      if not restarted and w.places==1 then c,b=reboot(); restarted=true end
      if c.state.automation.cathedral.status=='completed' and not b.state.currentTask then break end
    end
    assert(restarted); eq(c.state.automation.cathedral.status,'completed')
    eq(c.state.automation.cathedral.completedBlocks,2); eq(w.places,2)
    eq(w.blocks['2,0,0'].name,'minecraft:stone'); eq(w.blocks['2,1,0'].name,'minecraft:stone')
    eq(next(c.state.automation.projects),nil); eq(next(c.state.automation.jobs),nil); eq(next(c.state.automation.requests),nil)
  end)
  package.loaded['autobuilder.blueprint.catalog']=prior
  assert(ok,err)
end)
