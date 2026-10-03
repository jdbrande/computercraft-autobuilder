local U=require('autobuilder.core.util')
local function pos(x,z) return {x=x,y=64,z=z or 8,known=true,heading='east'} end
local function worker(id,x)
  return {id=id,online=true,telemetry={status='idle',position=pos(x),depot=pos(x),capabilities={chunkCoverageV1=true}}}
end
local function anchor(id,x)
  local w=worker(id,x);w.telemetry.chunkAnchor={provider='advanced_peripherals_chunky',x=math.floor(x/16),z=0};return w
end
local function job(id,x)
  return {id=id or 'task:7:1',type='BUILD',blocks={{x=x or 24,y=64,z=8,name='minecraft:stone',state={}}}}
end
local function config(areas) return {chunkLoading={enabled=true,anchor=false,areas=areas or {}}} end

test('chunk mission envelopes include negative edges depot and bounded side approaches',function()
  local C=require('autobuilder.core.chunks');local w=worker(12,-1);w.telemetry.depot=pos(-33)
  local a=assert(C.area(job(nil,17),w.telemetry));eq(a.minX,-3);eq(a.maxX,1);eq(a.minZ,0);eq(a.maxZ,0)
  assert(C.contains(a,pos(-34)));assert(not C.contains(a,pos(32)))
  local p=job();p.blocks[1].x=30000;assert(not C.area(p,worker(12,8).telemetry),'oversized mission accepted')
  assert(not C.area({type='MINE'},worker(12,8).telemetry),'unknown legacy mine area accepted')
  local m={type='MINE',miningArea={min=pos(8),max=pos(25)}};eq(assert(C.area(m,worker(12,8).telemetry)).maxX,1)
end)

test('chunk claims refuse uncovered or offline providers while independent covered work can proceed',function()
  local C=require('autobuilder.core.chunks');local w=worker(12,8)
  local state={workers={['20']=anchor(20,8),['21']=anchor(21,24)}};state.workers['21'].online=false
  local ledger=C.new(state,config(),function() return true end)
  local held,why=ledger:reserve(job(),w);assert(not held and why:find('MISSION_BLOCKED_UNLOADED_AREA',1,true) and why:find('1,0',1,true),why)
  eq(next(state.chunkLedger.leases),nil)
  assert(ledger:reserve(job('local',9),w));state.workers['21'].online=true
  local lease=assert(ledger:reserve(job(),w));eq(lease.providers['0,0'].workerId,20);eq(lease.providers['1,0'].workerId,21)
end)

test('chunk provider claims survive reboot and offline owners without changing grants',function()
  local C=require('autobuilder.core.chunks');local state={workers={['20']=anchor(20,8),['21']=anchor(21,24)}}
  local w=worker(12,8);local j=job();local ledger=C.new(state,config(),function() return true end)
  local first=assert(ledger:reserve(j,w));assert(C.validArea(j.loadedArea))
  local restored=U.copy(state);restored.workers['20'].online=false;restored.workers['21'].online=false
  ledger=C.new(restored,config(),function() return true end);local second=assert(ledger:reserve(j,w))
  eq(second.providers['0,0'].workerId,first.providers['0,0'].workerId)
  local changed=U.copy(j);changed.blocks[1].x=40;assert(not pcall(ledger.reserve,ledger,changed,w),'changed geometry retained old grant')
  changed=U.copy(j);changed.loadedArea.maxX=2;assert(not pcall(ledger.reserve,ledger,changed,w),'changed loaded envelope accepted')
  assert(not ledger:reserve(job('new'),w),'offline loaders acquired a new mission')
  assert(ledger:release(j.id));assert(ledger:release(j.id));eq(restored.chunkLedger.leases[j.id].status,'released')
end)

test('chunk grant and release checkpoints roll back both job authority and ledger state',function()
  local C=require('autobuilder.core.chunks');local fail=true;local state={workers={}}
  local ledger=C.new(state,config({{minX=0,maxX=1,minZ=0,maxZ=0}}),function() return not fail,'disk full' end)
  local j=job();assert(not pcall(ledger.reserve,ledger,j,worker(12,8)));eq(j.loadedArea,nil);eq(next(state.chunkLedger.leases),nil)
  fail=false;assert(ledger:reserve(j,worker(12,8)));fail=true
  assert(not pcall(ledger.release,ledger,j.id));eq(state.chunkLedger.leases[j.id].status,'held')
end)

test('chunk anchors need real enabled hardware a settled pose and no physical task',function()
  local C=require('autobuilder.core.chunks');local cfg=config();cfg.chunkLoading.anchor=true
  local s={position=pos(24)};local kind='modem';local e={peripheral={getType=function(side) return side=='left' and kind or 'modem' end}}
  eq(C.probe(e,s,cfg),nil);kind='disabled_peripheral';eq(C.probe(e,s,cfg),nil)
  kind='chunky';local found=assert(C.probe(e,s,cfg));eq(found.x,1);eq(found.z,0)
  s.position.pending={};eq(C.probe(e,s,cfg),nil);s.position.pending=nil;s.currentTask={id='active'};eq(C.probe(e,s,cfg),nil)
  local state={workers={['20']=anchor(20,8)}};state.workers['20'].telemetry.task='active'
  local ledger=C.new(state,config(),function() return true end);assert(not ledger:reserve(job('local',9),worker(12,8)))
end)

test('chunk configuration enforces coverage by default and validates explicit assurances',function()
  local C=require('autobuilder.config');eq(C.load().chunkLoading.enabled,true)
  local area={minX=-2,maxX=1,minZ=-1,maxZ=0}
  eq(C.load({chunkLoading={areas={area}}}).chunkLoading.areas[1].minX,-2)
  for _,override in ipairs({{enabled='yes'},{areas={{minX=1,maxX=0,minZ=0,maxZ=0}}},{areas={[2]=area}},{anchor=true}}) do
    assert(not pcall(C.load,{chunkLoading=override}),'invalid chunk policy accepted')
  end
end)
