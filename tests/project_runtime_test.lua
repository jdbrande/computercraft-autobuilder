local U=require('autobuilder.core.util')
local IS=require('tests.install_support')
local function fixture(options)
  options=options or {}
  local w=require('tests.build_world').new(); w.items[1]={name='minecraft:stone',count=8}
  -- Ordinary construction fixtures start on a finite support layer with a north
  -- access trench for inspecting beneath retained structures.
  -- Terrain-specific cases configure their own elevations and missing supports.
  if not options.site then for x=1,9 do for z=0,9 do w.blocks[x..',-1,'..z]={name='minecraft:stone',state={}} end end end
  local storage=require('tests.managed_logistics_support').new()
  storage.inventories={stock=options.stock or {[1]={name='minecraft:stone',count=8}},home={},stage={}}
  if options.expansion then storage.size=1 end
  w.blocks['0,1,0']={name='minecraft:chest',state={}}
  w.blocks['0,2,-1']={name='minecraft:chest',state={}}
  w.turtle.getItemSpace=function(slot) return 64-w.turtle.getItemCount(slot) end
  local function move(from,to,slot,n,target)
    local item=from[slot];if not item then return false end
    for i=target or 1,target or 3 do
      if not to[i] or to[i].name==item.name and to[i].count<64 then
        local count=math.min(n,item.count,64-(to[i] and to[i].count or 0))
        to[i]=to[i] or {name=item.name,count=0};to[i].count=to[i].count+count
        item.count=item.count-count;if item.count==0 then from[slot]=nil end;return count>0
      end
    end
    return false
  end
  w.turtle.dropDown=function(n)
    assert(w.pose.x==0 and w.pose.y==2 and w.pose.z==0)
    return move(w.items,storage.inventories.home,w.selected,n)
  end
  w.turtle.suck=function(n)
    assert(w.pose.x==0 and w.pose.y==2 and w.pose.z==0 and w.pose.heading=='north')
    local slot=next(storage.inventories.stage);if not slot then return false end
    return move(storage.inventories.stage,w.items,slot,n,w.selected)
  end
  local function env(id)
    local codec=require('tests.support').codec(); codec.unserializeJSON=codec.unserialize; codec.serializeJSON=codec.serialize
    local e={fs=IS.fs(),textutils=codec,now=100,packets={}}
    e.os={getComputerID=function() return id end,epoch=function() return e.now*1000 end}
    e.rednet={isOpen=function() return true end,open=function() end,send=function(to,m,p) e.packets[#e.packets+1]={to=to,m=U.copy(m),protocol=p}; return true end}
    e.peripheral={getNames=function() return {'right'} end,getType=function() return 'modem' end,
      call=function(name,method,...) if method=='isWireless' then return true end; return storage.e.peripheral.call(name,method,...) end}
    return e
  end
  local ce,we=env(7),env(12); we.turtle=w.turtle
  local C=require('tests.loaded_config'); local cc=C.load({storageInventories={'stock'},turtleFuelReserveItems={},supply={inventory='stage',side='front'},logistics={nodes={{id='home',inventory='stock',position={x=-3,y=1,z=0},buffers={{inventory='home',position={x=0,y=2,z=0}}}}}},clearSite=options.clearSite or false,build={enabled=true,origin=options.origin or {x=2,y=0,z=0},regionSize=options.regionSize or 8,rotation=options.rotation or 0,mirrorX=options.mirrorX or false,site=options.site or {}},autoDepotExpansion={enabled=options.expansion~=nil,freeSlots=0},depotExpansion=options.expansion or {}})
  local wc=C.load({role='worker',controllerId=7,automation={building=true},clearSite=options.clearSite or false,minimumFuelReserve=0,depot=U.copy(w.pose),supply={inventory='stage',side='front'},initialPosition=U.copy(w.pose)})
  local R=require('autobuilder.core.runtime'); local c,b=R.new(cc,ce),R.new(wc,we)
  local blueprint={schema=1,size={x=2,y=1,z=1},palette={{name='minecraft:stone',state={}}},runs={{id=1,count=2}},metadata={},requirements={['minecraft:stone']=2}}
  ce.fs.files['/example.json']=ce.textutils.serialize(options.blueprint or blueprint)
  local function pump(from,to)
    local packets=from.packets; from.packets={}
    for _,p in ipairs(packets) do to:receive(p.m.sender,p.m,p.protocol) end
  end
  local function step()
    ce.now=ce.now+1; we.now=ce.now
    b:tick(); pump(we,c); c:tick(); pump(ce,b); c:workStep(); b:workStep(); pump(we,c); pump(ce,b)
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
  for i=1,1500 do
    step()
    if not restarted and w.places==1 then c,b=reboot(); restarted=true end
    if c.state.automation.projects.sample.phase=='built' and not b.state.currentTask then break end
  end
  assert(restarted); eq(c.state.automation.projects.sample.phase,'built'); eq(w.places,2)
  assert(c:command('build verify sample'))
  for _=1,250 do step(); if c.state.automation.projects.sample.phase=='verified' and not b.state.currentTask then break end end
  eq(c.state.automation.projects.sample.report.counts.correct,2)
  w.blocks['2,0,0']=nil
  w.blocks['2,-1,0']=nil;w.blocks['2,-2,0']={name='minecraft:stone',state={}}
  local generation=c.state.automation.projects.sample.site.generation
  assert(c:command('build repair sample'))
  for _=1,1500 do step(); if c.state.automation.projects.sample.phase=='built' and not b.state.currentTask then break end end
  assert(c.state.automation.projects.sample.site.generation>generation,'new repair run reused old site evidence')
  assert(c.state.automation.projects.sample.phase=='built',c.state.automation.projects.sample.phase..': '..tostring(c.state.automation.projects.sample.error))
  eq(w.blocks['2,-1,0'].name,'minecraft:stone');eq(w.blocks['2,0,0'].name,'minecraft:stone');eq(w.places,4)
end)
test('build commands reject unsupported palette and modified imported data before placement',function()
  local w,ce,_,c=fixture()
  assert(c:command('build import /example.json sample'))
  ce.fs.files['/autobuilder/blueprints/sample.json']='corrupted'
  assert(not c:command('build prepare sample')); eq(w.places,0)
  assert(not c:command('request minecraft:stone nope')); assert(not c:command('request minecraft:stone -1'))
end)
test('build auto streams supply and resumes through reboot without a separate start command',function()
  local w,ce,we,c,b,step,reboot=fixture()
  assert(c:command('build import /example.json automatic'))
  assert(c:command('build auto automatic'))
  local p=c.state.automation.projects.automatic
  assert(p.autoStart and not p.stockOnly)
  assert(c:command('build pause automatic'))
  for _=1,5 do step() end
  eq(w.places,0)
  eq(p.requestId,nil);eq(p.streaming,true);eq(p.paused,true)
  c,b=reboot(); assert(c:command('build resume automatic'))
  for _=1,1500 do step(); if c.state.automation.projects.automatic.phase=='built' and not b.state.currentTask then break end end
  eq(c.state.automation.projects.automatic.phase,'built'); eq(w.places,2)
  assert(not c.state.automation.projects.automatic.autoStart)
end)
local function airBlueprint()
  return {schema=1,size={x=2,y=1,z=1},palette={{name='minecraft:stone',state={}},{name='minecraft:air',state={}}},runs={{id=1,count=1},{id=2,count=1}},metadata={},requirements={['minecraft:stone']=1}}
end
local function awaitProject(c,b,step,phase)
  for _=1,1500 do
    step()
    if c.state.automation.projects.air.phase==phase and not b.state.currentTask then return end
  end
  assert(c.state.automation.projects.air.phase==phase,c.state.automation.projects.air.phase..': '..tostring(c.state.automation.projects.air.error))
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
test('project verification reports occupied schematic air and repair prepares it without legacy clearSite',function()
  local w,ce,we,c,b,step=fixture({blueprint=airBlueprint()})
  w.blocks['2,0,0']={name='minecraft:stone',state={}}; w.blocks['3,0,0']={name='minecraft:dirt',state={}}
  assert(c:command('build import /example.json air')); assert(c:command('build analyze air')); eq(w.digs,0); eq(w.places,0)
  assert(c:command('build verify air')); assert(c:command('build analyze air')); eq(c.state.automation.projects.air.total,2); awaitProject(c,b,step,'needs_repair')
  eq(c.state.automation.projects.air.report.counts.wrong,1); eq(c.state.automation.projects.air.report.counts.correct,1)
  eq(#c.state.automation.projects.air.report.entries,1); eq(c.state.automation.projects.air.report.entries[1].status,'wrong')
  assert(c:command('build repair air')); awaitProject(c,b,step,'built')
  eq(w.digs,1);eq(w.blocks['3,0,0'],nil);assert(not c:command('build clear air'))
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
  local sitePath='/autobuilder/data/sites/'..p.name
  ce.fs.makeDir(sitePath);ce.fs.files[sitePath..'/proof']='durable preparation evidence'
  assert(c.automation.projects:retire(p.name))
  eq(c.state.automation.requests['request:99'],nil); eq(c.state.automation.jobs['fuel-factory'],nil)
  assert(ce.fs.exists(path),'backup still needs this import')
  assert(ce.fs.exists(sitePath),'backup still needs preparation evidence')
  c.automation.projects:tick()
  assert(not ce.fs.exists(path))
  assert(not ce.fs.exists(sitePath),'retired preparation evidence leaked')
  local statePath='/autobuilder/data/controller.state'
  ce.fs.files[statePath]='corrupt primary'
  local recovered,source=require('autobuilder.core.checkpoint').new(ce.fs,ce.textutils,statePath):load()
  assert(source:find('backup')); eq(recovered.automation.projects.old_batch,nil)
end)
test('ordinary project preparation clears required air even when legacy clearSite is disabled',function()
  local w,ce,we,c,b,step=fixture({blueprint=airBlueprint()})
  w.blocks['3,0,0']={name='minecraft:dirt',state={}}
  assert(c:command('build import /example.json air')); assert(c:command('build prepare air')); for _=1,3 do step() end
  assert(c:command('build start air')); awaitProject(c,b,step,'built')
  eq(w.places,1); eq(w.digs,1); eq(c.state.automation.projects.air.report.counts.correct,2)
end)
test('project aggregation keeps exact report counts and omitted issue totals without correct-cell details',function()
  local w,ce,we,c=fixture({blueprint=airBlueprint()})
  assert(c:command('build import /example.json air')); assert(c:command('build verify air')); c:tick()
  local p=c.state.automation.projects.air; local j=c.state.automation.jobs[p.jobs[1]]
  j.status='completed'; j.progress=1
  j.report={materials={['minecraft:stone']=1},counts={correct=1,wrong=1},entries={{status='correct',x=2,y=0,z=0},{status='wrong',x=3,y=0,z=0}},omittedEntries=7}
  c:tick(); eq(p.report.counts.correct,1); eq(p.report.counts.wrong,1)
  eq(#p.report.entries,1); eq(p.report.entries[1].status,'wrong'); eq(p.report.omittedEntries,7)
  eq(p.report.materials['minecraft:stone'],1);eq(j.report,nil);eq(j.blocks,nil)
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
    for _=1,3000 do
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
test('project import refuses a volume occupied by an exploration claim',function()
  local _,ce,_,c=fixture()
  c.state.jobs.claim={id='claim',type='MINE',workerId=99,status='running',exploration={bounds={min={x=2,y=0,z=0},max={x=3,y=2,z=1}},route={}}}
  local ok,err=c:command('build import /example.json conflict'); assert(not ok,'import must reject owned excavation'); assert(tostring(err):find('exploration'))
  eq(c.state.automation.projects.conflict,nil)
  c.state.jobs.claim.physicalComplete=true
  assert(c:command('build import /example.json safe')); assert(c.state.automation.projects.safe.protectedBounds)
end)

test('native schematic import reads binary once and stores immutable normalized JSON',function()
  local w,ce,_,c=fixture(); local N=require('tests.native_support'); local raw=N.file('sponge-v3.gz')
  ce.fs.files['/native.schem']=raw
  local open=ce.fs.open; local reads=0
  ce.fs.open=function(path,mode)
    local h,why=open(path,mode)
    if path=='/native.schem' then
      eq(mode,'rb'); reads=reads+1
      local close=h.close; h.close=function() close(); ce.fs.files[path]='changed after snapshot' end
    end
    return h,why
  end
  local ok,why=c:command('build import /native.schem native'); assert(ok,why); eq(reads,1)
  local p=c.state.automation.projects.native
  eq(p.sourceHash,require('autobuilder.install.sha256').digest(raw))
  local bp=assert(ce.textutils.unserializeJSON(ce.fs.files[p.path])); eq(bp.metadata.sourceVersion,3)
  eq(bp.requirements['minecraft:oak_log'],2); eq(w.places,0); eq(next(c.state.automation.jobs),nil)
  assert(c:command('build analyze native')); eq(c.state.automation.projects.native.airCells,2)
end)

test('native schematic shorthand resumes one automatic project across repeated commands and reboot',function()
  local w,ce,we,c,b,step,reboot=fixture(); local N=require('tests.native_support')
  ce.fs.files['/native.schem']=N.fixture({width=2,length=1,palette={{'minecraft:stone',0}},data='\0\0'})
  local ok,why=c:command('build /native.schem'); assert(ok,why)
  assert(c:command('build /native.schem')); eq(c.state.automation.requestSequence,0)
  c,b=reboot(); assert(c:command('build /native.schem')); eq(c.state.automation.requestSequence,0)
  for _=1,1500 do step(); if c.state.automation.projects.native.phase=='built' and not b.state.currentTask then break end end
  eq(c.state.automation.projects.native.phase,'built'); eq(w.places,2)
  local seq=c.state.automation.sequence
  assert(c:command('build /native.schem')); eq(c.state.automation.sequence,seq); eq(c.state.automation.requestSequence,0)
  ce.fs.files['/native.schem']=N.fixture({width=3,length=1,palette={{'minecraft:stone',0}},data='\0\0\0'})
  local accepted,reason=c:command('build /native.schem')
  assert(not accepted and reason:find('changed',1,true),reason); eq(c.state.automation.sequence,seq)
end)

test('native shorthand rejects corrupt or unsupported schematics before issuing work',function()
  local w,ce,_,c=fixture(); local N=require('tests.native_support')
  ce.fs.files['/bad.schem']=N.fixture():sub(1,-2)
  assert(not c:command('build /bad.schem')); eq(next(c.state.automation.projects),nil)
  ce.fs.files['/entity.schem']=N.fixture({extra={N.tag(9,'Entities','\10'..N.uint(1,4)..'\0')}})
  local ok,why=c:command('build /entity.schem')
  assert(not ok and why:find('Unsupported',1,true),why)
  eq(next(c.state.automation.requests),nil); eq(next(c.state.automation.jobs),nil); eq(w.places,0); eq(w.digs,0)
end)

test('JSON import persists the same single file snapshot that passed validation',function()
  local _,ce,_,c=fixture(); local original=ce.fs.files['/example.json']; local open=ce.fs.open; local reads=0
  ce.fs.open=function(path,mode)
    local h,why=open(path,mode)
    if path=='/example.json' then
      reads=reads+1; local close=h.close
      h.close=function() close(); ce.fs.files[path]='invalid source changed after validation' end
    end
    return h,why
  end
  assert(c:command('build import /example.json snapshot')); eq(reads,1)
  local p=c.state.automation.projects.snapshot; eq(ce.fs.files[p.path],original)
  assert(c:command('build analyze snapshot'))
end)

test('project settlement waits for linked claims requests and acknowledgements then accepts safe reassignment',function()
  local w,ce,we,c,b,step=fixture()
  assert(c:command('build import /example.json settlement'));assert(c:command('build prepare settlement'))
  for _=1,3 do step() end
  local s=c.state.automation;local p=s.projects.settlement
  local j=c.automation.queue:submit('VERIFY',{project=p.name,projectRun=p.run,blocks={{x=2,y=0,z=0,name='minecraft:stone',state={}}}},{})
  j.workerId=12;j.status='completed';j.completedAt=ce.now
  p.phase='settling';p.settlement={target='built'}
  local worker=c.state.workers['12'];worker.telemetry.cargo={items={},limits={}}
  worker.telemetry.task=nil;worker.telemetry.status='idle';worker.lastSeen=ce.now
  c.automation.projects:tick();eq(p.phase,'settling');assert(p.error:find('fresh acknowledgement',1,true))
  worker.lastSeen=ce.now+1;worker.telemetry.position.x=8
  c.automation.projects:tick();eq(p.phase,'settling');local rid=assert(p.returnRequests['12'])
  local nextJob=c.automation.queue:submit('BUILD',{blocks={{x=20,y=0,z=0,name='minecraft:stone',state={}}}},{})
  nextJob.workerId=12;nextJob.status='assigned';worker.telemetry.task=nextJob.id;worker.telemetry.status='working'
  c.state.capacityLedger.leases[j.id]={status='held'}
  s.requests[p.requestId].status='waiting'
  c.automation.projects:tick();eq(p.phase,'settling');eq(s.returns[rid].status,'completed')
  s.requests[p.requestId].status='completed';c.automation.projects:tick();eq(p.phase,'settling')
  c.state.capacityLedger.leases[j.id].status='released';c.automation.projects:tick();eq(p.phase,'built')
  eq(p.actors['12'].settled.reassigned,nextJob.id)
end)

test('project remembers a production miner after its completed task is pruned',function()
  local w,ce,we,c,b,step=fixture()
  assert(c:command('build import /example.json settlement'));assert(c:command('build prepare settlement'))
  for _=1,3 do step() end
  local s=c.state.automation;local p=s.projects.settlement;local r=s.requests[p.requestId]
  c.state.jobs['old-mine']={id='old-mine',workerId=99,status='completed',completedAt=101};r.mines={stone='old-mine'}
  c.automation.projects:tick();assert(p.actors['99']);c.state.jobs['old-mine']=nil
  p.phase='settling';p.settlement={target='built'};c.automation.projects:tick()
  eq(p.phase,'settling');assert(p.error:find('99',1,true))
end)

test('project pause before home job creation prevents return admission until resumed',function()
  local w,ce,we,c,b,step=fixture();assert(c:command('build import /example.json paused'));step()
  local p=c.state.automation.projects.paused;p.phase='settling';p.settlement={target='built'}
  p.actors={['12']={after=0}};p.returnRequests={};w.pose.x=8
  local worker=c.state.workers['12'];worker.telemetry.position.x=8
  c.automation.projects:tick();local rid=assert(p.returnRequests['12'])
  assert(c:command('build pause paused'));c:workStep()
  local r=c.state.automation.returns[rid];local j=c.state.automation.jobs[r.jobId]
  assert(not j.returnReady,'paused project granted home ownership')
  assert(c:command('build resume paused'));c:workStep();assert(j.returnReady)
end)

test('project consumes durable home settlement evidence before later unrelated cargo or offline telemetry',function()
  for _,mode in ipairs({'cargo','offline','stale','completed_task'}) do
    local w,ce,we,c,b,step=fixture();assert(c:command('build import /example.json proof'));assert(c:command('build prepare proof'))
    for _=1,3 do step() end
    local s=c.state.automation;local p=s.projects.proof;local worker=c.state.workers['12']
    p.phase='settling';p.settlement={target='built'};p.actors={['12']={after=ce.now}};p.returnRequests={}
    local r
    if mode~='completed_task' then
      r=c.automation.production.returns:request(12,'project:proof:run:0:worker:12')
      r.status='completed';r.settledAt=mode=='stale' and ce.now or ce.now+1;p.returnRequests['12']=r.id
    end
    local j=c.automation.queue:submit('BUILD',{blocks={{x=20,y=0,z=0,name='minecraft:stone',state={}}}},{})
    j.workerId=12;j.status=mode=='completed_task' and 'completed' or 'assigned'
    worker.lastSeen=ce.now+2;worker.telemetry.task=j.id;worker.telemetry.status='working';worker.telemetry.position.x=8
    worker.telemetry.cargo=mode=='completed_task' and {items={},limits={}} or {items={['minecraft:dirt']=1},limits={['minecraft:dirt']=64}}
    if mode=='offline' then worker.online=false end
    c.automation.projects:tick()
    if mode=='cargo' or mode=='offline' then eq(p.phase,'built')
    else eq(p.phase,'settling');if mode=='stale' then assert(p.returnRequests['12']~=r.id,'stale completed return was reused') end end
  end
end)

test('build survey schedules every footprint and workspace column with pause and controller restart',function()
  local w,ce,we,c,b,step,reboot=fixture({site={minY=-2,maxY=15}})
  w.blocks['2,1,0']={name='minecraft:dirt',state={}}
  assert(c:command('build import /example.json survey'))
  assert(c:command('build survey survey'),'project survey command unavailable')
  local restarted,paused=false,false
  for _=1,1500 do
    step()
    local p=c.state.automation.projects.survey
    if not paused and b.state.currentTask then
      assert(c:command('build pause survey'))
      for _=1,10 do step();if b.state.currentTask.paused then break end end
      assert(b.state.currentTask.paused);local position=U.copy(w.pose)
      for _=1,5 do step() end;eq(U.distance(position,w.pose),0)
      assert(c:command('build resume survey'));paused=true
    end
    if not restarted and b.state.currentTask and (b.state.currentTask.progress or 0)>0 then c,b=reboot();restarted=true end
    if p.phase=='surveyed' and not b.state.currentTask then break end
  end
  local p=c.state.automation.projects.survey;eq(p.phase,'surveyed');eq(p.completed,12)
  assert(paused and restarted);eq(w.digs,0);eq(w.places,0);eq(w.blocks['2,1,0'].name,'minecraft:dirt')
  assert(not next(c.state.automation.requests),'read-only survey acquired building stock')
end)

test('project survey retries real overhead obstructions with higher immutable access',function()
  local w,ce,we,c,b,step=fixture({site={minY=-2,maxY=15}})
  w.blocks['2,2,0']={name='minecraft:stone',state={}}
  assert(c:command('build import /example.json hill'));assert(c:command('build survey hill'))
  for _=1,2500 do step();if c.state.automation.projects.hill.phase=='surveyed' and not b.state.currentTask then break end end
  local p=c.state.automation.projects.hill;eq(p.phase,'surveyed');eq(p.completed,12);eq(w.digs,0);eq(w.places,0)
  local count,height=0,0
  for _,j in pairs(c.state.automation.jobs) do if j.type=='SURVEY_SITE' then count=count+1;height=math.max(height,j.clearanceY) end end
  assert(count>1 and height>3,'obstructed route never caused a higher attempt')
  eq(w.blocks['2,2,0'].name,'minecraft:stone');eq(p.protectedBounds.max.y,height)
end)

test('build level surveys excavates returns debris fills holes and verifies a retained partial structure',function()
  local w,ce,we,c,b,step,reboot=fixture({site={minY=-2,maxY=15}})
  w.blocks['2,1,0']={name='minecraft:dirt',state={}};w.blocks['2,0,0']={name='minecraft:stone',state={}};w.blocks['3,-2,0']={name='minecraft:stone',state={}}
  assert(c:command('build import /example.json terrain'));assert(c:command('build level terrain'))
  local restarted=false
  for _=1,3000 do
    step();local p=c.state.automation.projects.terrain
    if not restarted and w.digs>0 and p.phase=='preparing_site' then c,b=reboot();restarted=true end
    if (p.phase=='site_ready' or p.phase=='site_blocked') and not b.state.currentTask then break end
  end
  local p=c.state.automation.projects.terrain
  if p.phase~='site_ready' then
    local errors={};for id,j in pairs(c.state.automation.jobs) do if j.status~='completed' then errors[#errors+1]=id..':'..j.status..':'..tostring(j.error) end end
    error(p.phase..':'..tostring(p.error)..':'..table.concat(errors,';'))
  end
  assert(restarted);eq(w.digs,1);eq(w.blocks['2,0,0'].name,'minecraft:stone');assert(not w.blocks['2,1,0']);assert(not w.blocks['3,0,0'])
  assert(w.blocks['2,-1,0'] and w.blocks['3,-1,0'],'foundation not filled');eq(p.site.work.blocked,0)
  local returns=0;for _,r in pairs(c.state.automation.returns) do eq(r.status,'completed');returns=returns+1 end;assert(returns>0,'debris was not collected')
end)

test('leveling runtime recovers both lost region files without abandoning excavation or duplicating effects',function()
  local w,ce,we,c,b,step,reboot=fixture({site={minY=-2,maxY=15}})
  w.blocks['2,1,0']={name='minecraft:dirt',state={}};w.blocks['2,0,0']={name='minecraft:stone',state={}};w.blocks['3,-2,0']={name='minecraft:stone',state={}}
  assert(c:command('build import /example.json terrain_recovery'));assert(c:command('build level terrain_recovery'))
  local lost=false
  for _=1,5000 do
    step();local p=c.state.automation.projects.terrain_recovery
    if not lost and w.digs>0 and p.phase=='preparing_site' then
      for path in pairs(ce.fs.files) do if path:find('/sites/terrain_recovery/',1,true) then ce.fs.files[path]=nil end end
      c,b=reboot();lost=true
    end
    if p.phase=='site_ready' and not b.state.currentTask then break end
  end
  local p=c.state.automation.projects.terrain_recovery
  assert(p.phase=='site_ready',p.phase..':'..tostring(p.error));assert(lost);eq(w.digs,1);eq(w.places,2)
  local surveys=0;for _,j in pairs(c.state.automation.jobs) do if j.type=='SURVEY_SITE' then surveys=surveys+1 end end;assert(surveys>=2)
  eq(w.blocks['2,0,0'].name,'minecraft:stone');assert(w.blocks['2,-1,0'] and w.blocks['3,-1,0']);assert(not w.blocks['2,1,0'])
end)

test('ordinary build auto prepares uneven terrain and fills foundations before structural placement',function()
  local w,ce,we,c,b,step=fixture({site={minY=-2,maxY=15}})
  w.blocks['2,1,0']={name='minecraft:dirt',state={}};w.blocks['2,-1,0']={name='minecraft:stone',state={}};w.blocks['3,-2,0']={name='minecraft:stone',state={}}
  assert(c:command('build import /example.json automatic_site'));assert(c:command('build auto automatic_site'))
  local structural=w.turtle.placeDown;local checked=false
  w.turtle.placeDown=function(...)
    if w.pose.y-1==0 and (w.pose.x==2 or w.pose.x==3) and w.pose.z==0 then
      local task=b.state.currentTask
      assert(task and task.type~='PREPARE_REGION');assert(w.blocks['2,-1,0'] and w.blocks['3,-1,0'],'builder started without level foundation')
      assert(not w.blocks['2,1,0'],'builder started before excavation');checked=true
    end
    return structural(...)
  end
  for _=1,3500 do step();if c.state.automation.projects.automatic_site.phase=='built' and not b.state.currentTask then break end end
  local p=c.state.automation.projects.automatic_site;assert(p.phase=='built',p.phase..':'..tostring(p.error));assert(checked);eq(w.digs,1)
  eq(w.blocks['2,0,0'].name,'minecraft:stone');eq(w.blocks['3,0,0'].name,'minecraft:stone');eq(p.report.counts.correct,2)
end)

test('automatic construction builds an independent verified region while a distant preparation region is blocked',function()
  local source={schema=1,size={x=32,y=1,z=1},palette={{name='minecraft:stone',state={}},{name='minecraft:air',state={}}},runs={{id=1,count=1},{id=2,count=30},{id=1,count=1}},metadata={},requirements={}}
  local w,ce,we,c,b,step=fixture({blueprint=source,site={minY=-2,maxY=15}})
  for x=2,33 do w.blocks[x..',-1,0']={name='minecraft:stone',state={}} end
  w.blocks['30,0,0']={name='minecraft:bedrock',state={}}
  assert(c:command('build import /example.json independent'));assert(c:command('build auto independent'))
  for _=1,12000 do
    step();local p=c.state.automation.projects.independent
    if p.site and p.site.work and p.site.work.status=='completed' and w.blocks['2,0,0'] then break end
  end
  local p=c.state.automation.projects.independent
  assert(w.blocks['2,0,0'],'distant blocked preparation withheld independent placement')
  eq(w.blocks['2,0,0'].name,'minecraft:stone');assert(not w.blocks['33,0,0']);eq(w.blocks['30,0,0'].name,'minecraft:bedrock')
  eq(p.site.work.blocked,1);eq(p.phase,'building');eq(p.issuedCount,1)
  for _,id in ipairs(p.jobs) do assert(c.state.automation.jobs[id].type=='BUILD','preparation receipt entered structural phase accounting') end
end)

test('automatic final verification repairs a new defect across restart without replacing correct blocks',function()
 local w,ce,we,c,b,step,reboot=fixture()
 assert(c:command('build import /example.json self_repair'));assert(c:command('build auto self_repair'))
 local damaged,restarted=false,false
 for _=1,3500 do
  step();local p=c.state.automation.projects.self_repair
  if not damaged and p.phase=='verifying' and p.afterBuild then w.blocks['2,0,0']=nil;damaged=true end
  if (p.repairAttempts or 0)==1 and not restarted then c,b=reboot();restarted=true end
  if p.phase=='built' and not b.state.currentTask then break end
 end
 local p=c.state.automation.projects.self_repair
 assert(damaged and restarted,'automatic repair did not persist its attempt');eq(p.phase,'built')
 eq(p.repairAttempts,1);eq(#p.repairHistory,1);eq(p.repairHistory[1].counts.missing,1)
 eq(p.report.counts.correct,2);eq(w.places,3);eq(w.digs,0)
end)

test('automatic final repair stops after three unsuccessful rounds and retains exact defects',function()
 local w,ce,we,c,b,step=fixture()
 assert(c:command('build import /example.json unstable'));assert(c:command('build auto unstable'))
 local generation
 for _=1,6000 do
  step();local p=c.state.automation.projects.unstable
  if p.phase=='verifying' and p.afterBuild and generation~=p.generation then generation=p.generation;w.blocks['2,0,0']=nil end
  if p.phase=='needs_repair' and not b.state.currentTask then break end
 end
 local p=c.state.automation.projects.unstable;eq(p.phase,'needs_repair');eq(p.repairAttempts,3)
 eq(#p.repairHistory,3);eq(p.report.counts.missing,1);eq(p.report.entries[1].x,2)
 assert(p.error:find('3',1,true));local jobs=0;for _ in pairs(c.state.automation.jobs) do jobs=jobs+1 end
 for _=1,20 do step() end
 local later=0;for _ in pairs(c.state.automation.jobs) do later=later+1 end;eq(later,jobs);eq(w.places,5)
end)

test('preparation automatically resurveys changed foundation and resumes construction across retry reboot',function()
  local w,ce,we,c,b,step,reboot=fixture()
  assert(c:command('build import /example.json retry_ground'));assert(c:command('build auto retry_ground'))
  local removed,restarted=false,false
  for _=1,2500 do
    local t=b.state.currentTask
    if not removed and t and t.siteWork and t.siteWork.stage=='verify' and t.blocks[1].support then
      w.blocks['2,-1,0']=nil;w.blocks['2,-2,0']={name='minecraft:stone',state={}};removed=true
    end
    step()
    for _,j in pairs(c.state.automation.jobs) do
      if j.type=='SURVEY_SITE' and j.key:find(':resurvey:',1,true) and not restarted then c,b=reboot();restarted=true;break end
    end
    if c.state.automation.projects.retry_ground.phase=='built' then break end
  end
  assert(removed and restarted);eq(c.state.automation.projects.retry_ground.phase,'built')
  eq(w.places,3);eq(w.blocks['2,-1,0'].name,'minecraft:stone');eq(w.blocks['3,-1,0'].name,'minecraft:stone')
  eq(w.blocks['2,0,0'].name,'minecraft:stone');eq(w.blocks['3,0,0'].name,'minecraft:stone')
  local surveys=0;for _,j in pairs(c.state.automation.jobs) do if j.type=='SURVEY_SITE' then surveys=surveys+1 end end
  eq(surveys,2);eq(c.state.automation.projects.retry_ground.report.counts.correct,2)
end)


test('automatic preparation seals a finite fluid source then clears temporary fill and builds across reboot',function()
  for _,fluid in ipairs({'minecraft:water','minecraft:lava'}) do
    local source={schema=1,size={x=2,y=1,z=1},palette={{name='minecraft:glass',state={}}},runs={{id=1,count=2}},metadata={},requirements={['minecraft:glass']=2}}
    local w,ce,we,c,b,step,reboot=fixture({blueprint=source,stock={[1]={name='minecraft:glass',count=2},[2]={name='minecraft:stone',count=2}}})
    w.items={};w.blocks['2,0,0']={name=fluid,state={level='0'}};w.blocks['3,0,0']={name=fluid,state={level='1'}}
    local place=w.turtle.placeDown;local plugged=false
    w.turtle.placeDown=function()
      local key=w.pose.x..','..(w.pose.y-1)..','..w.pose.z
      if w.blocks[key] and w.blocks[key].name==fluid then
        assert(w.items[w.selected].name=='minecraft:stone');w.blocks[key]=nil
        if key=='2,0,0' then plugged=true;w.blocks['3,0,0']=nil end -- finite flow decays after its source is sealed
      end
      return place()
    end
    assert(c:command('build import /example.json drain'));assert(c:command('build auto drain'))
    local restarted=false
    for _=1,3000 do
      step()
      if plugged and not restarted then c,b=reboot();restarted=true end
      if c.state.automation.projects.drain.phase=='built' then break end
    end
    assert(restarted);eq(c.state.automation.projects.drain.phase,'built');eq(c.state.automation.projects.drain.report.counts.correct,2)
    eq(w.places,3);eq(w.digs,1);eq(w.blocks['2,0,0'].name,'minecraft:glass');eq(w.blocks['3,0,0'].name,'minecraft:glass')
    local seals=0;for _,j in pairs(c.state.automation.jobs) do if j.siteWork and j.siteWork.stage=='seal' then seals=seals+1 end end
    assert(seals>0);eq(c.state.automation.supply,nil)
  end
end)

test('cross-region preparation reopens exhausted fluid work after a delayed source removal across reboot',function()
  local source={schema=1,size={x=9,y=1,z=1},palette={{name='minecraft:glass',state={}}},runs={{id=1,count=9}},metadata={},requirements={['minecraft:glass']=9}}
  local w,ce,we,c,b,step,reboot=fixture({blueprint=source,site={minY=-2,maxY=15},stock={[1]={name='minecraft:glass',count=9},[2]={name='minecraft:stone',count=16}}})
  w.items={};for x=2,10 do w.blocks[x..',-1,0']={name='minecraft:stone',state={}};w.blocks[x..',0,0']={name='minecraft:water',state={level=x==10 and '0' or '1'}} end
  local sourceActive=true;local place=w.turtle.placeDown
  w.turtle.placeDown=function()
    local key=w.pose.x..','..(w.pose.y-1)..','..w.pose.z
    if w.blocks[key] and w.blocks[key].name=='minecraft:water' then
      w.blocks[key]=nil
      if key=='10,0,0' then sourceActive=false end
    end
    return place()
  end
  local exhausted,restarted=false,false
  local queue=c.automation.queue;local submit=queue.submit
  function queue:submit(kind,payload,...)
    local j=submit(self,kind,payload,...)
    if j.siteWork and j.siteWork.region==2 and not exhausted then j.paused=true end
    return j
  end
  assert(c:command('build import /example.json connected_water'));assert(c:command('build auto connected_water'))
  for _=1,16000 do
    local p=c.state.automation.projects.connected_water
    if p.site and p.site.work then
      -- Delay the second region as if its worker/route were unavailable. The
      -- first region must exhaust its initial retry budget before inflow stops.
      for _,j in pairs(c.state.automation.jobs) do if j.siteWork and j.siteWork.region==2 and not j.workerId then j.paused=not exhausted end end
      if p.site.work.blocked>0 then exhausted=true end
      if p.site.work.fluidRecheck and not restarted then c,b=reboot();restarted=true end
    end
    step()
    for x=2,9 do
      local key=x..',0,0';local current=w.blocks[key]
      if sourceActive and not current then w.blocks[key]={name='minecraft:water',state={level='1'}}
      elseif not sourceActive and current and current.name=='minecraft:water' then w.blocks[key]=nil end
    end
    if c.state.automation.projects.connected_water.phase=='built' then break end
  end
  local p=c.state.automation.projects.connected_water
  assert(exhausted and restarted and not sourceActive,'cross-region recovery path was not exercised')
  assert(p.phase=='built',p.phase..': '..tostring(p.error));eq(p.report.counts.correct,9)
  for x=2,10 do eq(w.blocks[x..',0,0'].name,'minecraft:glass') end
  eq(c.state.automation.supply,nil);assert(not b.state.currentTask)
end)

test('automatic preparation tunnels beneath retained floor fills hidden foundation and restores excavated ground',function()
  local blueprint={schema=1,size={x=3,y=1,z=3},palette={{name='minecraft:stone',state={}}},runs={{id=1,count=9}},metadata={},requirements={['minecraft:stone']=9}}
  local w,ce,we,c,b,step,reboot=fixture({site={minY=-2,maxY=10},blueprint=blueprint,stock={[1]={name='minecraft:stone',count=32}}})
  for x=1,5 do for z=-1,3 do for y=-2,-1 do w.blocks[x..','..y..','..z]={name='minecraft:stone',state={}} end end end
  for x=2,4 do for z=0,2 do w.blocks[x..',0,'..z]={name='minecraft:stone',state={}} end end
  w.blocks['3,-1,1']=nil
  assert(c:command('build import /example.json hidden'));assert(c:command('build auto hidden'))
  local restarted=false;local accessJobs=0
  for _=1,12000 do
    step()
    local t=b.state.currentTask
    if not restarted and t and t.siteAccess and w.places>0 then c,b=reboot();restarted=true end
    if c.state.automation.projects.hidden.phase=='built' and not b.state.currentTask then break end
  end
  local p=c.state.automation.projects.hidden
  assert(p.phase=='built',ce.textutils.serialize({phase=p.phase,error=p.error,worker=b.state.currentTask,site=p.site}))
  assert(restarted);eq(p.report.counts.correct,9)
  for _,j in pairs(c.state.automation.jobs) do if j.key and j.key:find(':access:',1,true) then accessJobs=accessJobs+1;assert(j.status=='completed');assert(not j.siteAccess and not j.report) end end
  assert(accessJobs>=5);assert(w.digs>=2)
  for x=1,5 do for z=-1,3 do for y=-2,-1 do assert(w.blocks[x..','..y..','..z],'ground left excavated') end end end
  for x=2,4 do for z=0,2 do eq(w.blocks[x..',0,'..z].name,'minecraft:stone') end end
  eq(w.places,w.digs+1)
end)

test('cross-region preparation reaches a sealed interior region through the project margin',function()
  local blueprint={schema=1,size={x=3,y=1,z=3},palette={{name='minecraft:stone',state={}}},runs={{id=1,count=9}},metadata={},requirements={['minecraft:stone']=9}}
  local w,ce,we,c,b,step,reboot=fixture({regionSize=2,site={minY=-2,maxY=10},blueprint=blueprint,stock={[1]={name='minecraft:stone',count=32}}})
  for x=1,5 do for z=-1,3 do for y=-2,-1 do w.blocks[x..','..y..','..z]={name='minecraft:stone',state={}} end end end
  for x=2,4 do for z=0,2 do w.blocks[x..',0,'..z]={name='minecraft:stone',state={}} end end
  w.blocks['3,-1,1']=nil
  assert(c:command('build import /example.json hidden'));assert(c:command('build auto hidden'))
  local restarted=false;local accessJobs=0;local crossed=false
  for _=1,18000 do
    step()
    local t=b.state.currentTask
    if t and t.siteAccess and t.siteAccess.bounds then crossed=true end
    if not restarted and t and t.siteAccess and w.places>0 then c,b=reboot();restarted=true end
    if c.state.automation.projects.hidden.phase=='built' and not b.state.currentTask then break end
  end
  local p=c.state.automation.projects.hidden
  assert(p.phase=='built',ce.textutils.serialize({phase=p.phase,error=p.error,worker=b.state.currentTask,site=p.site}))
  assert(restarted and crossed);eq(p.report.counts.correct,9)
  for _,j in pairs(c.state.automation.jobs) do if j.key and j.key:find(':access:',1,true) then accessJobs=accessJobs+1;assert(j.status=='completed');assert(not j.siteAccess and not j.report) end end
  assert(accessJobs>=5);assert(w.digs>=2)
  for x=1,5 do for z=-1,3 do for y=-2,-1 do assert(w.blocks[x..','..y..','..z],'ground left excavated') end end end
  for x=2,4 do for z=0,2 do eq(w.blocks[x..',0,'..z].name,'minecraft:stone') end end
  eq(w.places,w.digs+1)
end)

test('external water inflow is contained outside the working volume before fresh preparation and construction',function()
  local source={schema=1,size={x=1,y=1,z=1},palette={{name='minecraft:glass',state={}}},runs={{id=1,count=1}},metadata={},requirements={['minecraft:glass']=1}}
  local w,ce,we,c,b,step,reboot=fixture({origin={x=6,y=0,z=0},site={minY=-1,maxY=10},blueprint=source,
    stock={[1]={name='minecraft:glass',count=1},[2]={name='minecraft:stone',count=64}}})
  w.items={}
  for x=4,8 do for z=-2,2 do w.blocks[x..',-1,'..z]={name='minecraft:stone',state={}} end end
  w.blocks['3,0,0']={name='minecraft:water',state={level='0'}}
  w.blocks['4,0,0']={name='minecraft:water',state={level='1'}}
  local place=w.turtle.placeDown
  w.turtle.placeDown=function()
    local key=w.pose.x..','..(w.pose.y-1)..','..w.pose.z
    if w.blocks[key] and w.blocks[key].name=='minecraft:water' then w.blocks[key]=nil end
    return place()
  end
  assert(c:command('build import /example.json inflow'));assert(c:command('build auto inflow'))
  local restarted=false;local reappeared=0
  for _=1,18000 do
    if w.blocks['4,0,0'].name=='minecraft:water' and not w.blocks['5,0,0'] then
      w.blocks['5,0,0']={name='minecraft:water',state={level='2'}};reappeared=reappeared+1
    end
    step()
    local p=c.state.automation.projects.inflow
    if not restarted and p.site and p.site.barrier and w.blocks['4,0,-2'] then c,b=reboot();restarted=true end
    if p.phase=='built' and not b.state.currentTask then break end
  end
  local p=c.state.automation.projects.inflow
  assert(p.phase=='built',ce.textutils.serialize({phase=p.phase,error=p.error,site=p.site,worker=b.state.currentTask}))
  assert(restarted);assert(reappeared>=8);eq(p.site.barrier.status,'verified');assert(p.site.work.containmentRecheck)
  eq(w.blocks['3,0,0'].name,'minecraft:water');eq(w.blocks['6,0,0'].name,'minecraft:glass');assert(not w.blocks['5,0,0'])
  for x=4,8 do for z=-2,2 do if x==4 or x==8 or z==-2 or z==2 then
    for y=0,1 do eq(w.blocks[x..','..y..','..z].name,'minecraft:stone') end
  end end end
  eq(p.report.counts.correct,1);eq(c.state.automation.supply,nil)
end)

test('project settlement and retirement wait through gaps between retaining barrier child jobs',function()
  local w,ce,we,c,b,step=fixture()
  assert(c:command('build import /example.json boundary'));assert(c:command('build auto boundary'))
  for _=1,1600 do step();if c.state.automation.projects.boundary.phase=='built' then break end end
  local p=c.state.automation.projects.boundary;eq(p.phase,'built')
  p.phase='settling';p.site.work.status='working'
  p.site.barrier={status='working',stage='fill',cursor=0,sequence=2,height=2,fill='minecraft:stone',failed=0,defects={}}
  step();eq(p.site.barrier.stage,'verify')
  eq(p.phase,'settling');assert(p.error:find('preparation',1,true))
  p.phase='verified'
  local ok,why=c.automation.projects:retire('boundary')
  assert(not ok and why:find('preparation',1,true),'project retired its unfinished retaining barrier')
  assert(c.state.automation.projects.boundary)
end)


test('build forecast exposes current shared materials without submitting production work',function()
  local w,ce,we,c=fixture({blueprint=airBlueprint()})
  assert(c:command('build import /example.json forecast'))
  local before=U.copy(c.state.automation.requests)
  assert(c:command('build forecast forecast'))
  eq(c.state.view,'forecast');assert(c.state.forecastLines[1]:find('forecast'))
  assert(table.concat(c.state.forecastLines,';'):find('minecraft:stone required=1'))
  assert(require('autobuilder.factory.factory').equal(before,c.state.automation.requests))
  c.state.automation.projects.forecast=nil;c.state.automation.currentProject=nil
  c:tick();assert(c.state.forecastLines[1]:find('No selected project'))
end)

test('automatic empty-stock build prepares regions and asks for finite supply without whole-project stock',function()
  local w,ce,we,c,b,step,reboot=fixture({stock={}});w.items={}
  assert(c:command('build import /example.json streaming'));assert(c:command('build auto streaming'))
  local p=c.state.automation.projects.streaming;eq(p.streaming,true);eq(p.requestId,nil)
  assert(c:command('build pause streaming'));for _=1,5 do step() end;eq(w.places,0);eq(next(c.state.automation.requests),nil)
  c,b=reboot();assert(c:command('build resume streaming'));local supplied=false
  for _=1,1500 do
    step();p=c.state.automation.projects.streaming
    for _,r in pairs(c.state.automation.requests) do
      assert(r.key:sub(1,8)~='project:','automatic run created a whole-project target')
      if r.key:sub(1,7)=='supply:' then supplied=true;eq(r.requirements['minecraft:stone'],2) end
    end
    if supplied then break end
  end
  assert(supplied,'prepared region never asked for its bounded material batch');eq(p.phase,'building');eq(w.places,0)
  assert(p.site.work.preparedCount>0);eq(p.requestId,nil)
end)

test('explicit preparation and saved automatic requests retain their whole-stock ownership',function()
  local w,ce,we,c,b,step,reboot=fixture({stock={}})
  assert(c:command('build import /example.json legacy'));assert(c:command('build prepare legacy'))
  local p=c.state.automation.projects.legacy;local rid=assert(p.requestId)
  assert(not p.streaming);assert(not c:command('build start legacy'))
  p.autoStart=true;assert(c:save());c,b=reboot()
  p=c.state.automation.projects.legacy;eq(p.requestId,rid);assert(not p.streaming)
  assert(c:command('build auto legacy'));eq(p.requestId,rid);assert(not p.streaming)
  local n=0;for _ in pairs(c.state.automation.requests) do n=n+1 end;eq(n,1)
  assert(c:command('build pause legacy'));eq(c.state.automation.requests[rid].paused,true)
end)

test('streaming project pause stops queued supply acquisition across reboot',function()
  local w,ce,we,c,b,step,reboot=fixture({stock={}});w.items={}
  assert(c:command('build import /example.json paused_stream'));assert(c:command('build auto paused_stream'))
  local request
  for _=1,1500 do step();for _,r in pairs(c.state.automation.requests) do if r.key:sub(1,7)=='supply:' then request=r end end;if request then break end end
  assert(request);assert(c:command('build pause paused_stream'));eq(request.paused,true)
  local id=request.id;local count=0;for _ in pairs(c.state.jobs) do count=count+1 end
  c,b=reboot();for _=1,15 do step() end
  eq(c.state.automation.requests[id].paused,true);local after=0;for _ in pairs(c.state.jobs) do after=after+1 end;eq(after,count)
  assert(c:command('build resume paused_stream'));eq(c.state.automation.requests[id].paused,false)
  for _=1,10 do step() end;assert(next(c.state.jobs),'resumed request did not acquire inputs');eq(c.state.automation.requestSequence,1)
end)

test('fresh ordinary automatic run clears completed stock-only policy but preserves active ownership',function()
  local w,ce,we,c,b,step,reboot=fixture({stock={}});w.items={}
  assert(c:command('build import /example.json renewed'));local p=c.state.automation.projects.renewed
  p.phase='built';p.run=0;p.stockOnly=true;assert(c:save());c,b=reboot()
  assert(c:command('build auto renewed'));p=c.state.automation.projects.renewed;eq(p.run,1);eq(p.stockOnly,false)
  for _=1,1500 do step();if next(c.state.automation.requests) then break end end
  local _,r=next(c.state.automation.requests);assert(r);eq(r.stockOnly,false)
  w,ce,we,c,b,step,reboot=fixture({stock={}})
  assert(c:command('build import /example.json active'));assert(c:command('build prepare active'))
  p=c.state.automation.projects.active;p.stockOnly=true;c.state.automation.requests[p.requestId].stockOnly=true
  assert(c:save());c,b=reboot();assert(c:command('build auto active'));p=c.state.automation.projects.active
  eq(p.stockOnly,true);assert(not p.streaming);eq(c.state.automation.requests[p.requestId].stockOnly,true)
end)

test('automatic streaming bootstrap survives interruption at its first site checkpoint',function()
  local w,ce,we,c,b,step,reboot=fixture()
  assert(c:command('build import /example.json bootstrap'))
  local save=c.save;local cut=false
  c.save=function(self)
    local ok,why=save(self)
    local p=self.state.automation.projects.bootstrap
    if ok and not cut and p.autoStart and p.site then cut=true;error('power loss after first site checkpoint') end
    return ok,why
  end
  assert(not c:command('build auto bootstrap'));assert(cut)
  c,b=reboot();eq(c.state.automation.projects.bootstrap.streaming,true)
  for _=1,1500 do step();if c.state.automation.projects.bootstrap.phase=='built' and not b.state.currentTask then break end end
  eq(c.state.automation.projects.bootstrap.phase,'built');eq(w.places,2)
end)

test('analysis reports placement families and rejects incomplete paired schematic footprints',function()
 local bp={schema=1,size={x=1,y=1,z=1},palette={{name='minecraft:red_bed',state={part='foot',facing='east',occupied='false'}}},runs={{id=1,count=1}},metadata={},requirements={}}
 local w,ce,we,c=fixture({blueprint=bp});assert(c:command('build import /example.json bed'));assert(c:command('build analyze bed'))
 local p=c.state.automation.projects.bed;eq(p.analysis.placementFamilies.paired,1);assert(#p.issues>0);eq(p.issues[1].status,'UNSUPPORTED')
 local ok=c:command('build prepare bed');eq(ok,false);eq(w.places,0)
end)

test('ordinary seedling project preserves supplied farmland through preparation and restart',function()
 local bp={schema=1,size={x=1,y=1,z=1},palette={{name='minecraft:wheat',state={age='0'}}},runs={{id=1,count=1}},metadata={},requirements={}}
 local w,ce,we,c,b,step,reboot=fixture({blueprint=bp,stock={[1]={name='minecraft:wheat_seeds',count=1}},site={minY=-1,maxY=10,margin=1}})
 w.items={};w.blocks['2,-1,0']={name='minecraft:farmland',state={moisture=7}}
 for _,action in ipairs({'forward','up','down'}) do local original=w.turtle[action];w.turtle[action]=function(...)
  local ok,why=original(...)
  if ok and w.pose.x==2 and w.pose.y==0 and w.pose.z==0 then w.trampled=true;w.blocks['2,-1,0'].name='minecraft:dirt' end
  return ok,why
 end end
 local place=w.turtle.placeDown;w.turtle.placeDown=function(...)
  local item=w.items[w.selected]
  if item and item.name=='minecraft:wheat_seeds' then
   if w.blocks['2,-1,0'].name~='minecraft:farmland' then return false,'invalid soil' end
   local ok,why=place(...);if ok then w.blocks['2,0,0']={name='minecraft:wheat',state={age=0}} end;return ok,why
  end
  return place(...)
 end
 assert(c:command('build import /example.json seedling'));assert(c:command('build auto seedling'))
 local restarted=false
 for _=1,2200 do
  step();local p=c.state.automation.projects.seedling
  if not restarted and p.site and p.site.work then c,b=reboot();restarted=true end
  if p.phase=='built' and not b.state.currentTask then break end
 end
 eq(c.state.automation.projects.seedling.phase,'built');assert(restarted);eq(w.trampled,nil);eq(w.blocks['2,-1,0'].name,'minecraft:farmland');eq(w.blocks['2,0,0'].name,'minecraft:wheat')
 for _,r in pairs(c.state.automation.requests) do assert(not r.requirements['minecraft:cobblestone'],'unnecessary foundation acquisition') end
end)

test('empty container metadata builds through ordinary preparation supply restart and read-only final verification',function()
 local bp={schema=1,size={x=1,y=1,z=1},palette={{name='minecraft:chest',state={facing='south',type='single',waterlogged='false'}}},runs={{id=1,count=1}},
 metadata={blockEntities={{x=0,y=0,z=0,id='minecraft:chest',kind='empty_inventory'}}},requirements={}}
 local w,ce,we,c,b,step,reboot=fixture({blueprint=bp,stock={[1]={name='minecraft:chest',count=1}},site={minY=-1,maxY=10,margin=1}})
 w.items={};w.blocks['2,-1,0']={name='minecraft:stone',state={}};local contents={};local reads=0
 local call=we.peripheral.call;we.peripheral.call=function(name,method,...)
  if name=='bottom' and method=='list' and w.pose.x==2 and w.pose.y==1 and w.pose.z==0 then reads=reads+1;return U.copy(contents) end
  return call(name,method,...)
 end
 local place=w.turtle.placeDown;w.turtle.placeDown=function(...)
  local item=w.items[w.selected];local chest=item and item.name=='minecraft:chest';local ok,why=place(...)
  if ok and chest then w.blocks['2,0,0'].state={facing='south',type='single',waterlogged=false} end;return ok,why
 end
 assert(c:command('build import /example.json containers'));assert(c:command('build auto containers'))
 local restarted=false
 for _=1,2200 do
  step();local p=c.state.automation.projects.containers
  if not restarted and w.places>0 then c,b=reboot();restarted=true end
  if p.phase=='built' and not b.state.currentTask then break end
 end
 eq(c.state.automation.projects.containers.phase,'built');assert(restarted);eq(w.places,1);assert(reads>0)
 contents[1]={name='minecraft:diamond',count=1};assert(c:command('build verify containers'))
 for _=1,500 do step();if c.state.automation.projects.containers.phase=='needs_repair' and not b.state.currentTask then break end end
 local p=c.state.automation.projects.containers;eq(p.phase,'needs_repair');eq(p.report.counts.wrong,1);eq(w.digs,0);eq(w.places,1)
 eq(contents[1].count,1)
end)
