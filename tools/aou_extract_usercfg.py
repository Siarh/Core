#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Read DPScope event rows directly from Allods Online user.cfg (read-only).

The game must be closed so the on-disk config is fully flushed. This script
extracts aou_evt_* values, creates an AOUCSV text export locally, then hands
that file to the existing local Ollama/Qwen companion.
"""
from __future__ import annotations

import argparse
import ast
import re
import subprocess
import sys
from pathlib import Path
from typing import Any

EVENT_COLUMNS = (
    "fight_id|profile|second|kind|observed_amount|target_hp_before|hp_quality|"
    "target_max_hp|critical|element|damage_source|resist|absorb|runes_absorb|"
    "block|parry|barrier|mount|multiplier_absorb|overall_absorbed|"
    "overall_prevented|resolve_pool|recipient|ability|M|R|U|L|S|W|B|C|HPmax"
)
SECTION_NAME = "ScriptUserMods_DPScope"
MAX_EVENTS = 1000
CHUNK_SIZE = 58

TABLE_BEGIN_RE = re.compile(r"^\s*table_begin\s+([^\s]+)\s*$", re.I)
TABLE_END_RE = re.compile(r"^\s*table_end\s+([^\s]+)\s*$", re.I)
KEY_VALUE_RE = re.compile(
    r'^\s*(?:\["?([^"\]]+)"?\]|([A-Za-z_][A-Za-z0-9_]*))\s*=\s*(.*?)\s*$'
)


def read_config_text(path: Path) -> str:
    raw = path.read_bytes()
    for encoding in ("utf-8-sig", "utf-16", "cp1251"):
        try:
            return raw.decode(encoding)
        except UnicodeDecodeError:
            pass
    raise ValueError(
        f"Не удалось определить текстовую кодировку {path}. "
        "Файл не изменён; нужна отдельная проверка формата."
    )


def extract_named_table(text: str, name: str) -> str | None:
    lines = text.splitlines()
    start = None
    for index, line in enumerate(lines):
        match = TABLE_BEGIN_RE.match(line)
        if match and match.group(1) == name:
            start = index
            break
    if start is None:
        return None

    stack: list[str] = []
    captured: list[str] = []
    for index in range(start, len(lines)):
        line = lines[index]
        begin = TABLE_BEGIN_RE.match(line)
        end = TABLE_END_RE.match(line)
        if begin:
            stack.append(begin.group(1))
            if index > start:
                captured.append(line)
            continue
        if end:
            if not stack or stack[-1] != end.group(1):
                raise ValueError(
                    f"Повреждена структура таблиц user.cfg около строки {index + 1}."
                )
            stack.pop()
            if not stack:
                return "\n".join(captured)
            captured.append(line)
            continue
        if index > start:
            captured.append(line)
    raise ValueError(f"Таблица {name} не закрыта в user.cfg.")


def parse_config_value(raw: str) -> Any:
    value = raw.strip()
    # Allods text configs commonly prefix strings with l, e.g. l"some text".
    if len(value) >= 2 and value[0] in "lsw" and value[1] == '"':
        value = value[1:]
    # Also accept typed scalar markers if present in a client build.
    if len(value) >= 2 and value[0] in "if" and value[1] in "+-0123456789":
        value = value[1:]
    if value.startswith('"'):
        try:
            return ast.literal_eval(value)
        except (SyntaxError, ValueError):
            # Conservative fallback for a quoted config string with an unknown
            # escape sequence. Only unescape quote and backslash.
            if not value.endswith('"') or len(value) < 2:
                raise ValueError("Строковое значение в user.cfg не закрыто кавычкой.")
            inner = value[1:-1]
            return inner.replace(r'\"', '"').replace(r"\\", "\\")
    if value.lower() == "true":
        return True
    if value.lower() == "false":
        return False
    try:
        if re.fullmatch(r"[-+]?\d+", value):
            return int(value)
        if re.fullmatch(r"[-+]?(?:\d+\.\d*|\.\d+)(?:[eE][-+]?\d+)?", value):
            return float(value)
    except ValueError:
        pass
    return value


def parse_dpscope_config(text: str) -> tuple[list[str], dict[str, int]]:
    section = extract_named_table(text, SECTION_NAME)
    if section is None:
        # Some older layouts place the addon data directly in Personal/user.cfg.
        # Only accept the fallback if our distinctive event counter is present.
        if not re.search(r"(?m)^\s*aou_evt_count\s*=", text):
            raise ValueError(
                f"Не найдена таблица {SECTION_NAME} и ключ aou_evt_count. "
                "Проверь, что выбран user.cfg именно DPScope."
            )
        section = text

    data = extract_named_table(section, "data")
    if data is None:
        data = section

    values: dict[str, Any] = {}
    for line_no, line in enumerate(data.splitlines(), 1):
        match = KEY_VALUE_RE.match(line)
        if not match:
            continue
        key = match.group(1) or match.group(2)
        if key == "aou_evt_count" or re.fullmatch(r"aou_evt_\d+", key):
            if key in values:
                raise ValueError(f"Ключ {key} повторяется в user.cfg.")
            values[key] = parse_config_value(match.group(3))

    if "aou_evt_count" not in values:
        raise ValueError("В секции DPScope нет aou_evt_count: журнал ещё не сохранён.")
    try:
        count = int(values["aou_evt_count"])
    except (TypeError, ValueError):
        raise ValueError("aou_evt_count в user.cfg имеет неверный формат.") from None
    if count < 0:
        raise ValueError("aou_evt_count отрицательный.")
    if count > MAX_EVENTS:
        count = MAX_EVENTS
    if count == 0:
        raise ValueError("В user.cfg сохранено 0 событий.")

    header = EVENT_COLUMNS.split("|")
    rows: list[str] = []
    missing: list[int] = []
    for number in range(1, count + 1):
        key = f"aou_evt_{number}"
        value = values.get(key)
        if not isinstance(value, str) or not value:
            missing.append(number)
            continue
        fields = value.split("|")
        if len(fields) != len(header):
            raise ValueError(
                f"{key}: найдено {len(fields)} полей вместо {len(header)}. "
                "Конфиг может иметь другую схему или быть повреждён."
            )
        rows.append(value)
    if missing:
        preview = ", ".join(map(str, missing[:20]))
        suffix = " ..." if len(missing) > 20 else ""
        raise ValueError(
            f"В конфиге отсутствуют записи {preview}{suffix}. "
            "Неполный журнал не будет передан AI."
        )
    return rows, {"stored_events": count, "rows_read": len(rows)}


def chunk_line(kind: str, value: str) -> list[str]:
    total = max(1, (len(value) + CHUNK_SIZE - 1) // CHUNK_SIZE)
    return [
        f"AOUCSV|{kind}|{part}|{total}|"
        f"{value[(part - 1) * CHUNK_SIZE:part * CHUNK_SIZE]}"
        for part in range(1, total + 1)
    ]


def write_aoucsv(path: Path, rows: list[str]) -> None:
    lines = [f"AOUCSV|BEGIN|2|{len(rows)}|events"]
    lines.extend(chunk_line("H", EVENT_COLUMNS))
    for index, row in enumerate(rows, 1):
        lines.extend(chunk_line(f"R{index}", row))
    lines.append("AOUCSV|END")
    path.write_text("\n".join(lines) + "\n", encoding="utf-8")


def locate_config(source: Path) -> tuple[Path, Path]:
    """Return (user.cfg path, game root). Never write to the config tree."""
    source = source.expanduser().resolve()
    if source.is_file():
        if source.name.lower() not in {"user.cfg", "user.cfg.bak"}:
            raise ValueError("Укажи папку игры либо сам файл user.cfg.")
        # Root is inferred for the documented addon config path.
        parts = [part.lower() for part in source.parts]
        try:
            data_index = parts.index("data")
            root = Path(*source.parts[:data_index])
        except ValueError:
            root = source.parent
        return source, root

    if not source.is_dir():
        raise ValueError(f"Путь не найден: {source}")

    candidates = [
        source / "data" / "Mods" / "Configs" / "DPScope" / "user.cfg",
        source / "data" / "Mods" / "Configs" / "DPScope" / "user.cfg.bak",
        source / "Personal" / "user.cfg",
    ]
    for candidate in candidates:
        if candidate.is_file():
            return candidate, source

    # Case-insensitive folder search under the known config root.
    config_root = source / "data" / "Mods" / "Configs"
    if config_root.is_dir():
        for addon_dir in config_root.iterdir():
            if addon_dir.is_dir() and addon_dir.name.casefold() == "dpscope":
                for filename in ("user.cfg", "user.cfg.bak"):
                    candidate = addon_dir / filename
                    if candidate.is_file():
                        return candidate, source

    expected = candidates[0]
    raise FileNotFoundError(
        "Не найден конфиг DPScope. Ожидаемый путь:\n"
        f"{expected}\n"
        "Убедись, что игра хотя бы раз сохранила настройки DPScope."
    )


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Извлечение журнала DPScope напрямую из Allods user.cfg без чата/OCR."
    )
    parser.add_argument(
        "source", type=Path,
        help="корневая папка Allods Online или полный путь к user.cfg"
    )
    parser.add_argument("--model", default="qwen3.5:27b")
    parser.add_argument("--ollama-url", default="http://localhost:11434")
    parser.add_argument("--timeout", type=int, default=600)
    parser.add_argument("--budget", type=int, default=20)
    parser.add_argument("--resolve-coefficient", type=float, choices=(0.015, 0.0015), default=0.015)
    parser.add_argument("--prepare-only", action="store_true")
    parser.add_argument("--overwrite", action="store_true")
    args = parser.parse_args()

    try:
        config_path, game_root = locate_config(args.source)
        text = read_config_text(config_path)
        rows, summary = parse_dpscope_config(text)

        output_dir = game_root / "DPScope_UserCfg_Export"
        output_dir.mkdir(parents=True, exist_ok=True)
        export_text = output_dir / "aou_usercfg_export.txt"
        if export_text.exists() and not args.overwrite:
            raise FileExistsError(
                f"Файл уже существует: {export_text}. "
                "Добавь --overwrite, если хочешь заменить результат."
            )
        write_aoucsv(export_text, rows)

        print("Конфигурация прочитана (только чтение):", config_path)
        print(f"Событий извлечено: {summary['rows_read']}")
        print("AOUCSV сохранён:", export_text)

        companion = Path(__file__).resolve().with_name("aou_ai_companion.py")
        command = [
            sys.executable, str(companion), str(export_text),
            "--out-dir", str(output_dir / "analysis"),
            "--budget", str(args.budget),
            "--resolve-coefficient", str(args.resolve_coefficient),
            "--model", args.model,
            "--ollama-url", args.ollama_url,
            "--timeout", str(args.timeout),
        ]
        if args.prepare_only:
            command.append("--prepare-only")
        if args.overwrite:
            command.append("--overwrite")
        return subprocess.run(command, check=False).returncode
    except (OSError, ValueError) as exc:
        print(f"Ошибка извлечения DPScope user.cfg: {exc}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
