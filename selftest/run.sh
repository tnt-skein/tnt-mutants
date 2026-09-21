#!/usr/bin/env bash
# Самопроверка tnt-mutants на файлах-образцах.
#
# Утилита не кричит, когда ломается, — она молча перестаёт смотреть, и цифра
# остаётся зелёной: глушитель правил прячет любой возврат одного слова, пара
# «косая черта со звёздочкой» в литерале слепит остаток файла, неизвестный
# аргумент luatest делает каждого мутанта убитым, файл без мутантов проходит
# с нулевым кодом, набор, идущий почти весь предел мутанта, делает убитым
# любого выжившего. Каждое такое пятно живёт неделями, потому что заметить
# его нечем.
#
# Здесь утилита гоняется по образцам из selftest/samples, у которых итог
# известен заранее, и итог сверяется: где мутанты обязаны быть и где их
# быть не должно, какие выжившие обязаны попасть в отчёт, на чём прогон
# обязан отказать. Правка bin/tnt-mutants или rules/lua.rules, ослепившая
# утилиту, валит эту проверку.
#
# Запуск: tnt-mutants selftest (или make selftest в каталоге утилиты).
# Нужны tarantool и luatest в .rocks утилиты (make setup).

set -euo pipefail

TOOL_ROOT=$(cd "$(dirname "$0")/.." && pwd -P)
cd "${TOOL_ROOT}"

GATE='bin/tnt-mutants'
SAMPLES='selftest/samples'
WORK='var/selftest'
MUTANTS_WORK='var/mutants'
STEPS=11

if [ ! -x .rocks/bin/luatest ]; then
    echo 'Самопроверке нужен luatest в .rocks утилиты: выполните «make setup».' >&2
    exit 1
fi

# Живой прогон в этом каталоге держит замок, и каждый запуск утилиты ниже
# отказал бы «прогон уже идёт» — самопроверка показала бы ложные поломки.
holder=$(head -n 1 "${MUTANTS_WORK}/lock" 2>/dev/null || true)

if [[ "${holder}" =~ ^[0-9]+$ ]] && kill -0 "${holder}" 2>/dev/null; then
    echo "Мутационный прогон уже идёт (${MUTANTS_WORK}/lock): самопроверку запустите после него." >&2
    exit 1
fi

rm -rf "${WORK}"
mkdir -p "${WORK}"

step=0
checks=0
problems=()

# Заголовок шага: что проверяется и сколько осталось.
begin() {
    step=$((step + 1))
    echo
    echo "[${step}/${STEPS}] $1"
}

# Прогон утилиты: вывод идёт на экран и в журнал шага, код запоминается.
#
#   gate <имя журнала> [ПЕРЕМЕННАЯ=значение ...] <файл ...>
#
# Проверки образцов гоняются все разом: они быстрые, а свой набор
# у каждого образца пришлось бы задавать отдельно.
gate() {
    log="${WORK}/$1.log"
    shift

    set +e
    env MUTANTS_SUITE="${SAMPLES}/" "$@" 2>&1 | tee "${log}" | sed 's/^/    │ /'
    local codes=("${PIPESTATUS[@]}")
    set -e

    status="${codes[0]}"
    echo "    └ код выхода ${status}"
}

# Итог одной сверки.
expect() {
    local what="$1"
    shift

    checks=$((checks + 1))

    if "$@"; then
        echo "      ✓ ${what}"
    else
        echo "      ✗ ${what}"
        problems+=("[${step}] ${what}")
    fi
}

# Сверки над журналом последнего прогона.
code_is() { [ "${status}" -eq "$1" ]; }
said() { grep -qF -- "$1" "${log}"; }
silent() { ! grep -qF -- "$1" "${log}"; }
said_times() { [ "$(grep -cF -- "$1" "${log}")" -eq "$2" ]; }

# Сколько мутантов в списке утилиты (строки «── <мутант>»); без файла сверка не проходит.
listed_times() { [ "$(grep -c '^── ' "$1" 2>/dev/null || true)" = "$2" ]; }

# Номер строки образца, где стоит ровно этот текст (без отступа).
line_of() {
    local number
    number=$(awk -v text="$2" '{ line = $0; sub(/^[ \t]+/, "", line) } line "" == text "" { print NR; exit }' "$1")

    if [ -z "${number}" ]; then
        echo "В образце $1 нет строки «$2»: образец и самопроверка разошлись." >&2
        exit 1
    fi

    echo "${number}"
}

# Имя журнала по пути файла — так же, как его называет утилита.
slug_of() {
    echo "$1" | tr '/' '@'
}

# Журнал генератора по образцу: там видно, какие строки он мутировал.
gen_log_of() {
    echo "${MUTANTS_WORK}/gen-$(slug_of "$1").log"
}

# Породил ли генератор годного мутанта в строке — с этой заменой.
# Годный отмечен «...VALID»; у негодного там «...INVALID».
mutated() {
    awk -v prefix="PROCESSING MUTANT: $2:" -v replacement="$3" '
        index($0, prefix) == 1 && index($0, " ==> ") && index($0, replacement) && index($0, "...VALID") { found = 1 }
        END { exit !found }
    ' "$1"
}

# Не пытался ли генератор мутировать строку вовсе — ни годно, ни негодно.
untouched() {
    awk -v prefix="PROCESSING MUTANT: $2:" '
        index($0, prefix) == 1 { found = 1 }
        END { exit found }
    ' "$1"
}

# ─── 1. Образцы вне обычного прогона ────────────────────────────────────────

begin 'Образцы не попадают в обычный прогон; несуществующий файл — отказ'

# Относительно первого коммита изменено всё дерево: так видно, что
# настройки утилиты не подпускают образцы к обычному прогону.
first_commit=$(git rev-list --max-parents=0 HEAD 2>/dev/null | tail -1) || first_commit=''
listed="${WORK}/list.txt"

if [ -n "${first_commit}" ]; then
    MUTANTS_BASE="${first_commit}" "${GATE}" --list > "${listed}"
else
    # Репозиторий без коммитов: изменено всё, что есть.
    "${GATE}" --list > "${listed}"
fi

echo "    │ прогон по изменённому нашёл файлов: $(grep -c '' "${listed}" || true)"

expect 'образцов среди найденного нет' bash -c "! grep -q '^${SAMPLES}/' '${listed}'"

gate missing "${GATE}" "${SAMPLES}/missing.lua"
expect 'явно названный несуществующий файл — отказ' code_is 1
expect 'отказ называет файл' said "Файл не найден: ${SAMPLES}/missing.lua"

# ─── 2. Возвраты ────────────────────────────────────────────────────────────

begin 'Возвраты: развилки мутируются, таблица модуля и пустой возврат — нет'

returns="${SAMPLES}/returns.lua"
returns_log=$(gen_log_of "${returns}")
true_line=$(line_of "${returns}" 'return true')
value_line=$(line_of "${returns}" 'return value')
module_line=$(line_of "${returns}" 'return Module')
nil_line=$(line_of "${returns}" 'return nil')
gate returns "${GATE}" "${returns}"

expect 'выжившие валят прогон' code_is 1
expect 'мутантов три, убит один' said 'мутантов: 3, убито: 33.3%'
expect 'мутант на «return true» → false' mutated "${returns_log}" "${true_line}" 'return false'
expect 'мутант на «return true» → nil' mutated "${returns_log}" "${true_line}" 'return nil'
expect 'мутант на «return value» → nil' mutated "${returns_log}" "${value_line}" 'return nil'
expect 'на «return Module» мутантов нет' untouched "${returns_log}" "${module_line}"
expect 'на «return nil» мутантов нет' untouched "${returns_log}" "${nil_line}"
expect 'выжившие показаны' said 'выжили:'
expect 'в отчёте выживший «return false»' said '>     return false'
expect 'итог называет образец' said "${returns} — 33.3% при пороге 100%"

# ─── 3. Слепые пятна ────────────────────────────────────────────────────────

begin 'Пары комментариев в литералах: предупреждение с номером строки и отказ'

blind="${SAMPLES}/blind.lua"
open_line=$(line_of "${blind}" "Module.OPEN = '{{-'")
glob_line=$(line_of "${blind}" "Module.GLOB = 'var/*.xlog'")
double_line=$(line_of "${blind}" 'return value * 2')
positive_line=$(line_of "${blind}" 'return value > 0')
halve_line=$(line_of "${blind}" 'return value / 2')
blind_lines=$(grep -c '' "${blind}")
gate blind "${GATE}" "${blind}"

expect 'слепота валит прогон' code_is 1
expect 'названа строка с парой Haskell' said "строка ${open_line}: Module.OPEN"
expect 'названа строка с парой C' said "строка ${glob_line}: Module.GLOB"
expect 'потеряна строка между парами' said "строка ${double_line}: return value * 2"
expect 'потеряна строка до конца файла' said "строка ${positive_line}: return value > 0"
expect 'видимые мутанты убиты' said 'убито: 100.0%'
expect 'грубая сверка: мутанты кончились рано' said "мутанты кончились на строке ${halve_line} из ${blind_lines}"
expect 'итог называет слепое пятно' said "${blind} — слепое пятно генератора"

# ─── 4. Пропущенные строки ──────────────────────────────────────────────────

begin 'Многострочный error(..., 0): пропущенная генератором строка названа'

skipped="${SAMPLES}/skipped.lua"
level_line=$(line_of "${skipped}" '0')
gate skipped "${GATE}" "${skipped}"

expect 'прогон проходит' code_is 0
expect 'пропуск посчитан' said 'генератор пропустил строк: 1'
expect 'названа строка с уровнем' said "строка ${level_line}: 0"
expect 'остальные мутанты убиты' said 'убито: 100.0%'
expect 'пределом времени не убит никто' silent 'убито пределом времени'

# ─── 5. Ноль мутантов ───────────────────────────────────────────────────────

begin 'Ноль мутантов: отказ, если файла нет в списке'

empty="${SAMPLES}/empty.lua"
gate empty "${GATE}" "${empty}"

expect 'ноль мутантов валит прогон' code_is 1
expect 'итог называет файл' said "${empty} — мутантов не получилось"

# Список с образцом без мутантов и с образцом, у которого мутанты есть:
# первого список пропускает, запись о втором обязана уйти.
allowed="${WORK}/allowed.empty"
printf '# Список для самопроверки.\n%s\n%s\n' "${empty}" "${skipped}" > "${allowed}"
gate allowed MUTANTS_EMPTY_LIST="${allowed}" "${GATE}" "${empty}" "${skipped}"

expect 'файл из списка принят' said 'мутантов нет — файл записан в'
expect 'база гоняется раз на набор, а не на каждый файл' said_times '── база:' 1
expect 'пустой файл из списка не в отказах' silent "${empty} — мутантов не получилось"
expect 'лишняя запись валит прогон' code_is 1
expect 'итог называет лишнюю запись' said "${skipped} — лишняя запись в ${allowed}"

gate missing_empty MUTANTS_EMPTY_LIST="${WORK}/missing.empty" "${GATE}" "${empty}"

expect 'названный явно несуществующий список — отказ' code_is 1
expect 'отказ называет список' said "Список файлов без мутантов ${WORK}/missing.empty не найден."

# ─── 6. Сломанная строка запуска ────────────────────────────────────────────

begin 'Сломанная строка запуска: прогон падает на проверке базы'

gate launch MUTANTS_LUATEST_FLAGS='--shuffle none --failure' "${GATE}" "${returns}"

expect 'отказ' code_is 1
expect 'отказ назван отказом запуска' said 'строка запуска проверок сломана'
expect 'виден ответ luatest' said 'Unknown option: --failure'
expect 'до мутантов не дошло' silent 'мутантов:'

# ─── 7. Отказ запуска под мутантами ─────────────────────────────────────────

begin 'Отказ запуска под мутантами: ошибка проверки, а не убитые мутанты'

# Набор проходит на базе и уносит свой каталог: под мутантами luatest
# отказывает «Path ... does not exist» ещё до первой проверки. Так
# выглядит поломка, которую проверка базы поймать не может.
vanishing="${WORK}/vanishing"
mkdir -p "${vanishing}"
cat > "${vanishing}/vanishing_test.lua" <<LUA
local fio = require('fio')
local t = require('luatest')

local g = t.group('tnt_mutants_selftest.vanishing')

g.test_takes_its_directory_away = function()
    t.assert(fio.rmtree('${vanishing}'))
end
LUA

gate vanishing MUTANTS_SUITE="${vanishing}/" "${GATE}" "${returns}"

expect 'отказ' code_is 1
expect 'названы мутанты без проверок' said 'проверки не запустились на мутантах: 3'
expect 'виден ответ luatest' said 'does not exist'
expect 'итог называет отказ запуска' said "${returns} — проверки не запустились на мутантах: 3"

# ─── 8. Сломанное правило ───────────────────────────────────────────────────

begin 'Сломанное правило в наборе правил: прогон останавливается'

broken="${WORK}/broken.rules"
cp rules/lua.rules "${broken}"
printf '%s\n' '(?<!unclosed ==> DO_NOT_MUTATE' >> "${broken}"
gate broken MUTANTS_RULES="${broken}" "${GATE}" "${returns}"

expect 'отказ' code_is 1
expect 'названо отброшенное правило' said 'генератор отбросил правила'
expect 'до мутантов не дошло' silent 'мутантов:'

# ─── 9. Долгая база ─────────────────────────────────────────────────────────

begin 'Набор дольше половины предела: явный срок — отказ до мутантов, срок по умолчанию — подъём'

gate fraction MUTANTS_TIMEOUT=2.5 "${GATE}" "${skipped}"

expect 'дробный срок — отказ' code_is 1
expect 'отказ называет срок' said 'MUTANTS_TIMEOUT — целое число секунд больше нуля, а задано «2.5»'

# Проверка спит только на базе: под мутантом анализатор задаёт
# CURRENT_MUTANT_SOURCE, и долгий набор не повторяется на каждом мутанте.
slow="${WORK}/slow"
mkdir -p "${slow}"
cat > "${slow}/slow_test.lua" <<'LUA'
local fiber = require('fiber')
local t = require('luatest')

local g = t.group('tnt_mutants_selftest.slow')

g.test_baseline_takes_time = function()
    if os.getenv('CURRENT_MUTANT_SOURCE') == nil then
        fiber.sleep(tonumber(os.getenv('MUTANTS_SELFTEST_SLEEP')))
    end
end
LUA

# Набор образцов и долгая проверка: мутантов убивают проверки образца.
# Сон в 1,2 с при пределе в 2 с — база дольше половины предела при любой
# нагрузке: нагрузка базу только удлиняет.
slow_suite="${SAMPLES}/ ${slow}/"
gate slow_explicit MUTANTS_SUITE="${slow_suite}" MUTANTS_SELFTEST_SLEEP=1.2 MUTANTS_TIMEOUT=3 "${GATE}" "${skipped}"

expect 'отказ' code_is 1
expect 'отказ называет набор' said "Набор ${slow_suite} идёт"
expect 'отказ называет предел' said 'при пределе 2 с (MUTANTS_TIMEOUT=3): мутанты будут убиты по времени'
expect 'отказ называет, какой срок задать' said 'Задайте MUTANTS_TIMEOUT не меньше'
expect 'до генерации мутантов не дошло' silent 'VALID MUTANTS'

gate slow_default MUTANTS_SUITE="${slow_suite}" MUTANTS_SELFTEST_SLEEP=1.2 MUTANTS_DEFAULT_TIMEOUT=3 "${GATE}" "${skipped}"

expect 'прогон проходит' code_is 0
expect 'подъём предела назван' said 'предел мутанта поднят с 2 до'
expect 'мутанты прогнаны и убиты' said 'убито: 100.0%'

# База, не уложившаяся в своё ожидание, — отказ, а не долгий предел.
gate slow_cap MUTANTS_SUITE="${slow_suite}" MUTANTS_SELFTEST_SLEEP=1.2 MUTANTS_DEFAULT_TIMEOUT=2 MUTANTS_BASELINE_LIMIT=1 "${GATE}" "${skipped}"

expect 'отказ' code_is 1
expect 'отказ назван' said 'не уложился в 1 с на исходном коде'
expect 'до генерации мутантов не дошло' silent 'VALID MUTANTS'

# ─── 10. Зависание под мутантом ─────────────────────────────────────────────

begin 'Зависание под мутантом: убит пределом, и число таких названо'

# Под мутантом проверка не кончается — так выглядит мутант, сломавший
# условие выхода; базу она проходит сразу.
hang="${WORK}/hang"
mkdir -p "${hang}"
cat > "${hang}/hang_test.lua" <<'LUA'
local fiber = require('fiber')
local t = require('luatest')

local g = t.group('tnt_mutants_selftest.hang')

g.test_hangs_under_mutant = function()
    if os.getenv('CURRENT_MUTANT_SOURCE') ~= nil then
        fiber.sleep(3600)
    end
end
LUA

# Срок по умолчанию, а не явный: под нагрузкой утилита поднимет предел,
# а не откажет, и сверки останутся верными.
gate hang MUTANTS_SUITE="${hang}/" MUTANTS_DEFAULT_TIMEOUT=2 "${GATE}" "${returns}"

expect 'прогон проходит' code_is 0
expect 'зависшие мутанты убиты' said 'мутантов: 3, убито: 100.0%'
expect 'число убитых пределом названо' said 'убито пределом времени: 3'
expect 'список убитых пределом сохранён со всеми тремя' listed_times "${MUTANTS_WORK}/timeout-$(slug_of "${returns}").log" 3

# ─── 11. Правила исключения ─────────────────────────────────────────────────

begin 'Правила исключения: мёртвое и неразборчивое — отказ с номером правила, широкое — названо'

ignored="${SAMPLES}/ignored.lua"
ignored_log=$(gen_log_of "${ignored}")
first_line=$(line_of "${ignored}" 'return 1')
step_lines=$(grep -n 'local step = 2$' "${ignored}" | cut -d: -f1)
step_shown=$(printf '%s\n' "${step_lines}" | paste -sd, - | sed 's/,/, /g')

# Список правил пишется строка за строкой: номера строк в нём сверяются
# с отчётом утилиты. Правило чужого файла не совпадает ни с чем в образце,
# но судить его прогон по образцу не должен.
rules="${WORK}/ignored.ignore"
{
    echo '# Список правил для самопроверки.'
    printf '%s %s\n' "${ignored}" '^\s*return 1$'          # 2: живое
    printf '%s %s\n' "${ignored}" '^\s*local step = 2$'    # 3: широкое
    printf '%s %s\n' "${ignored}" '^\s*return value \* 2$' # 4: мёртвое
    printf '%s %s\n' "${ignored}" '^\s*return (value$'     # 5: не разбирается
    printf '%s %s\n' "${returns}" '^\s*return nothing$'    # 6: чужое
} > "${rules}"

gate ignored MUTANTS_IGNORE="${rules}" "${GATE}" "${ignored}"

expect 'мёртвые правила валят прогон' code_is 1
expect 'мёртвых правил два' said 'мёртвые: 2'
expect 'мёртвое правило названо местом в списке' said "${rules}:4: ^\s*return value \* 2\$"
expect 'неразборчивое правило названо с причиной' said "${rules}:5: ^\s*return (value\$ — не разбирается как выражение Python"
expect 'правило чужого файла не судится' silent "${rules}:6:"
expect 'живое правило не названо' silent "${rules}:2:"
expect 'широкое правило названо со строками' said "${rules}:3: ^\s*local step = 2\$ — строк 2: ${step_shown}"
expect 'живое правило глушит свою строку' untouched "${ignored_log}" "${first_line}"
while IFS= read -r step_line; do
    expect "широкое правило глушит строку ${step_line}" untouched "${ignored_log}" "${step_line}"
done <<< "${step_lines}"
expect 'анализ дошёл до конца' said 'мутантов: 5, убито: 100.0%'
expect 'итог называет мёртвые правила с номерами' said "${ignored} — мёртвые правила исключения: 2 (строки ${rules}: 4, 5)"

# Без мёртвых правил широкое только названо: прогон проходит.
clean="${WORK}/clean.ignore"
awk 'NR != 4 && NR != 5' "${rules}" > "${clean}"
gate clean MUTANTS_IGNORE="${clean}" "${GATE}" "${ignored}"

expect 'прогон проходит' code_is 0
expect 'широкое правило названо' said "${clean}:3: ^\s*local step = 2\$ — строк 2: ${step_shown}"
expect 'о мёртвых правилах ни слова' silent 'мёртвые'

gate missing_rules MUTANTS_IGNORE="${WORK}/missing.ignore" "${GATE}" "${ignored}"

expect 'названный явно несуществующий список правил — отказ' code_is 1
expect 'отказ называет список' said "Список правил исключения ${WORK}/missing.ignore не найден."

# ─── Итог ───────────────────────────────────────────────────────────────────

echo

if [ "${#problems[@]}" -gt 0 ]; then
    echo "Самопроверка tnt-mutants не пройдена: ${#problems[@]} из ${checks}." >&2
    for problem in "${problems[@]}"; do
        echo "  ${problem}" >&2
    done
    echo "Журналы прогонов: ${WORK}/" >&2
    exit 1
fi

echo "Самопроверка tnt-mutants пройдена: сверок ${checks}."
