--- Проверка образца пропущенных строк.

local t = require('luatest')
local loader = require('selftest.samples.loader')

local g = t.group('tnt_mutants_selftest.skipped')

g.test_fail_names_the_reason = function()
    local skipped = loader.load('skipped.lua')

    t.assert_error_msg_contains('отказал: причина', skipped.fail, 'причина')
end

g.test_is_even_tells_parity = function()
    local skipped = loader.load('skipped.lua')

    t.assert_equals({ skipped.is_even(4), skipped.is_even(3) }, { true, false })
end
