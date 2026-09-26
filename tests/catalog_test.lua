local S=require('tests.support')
local H=require('autobuilder.install.sha256')
local function fixture()
  local codec=S.codec(); codec.serializeJSON=codec.serialize; codec.unserializeJSON=codec.unserialize
  local f=S.fs(); local responses={}; local requests={}; local closed=0
  local e={fs=f,textutils=codec,http={get=function(options)
    assert(type(options)=='table' and options.redirect==false,'redirects must be disabled')
    local url=options.url; requests[#requests+1]=url
    local raw=responses[url]; if not raw then return nil,'offline' end
    local cursor=1
    return {read=function(n) local s=raw:sub(cursor,cursor+n-1); cursor=cursor+#s; if #s>0 then return s end end,
      getResponseCode=function() return 200 end, close=function() closed=closed+1 end}
  end}}
  local base='https://example.test/stream'
  local function publish(name,value)
    local raw=codec.serializeJSON(value); responses[base..'/'..name]=raw
    return {file=name,bytes=#raw,sha256=H.digest(raw)}
  end
  local function chunk(name,x)
    local data={schema=1,size={x=1,y=1,z=1},palette={{name='minecraft:stone',state={}}},runs={{id=1,count=1}},requirements={['minecraft:stone']=1},metadata={}}
    local descriptor=publish(name,data)
    descriptor.offset={x=x or 0,y=0,z=0}; descriptor.size=data.size; descriptor.blockCount=1; descriptor.requirements=data.requirements
    return descriptor,data
  end
  local entry,data=chunk('chunks/one.json')
  local p=publish('pages/one.json',{schema=1,entries={entry}}); p.count=1
  local root={schema=1,project='fixture',size={x=1,y=1,z=1},requirements={['minecraft:stone']=1},totalBlocks=1,pages={p}}
  publish('index.json',root)
  return {e=e,fs=f,codec=codec,base=base,responses=responses,requests=requests,publish=publish,chunk=chunk,entry=entry,data=data,root=root,closed=function() return closed end}
end
local function loader(f) return require('autobuilder.blueprint.catalog').new(f.e,f.base,'cache') end
local function rejected(fn,fragment)
  local ok,err=pcall(fn); assert(not ok,'expected rejection'); if fragment then assert(tostring(err):find(fragment,1,true),tostring(err)) end
end

test('stream cache resumes without HTTP and returns schematic-compatible chunks',function()
  local f=fixture(); local c=loader(f); local root=c:root(); local page=c:page(root,1)
  local path=c:chunk(page.entries[1]); local value,err=require('autobuilder.blueprint.schematic').load(f.fs,f.codec,path)
  assert(value,err); eq(value.palette[1].name,'minecraft:stone'); eq(#f.requests,3); eq(f.closed(),3)
  c=loader(f); root=c:root(); page=c:page(root,1); eq(c:chunk(page.entries[1]),path); eq(#f.requests,3)
  local n=0; for _ in pairs(f.fs.files) do n=n+1 end; eq(n,3)
end)
test('corrupt and oversized chunk downloads preserve the working cache',function()
  local f=fixture(); local c=loader(f); local path=c:chunk(f.entry); local old=f.fs.files[path]
  local second,data=f.chunk('chunks/two.json'); data.metadata.changed=true
  local digest=f.publish('chunks/two.json',data); second.bytes=digest.bytes; second.sha256=digest.sha256
  f.responses[f.base..'/chunks/two.json']='bad'
  rejected(function() c:chunk(second) end); eq(f.fs.files[path],old)
  f.responses[f.base..'/chunks/two.json']=string.rep('x',1048577)
  rejected(function() c:chunk(second) end); eq(f.fs.files[path],old)
  eq(f.closed(),3)
end)
test('chunk validation rejects dishonest requirements even with a matching digest',function()
  local f=fixture(); f.data.requirements={['minecraft:dirt']=1}
  local entry=f.publish('chunks/bad.json',f.data); entry.offset=f.entry.offset; entry.size=f.entry.size; entry.blockCount=1; entry.requirements=f.data.requirements
  rejected(function() loader(f):chunk(entry) end,'requirements')
  eq(f.fs.files['cache/chunk.json'],nil)
end)
test('catalog rejects path traversal URL injection invalid counts and dimensions',function()
  for _,path in ipairs({'../outside.json','/outside.json','https://evil.test/a','a//b','a/%2e%2e/b','a/./b','a\\b','a?x=1'}) do
    local f=fixture(); f.root.pages[1].file=path; f.publish('index.json',f.root)
    rejected(function() loader(f):root() end)
    eq(#f.requests,1)
  end
  for _,mutation in ipairs({function(r) r.schema=2 end,function(r) r.totalBlocks=2 end,function(r) r.size.x=0 end,
    function(r) r.pages[1].count=129 end,function(r) r.pages[1].bytes=1048577 end}) do
    local f=fixture(); mutation(f.root); f.publish('index.json',f.root); rejected(function() loader(f):root() end)
  end
end)
test('pages reject duplicate out-of-order and out-of-bounds layer entries',function()
  for _,mutation in ipairs({function(entries) entries[2]=entries[1] end,
      function(entries) entries[1].offset.x=1 end,function(entries) entries[1].size.y=2 end,
      function(entries) entries[1].blockCount=2 end}) do
    local f=fixture(); local entries={f.entry}; mutation(entries)
    local p=f.publish('pages/one.json',{schema=1,entries=entries}); p.count=#entries; f.root.pages={p}
    rejected(function() loader(f):page(f.root,1) end)
  end
end)
test('cache cannot mix descriptors or roots from different origins',function()
  local f=fixture(); local c=loader(f); c:root(); local path=c:chunk(f.entry)
  local second,data=f.chunk('chunks/two.json'); data.palette[1].name='minecraft:dirt'; data.requirements={['minecraft:dirt']=1}
  local descriptor=f.publish('chunks/two.json',data); descriptor.offset=second.offset; descriptor.size=second.size; descriptor.blockCount=1; descriptor.requirements=data.requirements
  c:chunk(descriptor); eq(#f.requests,3)
  local value=require('autobuilder.blueprint.schematic').load(f.fs,f.codec,path); eq(value.palette[1].name,'minecraft:dirt')
  local different=require('autobuilder.blueprint.catalog').new(f.e,'https://other.test/stream','cache')
  rejected(function() different:root() end,'offline')
  eq(loader(f):root().project,'fixture')
end)
test('failed cache promotion restores the previous working chunk',function()
  local f=fixture(); local c=loader(f); local path=c:chunk(f.entry); local old=f.fs.files[path]
  local nextEntry,data=f.chunk('chunks/two.json'); data.metadata.changed=true
  local descriptor=f.publish('chunks/two.json',data); descriptor.offset=nextEntry.offset; descriptor.size=nextEntry.size; descriptor.blockCount=1; descriptor.requirements=data.requirements
  local move=f.fs.move; local failed=false
  f.fs.move=function(a,b) if b==path and not failed then failed=true; error('promotion fault') end; return move(a,b) end
  rejected(function() c:chunk(descriptor) end,'promotion fault'); eq(f.fs.files[path],old)
end)
test('stream pages reject descending global layer order',function()
  local f=fixture(); local second=f.chunk('chunks/two.json',32)
  f.entry.size={x=32,y=1,z=1}; f.entry.blockCount=32; f.entry.requirements={['minecraft:stone']=32}
  f.root.size.x=33; f.root.totalBlocks=33; f.root.requirements={['minecraft:stone']=33}
  local p=f.publish('pages/one.json',{schema=1,entries={second,f.entry}}); p.count=2; f.root.pages={p}
  rejected(function() loader(f):page(f.root,1) end,'order')
end)
test('tampered disk caches are fetched again before use',function()
  local f=fixture(); local c=loader(f); local root=c:root(); c:page(root,1); local path=c:chunk(f.entry)
  f.fs.files['cache/root.json']='corrupted'; f.fs.files['cache/page.json']='corrupted'; f.fs.files[path]='corrupted'
  c=loader(f); root=c:root(); local page=c:page(root,1); eq(c:chunk(page.entries[1]),path)
  eq(#f.requests,6)
end)
test('HTTP errors close response handles and cannot replace cached data',function()
  local f=fixture(); local c=loader(f); local root=c:root(); c:page(root,1); local old=f.fs.files['cache/page.json']
  local other=f.publish('pages/two.json',{schema=1,entries={f.entry},revision=2}); other.count=1; root.pages={other}
  local get=f.e.http.get
  f.e.http.get=function(options) local response=get(options); response.getResponseCode=function() return 302 end; return response end
  rejected(function() c:page(root,1) end,'HTTP status 302'); eq(f.fs.files['cache/page.json'],old); eq(f.closed(),3)
end)
