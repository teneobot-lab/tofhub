#!/usr/bin/env python3
"""Gabungkan loader + semua modul menjadi satu file: TOFHub_bundle.lua
Pakai: python3 build.py  (jalankan di folder TOFHub)"""
import re, pathlib

here = pathlib.Path(__file__).parent
loader = (here / "loader.lua").read_text(encoding="utf-8")

m = re.search(r"local ORDER = \{(.*?)\n\}", loader, re.S)
names = re.findall(r'"([a-z_]+)"', m.group(1))

parts = ["local EMBEDDED = {}"]
for n in names:
    src = (here / f"{n}.lua").read_text(encoding="utf-8").rstrip()
    parts.append(f'EMBEDDED["{n}"] = (function()\n{src}\nend)()')
embedded = "\n\n".join(parts)

assert "local EMBEDDED = {}" in loader
out = loader.replace("local EMBEDDED = {}", embedded, 1)
(here / "TOFHub_bundle.lua").write_text(out, encoding="utf-8")
print(f"OK: {len(names)} modul -> TOFHub_bundle.lua ({len(out.splitlines())} baris)")
