local M={}
function M.upcoming(task,turtle,config)
  if not task or not ({BUILD=true,REPAIR=true})[task.type] or task.paused or task.phase=='completed'
    or task.intent or task.moveRoute or task.supportCheck or task.pairCheck or task.supplyRequest or task.fuelRecovery or not config.supply or config.supply.inventory=='' then return nil end
  if task.phase=='blocked' and not task.missingItem and not tostring(task.error):find('movement reservation pending',1,true) then return nil end
  local R=require('autobuilder.core.reports');local item,remaining
  for index=task.index or 1,#(task.blocks or {}) do
    local name=R.materialItem(task.blocks[index])
    if name and not item then item=name;remaining=0 end
    if name==item and item then remaining=remaining+1 end
  end
  if not item then return nil end
  local held,capacity=0,0;local reserved=require('autobuilder.workers.resupply').reserved(config)
  for slot=1,16 do if not reserved[slot] then
    local value=turtle.getItemDetail(slot)
    if not value then capacity=capacity+1 -- Seed empty stacks conservatively, as resupply.slot does.
    elseif value.name==item and not value.nbt then
      held=held+value.count;capacity=capacity+(turtle.getItemSpace and turtle.getItemSpace(slot) or 0)
    end
  end end
  local batch=config.supply.batch or 64
  if capacity<=0 or held==0 or held>=remaining or held>math.max(1,math.floor(batch/4)) then return nil end
  return {item=item,remaining=remaining,held=held,count=math.min(batch,remaining-held,capacity)}
end
-- Read-only allocation for visibility. This does not create inventory promises;
-- actual dispatch and transfer still require the existing physical ledger.
function M.build(state,stock,scopes)
  local leases=(state.inventoryLedger or {}).leases or {}
  local reserved,pool={},{}
  for _,lease in pairs(leases) do if lease.status=='held' then
    for item,n in pairs(lease.inputs or {}) do reserved[item]=(reserved[item] or 0)+n-((lease.withdrawn or {})[item] or 0) end
  end end
  if stock then for item,n in pairs(stock) do pool[item]=math.max(0,n-(reserved[item] or 0)) end end
  local ordered={};for _,scope in ipairs(scopes) do ordered[#ordered+1]=scope end
  table.sort(ordered,function(a,b) return a.project.name<b.project.name end)
  local result,seenJobs,seenCargo={}, {}, {}
  for _,scope in ipairs(ordered) do
    local p=scope.project;local f={name=p.name,phase=p.phase,items={},materialUnknown=false};result[p.name]=f
    for item,n in pairs(p.requirements or {}) do
      f.items[item]={required=n,placed=0,held=0,inTransit=0,reserved=0,mining=0,harvesting=0,crafting=0,processing=0,
        sharedPhysical=stock and (stock[item] or 0),sharedReserved=reserved[item] or 0}
    end
    local current={};for _,id in ipairs(p.jobs or {}) do current[id]=true end
    for id,j in pairs(scope.work) do
      if current[id] then
        local materials=j.materials or j.report and j.report.materials
        if materials then
          for item,n in pairs(materials) do if f.items[item] then f.items[item].placed=f.items[item].placed+n end end
        elseif (j.progress or 0)>0 then f.materialUnknown=true end
      end
      if not seenJobs[id] and not j.cancelled and j.status~='completed' and not j.physicalComplete then
        seenJobs[id]=true
        local lease=leases[id]
        if lease and lease.status=='held' then
          for item,n in pairs(lease.inputs or {}) do if f.items[item] then
            f.items[item].reserved=f.items[item].reserved+n-((lease.withdrawn or {})[item] or 0)
          end end
          for item,n in pairs(lease.transit or {}) do if f.items[item] then f.items[item].inTransit=f.items[item].inTransit+n end end
        end
        local item=j.item;local row=item and f.items[item]
        local kind=j.type=='CRAFT' and 'crafting' or j.type=='SMELT' and 'processing'
          or (j.type=='HARVEST' or j.type=='FARM') and 'harvesting' or (not j.type or j.type=='MINE') and 'mining'
        local w=j.workerId and (state.workers or {})[tostring(j.workerId)]
        local t=w and w.online and w.telemetry
        if not (t and t.task==id and t.cargo and not t.cargo.error) then t=nil end
        local held=0
        if (current[id] or kind=='harvesting') and j.workerId and not seenCargo[j.workerId] then
          seenCargo[j.workerId]=true
          if t then
            for name,n in pairs(t.cargo.items or {}) do if f.items[name] and (current[id] or name==item) then
              f.items[name].held=f.items[name].held+n
              if name==item then held=n end
            end end
          else f.materialUnknown=true end
        end
        if row and kind then
          local delivered=kind=='mining' and type(j.progress)=='table' and (j.progress.delivered or 0)
            or lease and (lease.delivered or {})[item] or 0
          if kind=='harvesting' then
            delivered=t and t.harvestDelivered
            if delivered==nil then f.materialUnknown=true end
          end
          if delivered~=nil then
            row[kind]=row[kind]+math.max(0,(j.quantity or (j.stockOutputs or {})[item] or 0)-delivered-held)
          end
        end
      end
    end
    local supply=(state.automation or {}).supply
    if supply and f.items[supply.item] then
      for _,j in pairs(scope.work) do if j.workerId==supply.owner and j.status~='completed' then
        -- The offered amount can already be partly in worker inventory. Do not
        -- count a stale staging quantity again as confirmed in-transit cargo.
        f.materialUnknown=true
      end end
    end
    for item,row in pairs(f.items) do
      row.placed=math.min(row.required,row.placed)
      local need=math.max(0,row.required-row.placed-row.held-row.inTransit-row.mining-row.harvesting-row.crafting-row.processing)
      if stock then
        row.stored=math.min(need,pool[item] or 0);pool[item]=(pool[item] or 0)-row.stored
        row.deficit=need-row.stored
      end
    end
  end
  return result
end
function M.describe(f)
  local lines={f.name..': material forecast (shared stock allocated by project name; estimates do not reserve items)'}
  if f.materialUnknown then lines[#lines+1]='Some material progress or owned cargo is unknown; deficits are estimates.' end
  local items={};for item in pairs(f.items) do items[#items+1]=item end;table.sort(items)
  local function v(n) return n==nil and 'unknown' or tostring(n) end
  for _,item in ipairs(items) do
    local r=f.items[item]
    lines[#lines+1]=item..' required='..r.required..' correct='..r.placed..' stored='..v(r.stored)..' reserved='..r.reserved
      ..' transit='..r.inTransit..' held='..r.held..' mining~='..r.mining..' harvesting~='..r.harvesting
      ..' crafting~='..r.crafting..' processing~='..r.processing..' deficit~='..v(r.deficit)
  end
  return lines
end
return M
