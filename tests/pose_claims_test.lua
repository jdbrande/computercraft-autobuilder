local U=require('autobuilder.core.util')
local W=require('autobuilder.core.workflows')
local function point(x,z) return {x=x or 8,y=64,z=z or 8} end
local function fixture()
  local cfg=require('autobuilder.config').load({chunkLoading={areas={{minX=0,maxX=0,minZ=0,maxZ=0}}}})
  local f={state={workers={}},config=cfg}
  local function save() if f.fail then return false,'disk full' end;f.saved=U.copy(f.state);return true end
  f.chunks=require('autobuilder.core.chunks').new(f.state,cfg,save)
  f.q=W.new(f.state,save,function() return 100 end,7,f.chunks,cfg)
  f.job=f.q:submit('RETURN_HOME',{});f.job.workerId=12;f.job.status='running'
  f.job.loadedArea={minX=0,maxX=0,minZ=0,maxZ=0}
  f.state.chunkLedger.leases[f.job.id]={status='held',workerId=12,area=U.copy(f.job.loadedArea)}
  f.state.workers['12']={id=12,online=true,telemetry={task=f.job.id,position=point()}}
  function f:request(sequence,origin) return self.q:reservePose(12,self.job.id,sequence or 1,origin or point(),self.state.workers) end
  function f:restore()
    self.state=U.copy(self.saved);self.job=self.state.automation.jobs[self.job.id]
    self.chunks=require('autobuilder.core.chunks').new(self.state,cfg,save)
    self.q=W.new(self.state,save,function() return 100 end,7,self.chunks,cfg)
  end
  return f
end

test('pose probe claims all possible forward cells atomically and retains exact ownership over reboot',function()
  local f=fixture();assert(f:request())
  for _,k in ipairs({'8,64,8','7,64,8','9,64,8','8,64,7','8,64,9'}) do eq(f.state.automation.cells[k].owner,12) end
  assert(not f.q:reserve(12,f.job.id,point(),point(9),f.state.workers),'ordinary movement shrank active pose claim')
  f:restore();assert(f:request());assert(not f:request(1,point(9)),'changed duplicate origin accepted')
  assert(not f:request(2),'new probe replaced unsettled ownership')
  assert(not f.q:finishPose(12,f.job.id,1,point(9)),'probe was settled before returning to origin')
  assert(f.q:finishPose(12,f.job.id,1,point()));assert(f.q:finishPose(12,f.job.id,1,point()))
  eq(f.state.automation.cells['9,64,8'],nil);eq(f.state.automation.cells['8,64,8'].owner,12)
  assert(not f:request(1),'finished probe was reopened by delayed duplicate')
  assert(f:request(2))
end)

test('pose claims refuse any occupied protected or unloaded candidate without partial acquisition',function()
  for _,cause in ipairs({'cell','worker','protected','loaded','foreign','region'}) do
    local f=fixture()
    if cause=='cell' then f.state.automation.cells['9,64,8']={owner=13,jobId='other'}
    elseif cause=='worker' then f.state.workers['13']={id=13,telemetry={position={x=7,y=64,z=8,known=true}}}
    elseif cause=='protected' then f.config.restrictedAreas={{min=point(8,9),max=point(8,9)}}
    elseif cause=='loaded' then f.job.loadedArea.maxX=-1
    elseif cause=='foreign' then f.job.workerId=13
    else f.state.jobs={mine={id='mine',workerId=13,status='running',miningArea={min=point(9),max=point(10)}}} end
    assert(not f:request(),'admitted '..cause);eq(f.job.poseRecovery,nil)
    for _,cell in pairs(f.state.automation.cells) do assert(cell.owner~=12,'partial claim on '..cause) end
  end
end)

test('pose claim checkpoints roll back grants and releases without freeing another owner',function()
  local f=fixture();f.fail=true;assert(not pcall(f.request,f));eq(f.job.poseRecovery,nil);eq(next(f.state.automation.cells),nil)
  f.fail=false;assert(f:request());f.state.automation.cells['30,64,8']={owner=13,jobId='other'}
  f.fail=true;assert(not pcall(f.q.finishPose,f.q,12,f.job.id,1,point()))
  eq(f.job.poseRecovery.status,'held');eq(f.state.automation.cells['9,64,8'].owner,12)
  f.fail=false;assert(f.q:finishPose(12,f.job.id,1,point()));eq(f.state.automation.cells['30,64,8'].owner,13)
end)

test('pose request protocol validates bounded identity coordinates and exact grant evidence',function()
  local P=require('autobuilder.core.task_messages')
  local p={jobId='task:7:1',sequence=1,origin=point()}
  assert(P.validate('task_pose_reserve',p))
  p.sequence=0;assert(not P.validate('task_pose_reserve',p));p.sequence=1
  assert(not P.validate('task_pose_grant',p));p.granted=true;assert(P.validate('task_pose_grant',p))
  p.reason={};assert(not P.validate('task_pose_grant',p),'malformed refusal reason accepted');p.reason=nil
  p.origin.x=0/0;assert(not P.validate('task_pose_grant',p))
end)

test('recovery heartbeat evidence is bounded and cleans unknown fields before restoring ownership',function()
  local S=require('tests.support');local cfg=require('tests.loaded_config').load({role='worker',controllerId=7})
  local state={id=12,position={known=true,x=8,y=64,z=8},currentTask={id='task:7:1',type='MINE'},
    poseRecovery={jobId='task:7:1',sequence=1,stage='probe',granted=true,origin=point()}}
  local payload=require('autobuilder.workers.agent').new(state,cfg,{},S.turtle(),function() return true end):telemetry()
  local msg={version=1,id='12:1:1',sender=12,boot=1,sequence=1,type='register',payload=payload}
  local N=require('autobuilder.core.network');assert(N.validate(12,msg));payload.poseRecovery.extra=payload
  local clean=assert(N.new({},cfg,7,1):accept(12,msg,cfg.protocol,100));eq(clean.payload.poseRecovery.extra,nil)
  payload.poseRecovery.sequence=0;assert(not N.validate(12,msg));payload.poseRecovery.sequence=1
  payload.poseRecovery.jobId='other';assert(not N.validate(12,msg));payload.poseRecovery.jobId=payload.task
  payload.poseRecovery.stage='unknown';assert(not N.validate(12,msg))
end)
