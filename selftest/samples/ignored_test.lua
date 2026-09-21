--- Проверка образца правил исключения.
---
--- Все мутанты, которых прогон не заглушил, погибают: отказ на этом образце
--- обязан идти от мёртвого правила, а не от выживших.

local t = require('luatest')
local loader = require('selftest.samples.loader')

local g = t.group('tnt_mutants_selftest.ignored')

g.test_steps_move_by_two = function()
    local ignored = loader.load('ignored.lua')

    t.assert_equals({ ignored.forward(5), ignored.back(5) }, { 7, 3 })
end

g.test_first_is_one = function()
    local ignored = loader.load('ignored.lua')

    t.assert_equals(ignored.first(), 1)
end
