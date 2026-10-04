local U=require('autobuilder.core.util')
test('structured receipts follow checkpoints and duplicates or failed writes emit no delivery',function()
 local state,saved={},{};local fail=false;local events={}
 local l=require('autobuilder.storage.ledger').new(state,function() if fail then return false,'disk failed' end;saved=U.copy(state);return true end,function(kind,fields)
  assert(saved.inventoryLedger.leases[fields.lease]);events[#events+1]={kind=kind,fields=U.copy(fields)}
 end)
 l:reserve('haul',{stone=3},{stone=3},{stone=3});eq(#events,1)
 l:receipt('haul',{stone=3},{stone=1},{stone=2},1);eq(#events,2);eq(events[2].fields.count,1)
 l:receipt('haul',{stone=3},{stone=1},{stone=2},1);eq(#events,2)
 fail=true;assert(not pcall(l.receipt,l,'haul',{stone=3},{stone=3},{},2));eq(#events,2)
 fail=false;l:receipt('haul',{stone=3},{stone=3},{},2);eq(events[3].fields.count,2);eq(events[3].fields.destination,'managed_inventory')
 l:release('haul');eq(events[4].kind,'stock_release')
end)

test('assignment and task transition events omit resends repeated progress and failed checkpoints',function()
 local state={};local saved;local events={};local fail=false
 local q=require('autobuilder.core.workflows').new(state,function() if fail then return false,'disk failed' end;saved=U.copy(state);return true end,function() return 1 end,7,nil,require('tests.loaded_config').load({}),function(kind,fields)
  assert(saved.automation.jobs[fields.job]);events[#events+1]={kind=kind,fields=fields}
 end)
 local j=q:submit('VERIFY',{blocks={{x=1,y=0,z=0,name='minecraft:stone',state={}}}})
 local workers={['12']={id=12,online=true,telemetry={status='idle',fuel='unlimited',capabilities={building=true}}}}
 fail=true;assert(not pcall(q.assign,q,workers));eq(#events,0);fail=false
 eq(q:assign(workers).id,j.id);eq(#events,1);eq(events[1].kind,'assignment')
 q:assign(workers);eq(#events,1)
 q:progress(12,{jobId=j.id,phase='blocked',progress=0,error='stone in way'});eq(#events,2)
 q:progress(12,{jobId=j.id,phase='blocked',progress=0,error='stone in way'});eq(#events,2)
 q:progress(12,{jobId=j.id,phase='completed',progress=1});eq(#events,3);eq(events[3].fields.status,'completed')
end)

test('worker availability logs transitions instead of heartbeats and only after save',function()
 local state={};local saved;local fail=false;local events={}
 local r=require('autobuilder.workers.workers').new(state,{workerTimeout=30},function() if fail then return false,'disk failed' end;saved=U.copy(state);return true end,function(kind,fields)
  eq(saved.workers[tostring(fields.worker)].online,kind=='worker_online');events[#events+1]=kind
 end)
 local m={type='register',sender=12,boot=1,sequence=1,payload={status='idle'}}
 assert(r:handle(m,1));eq(#events,1);m.type='heartbeat';m.sequence=2;assert(r:handle(m,2));eq(#events,1)
 fail=true;eq(r:expire(40),false);eq(#events,1);eq(state.workers['12'].online,true)
 fail=false;assert(r:expire(40));eq(#events,2);eq(events[2],'worker_offline')
 m.sequence=3;assert(r:handle(m,41));eq(#events,3)
end)
