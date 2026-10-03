local U=require('autobuilder.core.util')
local MM=require('autobuilder.core.mining_messages')
local function assignment()
  return {jobId='mine:1:1:1',item='minecraft:cobblestone',quantity=64,exploration={version=1,groupId='acquire:1',sectorId='0,0,0',
    bounds={min={x=0,y=0,z=0},max={x=7,y=2,z=7}},envelope={min={x=-8,y=-3,z=-8},max={x=15,y=5,z=15}},
    depot={x=-2,y=0,z=0},entry={x=0,y=0,z=0},exitRoute={{x=-1,y=0,z=0}},route={{x=0,y=0,z=0}},cursor=1,protectedAreas={}}}
end
test('exploration protocol retains owned geometry and refuses malformed routes',function()
  local p=assignment(); assert(MM.validate('mine_assign',p)); local clean=MM.clean('mine_assign',p)
  assert(clean.exploration,'exploration must survive message cleaning'); eq(clean.exploration.groupId,'acquire:1')
  clean.exploration.route[1].x=3; eq(p.exploration.route[1].x,0)
  p.exploration.route[1].x=8; assert(not MM.validate('mine_assign',p))
  p=assignment(); p.exploration.route[3]={x=1,y=0,z=0}; assert(not MM.validate('mine_assign',p))
  p=assignment(); p.exploration.route[1]=p.exploration; assert(not MM.validate('mine_assign',p))
  p=assignment(); p.exploration.version=2; assert(not MM.validate('mine_assign',p))
end)
test('network rejects malformed exploration fields before copying or deduplication',function()
  local N=require('autobuilder.core.network').new({}, {protocol='test'},1,1)
  local p=assignment()
  local cases={}
  for _,kind in ipairs({'mine_ack','mine_resume','mine_return'}) do
    cases[#cases+1]={kind=kind,payload={jobId=p.jobId,exploration={}}}
  end
  for _,quantity in ipairs({false,'64',{},0/0}) do local a=assignment(); a.quantity=quantity; cases[#cases+1]={kind='mine_assign',payload=a} end
  local a=assignment(); a.quantity=nil; cases[#cases+1]={kind='mine_assign',payload=a}
  for _,c in ipairs(cases) do
    local ok,result=pcall(N.accept,N,2,{version=1,sender=2,boot=1,sequence=1,id='2:1:1',type=c.kind,payload=c.payload},'test',0)
    assert(ok,'malformed message threw'); eq(result,nil); eq(N:cacheSize(),0)
  end
end)
test('exploration partial results and return requests use bounded report fields',function()
  local p={jobId='mine:1:1:1',phase='completed',delivered=3,held=0,exploration={result='survey_exhausted',cursor=193,clearedRouteCount=1,observations={}}}
  assert(MM.validate('mine_progress',p)); assert(MM.clean('mine_progress',p).exploration)
  assert(MM.validate('mine_return',{jobId=p.jobId}))
  p.exploration.result='magic'; assert(not MM.validate('mine_progress',p))
  p.exploration.result='quota'; for n=1,65 do p.exploration.observations[n]={x=n,y=0,z=0,name='minecraft:stone'} end
  assert(not MM.validate('mine_progress',p))
end)


test('initial depot cargo receipts are optional bounded and cannot exceed physical delivery',function()
  local p={jobId='mine:1:1:1',phase='completed',delivered=2,held=0,
    exploration={result='quota',cursor=1,clearedRouteCount=0,observations={},initialDelivered=2}}
  assert(MM.validate('mine_progress',p));eq(MM.clean('mine_progress',p).exploration.initialDelivered,2)
  for _,value in ipairs({-1,1.5,3,'2',1000001}) do p.exploration.initialDelivered=value;assert(not MM.validate('mine_progress',p)) end
  p.exploration.initialDelivered=nil;assert(MM.validate('mine_progress',p))
end)
