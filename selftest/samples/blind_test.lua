--- Проверка образца слепых пятен.
---
--- Все мутанты, которые генератор всё-таки породил, погибают: отказ
--- на этом образце обязан идти от слепоты, а не от выживших.

local t = require('luatest')
local loader = require('selftest.samples.loader')

local g = t.group('tnt_mutants_selftest.blind')

g.test_increment_adds_one = function()
    local blind = loader.load('blind.lua')

    t.assert_equals(blind.increment(5), 6)
end

g.test_halve_divides_by_two = function()
    local blind = loader.load('blind.lua')

    t.assert_equals(blind.halve(8), 4)
end

g.test_blind_functions_answer = function()
    local blind = loader.load('blind.lua')

    t.assert_equals({ blind.double(3), blind.decrement(3), blind.is_positive(3) }, { 6, 2, true })
end
