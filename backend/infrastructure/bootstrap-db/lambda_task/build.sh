#!/usr/bin/env bash
set -e
# clean up
rm -rf build
mkdir build
# vendor dependencies
uv pip install -r requirements.txt --target build
# use pip if uv is not installed
# pip install -r requirements.txt -t build

# copy needed files
cp handler.py build/
cp sqlite_dump_clean.sql build/
