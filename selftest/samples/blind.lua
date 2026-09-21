--- Образец самопроверки: слепые пятна генератора.
---
--- Генератор принимает за начало блочного комментария пары из C и Haskell,
--- где бы они ни стояли, хоть в строковом литерале. Ниже две такие пары:
--- первая закрывается тремя строками ниже, у второй закрытия нет вовсе.
--- Прогон обязан назвать строки с парами и отказать: код за ними остался
--- без мутантов. Сами пары в комментариях не пишутся — комментарий
--- слепит генератор точно так же.

local Module = {}

--- До первой пары: мутанты есть, проверка их убивает.
---@param value number
---@return number
function Module.increment(value)
    return value + 1
end

--- Открывающая пара Haskell в литерале: слепота до строки с закрывающей.
Module.OPEN = '{{-'

---@param value number
---@return number
function Module.double(value)
    return value * 2
end

Module.CLOSE = '-}}'

--- Между парами: мутанты снова есть.
---@param value number
---@return number
function Module.halve(value)
    return value / 2
end

--- Открывающая пара C в образце пути: закрывающей нет, слепота до конца файла.
Module.GLOB = 'var/*.xlog'

---@param value number
---@return number
function Module.decrement(value)
    return value - 1
end

---@param value number
---@return boolean
function Module.is_positive(value)
    return value > 0
end

return Module
