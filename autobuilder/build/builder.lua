local U=require('autobuilder.core.util')
local C=require('autobuilder.build.blockstates')
local P=require('autobuilder.build.placement')
local Site=require('autobuilder.build.site_work')
local M={}
function M.new(task,e,config,nav,save,mode)
  assert(type(task)=='table' and type(task.blocks)=='table' and #task.blocks<=4096,'bounded blocks task required')
  assert(e and e.turtle and nav and type(save)=='function','construction hardware/navigation/persistence required')
  config=config or {}; mode=mode or 'build'; local t=e.turtle; local self={task=task}; local fault
  task.phase=task.phase or 'setup'; task.index=task.index or 1; task.progress=task.progress or 0; task.delivered=task.delivered or 0
  task.attempts=task.attempts or {}; task.report=task.report or {entries={},counts={}}
  task.deferred=task.deferred or {}
  local ceiling=-math.huge
  for _,b in ipairs(task.blocks) do assert(U.position(b) and type(b.name)=='string','invalid construction block'); ceiling=math.max(ceiling,b.y+(mode=='prepare' and 1 or 2)) end
  if task.clearanceY then
    assert(U.integer(task.clearanceY) and math.abs(task.clearanceY)<=30000000,'invalid construction clearance height')
    ceiling=math.max(ceiling,task.clearanceY)
  end
  local reserved={[config.fuelSlot or 15]=true,[16]=true}
  for _,s in ipairs(config.reservedSlots or {}) do reserved[s]=true end
  if mode=='prepare' then reserved=require('autobuilder.workers.resupply').reserved(config) end
  local scanner
  if mode=='prepare' and config.scanner and e.peripheral then
    scanner=require('autobuilder.resources.scanner').new(e,config.scanner,function() return e.os.epoch('utc')/1000 end)
  end
  local function persist()
    local ok,value,err=pcall(save)
    if not ok or not value then fault='construction checkpoint failed: '..tostring(ok and err or value); error(fault,0) end
    return true
  end
  local function blocked(err,category)
    task.resumePhase=task.phase~='blocked' and task.phase or task.resumePhase
    task.phase='blocked'; task.error=tostring(err); task.blockedCategory=category; persist(); return false,task.error
  end
  local function restricted(p)
    for _,a in ipairs(config.restrictedAreas or {}) do
      if p.x>=a.min.x and p.x<=a.max.x and p.y>=a.min.y and p.y<=a.max.y and p.z>=a.min.z and p.z<=a.max.z then return true end
    end
    return false
  end
  local function awaitingMovement(err)
    return nav.pose.pending or nav.pose.uncertain or tostring(err):find('reservation',1,true)
  end
  local function move(target)
    local pose=nav.pose
    local route=task.moveRoute
    if route and U.distance(route.target,target)~=0 then return false,'construction route target changed before completion' end
    if not route then
      if U.distance(pose,target)==0 then return true end
      local height=math.max(ceiling,pose.y,target.y)
      local points,why=require('autobuilder.workers.resupply').overheadPoints(task,nav,t,config,target,height)
      if not points then return false,why end
      route={target=U.copy(target),height=height,index=1,attempt=0,points=points}
      task.moveRoute=route; persist()
    end
    local offsets={{-1,0},{1,0},{0,-1},{0,1}}
    while route.index<=#route.points do
      local ok,err=nav:goTo(route.points[route.index])
      if ok then route.index=route.index+1; persist()
      elseif awaitingMovement(err) then return false,err
      else
        -- A failed descent may need an approach from the side. Preserve that
        -- selected approach too: a reservation yield must not restart the ascent.
        if route.attempt==0 and route.index<#route.points then task.moveRoute=nil; persist(); return false,err end
        route.originalError=route.originalError or tostring(err)
        route.attempt=route.attempt+1
        local offset=offsets[route.attempt]
        if not offset then task.moveRoute=nil; persist(); return false,route.originalError end
        route.points={{x=pose.x,y=route.height,z=pose.z},
          {x=target.x+offset[1],y=route.height,z=target.z+offset[2]},
          {x=target.x+offset[1],y=target.y,z=target.z+offset[2]},U.copy(target)}
        route.index=1; persist()
      end
    end
    task.moveRoute=nil; return persist()
  end
  local function inspect(plan)
    local ok,found,actual=pcall(t['inspect'..P.suffix(plan.direction)])
    if not ok then return nil,nil,'inspection failed: '..tostring(found) end
    if type(found)~='boolean' or found and (type(actual)~='table' or type(actual.name)~='string') then return nil,nil,'invalid inspection response' end
    return found,actual
  end
  local function pairInspection(b,p,purpose)
    purpose=purpose or 'existing'
    task.pairResults=task.pairResults or {}
    local cached=task.pairResults[purpose]
    if cached then return cached.found,cached.actual,cached.error end
    local check=task.pairCheck
    if not check then
      local stand={x=p.stand.x+p.pair.x-b.x,y=p.stand.y+p.pair.y-b.y,z=p.stand.z+p.pair.z-b.z}
      if restricted(p.pair) or restricted(stand) then return nil,nil,'paired block cell or inspection stand is protected' end
      check={purpose=purpose,stage='out',stand=stand}; task.pairCheck=check; persist()
    end
    if check.purpose~=purpose then return nil,nil,'paired inspection purpose changed before completion' end
    if check.stage=='out' then
      local ok,err=nav:goTo(check.stand); if not ok then return nil,nil,err end
      check.stage='inspect'; persist()
    end
    if check.stage=='inspect' then
      local ok,err=nav:face(p.heading); if not ok then return nil,nil,err end
      check.found,check.actual,check.error=inspect(p)
      check.stage='back'; persist()
    end
    if check.stage=='back' then
      local ok,err=nav:goTo(p.stand); if not ok then return nil,nil,err end
      check.stage='face'; persist()
    end
    local ok,err=nav:face(p.heading); if not ok then return nil,nil,err end
    local result={found=check.found,actual=check.actual,error=check.error}
    task.pairResults[purpose]=result; task.pairCheck=nil; persist()
    return result.found,result.actual,result.error
  end
  local function supportInspection(b,p)
    if task.supportApproved then return true end
    local check=task.supportCheck
    if not check then check={stage='enter'}; task.supportCheck=check; persist() end
    if check.stage=='enter' then
      local ok,err=nav:goTo({x=b.x,y=b.y,z=b.z}); if not ok then return false,err end
      check.stage='inspect'; persist()
    end
    if check.stage=='inspect' then
      if p.isolate then check.safe=true;check.stage='neighbors';check.side=1;persist() end
    end
    if check.stage=='inspect' then
      local ok,err=nav:face(p.support.heading); if not ok then return false,err end
      local found,solid,why=inspect(p.support)
      check.safe=found and Site.support(solid.name) or false
      check.error=why or (not check.safe and 'required solid support face is missing or unsupported' or nil)
      check.stage=check.safe and (C.family(b.name)=='door' and 'sides' or C.family(b.name)=='bed' and 'pairFloor' or 'return') or 'return'; check.level=0; check.side=1; persist()
    end
    if check.stage=='neighbors' then
      local headings={'north','east','south','west'}
      while check.side<=4 do
        local ok,err=nav:face(headings[check.side]);if not ok then return false,err end
        local found,actual,why=inspect({direction='forward'})
        if why or found and C.family(actual.name)=='chest' then check.safe=false;check.error=why or 'adjacent chest prevents isolated placement';break end
        check.side=check.side+1;persist()
      end
      check.stage='return';persist()
    end
    if check.stage=='pairFloor' then
      local ok,err=nav:goTo(p.pair);if not ok then return false,err end
      local found,solid,why=inspect({direction='down'})
      check.safe=found and Site.support(solid.name) or false
      check.error=why or (not check.safe and 'paired bed floor is missing or unsupported' or nil)
      check.stage='return';persist()
    end
    local sides={north={'west','east'},east={'north','south'},south={'east','west'},west={'south','north'}}
    while check.stage=='sides' or check.stage=='upper' do
      if check.stage=='upper' then
        local ok,err=nav:goTo({x=b.x,y=b.y+1,z=b.z}); if not ok then return false,err end
        check.level=1; check.side=1; check.stage='sides'; persist()
      end
      while check.side<=2 do
        local ok,err=nav:face(sides[p.heading][check.side]); if not ok then return false,err end
        local occupied,_,why=inspect({direction='forward'})
        if occupied or why then check.safe=false; check.error=why or 'door hinge sides must be empty'; check.stage='return'; persist(); break end
        check.side=check.side+1; persist()
      end
      if check.stage=='sides' then check.stage=check.level==0 and 'upper' or 'return'; persist() end
    end
    if check.stage=='return' then
      local ok,err=nav:goTo(p.stand); if not ok then return false,err end
      check.stage='face'; persist()
    end
    local ok,err=nav:face(p.heading); if not ok then return false,err end
    local safe,why=check.safe,check.error
    task.supportCheck=nil; task.supportApproved=safe or nil; persist()
    return safe,why
  end
  local function clearPreparation()
    task.moveRoute=nil; task.supportCheck=nil; task.supportApproved=nil
    task.pairCheck=nil; task.pairResults=nil
    task.siteApproach=nil;task.siteApproachIndex=nil
  end
  local function matchesBlock(b,found,actual,p)
    if mode=='prepare' and found then
      if b.retain and P.compare(b.retain,found,actual) then return true end
      if b.substrate then return actual.name==b.substrate,'required plant substrate is missing' end
      if b.support and Site.support(actual.name) then return true end
    end
    local family=C.family(b.name)
    local defer=mode~='verify' and not task.recheck and C.connected(family)
    local matches,why=P.compare(b,found,actual,defer)
    if matches and C.inventory(b.name) then
      local side=p.direction=='down' and 'bottom' or p.direction=='up' and 'top' or 'front'
      if not e.peripheral or type(e.peripheral.call)~='function' then return false,'inventory observation unavailable' end
      local ok,items=pcall(e.peripheral.call,side,'list')
      if not ok or type(items)~='table' then return false,'inventory observation failed' end
      if next(items)~=nil then return false,'expected empty inventory' end
    end
    return matches,why
  end
  local function inventory()
    if mode=='prepare' then return require('autobuilder.workers.resupply').snapshot(t) end
    local result={}
    for s=1,16 do local i=t.getItemDetail(s); if i then result[s]={name=i.name,count=i.count} end end
    return result
  end
  local function sameInventory(a,b)
    for s=1,16 do
      local x,y=a[s],b[s]
      if (x and not y) or (y and not x) or x and (x.name~=y.name or x.count~=y.count) then return false end
    end
    return true
  end
  local function slotFor(item)
    for s=1,16 do local i=t.getItemDetail(s); if not reserved[s] and i and i.name==item and i.count>0 and (mode~='prepare' or not i.nbt) and (not C.inventory(item) or not i.nbt) then return s,i.count end end
  end
  local function missing(item)
    task.missingItem=item; task.missingCount=1; return blocked('missing inventory: '..item,'missing_inventory')
  end
  local function record(b,status,reason,actual)
    clearPreparation()
    local r=task.report
    if task.recheck then
      local index=task.deferred[task.recheck]; local entry=r.entries[index]
      r.counts[entry.status]=r.counts[entry.status]-1; entry.status=status; entry.reason=reason; entry.actual=U.copy(actual)
      r.counts[status]=(r.counts[status] or 0)+1
      if status=='correct' then task.progress=task.progress+1; task.delivered=task.progress end
      task.recheck=task.recheck+1
      if task.recheck>#task.deferred then task.phase='completed' end
      return persist()
    end
    local family=C.family(b.name)
    if status=='correct' and mode~='verify' and C.connected(family) then
      status='pending'; task.deferred[#task.deferred+1]=task.index
    end
    r.entries[#r.entries+1]={index=task.index,x=b.x,y=b.y,z=b.z,status=status,reason=reason,expected={name=b.name,state=U.copy(b.state or {})},actual=type(actual)=='table' and U.copy(actual) or nil}
    r.counts[status]=(r.counts[status] or 0)+1
    if status=='correct' or status=='pending' and task.deferConnections==true then task.progress=task.progress+1; task.delivered=task.progress end
    task.index=task.index+1; task.intent=nil; task.missingItem=nil; task.missingCount=nil
    if task.index>#task.blocks then
      if #task.deferred>0 and task.deferConnections~=true then task.recheck=1 elseif mode~='prepare' then task.phase='completed' end
    end
    return persist()
  end
  local function issue(b,category,reason,actual)
    if mode=='verify' or mode=='prepare' then return record(b,category,reason,actual) end
    return blocked(reason,category)
  end
  local function countAttempt(kind)
    local key=kind..':'..task.index; local count=task.attempts[key] or 0
    if count>=3 then return false end
    task.attempts[key]=count+1; return true
  end
  local function recover(b,p,found,actual)
    local i=task.intent; if not i then return true end
    if i.index~=task.index then return false,'intent index does not match current block' end
    if i.kind=='place' then
      if mode=='prepare' then
        local delta,why=require('autobuilder.workers.resupply').delta(t,{kind='drop',slot=i.slot,item=i.item,limit=1,before=i.inventory})
        if not delta then return false,why end
      end
      local item=t.getItemDetail(i.slot)
      if item and item.name~=i.item then return false,'placement inventory changed during recovery' end
      local count=item and item.count or 0; local matches=matchesBlock(b,found,actual,p)
      if p.pair then
        local paired,other,why=pairInspection(b,p,'recover'); if why then return false,why end
        task.pairResults.existing=U.copy(task.pairResults.recover)
        if matches and not P.compare(p.pair,paired,other) then return false,'paired block half does not match recorded placement' end
        if not found and paired then return false,'paired block space changed during placement recovery' end
      end
      if matches and count==i.before-1 or (not found or mode=='prepare' and i.fluidBefore and found and Site.fluid(actual.name)) and count==i.before then
        task.intent=nil;persist();if nav.workDone then nav.workDone() end;return true
      end
      return false,'ambiguous placement outcome; inspected block/inventory disagree with recorded intent'
    elseif i.kind=='dig' then
      if mode=='prepare' then
        local ok,why=Site.reconcileDig(i,t,config,found,actual);if not ok then return false,why end
        task.intent=nil;persist();if nav.workDone then nav.workDone() end;return true
      end
      if not found then
        if sameInventory(i.inventory,inventory()) then return false,'dig target disappeared without observed inventory change' end
        task.intent=nil;persist();if nav.workDone then nav.workDone() end;return true
      end
      if P.compare(i.block,found,actual) and sameInventory(i.inventory,inventory()) then task.intent=nil;persist();if nav.workDone then nav.workDone() end;return true end
      return false,'ambiguous dig outcome; target or inventory changed'
    end
    return false,'unknown construction intent'
  end
  function self:resume()
    if fault then return false,fault end
    if task.phase~='blocked' then return false,'task is not blocked' end
    if not tostring(task.error):find('reservation',1,true) then
      task.supportApproved=nil; task.pairResults=nil
    end
    task.phase=task.resumePhase or 'work'; task.error=nil; task.blockedCategory=nil; task.missingItem=nil; task.missingCount=nil
    return persist()
  end
  function self:step()
    if fault then return false,fault end
    if task.paused then return false,'construction paused' end
    if task.phase=='completed' then return true end
    if task.phase=='blocked' then return false,task.error end
    local pose=nav.pose
    if not pose or not pose.known or pose.pending or pose.uncertain or not U.heading(pose.heading) then return blocked('trusted position and heading required','inaccessible') end
    if scanner then
      local ok,why=scanner:recover()
      if not ok then return blocked('tool recovery failed: '..tostring(why),'hardware') end
    end
    if task.clearSite or task.type=='CLEAR' then
      if mode~='repair' or config.clearSite~=true then return blocked('site clearing is not enabled','unsupported') end
      for _,b in ipairs(task.blocks) do if not C.isAir(b.name) then return blocked('clear tasks must explicitly target air cells','unsupported') end end
    end
    if task.index>#task.blocks and not task.recheck then
      if mode=='prepare' and (pose.y<ceiling or task.moveRoute) then
        local target=task.siteAccess and task.siteAccess.entry or {x=pose.x,y=ceiling,z=pose.z}
        local ok,why=move(target);if not ok then return blocked(why,'inaccessible') end;return true
      end
      task.phase='completed'; return persist()
    end
    task.phase='work'; local b=task.blocks[task.recheck and task.deferred[task.recheck] or task.index]
    if restricted(b) then return issue(b,'inaccessible','target is in a restricted area') end
    local p,why=P.plan(b)
    if mode=='prepare' and b.substrate and p then
      p.stand={x=b.x-1,y=b.y,z=b.z};p.direction='forward';p.heading='east';p.support=nil
    end
    if mode=='prepare' and task.siteAccess and p then p=Site.approach(task.siteAccess,b,p)
    elseif mode=='prepare' and task.siteApproach then p=task.siteApproach end
    if not p then return issue(b,'unsupported',why) end
    if p.pair and restricted(p.pair) then return issue(b,'inaccessible','paired block cell is in a restricted area') end
    if restricted(p.stand) then return issue(b,'inaccessible','placement stand is in a restricted area') end
    if task.pairCheck then
      local _,_,err=pairInspection(b,p,task.pairCheck.purpose)
      if err then return blocked(err,'inaccessible') end
    end
    if task.supportCheck then
      local ok,err=supportInspection(b,p)
      if not ok then return blocked(err,'inaccessible') end
    end
    local ok,err=move(p.stand)
    if not ok then
      if tostring(err):find('reservation',1,true) then return blocked(err,'inaccessible') end
      if mode=='prepare' and not task.siteAccess and not task.intent and not awaitingMovement(err) then
        local choices={{x=-1,y=0,z=0,heading='east'},{x=1,y=0,z=0,heading='west'},
          {x=0,y=0,z=-1,heading='south'},{x=0,y=0,z=1,heading='north'},{x=0,y=-1,z=0,heading='north'}}
        local index=(task.siteApproachIndex or 0)+1;local offset=choices[index]
        if offset then
          task.siteApproachIndex=index;task.moveRoute=nil
          task.siteApproach={stand={x=b.x+offset.x,y=b.y+offset.y,z=b.z+offset.z},direction=offset.y==-1 and 'up' or 'forward',heading=offset.heading,item=p.item}
          return persist()
        end
        if scanner and b.support then
          -- Names suffice only for generic stable support. Never infer air or
          -- exact schematic state from missing/name-only scanner observations.
          scanner:invalidate()
          local blocks,why,_,category=scanner:scan(pose)
          if category=='hardware' then return blocked(why,'hardware') end
          for _,observed in ipairs(blocks or {}) do
            if observed.x==b.x and observed.y==b.y and observed.z==b.z and (b.substrate and observed.name==b.substrate or not b.substrate and Site.support(observed.name)) then
              return record(b,'correct','fresh scanner support observation',{name=observed.name})
            end
          end
          if why then err=tostring(err)..'; '..tostring(why) end
        end
      end
      return issue(b,'inaccessible',err)
    end
    ok,err=nav:face(p.heading); if not ok then return issue(b,'inaccessible',err) end
    local found,actual,inspectError=inspect(p)
    if inspectError then return issue(b,'inaccessible',inspectError) end
    ok,err=recover(b,p,found,actual); if not ok then return blocked(err,'ambiguous') end
    if mode=='prepare' and task.siteWork.stage=='seal' and (not found or not Site.fluid(actual.name)) then
      return record(b,'correct',nil,actual)
    end
    local matches,reason=matchesBlock(b,found,actual,p)
    if matches then
      if p.pair then
        local paired,other,why=pairInspection(b,p)
        if why then
          if tostring(why):find('reservation',1,true) then return blocked(why,'inaccessible') end
          return issue(b,'inaccessible',why)
        end
        local correct,pairReason=P.compare(p.pair,paired,other)
        if not correct then return issue(b,'wrong','paired block half: '..tostring(pairReason),other) end
      end
      return record(b,'correct',nil,actual)
    end
    if mode=='verify' or mode=='prepare' and task.siteWork.stage=='verify' then return record(b,found and 'wrong' or 'missing',reason,actual) end
    if task.recheck then return blocked('final connected block verification failed: '..tostring(reason),'wrong') end
    if b.substrate then return issue(b,'unsupported','required plant substrate is missing; preparation will not replace it',actual) end
    if p.observeOnly then return blocked('secondary paired block must be generated by its matching primary block','unsupported') end
    local replaceFluid=mode=='prepare' and (task.siteWork.stage=='fill' or task.siteWork.stage=='seal') and found and Site.fluid(actual.name)
    if replaceFluid and (config.protectedBlocks or {})[actual.name] then return issue(b,'unsupported','fluid block is protected',actual) end
    if found and not replaceFluid then
      if mode~='repair' and mode~='prepare' then return issue(b,'wrong','existing block differs; explicit repair required',actual) end
      local classification=C.classify(actual.name,actual.state)
      local actualFamily=C.family(actual.name)
      local allowed=mode=='prepare' and Site.drops(actual,config)
      if mode=='prepare' and not allowed or mode~='prepare' and ((config.protectedBlocks or {})[actual.name] or actualFamily=='door' or actualFamily=='bed' or C.inventory(actual.name) or actualFamily=='sign' or actualFamily=='wall_sign' or (classification~='SUPPORTED' and classification~='PARTIALLY_SUPPORTED') or actual.name:find('computercraft:',1,true)) then
        return issue(b,'unsupported','refusing to dig protected or unsupported block: '..actual.name,actual)
      end
      if p.item and not slotFor(p.item) then return missing(p.item) end
      local empty
      for s=1,16 do if not reserved[s] and t.getItemCount(s)==0 then empty=s; break end end
      if not empty then return issue(b,'inventory_full','inventory full before repair dig',actual) end
      do
        local granted,why,denied=false,'controller mutation permission required'
        if nav.workGuard then granted,why,denied=nav.workGuard(b) end
        if not granted then
          if denied then if nav.workDone then nav.workDone() end;return issue(b,'inaccessible',why,actual) end
          return blocked(why,'inaccessible')
        end
      end
      if not countAttempt('dig') then return issue(b,'attempt_limit','repair dig attempt limit reached',actual) end
      assert(t.select(empty),'cannot select free repair slot')
      if task.siteAccess and task.siteWork.stage=='clear' and (Site.support(actual.name) or actualFamily=='gravity') then
        task.report.accessChanges=task.report.accessChanges or {}
        task.report.accessChanges[task.index]=task.report.accessChanges[task.index] or {x=b.x,y=b.y,z=b.z,name=actual.name}
      end
      task.intent={kind='dig',index=task.index,block=U.copy(actual),inventory=inventory()}; persist()
      local callOk,result,detail=pcall(t['dig'..P.suffix(p.direction)])
      if not callOk then return blocked('dig hardware error: '..tostring(result),'ambiguous') end
      local now,observed,readError=inspect(p); if readError then return blocked(readError,'inaccessible') end
      ok,err=recover(b,p,now,observed); if not ok then return blocked(err,'ambiguous') end
      if now and mode~='prepare' then return blocked(detail or 'block remains after repair dig','wrong') end
      return true
    end
    if C.isAir(b.name) then return record(b,'correct') end
    if p.pair then
      local paired,_,why=pairInspection(b,p,'empty')
      if why or paired then return blocked(why or 'paired space must be empty before primary placement','unsupported') end
      for _,other in ipairs(task.blocks) do
        if other.x==p.pair.x and other.y==p.pair.y and other.z==p.pair.z and not P.compare(p.pair,true,other) then
          return blocked('blueprint paired blocks disagree','unsupported')
        end
      end
    end
    local slot,before=slotFor(p.item); if not slot then return missing(p.item) end
    if (task.attempts['place:'..task.index] or 0)>=3 then return blocked('placement attempt limit reached','attempt_limit') end
    if p.support or p.isolate then
      ok,err=supportInspection(b,p); if not ok then return blocked(err,'inaccessible') end
      found,actual,inspectError=inspect(p)
      if inspectError or found then return blocked(inspectError or 'target changed during support inspection','wrong') end
    end
    do
      local granted,why,denied=false,'controller mutation permission required'
      if nav.workGuard then granted,why,denied=nav.workGuard(b) end
      if not granted then
        if denied then if nav.workDone then nav.workDone() end;return issue(b,'inaccessible',why,actual) end
        return blocked(why,'inaccessible')
      end
    end
    -- Keep preflight observations while awaiting the mutation grant: repeating
    -- navigation would discard that grant. Invalidate them with the intent so
    -- recovery always observes the actual post-placement paired cells.
    task.pairResults=nil;task.supportApproved=nil
    assert(t.select(slot),'cannot select placement item')
    countAttempt('place'); task.intent={kind='place',index=task.index,slot=slot,item=p.item,before=before,inventory=mode=='prepare' and inventory() or nil,fluidBefore=replaceFluid or nil}; persist()
    local callOk,result,detail=pcall(t['place'..P.suffix(p.direction)])
    if not callOk then return blocked('placement hardware error: '..tostring(result),'ambiguous') end
    found,actual,inspectError=inspect(p)
    if inspectError then return blocked(inspectError,'inaccessible') end
    ok,err=recover(b,p,found,actual); if not ok then return blocked(err,'ambiguous') end
    matches,reason=matchesBlock(b,found,actual,p)
    if matches then return record(b,'correct',nil,actual) end
    if replaceFluid and found and Site.fluid(actual.name) then
      if task.attempts['place:'..task.index]<3 then return persist() end
      return issue(b,'attempt_limit',detail or 'fluid cell could not be filled',actual)
    end
    if found then return blocked('placed block did not verify: '..tostring(reason),'wrong') end
    if (task.attempts['place:'..task.index] or 0)>=3 then return blocked(detail or 'placement attempt limit reached','attempt_limit') end
    return persist()
  end
  return self
end
return M
