#!/usr/bin/env python3
"""Копирует только выбранный публичный CA. Секреты из .env в сборку не попадают."""
import os
import re
import sys
from pathlib import Path


def selected_certificate():
    if "BLOT_GIGACHAT_CA_FILE" in os.environ:
        return os.environ["BLOT_GIGACHAT_CA_FILE"]
    source = Path(os.environ.get("BLOT_ENV_FILE", ".env"))
    if not source.is_file():
        return ""
    if source.stat().st_size > 262144:
        raise ValueError("Файл .env превышает 256 KiB")
    for line in source.read_text(encoding="utf-8-sig").splitlines():
        line = line.strip()
        if line.startswith("export "):
            line = line[7:].strip()
        key, separator, value = line.partition("=")
        if separator and key.strip() == "BLOT_GIGACHAT_CA_FILE":
            value = value.strip()
            if value.startswith(("'", '"')):
                if len(value) < 2 or value[-1] != value[0]:
                    raise ValueError("Проверьте кавычки BLOT_GIGACHAT_CA_FILE")
                value = value[1:-1]
            return value
    return ""


def copy_certificate(target):
    filename = selected_certificate()
    if not filename:
        target.unlink(missing_ok=True)
        return
    source = Path(filename)
    if not source.is_absolute() or not source.is_file() or source.stat().st_size > 65536:
        raise ValueError("Для BLOT_GIGACHAT_CA_FILE нужен абсолютный путь к PEM до 64 KiB")
    data = source.read_bytes()
    if b"-----BEGIN CERTIFICATE-----" not in data or b"PRIVATE KEY" in data:
        raise ValueError("BLOT_GIGACHAT_CA_FILE должен содержать публичный PEM-сертификат CA")
    certificates = re.findall(
        rb"-----BEGIN CERTIFICATE-----[A-Za-z0-9+/=\r\n\t ]+-----END CERTIFICATE-----", data
    )
    if not 1 <= len(certificates) <= 4:
        raise ValueError("Нужны от 1 до 4 публичных PEM-сертификатов CA")
    # Сохраняем только сертификаты, даже если рядом в исходном файле был другой текст.
    target.write_bytes(b"\n".join(certificates) + b"\n")


try:
    copy_certificate(Path(sys.argv[1]))
except (OSError, UnicodeError):
    sys.exit("Не удалось прочитать .env или выбранный CA при сборке")
except ValueError as failure:
    sys.exit(str(failure))
