#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""One-command local DPScope -> Ollama/Qwen companion.

Accepts the OCR text file containing AOUCSV chat lines, reconstructs and validates
all export chunks, runs the existing offline profile converter and calculator,
then sends only the compact, ID-free report to local Ollama.
"""
from __future__ import annotations

import argparse
import csv
import json
import os
import re
import sys
from pathlib import Path
from typing import Any

import aou_event_history_to_profile as importer
import aou_formula_calculator as calculator
import aou_ai_assistant as assistant


AOU_LINE_RE = re.compile(
    r"AOUCSV\s*\|\s*([^|\s]+)\s*\|\s*(\d+)\s*\|\s*(\d+)\s*\|(.*)$"
)
RECORD_KEY_RE = re.compile(r"^R(\d+)$")
REQUIRED_COLUMNS = {"kind", "M", "R", "U", "L", "observed_amount"}


def parse_aoucsv_text(source: str) -> tuple[list[str], list[list[str]], dict[str, int]]:
    """Reassemble AOUCSV packets; fail closed on missing or conflicting chunks."""
    chunks: dict[str, dict[int, str]] = {}
    totals: dict[str, int] = {}
    expected_event_records: int | None = None
    malformed: list[int] = []
    matched = 0

    for line_no, line in enumerate(source.splitlines(), 1):
        if "AOUCSV" not in line:
            continue
        # END is a control marker without chunk counters/payload.
        if re.search(r"AOUCSV\s*\|\s*END(?:\s|$)", line):
            continue
        match = AOU_LINE_RE.search(line)
        if not match:
            malformed.append(line_no)
            continue
        kind, part_text, total_text, payload = match.groups()
        part, total = int(part_text), int(total_text)
        matched += 1

        if kind == "BEGIN":
            if payload.strip().lower() == "events":
                if expected_event_records is not None and expected_event_records != total:
                    raise ValueError(
                        "Страницы относятся к разным выгрузкам: в AOUCSV BEGIN указано "
                        f"{expected_event_records} и {total} событий."
                    )
                expected_event_records = total
            continue
        if kind == "END":
            continue
        if total < 1 or part < 1 or part > total:
            raise ValueError(
                f"Некорректная часть экспорта в строке {line_no}: {kind} {part}/{total}."
            )
        if kind in totals and totals[kind] != total:
            raise ValueError(
                f"Для блока {kind} OCR дал разные размеры: {totals[kind]} и {total} частей."
            )
        totals[kind] = total
        block = chunks.setdefault(kind, {})
        if part in block and block[part] != payload:
            raise ValueError(
                f"Часть {kind} №{part} распознана по-разному. "
                "Исправь эту строку в OCR-TXT и повтори запуск."
            )
        block[part] = payload

    if malformed:
        lines = ", ".join(str(value) for value in malformed[:12])
        more = " ..." if len(malformed) > 12 else ""
        raise ValueError(
            "Найдены строки с AOUCSV, но их формат не распознан "
            f"(строки: {lines}{more}). Проверь OCR: метка, разделители и номера частей."
        )
    if matched == 0:
        raise ValueError("В TXT не найдены строки AOUCSV. Нужен текст из /aou eventfile.")

    def assemble(kind: str) -> str:
        if kind not in chunks:
            raise ValueError(f"Не найден обязательный блок {kind}.")
        total = totals[kind]
        missing = [str(i) for i in range(1, total + 1) if i not in chunks[kind]]
        if missing:
            raise ValueError(
                f"В блоке {kind} отсутствуют части: {', '.join(missing)} из {total}. "
                "Повтори OCR пропущенных строк; неполный журнал анализировать нельзя."
            )
        return "".join(chunks[kind][i] for i in range(1, total + 1))

    header = assemble("H").split("|")
    if len(header) != len(set(header)):
        raise ValueError("В заголовке CSV обнаружены повторяющиеся имена столбцов.")
    missing_columns = sorted(REQUIRED_COLUMNS - set(header))
    if missing_columns:
        raise ValueError(
            "В заголовке экспорта отсутствуют столбцы: " + ", ".join(missing_columns)
        )

    record_keys = sorted(
        (key for key in chunks if RECORD_KEY_RE.match(key)),
        key=lambda value: int(RECORD_KEY_RE.match(value).group(1)),  # type: ignore[union-attr]
    )
    if not record_keys:
        raise ValueError("Блоки журнала R1, R2, ... не найдены.")
    if expected_event_records is not None:
        actual_ids = sorted(int(RECORD_KEY_RE.match(key).group(1)) for key in record_keys)
        expected_ids = list(range(1, expected_event_records + 1))
        missing_ids = sorted(set(expected_ids) - set(actual_ids))
        extra_ids = sorted(set(actual_ids) - set(expected_ids))
        if missing_ids or extra_ids:
            preview = ", ".join(str(value) for value in missing_ids[:20])
            suffix = " ..." if len(missing_ids) > 20 else ""
            details = (
                f"Не хватает записей: {preview}{suffix}."
                if missing_ids else ""
            )
            if extra_ids:
                details += " Лишние номера записей: " + ", ".join(map(str, extra_ids[:20])) + "."
            raise ValueError(
                f"Собраны не все страницы выгрузки: найдено {len(actual_ids)} из "
                f"{expected_event_records} событий. {details} Добавь OCR-строки всех страниц."
            )

    rows: list[list[str]] = []
    for key in record_keys:
        values = assemble(key).split("|")
        if len(values) > len(header):
            raise ValueError(
                f"В записи {key} полей больше, чем в заголовке. "
                "Возможна ошибка OCR или лишний символ |."
            )
        values.extend([""] * (len(header) - len(values)))
        rows.append(values)

    return header, rows, {
        "matched_lines": matched,
        "data_records": len(rows),
        "data_blocks": len(record_keys),
        "export_chunks": sum(totals.values()),
    }


def write_csv(path: Path, header: list[str], rows: list[list[str]]) -> None:
    with path.open("w", encoding="utf-8-sig", newline="") as target:
        writer = csv.writer(
            target, delimiter=";", quotechar='"', quoting=csv.QUOTE_ALL,
            lineterminator="\r\n",
        )
        writer.writerow(header)
        writer.writerows(rows)


def write_json(path: Path, value: Any) -> None:
    path.write_text(
        json.dumps(value, ensure_ascii=False, indent=2, allow_nan=False) + "\n",
        encoding="utf-8",
    )


def run_pipeline(args: argparse.Namespace) -> int:
    if not args.input:
        raise ValueError("Укажи OCR-TXT с AOUCSV после параметров команды.")
    source_path: Path = args.input
    if not source_path.is_file():
        raise ValueError(f"Файл не найден: {source_path}")

    selected_model = None
    if not args.prepare_only:
        selected_model = assistant.check_ollama(args.ollama_url, args.model)

    try:
        raw_text = source_path.read_text(encoding=args.encoding)
    except UnicodeError as exc:
        raise ValueError(
            f"Не удалось прочитать {source_path} как {args.encoding}. "
            "Сохрани OCR-результат в UTF-8 или укажи --encoding cp1251."
        ) from exc

    header, rows, export_info = parse_aoucsv_text(raw_text)
    out_dir = args.out_dir or source_path.parent / (source_path.stem + "_DPScope")
    out_dir.mkdir(parents=True, exist_ok=True)

    output_names = ["AoU_combat_log.csv", "aou_event_profile.json", "aou_report.json"]
    if not args.prepare_only:
        output_names.extend(["aou_ai_payload.json", "aou_ai_advice.md"])
    conflicts = [name for name in output_names if (out_dir / name).exists()]
    if conflicts and not args.overwrite:
        raise FileExistsError(
            "Выходные файлы уже существуют: " + ", ".join(conflicts) +
            f". Укажи другой --out-dir или добавь --overwrite."
        )

    csv_path = out_dir / "AoU_combat_log.csv"
    profile_path = out_dir / "aou_event_profile.json"
    report_path = out_dir / "aou_report.json"
    write_csv(csv_path, header, rows)

    dict_rows = [dict(zip(header, row)) for row in rows]
    profile = importer.build_profile(
        dict_rows, max(0, min(500, args.budget)), args.resolve_coefficient
    )
    report = calculator.calculate_profile(profile)
    write_json(profile_path, profile)
    write_json(report_path, report)

    print(f"Экспорт восстановлен: {export_info['data_records']} записей из {export_info['matched_lines']} строк OCR.")
    print(f"Событий включено в профиль: {profile['import_summary']['included_events']}.")
    print(f"Выходная папка: {out_dir}")
    print(f"Профиль: {profile_path}")
    print(f"Расчёт: {report_path}")

    if args.prepare_only:
        print("Режим подготовки: Ollama не запускалась, AI-анализ не выполнялся.")
        return 0

    payload = assistant.build_ai_payload(profile, report)
    payload_path = out_dir / "aou_ai_payload.json"
    advice_path = out_dir / "aou_ai_advice.md"
    write_json(payload_path, payload)

    print(
        f"Передаю сводку локально в Ollama ({selected_model}); "
        "полные строки журнала и идентификаторы в запрос не включаются."
    )
    advice = assistant.call_ollama(
        payload, selected_model, args.ollama_url, timeout=args.timeout
    )
    advice_path.write_text(advice.rstrip() + "\n", encoding="utf-8")
    print(f"AI-разбор сохранён: {advice_path}")
    print(f"Модель: {selected_model}")
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Одна команда: OCR-TXT DPScope -> профиль -> расчёт -> локальная Qwen/Ollama."
    )
    parser.add_argument("input", nargs="?", type=Path, help="TXT с распознанными строками AOUCSV")
    parser.add_argument("--out-dir", type=Path, help="папка результатов; по умолчанию <имя_TXT>_DPScope")
    parser.add_argument("--model", default=os.environ.get("OLLAMA_MODEL", assistant.DEFAULT_MODEL))
    parser.add_argument(
        "--ollama-url", default=os.environ.get("OLLAMA_HOST", "http://localhost:11434")
    )
    parser.add_argument("--timeout", type=int, default=600, help="тайм-аут ответа модели в секундах")
    parser.add_argument("--budget", type=int, default=20, help="бюджет свободных очков (по умолчанию 20)")
    parser.add_argument(
        "--resolve-coefficient", type=float, choices=(0.015, 0.0015), default=0.015
    )
    parser.add_argument(
        "--encoding", choices=("utf-8-sig", "cp1251"), default="utf-8-sig",
        help="кодировка OCR-TXT"
    )
    parser.add_argument("--prepare-only", action="store_true", help="создать CSV/JSON без вызова Ollama")
    parser.add_argument("--check-ollama", action="store_true", help="только проверить Ollama и выбранную модель")
    parser.add_argument("--overwrite", action="store_true", help="разрешить перезапись результатов в --out-dir")
    args = parser.parse_args()

    try:
        if args.check_ollama:
            models = assistant.list_ollama_models(args.ollama_url)
            selected = assistant.check_ollama(args.ollama_url, args.model)
            print("Ollama доступна. Установленные модели: " + ", ".join(models))
            print("Выбрана модель: " + selected)
            return 0
        return run_pipeline(args)
    except (OSError, ValueError, RuntimeError, json.JSONDecodeError) as exc:
        print(f"Ошибка AI-компаньона: {exc}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
