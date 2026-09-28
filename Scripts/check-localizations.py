#!/usr/bin/env python3
"""Audit app-owned Chinese strings, catalog coverage, and placeholders."""

import json
import pathlib
import re

ROOT = pathlib.Path(__file__).resolve().parent.parent
HAN = re.compile(r"[\u4e00-\u9fff]")
PLACEHOLDER = re.compile(r"%[1-9][0-9]*\$@")


def string_end(source, start):
    index = start + 1
    while index < len(source):
        if source[index] == '"':
            return index + 1
        if source[index:index + 2] == "\\(":
            index = expression_end(source, index + 2)
        elif source[index] == "\\":
            index += 2
        else:
            index += 1
    raise ValueError(f"Unterminated string at offset {start}")


def expression_end(source, index):
    depth = 1
    while depth:
        if source[index] == '"':
            index = string_end(source, index)
            continue
        if source[index] == "(":
            depth += 1
        elif source[index] == ")":
            depth -= 1
        index += 1
    return index


def literals(source):
    """Read Swift string literals, skipping comments and respecting interpolation."""
    index = 0
    while index < len(source):
        if source[index:index + 2] == "//":
            newline = source.find("\n", index)
            index = newline if newline >= 0 else len(source)
        elif source[index:index + 2] == "/*":
            index = source.index("*/", index) + 2
        elif source[index] == '"':
            end = string_end(source, index)
            yield index, source[index + 1:end - 1]
            index = end
        else:
            index += 1


def catalog(language):
    result = {}
    path = ROOT / f"Sources/PicSee/Resources/{language}.lproj/Localizable.strings"
    for line in path.read_text().splitlines():
        if not line.strip():
            continue
        match = re.fullmatch(r'("(?:[^"\\]|\\.)*") = ("(?:[^"\\]|\\.)*");', line)
        if not match:
            raise ValueError(f"Invalid catalog line in {path}: {line}")
        key, value = map(json.loads, match.groups())
        assert key not in result, f"Duplicate key: {key}"
        result[key] = value
    return result


def main():
    chinese, english = catalog("zh-Hans"), catalog("en")
    assert chinese.keys() == english.keys(), "Language catalogs have different keys"
    errors = []
    for key, value in english.items():
        if not value or HAN.search(value):
            errors.append(f"Untranslated English value: {key}")
        if sorted(PLACEHOLDER.findall(key)) != sorted(PLACEHOLDER.findall(value)):
            errors.append(f"Placeholder mismatch: {key}")
    for path in (ROOT / "Sources/PicSee").rglob("*.swift"):
        source = path.read_text()
        for start, raw in literals(source):
            prefix = source[max(0, start - 30):start]
            if re.search(r"L10n\.(?:text|render)\($", prefix):
                key = json.loads('"' + raw + '"')
                if key not in chinese:
                    errors.append(f"Missing key in {path.name}: {raw}")
            elif not HAN.search(raw):
                continue
            elif path.name == "AppLanguage.swift" and raw == "简体中文":
                # Endonyms let users recover after accidentally choosing a language.
                continue
            else:
                errors.append(f"Unlocalized literal in {path.name}: {raw}")
    if errors:
        raise SystemExit("\n".join(errors))
    print(f"PASS: {len(chinese)} bilingual strings; no unlocalized Chinese application literals.")


if __name__ == "__main__":
    main()
