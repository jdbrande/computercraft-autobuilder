local U=require('autobuilder.core.util')
local Manifest=require('autobuilder.install.manifest')
local I=require('autobuilder.install.io')
local M={}
local statuses={verified=true,modified=true,unmanaged=true,unavailable=true}
local kinds={normal=true,advanced=true,unknown=true}
local function short(s) return U.shortString(s,160) end
local function version(s) return type(s)=='string' and #s<=30 and s:match('^%d+%.%d+%.%d+$')~=nil end
local function read(e,path)
  if e.fs.getSize then assert(e.fs.getSize(path)<=1048576,'metadata exceeds size limit') end
  local body=I.read(e.fs,path);assert(#body<=1048576,'file exceeds size limit');return body
end
function M.software(e)
  if not e.fs then return {status='unavailable',reason='installation metadata API unavailable'} end
  local result={status='unavailable'}
  local ok,err=pcall(function()
    if not e.fs.exists(Manifest.receipt) then result.status='unmanaged';return end
    assert(e.textutils and e.textutils.unserializeJSON,'installation metadata codec unavailable')
    local r=e.textutils.unserializeJSON(read(e,Manifest.receipt))
    assert(type(r)=='table' and r.schema==1 and r.project=='autobuilder' and Manifest.roles[r.role] and type(r.files)=='table' and version(r.version),'invalid installation receipt')
    result.version=r.version
    local m=e.textutils.unserializeJSON(read(e,'/manifest.json'));Manifest.validate(m)
    result.status='modified'
    assert(r.version==m.version,'receipt and manifest versions differ')
    local count=0
    for path,f in pairs(r.files) do
      count=count+1;assert(count<=256 and Manifest.path(path) and type(f)=='table','invalid receipt files')
    end
    local selected=Manifest.select(m,r.role);local paths={}
    for _,f in ipairs(selected) do paths[f.path]=true end
    for _,path in ipairs(Manifest.required) do assert(paths[path],'manifest missing required file: '..path) end
    for path in pairs(r.files) do assert(paths[path],'receipt file omitted from manifest: '..path) end
    for _,f in ipairs(selected) do
      -- The installer explicitly preserves operator-owned root startup scripts.
      if f.path~='startup.lua' then
        local prior=r.files[f.path]
        assert(prior and prior.sha256==f.sha256 and prior.bytes==f.bytes,'receipt mismatch: '..f.path)
        I.verify(read(e,'/'..f.path),f)
      end
      require('autobuilder.core.cooperate').every(1024)
    end
    result.status='verified'
  end)
  if not ok then result.reason=tostring(err):sub(1,160) end
  return result
end
local function equipped(t,side)
  local f=t['getEquipped'..side];if type(f)~='function' then return 'unknown' end
  local ok,item=pcall(f);if not ok then return 'unknown' end
  if item==nil then return 'none' end
  return type(item)=='table' and short(item.name) and item.name or 'unknown'
end
function M.observe(e,software)
  local t=e.turtle or {};local h={kind='unknown',left=equipped(t,'Left'),right=equipped(t,'Right'),
    movement=true,placing=type(t.place)=='function',digging=type(t.dig)=='function',crafting=type(t.craft)=='function',scanner=false,peripherals={},software=software}
  for _,name in ipairs({'forward','up','down','turnLeft','turnRight'}) do if type(t[name])~='function' then h.movement=false end end
  local term=e.term
  if term and type(term.native)=='function' then local ok,native=pcall(term.native);if ok and type(native)=='table' then term=native end end
  if term and type(term.isColor)=='function' then local ok,color=pcall(term.isColor);if ok and type(color)=='boolean' then h.kind=color and 'advanced' or 'normal' end end
  if e.peripheral and type(e.peripheral.getNames)=='function' and type(e.peripheral.getType)=='function' then
    local ok,names=pcall(e.peripheral.getNames)
    if ok and type(names)=='table' then
      for _,name in ipairs(names) do
        if #h.peripherals>=32 then break end
        if short(name) then
          local good,kind=pcall(e.peripheral.getType,name)
          if good and short(kind) then h.peripherals[#h.peripherals+1]={name=name,type=kind};if kind=='geoScanner' or kind=='blockScanner' then h.scanner=true end end
        end
      end
    end
  end
  return h
end
function M.valid(h)
  if type(h)~='table' or not kinds[h.kind] or not short(h.left) or not short(h.right) then return false end
  for _,key in ipairs({'movement','placing','digging','crafting','scanner'}) do if type(h[key])~='boolean' then return false end end
  local s=h.software
  if type(s)~='table' or not statuses[s.status] or s.version~=nil and not version(s.version) or s.reason~=nil and not short(s.reason) then return false end
  if s.status=='verified' and not s.version then return false end
  if type(h.peripherals)~='table' then return false end
  local count=0
  for k,p in pairs(h.peripherals) do
    count=count+1
    if count>32 or not U.integer(k) or k<1 or k>32 or type(p)~='table' or not short(p.name) or not short(p.type) then return false end
  end
  return count==#h.peripherals
end
function M.clean(h)
  if not h then return nil end
  local c={kind=h.kind,left=h.left,right=h.right,movement=h.movement,placing=h.placing,digging=h.digging,crafting=h.crafting,scanner=h.scanner,
    software={status=h.software.status,version=h.software.version,reason=h.software.reason},peripherals={}}
  for _,p in ipairs(h.peripherals) do c.peripherals[#c.peripherals+1]={name=p.name,type=p.type} end
  return c
end
function M.eligible(t,job)
  local h=t and t.health;if not h then return true end
  local kind=job.type
  if kind=='RETURN_HOME' or kind=='REFUEL' or kind=='RESCUE' then return true end
  if h.software.status=='modified' or h.software.status=='unavailable' then return false,'software '..h.software.status..': '..(h.software.reason or 'check installation') end
  if kind=='CRAFT' then return h.crafting,'crafting table upgrade unavailable' end
  if not h.movement then return false,'movement API unavailable' end
  if (kind=='BUILD' or kind=='REPAIR' or kind=='PREPARE_REGION') and not h.placing then return false,'placement API unavailable' end
  if (kind=='FARM' or kind=='HARVEST') and job.farm then
    local ok,spec=pcall(require('autobuilder.resources.renewables').forFarm,job.farm,{})
    if ok and spec and spec.seed and not h.placing then return false,'placement API unavailable for replanting' end
  end
  local mining=kind=='MINE';local digging=mining or kind=='REPAIR' or kind=='HARVEST' or kind=='FARM' or kind=='CLEAR' or kind=='PREPARE_REGION' or kind=='PREPARE_SITE'
  if digging then
    if not h.digging then return false,'digging API unavailable' end
    if h.left~='unknown' and h.right~='unknown' then
      local function tool(name) return name:match('_pickaxe$') or not mining and (name:match('_axe$') or name:match('_shovel$')) end
      if not tool(h.left) and not tool(h.right) then return false,mining and 'mining pickaxe unavailable' or 'digging tool unavailable' end
    end
  end
  return true
end
function M.describe(h)
  if not h then return 'Hardware/software unknown (legacy)' end
  return (h.software.version or '?')..' '..h.software.status..(h.software.reason and ': '..h.software.reason or '')
end
return M
