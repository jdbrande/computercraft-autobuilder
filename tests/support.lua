local M = {}
function M.codec()
  local function encode(v)
    if type(v) == 'table' then
      local out = {'{'}
      for k, x in pairs(v) do out[#out+1] = '['..encode(k)..']='..encode(x)..',' end
      return table.concat(out)..'}'
    elseif type(v) == 'string' then return string.format('%q', v)
    elseif type(v) == 'number' or type(v) == 'boolean' then return tostring(v)
    else error('not serializable') end
  end
  return {serialize=encode, unserialize=function(s)
    local f = load('return '..s, 'fixture', 't', {})
    if not f then return nil end
    local ok, value = pcall(f)
    if ok then return value end
  end}
end
function M.fs()
  local files, fault = {}, {}
  local api = {files=files, fault=fault}
  function api.exists(p) return files[p] ~= nil end
  function api.getDir(p) return p:match('^(.*)/') or '' end
  function api.makeDir() end
  function api.getSize(p) return #(files[p] or '') end
  function api.delete(p) files[p] = nil end
  function api.move(a,b)
    if fault.move == b then error('disk move fault') end
    assert(files[a] and not files[b], 'invalid move')
    files[b], files[a] = files[a], nil
  end
  function api.open(p, mode)
    if fault.open == p then return nil, 'disk full' end
    if mode == 'r' and not files[p] then return nil, 'missing' end
    local buf = mode == 'a' and (files[p] or '') or ''
    return {readAll=function() return files[p] end,
      write=function(s) buf=buf..s end,
      writeLine=function(s) buf=buf..s..'\n' end,
      close=function() if mode ~= 'r' then files[p]=buf end end}
  end
  return api
end
function M.turtle()
  local t = {fuel=100, calls=0, blocked=false}
  for _, name in ipairs({'forward','back','up','down','turnLeft','turnRight'}) do
    t[name] = function()
      t.calls=t.calls+1
      if t.blocked then return false, 'Movement obstructed' end
      if name ~= 'turnLeft' and name ~= 'turnRight' then t.fuel=t.fuel-1 end
      return true
    end
  end
  t.getFuelLevel=function() return t.fuel end
  t.getItemCount=function() return 0 end
  t.inspect=function() return true, {name='minecraft:bedrock'} end
  t.inspectUp=t.inspect; t.inspectDown=t.inspect
  return t
end
return M
