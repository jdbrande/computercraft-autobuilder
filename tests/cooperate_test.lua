test('large blueprint analysis yields without discarding queued input or network events',function()
  local old=os; local queued,events={},{{'char','x'},{'rednet_message',12,{id='reply'},'test'}}
  _G.os={queueEvent=function(...) queued[#queued+1]={...}; events[#events+1]={...} end,
    pullEventRaw=function() return table.unpack(table.remove(events,1)) end}
  local ok,err=pcall(function()
    local bp={schema=1,size={x=32,y=2,z=32},palette={{name='minecraft:stone',state={}}},runs={{id=1,count=2048}},metadata={},requirements={}}
    local B=require('autobuilder.blueprint.blueprint'); local blocks=B.blocks(bp)
    local regions=B.regions(blocks,8); eq(#blocks,2048); eq(#regions,16)
    assert(#queued>2,'large analysis never yielded')
    eq(events[1][1],'char'); eq(events[1][2],'x'); eq(events[2][1],'rednet_message')
    eq(events[2][2],12); eq(events[2][3].id,'reply')
  end)
  _G.os=old; assert(ok,err)
end)
