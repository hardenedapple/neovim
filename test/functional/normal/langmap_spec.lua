local helpers = require('test.functional.helpers')(after_each)

local eq, neq, call = helpers.eq, helpers.neq, helpers.call
local eval, feed, clear = helpers.eval, helpers.feed, helpers.clear
local feed_command, insert, expect = helpers.feed_command, helpers.insert, helpers.expect
local curwin = helpers.curwin

describe("'langmap'", function()
  clear()
  before_each(function()
    clear()
    insert('iii www')
    feed_command('set langmap=iw,wi')
    feed('gg0')
  end)

  it("converts keys in normal mode", function()
    feed('ix')
    expect('iii ww')
    feed('whello<esc>')
    expect('iii helloww')
  end)
  it("gives characters that are mapped by :nmap.", function()
    feed_command('map i 0x')
    feed('w')
    expect('ii www')
  end)
  describe("'langnoremap' setting.", function()
    before_each(function()
      feed_command('nmapclear')
    end)
    it("'langnoremap' is by default ON", function()
      eq(eval('&langnoremap'), 1)
    end)
    it("Results of maps are not converted when 'langnoremap' ON.",
    function()
      feed_command('nmap x i')
      feed('xdl<esc>')
      expect('dliii www')
    end)
    it("applies when deciding whether to map recursively", function()
      feed_command('nmap l i', 'nmap w j')
      feed('ll')
      expect('liii www')
    end)
    it("does not stop applying 'langmap' on first character of a mapping",
    function()
      feed_command('1t1', '1t1', 'goto 1', 'nmap w j')
      feed('iiahello')
      expect([[
      iii www
      iii www
      ihelloii www]])
    end)
    it("Results of maps are converted when 'langnoremap' OFF.",
    function()
      feed_command('set nolangnoremap', 'nmap x i')
      feed('xdl')
      expect('iii ww')
    end)
  end)
  -- e.g. CTRL-W_j  ,  mj , 'j and "jp
  it('conversions are applied to keys in middle of command',
  function()
    -- Works in middle of window command
    feed('<C-w>s')
    local origwin = curwin()
    feed('<C-w>i')
    neq(curwin(), origwin)
    -- Works when setting a mark
    feed('yy3p3gg0mwgg0mi')
    eq(call('getpos', "'i"), {0, 3, 1, 0})
    eq(call('getpos', "'w"), {0, 1, 1, 0})
    feed('3dd')
    -- Works when moving to a mark
    feed("'i")
    eq(call('getpos', '.'), {0, 1, 1, 0})
    -- Works when selecting a register
    feed('qillqqwhhq')
    eq(eval('@i'), 'hh')
    eq(eval('@w'), 'll')
    feed('a<C-r>i<esc>')
    expect('illii www')
    feed('"ip')
    expect('illllii www')
    -- Works with i_CTRL-O
    feed('0a<C-O>ihi<esc>')
    expect('illllii hiwww')
  end)
  it('conversions are recorded in macros', function()
    -- XXX macros are stored by calling gotchars() when in vgetorpeek()
    --     At that point we don't know whether the characters are going to be
    --     LANGMAP_ADJUST'ed or not.
    --     We could tell vgetorpeek() this information by making all
    --     character-getting functions take another argument.
    --     Alternatively we could tell vgetorpeek() by storing information in
    --     the global state.
    feed('qiiq')
    eq(eval('@w'), 'w')
  end)
  it('conversions of mappings are recorded in macros', function()
    -- This is a reasonably easy fix, but it doesn't make sense to fix this and
    -- not translating text recorded in the macro when mappings are not
    -- applied.
    feed_command('nnoremap w l')
    feed('qxiq')
    eq(eval('@x'), 'w')
  end)
  -- These used to be exceptions, but with the new implementation they aren't
  -- any more.
  -- Because turning them back into exceptions requires modifying global state
  -- and I think they shouldn't be exceptions anyway, I'm leaving them as they
  -- are.
  it(':s///c confirmation', function()
    feed_command('set langmap=yn,ny')
    feed('qa')
    feed_command('s/i/w/gc')
    feed('yynq')
    expect('iiw www')
    feed('u@a')
    expect('iiw www')
    eq(eval('@a'), ':s/i/w/gc\rnny')
  end)
  it('ask yes/no after backwards range', function()
    feed_command('set langmap=yn,ny')
    feed('dd')
    insert([[
    hello
    there
    these
    are
    some
    lines
    ]])
    feed_command('4,2d')
    feed('y')
    expect([[
    hello
    there
    these
    are
    some
    lines
    ]])
  end)
  describe('exceptions', function()
    -- All "command characters" that 'langmap' does not apply to.
    -- These tests consist of those places where some subset of ASCII
    -- characters define certain commands, yet 'langmap' is not applied to
    -- them.
    -- n.b. I think these shouldn't be exceptions.
    --      "Fixing" them is reasonably easy, but in case others don't like the
    --      idea I'm not going to.
    it('insert-mode CTRL-G', function()
      feed_command('set langmap=jk,kj', 'd')
      insert([[
      hello
      hello
      hello]])
      expect([[
      hello
      hello
      hello]])
      feed('qa')
      feed('gg3|ahello<C-G>jx<esc>')
      feed('q')
      expect([[
      helhellolo
      helxlo
      hello]])
      eq(eval('@a'), 'gg3|ahellojx')
    end)
    it('command-line CTRL-\\', function()
      feed_command('set langmap=en,ne')
      feed(':<C-\\>e\'hello\'\r<C-B>put ="<C-E>"<CR>')
      expect([[
      iii www
      hello]])
    end)
    it('command-line CTRL-R', function()
      helpers.source([[
        let i_value = 0
        let j_value = 0
        call setreg('i', 'i_value')
        call setreg('j', 'j_value')
        set langmap=ij,ji
      ]])
      feed(':let <C-R>i=1<CR>')
      eq(eval('i_value'), 1)
      eq(eval('j_value'), 0)
    end)
    -- pending('-- More -- prompt', function()
    --   -- The 'b' 'j' 'd' 'f' commands at the -- More -- prompt
    -- end)
    it('prompt for number', function()
      feed_command('set langmap=12,21')
      helpers.source([[
        let gotten_one = 0
        function Map()
          let answer = inputlist(['a', '1.', '2.', '3.'])
          if answer == 1
            let g:gotten_one = 1
          endif
        endfunction
        nnoremap x :call Map()<CR>
      ]])
      feed('x1<CR>')
      eq(eval('gotten_one'), 1)
      feed_command('let g:gotten_one = 0')
      feed_command('call Map()')
      feed('1<CR>')
      eq(eval('gotten_one'), 1)
    end)
  end)
  it('conversions are not applied during setreg()',
  function()
    call('setreg', 'i', 'ww')
    eq(eval('@i'), 'ww')
  end)
  it('conversions not applied in insert mode', function()
    feed('aiiiwww')
    expect('iiiiwwwii www')
  end)
  it('conversions not applied in search mode', function()
    feed('/iii<cr>x')
    expect('ii www')
  end)
  it('conversions applied in cmdline mode', function()
    feed(':call append(1, "iii")<cr>')
    expect([[
    iii www
    iii]])
  end)
end)
