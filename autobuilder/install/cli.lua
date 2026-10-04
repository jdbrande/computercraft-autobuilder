local Manager=require('autobuilder.install.manager')
local M={}
function M.run(args,e,base,recovery)
  if args[1]=='fleet' then local rest={};for i=2,#args do rest[#rest+1]=args[i] end;return require('autobuilder.install.fleet').run(rest,e,base,recovery) end
  local opts={defaultBase=base,recoverySource=recovery}; local i=1
  while i<=#args do
    local arg=args[i]
    if arg=='--base' or arg=='--controller' then
      assert(args[i+1],'Missing value for '..arg)
      opts[arg=='--base' and 'base' or 'controllerId']=args[i+1]; i=i+1
    elseif arg=='--recover' then opts.recover=true
    elseif arg=='--reboot' then opts.reboot=true
    elseif arg=='update' and not opts.role and not opts.mode then opts.mode='update'
    elseif arg=='--help' or arg=='help' then
      e.print('installer <controller|worker|miner|builder|logger|courier> [controllerID] [--base URL] [--reboot]')
      e.print('update [--base URL] [--reboot] | installer --recover'); return true
    elseif not arg:match('^%-') and not opts.role and not opts.mode then opts.role=arg
    elseif opts.role and not opts.controllerId and arg:match('^%d+$') then opts.controllerId=arg
    else error('Unknown argument: '..arg,0) end
    i=i+1
  end
  local result=Manager.run(e,opts)
  if opts.reboot then e.os.reboot() end
  return result
end
return M
