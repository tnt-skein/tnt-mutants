"""Сверка правил исключения со строками файла.

Аргументы: исходник, список выражений его правил (по одному на строку),
список номеров этих правил в общем списке (строка в строку) и путь
общего списка — для строки отчёта.

Совпадение ищется так же, как его ищет генератор: `re.search` по строке
вместе с её переводом строки, выражение — без последнего знака строки
списка.

Печатает через табуляцию вид (DEAD или WIDE), номер правила в общем
списке и готовую строку отчёта с местом правила — `путь:строка`.
"""

import re
import sys


def main():
    source, ignore, numbers_file, listed = sys.argv[1:5]

    with open(source, encoding='utf-8') as file:
        lines = file.readlines()

    with open(ignore, encoding='utf-8') as file:
        patterns = [line[:-1] for line in file]

    with open(numbers_file, encoding='utf-8') as file:
        numbers = [line.strip() for line in file]

    if len(patterns) != len(numbers):
        sys.exit(f'выражений {len(patterns)}, а номеров правил {len(numbers)}: списки разошлись')

    for number, pattern in zip(numbers, patterns):
        try:
            expression = re.compile(pattern)
        except Exception as error:  # noqa: BLE001 — любая ошибка разбора значит одно: правило мёртвое
            print('DEAD', number, f'     {listed}:{number}: {pattern} — не разбирается как выражение Python: {error}', sep='\t')
            continue

        matched = [str(index) for index, line in enumerate(lines, 1) if expression.search(line)]

        if not matched:
            print('DEAD', number, f'     {listed}:{number}: {pattern}', sep='\t')
        elif len(matched) > 1:
            print('WIDE', number, f'     {listed}:{number}: {pattern} — строк {len(matched)}: {", ".join(matched)}', sep='\t')


if __name__ == '__main__':
    main()
