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
test('exploration partial results and return requests use bounded report fields',function()
  local p={jobId='mine:1:1:1',phase='completed',delivered=3,held=0,exploration={result='survey_exhausted',cursor=193,clearedRouteCount=1,observations={}}}
  assert(MM.validate('mine_progress',p)); assert(MM.clean('mine_progress',p).exploration)
  assert(MM.validate('mine_return',{jobId=p.jobId}))
  p.exploration.result='magic'; assert(not MM.validate('mine_progress',p))
  p.exploration.result='quota'; for n=1,65 do p.exploration.observations[n]={x=n,y=0,z=0,name='minecraft:stone'} end
  assert(not MM.validate('mine_progress',p))
end)
