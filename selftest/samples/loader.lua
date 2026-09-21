--- Загрузка образца по имени.
---
--- Образцы читаются с диска при каждой проверке, а не подключаются через
--- `require`: под мутантом файл на диске подменён, а кэш `package.loaded`
--- отдал бы исходник. Путь считается от корня утилиты — самопроверка
--- запускает luatest оттуда.

local Module = {}

local DIR = 'selftest/samples/'

--- Загрузить и выполнить образец.
---@param name string имя файла образца
---@return table
function Module.load(name)
    return assert(loadfile(DIR .. name))()
end

return Module
