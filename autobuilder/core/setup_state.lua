local U=require('autobuilder.core.util')
local Checkpoint=require('autobuilder.core.checkpoint')
local M={}
function M.idle(e,config,preparation)
  local store=Checkpoint.new(e.fs,e.textutils,config.dataDir..'/'..config.role..'.state')
  local state,source=store:load()
  assert(source=='primary' or source=='missing','Checkpoint recovery required before setup: '..source)
  if state then
    assert(state.schema==1 and state.id==e.os.getComputerID() and state.role==config.role
      and U.integer(state.boot) and type(state.phase)=='string','Invalid or foreign checkpoint')
    assert(not state.fuelRecovery and not state.fuelResume,'Finish fuel recovery before setup')
    assert(not state.assignmentRecovery and not state.currentTask and not state.motionReservation
      and not next(state.pendingSupplyAcks or {}),'Finish current jobs and acknowledgements before setup')
    assert(not (state.firstBuild and state.firstBuild.autoStart),'Finish the requested first test before changing setup; pausing keeps its saved settings in use')
    if config.role=='worker' then
      assert(type(state.position)=='table' and type(state.position.known)=='boolean','Invalid saved position')
      assert(not state.position.pending and not state.position.uncertain,'Recover uncertain movement with /autobuilder/pose.lua before setup')
    end
    local a=state.automation or {}
    assert(not a.supply,'Finish the outstanding supply batch before setup')
    for _,jobs in ipairs({state.jobs or {},a.jobs or {},preparation and {} or a.requests or {}}) do
      for _,job in pairs(jobs) do
        assert(job.type~='RESCUE' or job.rescueSettled,'Finish fuel recovery before setup')
        assert(job.status=='completed','Finish queued or paused work before setup')
      end
    end
    for _,project in pairs(a.projects or {}) do
      assert(not ({building=true,verifying=true,repairing=true,clearing=true,preparing=not preparation})[project.phase],
        'Finish the active project before setup')
    end
  end
  return store,state
end
return M
