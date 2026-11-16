#!/usr/bin/env python3
# convert_console_scripts.py - compatibility wrapper. Rewrites the setuptools
# EASY-INSTALL launchers directly in one directory (not recursive) into
# importlib.metadata wrappers. The logic lives in prepare_python_install.py
# (same directory), which also ships unchecked-hash .pyc and covers bin/ plus
# every lib/<pkg>/; prefer that for a whole install/deploy tree.
# Usage: convert_console_scripts.py <bin_dir>

import os
import sys

sys.dont_write_bytecode = True  # do not leave __pycache__ next to the script
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from prepare_python_install import convert_dir  # noqa: E402


if __name__ == '__main__':
    if len(sys.argv) != 2:
        print('usage: %s <bin_dir>' % sys.argv[0], file=sys.stderr)
        sys.exit(2)
    n = convert_dir(sys.argv[1])
    print('convert_console_scripts: converted %d shim(s) in %s'
          % (n, sys.argv[1]))
    sys.exit(0)
