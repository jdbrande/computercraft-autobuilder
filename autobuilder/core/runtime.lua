local U=require('autobuilder.core.util')
local Checkpoint=require('autobuilder.core.checkpoint')
local Network=require('autobuilder.core.network')
local M={}
local operatorEvents={char=true,key=true,paste=true,autobuilder_command=true}
local function commandReply(e,id,ok,result)
  if U.shortString(id,64) and e.os.queueEvent then
    e.os.queueEvent('autobuilder_command_result',id,not not ok,tostring(result or (ok and 'OK' or 'failed')):sub(1,1024))
  end
end
local function validateState(s,role,id)
  assert(type(s)=='table' and s.schema==1,'unsupported application checkpoint schema')
  assert(s.id==id and s.role==role,'checkpoint belongs to a different computer or role')
  assert(U.integer(s.boot) and s.boot>=0,'invalid checkpoint boot counter')
  assert(type(s.phase)=='string','invalid phase')
  if role=='worker' then
    local p=s.position
    assert(type(p)=='table' and type(p.known)=='boolean','invalid saved position')
    assert(not p.known or U.position(p),'invalid saved coordinates')
    assert(not p.heading or U.heading(p.heading),'invalid saved heading')
    assert(not p.pending or (type(p.pending)=='table' and ({forward=true,back=true,up=true,down=true,turnLeft=true,turnRight=true})[p.pending.action]),'invalid movement intent')
  else
    assert(type(s.workers)=='table','invalid saved workers')
    for key,w in pairs(s.workers) do
      assert(type(w)=='table' and tostring(w.id)==key and U.finite(w.lastSeen),'invalid saved worker')
      local valid,err=Network.validate(w.id,{version=1,id=w.id..':'..w.boot..':'..w.sequence,sender=w.id,boot=w.boot,sequence=w.sequence,type='register',payload=w.telemetry})
      assert(valid,err)
    end
  end
end
function M.new(config,e)
  if e.shell and e.shell.setAlias then e.shell.setAlias('setup','/autobuilder/setup.lua');e.shell.setAlias('fleet','/fleet.lua') end
  local id=e.os.getComputerID()
  assert(config.role~='worker' or e.turtle,'worker must run on a turtle')
  assert(config.role~='worker' or config.controllerId~=id,'worker cannot be its own controller')
  local clock=function() return e.os.epoch('utc')/1000 end
  local store=Checkpoint.new(e.fs,e.textutils,config.dataDir..'/'..config.role..'.state')
  local state,source=store:load()
  if not state then
    assert(source=='missing',source)
    state={schema=1,id=id,role=config.role,boot=0,phase='telemetry',workers={}}
    state.position=U.copy(config.initialPosition or {known=false})
    if config.initialPosition then state.position.known=true; state.position.source='configured' end
  end
  validateState(state,config.role,id)
  if config.role=='controller' then
    require('autobuilder.factory.processors').validateSaved(config,state)
    require('autobuilder.factory.stations').validateSaved(config,state)
    require('autobuilder.storage.nodes').validateSaved(config,state)
    require('autobuilder.storage.supply').validateSaved(config,state.automation or {})
    require('autobuilder.core.inventory_geometry').initialize(state,config)
  end
  -- UTC prevents a restored older snapshot from reusing the last boot's IDs.
  state.boot=math.max(state.boot+1,math.floor(clock()*1000))
  local self={state=state,config=config,page=0,motionVersion=0,busy=false,input=''}
  local log=require('autobuilder.core.log').new(e.fs,config.logDir..'/'..config.role..'.log',config.log,clock)
  local network=Network.new(e,config,id,state.boot)
  local lastSave=clock()
  function self:save()
    state.savedAt=clock()
    local ok,err=store:save(state); assert(ok,err)
    lastSave=clock(); return true
  end
  function self:report(level,message)
    if level=='ERROR' or level=='WARN' then state.lastError=message end
    local ok,err=log:write(level,message); assert(ok,err)
  end
  self.chunks=require('autobuilder.core.chunks').new(state,config,function() return self:save() end)
  if config.role=='controller' then
    if source:find('backup') then state.assignmentRecovery=true end
    for _,worker in pairs(state.workers) do
      local recovery=worker.telemetry and worker.telemetry.poseRecovery
      if recovery and recovery.granted and recovery.stage~='settled' then state.assignmentRecovery=true end
    end
    self.registry=require('autobuilder.workers.workers').new(state,config,function() return self:save() end)
    if config.fleet.enabled then
      local ok,release=pcall(require('autobuilder.core.enrollment').release,e)
      if ok then self.fleetRelease=release else self:report('WARN','Fleet enrollment unavailable: '..tostring(release)) end
    end
  else
    state.controllerId=config.controllerId
    if source:find('backup') then
      -- Backup can predate a physical action whose intent was in the primary.
      state.position.known=false; state.position.heading=nil; state.position.uncertain=true
    end
    state.status=state.currentTask and 'task_paused' or 'idle'
    if state.position.pending or state.position.uncertain then state.position.uncertain=true; state.status='recovery_required' end
    if state.position.source=='gps' then state.position.source='local' end
    state.gpsError='awaiting GPS'
    self.navigation=require('autobuilder.core.navigation').new(e.turtle,state.position,config,function() return self:save() end)
    self.navigation.coverageGuard=function(from,target) return require('autobuilder.core.chunks').guard(config,state,from,target) end
    self.inventoryDonor=require('autobuilder.workers.inventory_donor').new(self,e)
    if state.inventoryRecovery then state.status='quarantined' end
    self.fuelRecovery=require('autobuilder.workers.fuel_recovery').new(self,config,e)
    self.agent=require('autobuilder.workers.agent').new(state,config,network,e.turtle,function() return self:save() end,function() return require('autobuilder.core.chunks').probe(e,state,config) end,e)
  end
  self:save() -- Persist boot generation before producing any message IDs.
  self:report('INFO','Started '..config.role..' '..id..' boot '..state.boot..' from '..source)
  if source:find('backup') then self:report('WARN','Recovered '..source) end
  if state.inventoryGeometry and state.inventoryGeometry.error then self:report('WARN',state.inventoryGeometry.error) end
  local gps=require('autobuilder.core.gps').new(e.gps,config.gps)
  self.mining=require('autobuilder.core.mining_service').new(self,config,e,network,clock)
  self.automation=require('autobuilder.core.automation_service').new(self,config,e,network,clock)
  if self.agent then self.poseRecovery=require('autobuilder.workers.pose_recovery').new(self,config,e,network,clock,gps) end
  if config.role=='controller' then
    self.firstBuild=require('autobuilder.core.first_build').new(self,config,e)
    state.view='guide'
  end
  local function restoreCoverage()
    local task=state.currentTask
    if task and task.chunkBlock and require('autobuilder.core.chunks').execution(config,state) then
      local prior=task.chunkBlock
      task.phase=prior.phase;task.blockedCategory=prior.category;task.error=prior.error;task.chunkBlock=nil
      state.status=task.phase or 'task_paused';self:save()
    end
  end
  function self:poseRecovered()
    if state.inventoryRecovery then state.status='quarantined';return self:save() end
    restoreCoverage()
    if self.mining.poseRecovered then self.mining:poseRecovered() end
    if self.automation.poseRecovered then self.automation:poseRecovered() end
    if state.status=='recovery_required' and U.heading(state.position.heading) then
      state.status=state.currentTask and (state.currentTask.phase or 'task_paused') or 'idle'
    end
    return self:save()
  end
  function self:confirmPose(fix,heading)
    if state.inventoryRecovery then return false,'quarantined inventory donor pose cannot be changed' end
    if not self.navigation or not U.heading(heading) then return false,'worker and explicit heading required' end
    if state.poseRecovery then return false,'automatic pose probe owns movement; restore GPS and settle its origin first' end
    local ok,err=self.navigation:reconcile(fix,heading); if not ok then return false,err end
    state.position.source='manual'; state.status=state.currentTask and (state.currentTask.phase or 'task_paused') or 'idle'
    self:poseRecovered()
    self:report('INFO','Operator confirmed position and heading'); return self:save()
  end
  function self:updateGPS()
    if not self.agent or self.busy then return true end
    local revision=self.motionVersion
    local fix,err=gps:locate()
    -- A locate call yields; never apply coordinates sampled before intervening motion.
    if self.busy or revision~=self.motionVersion then return true end
    local p=state.position
    if fix then
      if state.poseRecovery then
        local ok,why=self.poseRecovery:observe(fix)
        if not ok then state.gpsError=why;self:save();return false,why end
        p.source='gps';p.lastFix=clock();state.gpsError=nil;return self:save()
      end
      local changed=p.known and (p.x~=fix.x or p.y~=fix.y or p.z~=fix.z)
      if changed then self:report('WARN','GPS corrected local position') end
      local ok,why=self.navigation:reconcile(fix)
      if not ok then state.gpsError=why;state.status='recovery_required';self:save();return false,why end
      p.source='gps'; p.lastFix=clock(); state.gpsError=nil
      self:poseRecovered()
    else
      p.source=p.known and 'local' or 'unknown'
      if state.gpsError~=err then self:report('WARN',err) end
      state.gpsError=err
    end
    return self:save()
  end
  function self:tick()
    local ready,err=network:open()
    if not ready and state.lastError~=err then self:report('WARN',err) end
    if self.registry then
      self.chunks:reconcile()
      local ok,why=self.registry:expire(clock()); if not ok then return false,why end
    else
      local ok,why=self.agent:tick(clock())
      if not ok then self:report('WARN',why) end
    end
    if state.view=='chunks' then self.chunks:describe() end
    if self.automation.preflight then self.automation:preflight() end
    self.mining:tick()
    self.automation:tick()
    if self.firstBuild then self.firstBuild:tick() end
    if clock()-lastSave>=config.checkpointInterval then self:save() end
    return true
  end
  function self:receive(sender,message,protocol)
    if self.registry and protocol==require('autobuilder.install.discovery').protocol then
      return require('autobuilder.core.enrollment').reply(e,config,self.fleetRelease,sender,message)
    end
    if self.registry and protocol==config.protocol..'.setup' then
      return require('autobuilder.setup_share').reply(e,config,state.workers,sender,message)
    end
    local m,err=network:accept(sender,message,protocol,clock())
    if not m then
      if err~='different protocol' and err~='duplicate message' then self:report('DEBUG','Rejected message: '..err) end
      return false,err
    end
    if m.type:sub(1,5)=='mine_' then return self.mining:handle(sender,m) end
    if m.type:sub(1,5)=='task_' then return self.automation:handle(sender,m) end
    if self.registry then
      self.chunks:reconcile()
      local ok,why=self.registry:handle(m,clock())
      if not ok then
        if why=='registration required' then
          local sent,sendError=network:send(sender,'register_required',{reason=why})
          if not sent then self:report('WARN',sendError) end
        end
        self:report('DEBUG','Worker message rejected: '..tostring(why)); return false,why
      end
      local restored,reason=self.automation:restorePose(state.workers[tostring(sender)])
      if not restored then state.assignmentRecovery=true;self:save();self:report('WARN','Pose ownership reconciliation: '..tostring(reason)) end
      local sent,reason=network:send(sender,'ack',{requestId=m.id})
      if not sent then self:report('WARN',reason) end
      return sent,reason
    end
    return self.agent:handle(sender,m,clock())
  end
  function self:workStep()
    if self.busy or self.gpsRequested or self.quitRequested then return true end
    if not self.agent then return self.automation:step() end
    if self.inventoryDonor and self.inventoryDonor:active() then
      self.busy=true
      local ok,result,err=pcall(self.inventoryDonor.step,self.inventoryDonor)
      self.busy=false;state.status='quarantined'
      if not ok then error(result,0) end
      return result,err
    end
    local task=state.currentTask
    if task and task.type and task.type~='MINE' and not config.automation.enabled then return true end
    if self.poseRecovery:needed() then
      self.busy=true;self.motionVersion=self.motionVersion+1
      local ok,result,err=pcall(self.poseRecovery.step,self.poseRecovery)
      self.busy=false
      if not ok then error(result,0) end
      return result,err
    end
    if task and task.phase~='completed' then
      local covered,why=require('autobuilder.core.chunks').execution(config,state)
      if not covered then
        if not task.chunkBlock then task.chunkBlock={phase=task.phase,category=task.blockedCategory,error=task.error} end
        if task.phase~='blocked' or task.error~=why then
          task.phase='blocked';task.blockedCategory='chunks';task.error=why;state.status='blocked';self:save()
        end
        -- Keep prior action journals untouched. With coverage restored, the
        -- original engine reconciles them before attempting another side effect.
        return true
      elseif task.chunkBlock then restoreCoverage() end
    end
    if self.fuelRecovery and self.fuelRecovery:active() then
      self.busy=true
      local ok,result,err=pcall(self.fuelRecovery.step,self.fuelRecovery)
      self.busy=false
      if not ok then error(result,0) end
      -- A frozen recipient remains available for status and recovery messages.
      if not result and err then self:report('WARN',err) end
      return true
    end
    if state.fuelResume then
      local task=state.currentTask
      if task and task.id==state.fuelResume and not task.paused
        and require('autobuilder.workers.fuel_recovery').needsFuel(task) then
        local service=task.type=='MINE' and self.mining or self.automation
        service:resumeFuelTask()
      end
      state.fuelResume=nil; self:save()
    end
    if not state.currentTask or state.currentTask.phase=='completed' then return true end
    local generic=state.currentTask.type and state.currentTask.type~='MINE'
    if not generic and state.currentTask.phase=='blocked' then
      if not (state.motionReservation and state.motionReservation.granted and tostring(state.currentTask.error):find('movement reservation pending',1,true)) then return true end
    end
    self.busy=true; self.motionVersion=self.motionVersion+1
    local service=generic and self.automation or self.mining
    local ok,result,err=pcall(service.step,service)
    self.busy=false
    if state.currentTask and state.currentTask.phase=='blocked' and (state.position.pending or state.position.uncertain) then
      state.currentTask.poseBlocked=true;self:save()
    end
    if not ok then error(result,0) end
    return result,err
  end
  function self:command(line)
    line=line:match('^%s*(.-)%s*$')
    local called,ok,result=pcall(function()
      if line=='chunks' then
        if self.agent then state.telemetry=self.agent:telemetry() end
        state.view='chunks';return true,self.chunks:describe()
      end
      if line=='setup' or line=='7' or line:match('^setup%s') then
        if self.busy then return false,'Wait for the current turtle step to finish, then type setup again.' end
        self.nextProgram='setup'; self.nextProgramArgs={}
        local words={}; for word in line:gmatch('%S+') do words[#words+1]=word end
        for i=2,#words do self.nextProgramArgs[#self.nextProgramArgs+1]=words[i] end
        self.quitRequested=true; return true,'Opening setup. Current progress stays saved.'
      end
      if self.firstBuild then local a,b=self.firstBuild:command(line); if a~=nil then return a,b end end
      line=({['5']='workers',['6']='jobs'})[line] or line
      if line=='help' or line=='guide' or line=='1' then
        return true,'On this turtle: type setup. On the controller: type 1 to check, then 2 to start.'
      end
      if config.role=='worker' then return false,'Use controller '..config.controllerId..' to start/pause jobs. On this turtle, type setup or press Q for the shell.' end
      if self.automation.command then local a,b=self.automation:command(line); if a~=nil then return a,b end end
      return self.mining:command(line)
    end)
    if not called then result=ok; ok=false end
    state.commandResult=tostring(result or (ok and 'OK' or 'failed'))
    return ok,result
  end
  function self:draw() require('autobuilder.ui.ui').draw(e.term,state,self.agent,self.page,self.input) end
  function self:event(name,a,b,c)
    if self.quitRequested and not self.busy then self:save(); return false end
    if name=='rednet_message' then self:receive(a,b,c)
    elseif name=='autobuilder_command' then
      if U.shortString(a,64) then
        if type(b)~='string' or #b>256 or b:find('[%c]') then commandReply(e,a,false,'Invalid command; not executed')
        else local ok,result=self:command(b);commandReply(e,a,ok,result) end
      end
    elseif name=='autobuilder_input_discard' then
      self.input='';self.inputDiscarded=true;state.commandResult='Input overflow: command discarded. Press Enter, then retype.'
    elseif name=='key' and a==((e.keys or {}).enter or 28) then
      if self.inputDiscarded then self.inputDiscarded=nil;state.commandResult='Command discarded; ready for a new command.'
      else self:command(self.input) end
      self.input=''
    elseif self.inputDiscarded and (name=='char' or name=='paste' or name=='key') then return true
    elseif name=='char' and (a=='q' or a=='Q') and self.input=='' then
      if self.busy then self.quitRequested=true; return true end
      self:save(); return false
    elseif name=='char' and a=='N' and self.input=='' then self.page=self.page+1
    elseif name=='char' and a=='P' and self.input=='' then self.page=self.page-1
    elseif name=='char' or name=='paste' then
      local input=self.input..a:gsub('[%c]','')
      if #input>256 then self:event('autobuilder_input_discard') else self.input=input end
    elseif name=='key' and a==((e.keys or {}).backspace or 14) then self.input=self.input:sub(1,-2)
    elseif name=='peripheral' or name=='peripheral_detach' then self:tick() end
    return true
  end
  return self
end
function M.run(config,e)
  e=e or _G
  local app=M.new(config,e)
  local inbox,operators={},{};local dropped=0;local discardInput=false
  app.io={networkDropped=0,operatorDropped=0}
  local function collectEvents()
    while true do
      local name,a,b,c=e.os.pullEvent()
      if name=='rednet_message' then
        if #inbox<128 then inbox[#inbox+1]={a,b,c}
        else dropped=dropped+1;app.io.networkDropped=app.io.networkDropped+1 end
      elseif operatorEvents[name] then
        if name=='autobuilder_command' and (not U.shortString(a,64) or type(b)~='string' or #b>256 or b:find('[%c]')) then
          commandReply(e,a,false,'Invalid command; not executed')
        else
          if #operators>=128 then
            for _,event in ipairs(operators) do if event[1]=='autobuilder_command' then
              commandReply(e,event[2],false,'Input queue overflow; command not executed')
            end end
            app.io.operatorDropped=app.io.operatorDropped+#operators
            operators={{'autobuilder_input_discard'}};discardInput=true
          end
          if discardInput then
            app.io.operatorDropped=app.io.operatorDropped+1
            if name=='autobuilder_command' then commandReply(e,a,false,'Input queue overflow; command not executed')
            elseif name=='key' and a==((e.keys or {}).enter or 28) then
              operators[#operators+1]={name,a};discardInput=false
            end
          else operators[#operators+1]={name,a,b,c} end
        end
      end
      app.io.networkPending=#inbox;app.io.operatorPending=#operators
    end
  end
  local function drainOperators()
    local started=e.os.epoch('utc')
    for _=1,math.min(16,#operators) do
      local event=table.remove(operators,1)
      if not app:event(table.unpack(event)) then return false end
      if e.os.epoch('utc')-started>=250 then break end
    end
    app.io.operatorPending=#operators
    return true
  end
  local function drainNetwork()
    -- Only the main coroutine mutates controller/worker state. The collector
    -- retains packets while a peripheral call yields with another event filter.
    -- A backlog can contain128 packets, each requiring several atomic saves.
    -- Bound a turn between complete handlers; never yield inside a checkpoint.
    local started=e.os.epoch('utc')
    for _=1,math.min(8,#inbox) do
      local p=table.remove(inbox,1);app:receive(p[1],p[2],p[3])
      if e.os.epoch('utc')-started>=250 then break end
    end
    app.io.networkPending=#inbox
    if dropped>0 then
      app:report('WARN','Network inbox overflow: '..dropped..' packets dropped; durable protocols will retry')
      dropped=0
    end
  end
  local function main()
    app:tick(); drainNetwork(); if not drainOperators() then return end; app:draw()
    local nextTick=e.os.epoch('utc')/1000+1
    local timer=e.os.startTimer((#inbox>0 or #operators>0) and 0.05 or 1)
    while true do
      local name,a,b,c=e.os.pullEvent()
      if name=='timer' and a==timer then
        app:tick(); nextTick=e.os.epoch('utc')/1000+1
      elseif name~='rednet_message' and not operatorEvents[name] and not app:event(name,a,b,c) then return end
      if not drainOperators() then return end
      drainNetwork()
      if app.quitRequested and not app.busy then app:save(); return end
      -- CraftOS peripheral calls can yield with a task_complete filter and
      -- consume our one-shot timer while handling a command or network event.
      -- Check elapsed time and always rearm after the handler returns, even
      -- when that timer event never reached this loop. Keep all control work
      -- in this coroutine rather than racing another scheduler against it.
      if e.os.epoch('utc')/1000>=nextTick then
        app:tick(); nextTick=e.os.epoch('utc')/1000+1
      end
      if e.os.cancelTimer then e.os.cancelTimer(timer) end
      timer=e.os.startTimer((#inbox>0 or #operators>0) and 0.05 or math.max(0.05,nextTick-e.os.epoch('utc')/1000))
      app:draw()
    end
  end
  local function gpsLoop()
    if config.role~='worker' or not config.gps.enabled then
      while true do e.sleep(3600) end
    end
    while true do
      app.gpsRequested=true
      while app.busy do e.sleep(0.1) end
      app:updateGPS(); app.gpsRequested=false
      e.sleep(config.gps.interval)
    end
  end
  local function actionLoop()
    while true do app:workStep(); e.sleep(0.1) end
  end
  -- Start the collector first so an idle main loop can drain the same event.
  local ok,err=pcall(e.parallel.waitForAny,collectEvents,main,gpsLoop,actionLoop)
  if not ok then
    app:report('ERROR','Runtime stopped: '..tostring(err))
    app:save()
    error(err,0)
  end
  return app
end
return M
