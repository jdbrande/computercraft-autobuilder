local H=require('autobuilder.workers.health')
local S=require('tests.install_support')
local SHA=require('autobuilder.install.sha256')
local function hardware()
  local t={};for _,name in ipairs({'forward','up','down','turnLeft','turnRight','place','dig'}) do t[name]=function() error('physical probe forbidden') end end
  t.getEquippedLeft=function() return {name='minecraft:diamond_pickaxe'} end
  t.getEquippedRight=function() return {name='computercraft:wireless_modem_advanced'} end
  return {turtle=t,term={isColor=function() return true end},peripheral={getNames=function() return {'left','right'} end,getType=function(n) return n=='left' and 'geoScanner' or 'modem' end}}
end
local function managed()
  local e=hardware();e.fs=S.fs();e.textutils=S.codec()
  local body='return {}';local hash=SHA.digest(body)
  local m={schema=1,project='autobuilder',version='0.29.0',baseUrl='https://example.com/repo',roles={},files={}}
  for role in pairs(require('autobuilder.install.manifest').roles) do m.roles[role]={runtime=role=='controller' and 'controller' or 'worker'} end
  for _,path in ipairs({'autobuilder/main.lua','startup.lua'}) do
    m.files[#m.files+1]={path=path,url=m.baseUrl..'/'..path,sha256=hash,bytes=#body,version=m.version,roles={'worker'}}
    e.fs.files['/'..path]=body
  end
  local r={schema=1,project='autobuilder',role='worker',version=m.version,files={}}
  for _,f in ipairs(m.files) do r.files[f.path]={sha256=f.sha256,bytes=f.bytes} end
  e.fs.files['/manifest.json']=e.textutils.serializeJSON(m)
  e.fs.files['/autobuilder/.installation.json']=e.textutils.serializeJSON(r)
  return e,r
end
test('health observes tools APIs and scanner without physical probes and refreshes repaired equipment',function()
  local e=hardware();local h=H.observe(e,{status='unmanaged'});eq(h.kind,'advanced');eq(h.left,'minecraft:diamond_pickaxe');eq(h.scanner,true)
  eq(H.eligible({health=h},{type='MINE'}),true)
  e.turtle.getEquippedLeft=function() return nil end;h=H.observe(e,{status='unmanaged'});eq(h.left,'none');eq(H.eligible({health=h},{type='MINE'}),false)
  e.turtle.getEquippedLeft=function() return {name='minecraft:diamond_pickaxe'} end;eq(H.eligible({health=H.observe(e,{status='unmanaged'})},{type='MINE'}),true)
  eq(H.software(e).status,'unavailable')
end)
test('health preserves unknown legacy APIs and recovery eligibility but rejects known role failures',function()
  eq(H.eligible({}, {type='MINE'}),true)
  local e=hardware();e.turtle.getEquippedLeft=nil;e.turtle.getEquippedRight=nil
  local h=H.observe(e,{status='unmanaged'});eq(h.left,'unknown');eq(H.eligible({health=h},{type='MINE'}),true)
  eq(H.eligible({health=h},{type='CRAFT'}),false)
  e.turtle.craft=function() error('probe forbidden') end;h=H.observe(e,{status='modified',reason='changed main'})
  eq(H.eligible({health=h},{type='CRAFT'}),false);eq(H.eligible({health=h},{type='RETURN_HOME'}),true)
  eq(H.eligible({health=h},{type='REFUEL'}),true);eq(H.eligible({health=h},{type='RESCUE'}),true)
end)
test('software verifies complete managed manifest and permits custom startup and local settings',function()
  local e=managed();eq(H.software(e).status,'verified');eq(H.software(e).version,'0.29.0')
  e.fs.files['/startup.lua']='custom startup';e.fs.files['/autobuilder/settings.lua']='local';eq(H.software(e).status,'verified')
  e.fs.files['/autobuilder/main.lua']='changed';eq(H.software(e).status,'modified')
  e.fs.files['/autobuilder/main.lua']=nil;eq(H.software(e).status,'modified')
  e.fs.files['/autobuilder/.installation.json']=nil;eq(H.software(e).status,'unmanaged')
end)
test('software rejects truncated receipts malformed metadata and missing manifests',function()
  local e,r=managed();r.files['autobuilder/main.lua']=nil;e.fs.files['/autobuilder/.installation.json']=e.textutils.serializeJSON(r)
  eq(H.software(e).status,'modified')
  e.fs.files['/manifest.json']=nil;eq(H.software(e).status,'unavailable')
end)
test('health wire schema is bounded and clean drops cyclic unknown fields',function()
  local h=H.observe(hardware(),{status='verified',version='0.29.0'});eq(H.valid(h),true)
  h.extra=h;h.software.extra=h;local c=H.clean(h);eq(c.extra,nil);eq(c.software.extra,nil);eq(H.valid(c),true)
  h.left={};eq(H.valid(h),false);h.left='none';h.movement='yes';eq(H.valid(h),false)
  h.movement=true;h.peripherals={};for i=1,33 do h.peripherals[i]={name=tostring(i),type='modem'} end;eq(H.valid(h),false)
end)

test('stationary crafting needs its table API while mining distinguishes pickaxes from axes',function()
  local e=hardware();e.term.isColor=function() return false end
  e.turtle.getEquippedLeft=function() return {name='minecraft:diamond_axe'} end
  local h=H.observe(e,{status='unmanaged'});eq(h.kind,'normal');eq(H.eligible({health=h},{type='MINE'}),false);eq(H.eligible({health=h},{type='HARVEST'}),true)
  e.turtle={craft=function() error('physical probe forbidden') end};h=H.observe(e,{status='unmanaged'})
  eq(H.eligible({health=h},{type='CRAFT'}),true);eq(H.eligible({health=h},{type='TRANSPORT'}),false)
end)
