"""Слепые места генератора.

Генератор читает исходник как C-подобный и Haskell-подобный разом: пара
«косая черта со звёздочкой» и пара «фигурная скобка с минусом» для него —
начало блочного комментария, где бы они ни стояли, хоть в строковом
литерале, хоть в комментарии Lua. Слепа и сама строка с парой, и всё ниже
неё до строки со своей закрывающей парой включительно, а без закрытия —
до конца файла. Так же он понимает метку начала тестового кода.

Искать пары мало: пара в последней строке ничего не прячет. Поэтому
правила применяются дважды кодом самого генератора, с теми же
исключениями файла: к строкам как есть и к строкам, в которых он пар
не видит. Строки, где мутанты есть только во втором случае, — ровно то,
что эвристика спрятала. Проверка компиляцией здесь не нужна: речь
о строках, до которых генератор не дошёл вовсе.

Аргументы: исходник, файл правил, список выражений исключения файла.

Печатает строки с парами (PAIR) и потерянные строки (LOST), номер
и текст через табуляцию.
"""

import contextlib
import io
import sys

from universalmutator import mutator

MARKERS = ('/*', '*/', '{-', '-}', '@BEGIN_TEST_CODE', '@END_TEST_CODE')
OPENERS = ('/*', '{-', '@BEGIN_TEST_CODE')


class Unmarked(str):
    """Строка, в которой генератор не находит ни одной пары."""

    def __contains__(self, item):
        return item not in MARKERS and str.__contains__(self, item)


def mutated_lines(text, rules, patterns):
    # Генератор рассказывает о своей работе в stdout; здесь это шум.
    with contextlib.redirect_stdout(io.StringIO()):
        found = mutator.mutants_regexp(text, ruleFiles=[rules], ignorePatterns=patterns, ignoreStringOnly=True)

    return {mutant[0] for mutant in found}


def main():
    source, rules, ignore = sys.argv[1:4]

    with open(source, encoding='utf-8') as file:
        lines = file.readlines()

    # Исключения генератор читает так же: построчно, без последнего знака.
    with open(ignore, encoding='utf-8') as file:
        patterns = [line[:-1] for line in file]

    seen = mutated_lines(lines, rules, patterns)
    wanted = mutated_lines([Unmarked(line) for line in lines], rules, patterns)

    for number, line in enumerate(lines, 1):
        if any(opener in line for opener in OPENERS):
            print('PAIR', number, line.strip(), sep='\t')

    for number in sorted(wanted - seen):
        print('LOST', number, lines[number - 1].strip(), sep='\t')


if __name__ == '__main__':
    main()
