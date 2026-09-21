--- Проверка образца возвратов.
---
--- Ответ `flag` здесь не проверяется нарочно: его мутанты обязаны выжить.

local t = require('luatest')
local loader = require('selftest.samples.loader')

local g = t.group('tnt_mutants_selftest.returns')

g.test_pick_gives_back_its_argument = function()
    local returns = loader.load('returns.lua')

    t.assert_equals(returns.pick(7), 7)
end

g.test_nothing_gives_nil = function()
    local returns = loader.load('returns.lua')

    t.assert_equals(returns.nothing(), nil)
end
