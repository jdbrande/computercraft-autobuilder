local U=require('autobuilder.core.util')
local P=require('autobuilder.core.pathfinding')
local F=require('autobuilder.factory.factory')
local M={}
-- One bounded access operation lives in the existing region checkpoint and uses
-- its ordinary job sequence, cargo settlement and physical owner.
function M.discover(work,plan,region,height,report)
  work.accessProofs=work.accessProofs or {};work.accessPending=work.accessPending or {}
  for _,d in ipairs(report.entries or {}) do if d.status=='inaccessible' and U.position(d) then
    local key=P.key(d);local known=work.accessProofs[key]~=nil
    for _,target in ipairs(work.accessPending) do if P.key(target)==key then known=true end end
    if not known and plan:access(region,d,height) then
      work.accessPending[#work.accessPending+1]={x=d.x,y=d.y,z=d.z}
    end
  end end
end
function M.valid(work,plan,region,height)
  if work.accessProofs==nil and work.accessPending==nil and work.access==nil then return true end
  if type(work.accessProofs)~='table' or type(work.accessPending)~='table' or #work.accessPending>64 then return false end
  local n=0
  for key,proof in pairs(work.accessProofs) do
    n=n+1
    if n>64 or type(proof)~='table' or not U.position(proof.target) or key~=P.key(proof.target)
      or not ({verified=true,failed=true})[proof.status] or not plan:access(region,proof.target,height) then return false end
  end
  local pendingCount=0
  for index in pairs(work.accessPending) do
    if not U.integer(index) or index<1 or index>64 then return false end;pendingCount=pendingCount+1
  end
  for index=1,pendingCount do if not plan:access(region,work.accessPending[index],height) then return false end end
  if work.accessRetired~=nil then
    if type(work.accessRetired)~='table' or #work.accessRetired>1024 then return false end
    for _,id in ipairs(work.accessRetired) do if not U.shortString(id,160) then return false end end
  end
  local a=work.access
  if a then
    if type(a)~='table' or type(a.route)~='table' then return false end
    local route,mask=plan:access(region,a.route.target,height)
    if not route or not F.equal(route,a.route) or not F.equal(mask,a.restoreMask)
      or not ({open=true,fill=true,verify=true,restore_fill=true,restore_verify=true,done=true})[a.phase]
      or not U.integer(a.cursor) or a.cursor<1 or a.cursor>#route.cells+1
      or type(a.changes)~='table' or type(a.failed)~='boolean' or type(a.verified)~='boolean'
      or a.restoreRetries~=nil and (not U.integer(a.restoreRetries) or a.restoreRetries<0 or a.restoreRetries>3)
      or type(a.jobs)~='table' or #a.jobs>1024 then return false end
    for _,id in ipairs(a.jobs) do if not U.shortString(id,160) then return false end end
    for key,cell in pairs(a.changes) do
      if not U.position(cell) or key~=P.key(cell) or not mask[key] then return false end
    end
  end
  return true
end
function M.payload(work,plan,region,height)
  if not work.access then
    local target=table.remove(work.accessPending or {},1)
    if not target then return nil end
    local route,mask=plan:access(region,target,height);assert(route,'saved access target no longer matches geometry')
    work.access={route=route,restoreMask=mask,phase='open',cursor=1,changes={},failed=false,verified=false,jobs={}}
  end
  local a=work.access
  if a.phase=='done' then
    work.accessProofs[P.key(a.route.target)]={target=U.copy(a.route.target),status=not a.failed and a.verified and 'verified' or 'failed'}
    work.accessRetired=a.jobs;work.access=nil;return nil
  end
  local cells,stage={},a.phase
  if stage=='open' then
    for i=a.cursor,math.min(#a.route.cells,a.cursor+7) do cells[#cells+1]=U.copy(a.route.cells[i]) end
    stage='clear'
  elseif stage=='fill' or stage=='verify' then cells={U.copy(a.route.target)}
  else
    while a.cursor<=#a.route.cells do
      local p=a.route.cells[#a.route.cells-a.cursor+1]
      if a.changes[P.key(p)] then cells={U.copy(p)};break end
      a.cursor=a.cursor+1
    end
    if #cells==0 then a.phase='done';return nil end
    stage=a.phase=='restore_fill' and 'fill' or 'verify'
  end
  for _,b in ipairs(cells) do b.name=stage=='clear' and 'minecraft:air' or work.fill;b.state={};b.support=stage~='clear' or nil end
  local bounds=U.copy(a.route.bounds or plan:region(region).bounds);bounds.max.y=height
  return {type='PREPARE_REGION',blocks=cells,bounds=bounds,clearanceY=height,siteAccess=U.copy(a.route),
    siteWork={identity=plan.identity,region=region,stage=stage}}
end
function M.consume(work,report,failed)
  local a=assert(work.access)
  if a.phase=='open' then
    for _,p in pairs(report.accessChanges or {}) do
      if a.restoreMask[P.key(p)] then a.changes[P.key(p)]={x=p.x,y=p.y,z=p.z} end
    end
    if failed>0 then a.failed=true;a.phase='restore_fill';a.cursor=1
    else
      local total=0;for _,n in pairs(report.counts) do total=total+n end
      a.cursor=a.cursor+total
      if a.cursor>#a.route.cells then a.phase='fill';a.cursor=1 end
    end
  elseif a.phase=='fill' then
    if failed>0 then a.failed=true;a.phase='restore_fill' else a.phase='verify' end
  elseif a.phase=='verify' then
    a.verified=failed==0;a.failed=a.failed or failed>0;a.phase='restore_fill';a.cursor=1
  elseif a.phase=='restore_fill' then
    -- Never close the next cell while restoration of this one is unproven.
    if failed>0 then
      a.restoreRetries=(a.restoreRetries or 0)+1
      if a.restoreRetries>=3 then work.status='blocked';a.failed=true end
    else a.phase='restore_verify' end
  elseif a.phase=='restore_verify' then
    if failed>0 then
      a.restoreRetries=(a.restoreRetries or 0)+1;a.phase='restore_fill'
      if a.restoreRetries>=3 then work.status='blocked';a.failed=true end
    else a.cursor=a.cursor+1;a.phase='restore_fill';a.restoreRetries=0 end
  else error('unexpected access receipt phase') end
end
function M.recover(plan,region,height,jobs,fill,epoch)
  local route,mask=plan:access(region,jobs[1].siteAccess.target,height)
  assert(route,'cannot recover foundation access geometry')
  local a={route=route,restoreMask=mask,phase='restore_fill',cursor=1,changes={},failed=true,verified=false,jobs={}}
  for _,j in ipairs(jobs) do
    assert(j.status=='completed' and F.equal(j.siteAccess,route) and j.report,'missing foundation access receipt; retain ownership')
    a.jobs[#a.jobs+1]=j.id
    for _,cell in pairs(j.report.accessChanges or {}) do
      if mask[P.key(cell)] then a.changes[P.key(cell)]={x=cell.x,y=cell.y,z=cell.z} end
    end
    local phase,cursor=j.key:match(':access:([a-z_]+):(%d+)$')
    if phase=='restore_verify' and j.report.counts.correct==1 then a.cursor=math.max(a.cursor,tonumber(cursor)+1) end
  end
  -- Re-establish the original ground before the fresh census can start normal
  -- preparation. Old target receipts never become new-epoch support proof.
  return {status='working',stage='clear',cursor=1,sequence=1,epoch=epoch,defects={},failed=0,fill=fill,
    access=a,accessPending={},accessProofs={}}
end
function M.covered(work,b)
  local proof=work.accessProofs and work.accessProofs[P.key(b)]
  return b.support and proof and proof.status=='verified'
end
return M
