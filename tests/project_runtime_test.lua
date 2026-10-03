local U=require('autobuilder.core.util')
local IS=require('tests.install_support')
local function fixture(options)
  options=options or {}
  local w=require('tests.build_world').new(); w.items[1]={name='minecraft:stone',count=8}
  local storage=require('tests.managed_logistics_support').new()
  storage.inventories={stock={[1]={name='minecraft:stone',count=8}},home={},stage={}}
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
  local C=require('tests.loaded_config'); local cc=C.load({storageInventories={'stock'},turtleFuelReserveItems={},supply={inventory='stage',side='front'},logistics={nodes={{id='home',inventory='stock',position={x=-3,y=1,z=0},buffers={{inventory='home',position={x=0,y=2,z=0}}}}}},clearSite=options.clearSite or false,build={enabled=true,origin={x=2,y=0,z=0},rotation=options.rotation or 0,mirrorX=options.mirrorX or false},autoDepotExpansion={enabled=options.expansion~=nil,freeSlots=0},depotExpansion=options.expansion or {}})
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
  assert(c:command('build /native.schem')); eq(c.state.automation.requestSequence,1)
  c,b=reboot(); assert(c:command('build /native.schem')); eq(c.state.automation.requestSequence,1)
  for _=1,350 do step(); if c.state.automation.projects.native.phase=='built' and not b.state.currentTask then break end end
  eq(c.state.automation.projects.native.phase,'built'); eq(w.places,2)
  local seq=c.state.automation.sequence
  assert(c:command('build /native.schem')); eq(c.state.automation.sequence,seq); eq(c.state.automation.requestSequence,1)
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
