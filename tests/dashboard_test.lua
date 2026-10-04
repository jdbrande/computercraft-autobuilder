local U=require('autobuilder.core.util')
test('dashboard projects and worker details are read only and distinguish unknown stock and verification',function()
 local D=require('autobuilder.ui.dashboard')
 local state={id=7,workers={['12']={id=12,online=false,lastSeen=90,telemetry={status='blocked',fuel=20,task='job',position={known=true,x=1,y=2,z=3},inventory={used=4,slots=16}}}},
  jobs={job={id='job',type='MINE',workerId=12,status='blocked',quantity=8,progress={delivered=3},trafficWait={since=80,target={x=2,y=2,z=3},reason='worker occupies destination',blocker=13,remedy='Inspect worker 13'}}},
  automation={projects={castle={name='castle',phase='verifying',completed=4,total=10,priority=70,report={counts={correct=3}}}},jobs={},requests={}}}
 local before=U.copy(state);local forecasts={castle={items={['minecraft:stone']={required=10,placed=4,deficit=nil}}}}
 local lines=D.lines(state,forecasts,100,{networkPending=2,operatorPending=1,networkDropped=3,operatorDropped=0})
 local text=table.concat(lines,'\n');assert(text:find('castle',1,true));assert(text:find('Verified 3/10',1,true));assert(text:find('deficit~ unknown',1,true));assert(text:find('Inspect worker 13',1,true))
 text=table.concat(D.lines(state,forecasts,100,{},12),'\n');assert(text:find('OFFLINE',1,true));assert(text:find('Heartbeat 10s',1,true));assert(text:find('3/8',1,true));assert(text:find('Cargo 4/16',1,true))
 assert(require('autobuilder.factory.factory').equal(before,state))
end)

test('monitor redraw is bounded paged and recovers from resize detach and reconnect',function()
 local attached=true;local writes=0;local width,height=24,6;local screen={};local y
 local monitor={getSize=function() if not attached then error('detached') end;return width,height end,
  setTextScale=function() end,setCursorPos=function(_,row) y=row end,clear=function() screen={} end,
  write=function(s) assert(attached);assert(#s<=width);writes=writes+1;screen[y]=s end}
 local e={peripheral={wrap=function(n) eq(n,'monitor_0');return attached and monitor or nil end}}
 local m=require('autobuilder.ui.monitor').new(e,{name='monitor_0',scale=.5,interval=1})
 local lines={'Fleet','first','second','third','fourth','fifth','sixth'}
 assert(m:draw(lines,0));local first=writes;assert(m:draw(lines,.5));eq(writes,first)
 assert(m:draw(lines,1));eq(writes,first);m:touch();assert(m:draw(lines,2));assert(writes>first);assert(table.concat(screen,'\n'):find('Page 2/2',1,true))
 attached=false;local ok,why=m:draw(lines,3);eq(ok,false);assert(why)
 local retry,reason=m:draw(lines,3.1);eq(retry,false);eq(reason,why)
 attached=true;width=16;height=8;assert(m:draw(lines,4));assert(table.concat(screen,'\n'):find('Page 1/1',1,true))
 local disabled=require('autobuilder.ui.monitor').new({peripheral={wrap=function() error('disabled monitor touched hardware') end}},{name='',interval=1})
 assert(disabled:draw(lines,0))
end)

test('dashboard shows current reservation wait alongside the retained route failure',function()
 local state={id=7,workers={},jobs={},automation={projects={},requests={},jobs={j={id='j',status='blocked',workerId=12,
  error='movement reservation pending',lastRouteFailure='movement reservation pending: no bounded traffic detour',
  trafficWait={since=90,target={x=1,y=2,z=0},reason='worker occupies destination',blocker=13,remedy='Inspect worker 13; restore its connection'}}}}}
 local text=table.concat(require('autobuilder.ui.dashboard').lines(state,{},100,{}),'\n')
 assert(text:find('worker occupies destination',1,true));assert(text:find('Inspect worker 13',1,true))
 assert(text:find('Last route failure: movement reservation pending: no bounded traffic detour',1,true));assert(text:find('passing bay',1,true))
end)
