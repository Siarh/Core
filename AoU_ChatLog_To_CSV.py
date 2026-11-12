#!/usr/bin/env python3
# Rebuilds AoU Meter CSV export copied from the in-game chat.
import argparse
import csv
import re
import sys
from pathlib import Path

MARKER = re.compile(r'AOUCSV\|([^|\s]+)\|(\d+)\|(\d+)\|(.*)$')

def main():
    ap = argparse.ArgumentParser(description='Преобразует экспорт /aou rec export из чата в CSV.')
    ap.add_argument('chat_log', help='Текстовый файл с копией строк AOUCSV из игрового чата')
    ap.add_argument('-o', '--output', help='Имя CSV-файла (по умолчанию AoU_combat_log.csv)')
    args = ap.parse_args()
    source = Path(args.chat_log)
    text = source.read_text(encoding='utf-8-sig', errors='replace')
    chunks = {}
    expected = {}
    found = 0
    for line in text.splitlines():
        m = MARKER.search(line)
        if not m:
            continue
        kind, part_s, total_s, payload = m.groups()
        if kind in ('BEGIN', 'END'):
            continue
        part, total = int(part_s), int(total_s)
        chunks.setdefault(kind, {})[part] = payload
        expected[kind] = total
        found += 1
    if 'H' not in chunks:
        raise SystemExit('Не найден экспорт AOUCSV. Скопируйте строки AOUCSV из чата после /aou rec export.')

    def assemble(kind):
        parts = chunks[kind]
        total = expected[kind]
        missing = [i for i in range(1, total + 1) if i not in parts]
        if missing:
            raise SystemExit(f'Неполная строка {kind}: отсутствуют части {missing}')
        return ''.join(parts[i] for i in range(1, total + 1))

    header = assemble('H').split('|')
    rows = []
    record_kinds = [k for k in chunks if re.fullmatch(r'R\d+', k)]
    record_kinds.sort(key=lambda x: int(x[1:]))
    for kind in record_kinds:
        row = assemble(kind).split('|')
        if len(row) < len(header):
            row.extend([''] * (len(header) - len(row)))
        elif len(row) > len(header):
            row = row[:len(header)]
        rows.append(row)

    output = Path(args.output) if args.output else Path('AoU_combat_log.csv')
    with output.open('w', encoding='utf-8-sig', newline='') as f:
        writer = csv.writer(f, delimiter=';', lineterminator='\n')
        writer.writerow(header)
        writer.writerows(rows)
    print(f'Готово: {output.resolve()}')
    print(f'Записей: {len(rows)}; строк экспорта обработано: {found}')
    print('Если записей меньше ожидаемого, повторите экспорт и скопируйте все строки AOUCSV без пропусков.')

if __name__ == '__main__':
    main()
