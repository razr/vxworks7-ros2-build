#!/usr/bin/env python3
# prepare_python_install.py - prepare a ROS 2 install/deploy tree so Python
# starts fast on the VxWorks target. Used by the image build
# (python_prepare_deploy in mk/usr/defs.python.mk), by the toolkit self-test,
# and by toolkit users on their own colcon install/ tree.
#
# Why: on the target every file stat/open goes to a FAT image (over emulated
# AHCI under QEMU TCG), so Python startup cost grows with the number of files
# it touches. Two things in a default install touch many files:
#   1. the setuptools EASY-INSTALL console-script launchers call
#      pkg_resources.load_entry_point, and importing pkg_resources scans every
#      *.dist-info/*.egg-info first (measured ~238 s on QEMU);
#   2. without shipped .pyc, every module is compiled on first import.
#
# What it does, for <root>:
#   a. removes every __pycache__ (build-time caches may be host-arch or
#      timestamp-checked, and would be stale after the copy to the target);
#   b. compiles all .py with unchecked-hash .pyc, so the target loads the
#      bytecode as-is and never revalidates or recompiles it. Must run with the
#      same Python major.minor as the target (the SDK host python3);
#   c. rewrites the EASY-INSTALL launchers in <root>/bin and in every
#      <root>/lib/<pkg>/ (where ament_python puts node executables) into
#      importlib.metadata wrappers that resolve the same single entry point.
#
# Idempotent. Best-effort: compile errors are reported but do not fail.
# Usage: prepare_python_install.py [--no-compile] <root>

import compileall
import os
import py_compile
import re
import shutil
import sys

TRIPLE = re.compile(
    r"load_entry_point\('([^']+)==([^']+)',\s*'([^']+)',\s*'([^']+)'\)")

WRAPPER = '''%s
# importlib.metadata console-script wrapper (replaces the setuptools
# EASY-INSTALL shim, which imported the setuptools working-set machinery and
# scanned all *.dist-info at startup -- minutes on the target FS). Resolves
# exactly the %r entry point in group %r from distribution %r.
import sys
from importlib.metadata import entry_points


def _load():
    eps = entry_points()
    # Python 3.9: entry_points() returns a dict keyed by group.
    for ep in eps.get(%r, []):
        if ep.name == %r:
            return ep.load()
    raise RuntimeError("entry point %r in group %r not found")


if __name__ == '__main__':
    sys.exit(_load()())
'''


def convert_dir(bin_dir):
    """Rewrite the EASY-INSTALL launchers directly in bin_dir (not recursive)."""
    converted = 0
    for name in sorted(os.listdir(bin_dir)):
        path = os.path.join(bin_dir, name)
        if not os.path.isfile(path) or name.endswith('.easyinstall.bak'):
            continue
        try:
            with open(path, encoding='utf-8') as fh:
                txt = fh.read()
        except (UnicodeDecodeError, IsADirectoryError, PermissionError):
            continue  # binary / non-text file
        if 'EASY-INSTALL-ENTRY-SCRIPT' not in txt or 'load_entry_point' not in txt:
            continue  # not a slow shim (already converted or not a shim)
        m = TRIPLE.search(txt)
        if not m:
            print('SKIP (no entry-point triple): %s' % path)
            continue
        dist, _ver, group, ep_name = m.groups()
        shebang = txt.splitlines()[0]
        if not shebang.startswith('#!'):
            shebang = '#!/usr/bin/env python3'
        with open(path, 'w') as fh:
            fh.write(WRAPPER % (shebang, ep_name, group, dist,
                                group, ep_name, ep_name, group))
        os.chmod(path, 0o755)
        converted += 1
    return converted


def launcher_dirs(root):
    """<root>/bin plus every <root>/lib/<pkg>/ directory."""
    dirs = []
    b = os.path.join(root, 'bin')
    if os.path.isdir(b):
        dirs.append(b)
    lib = os.path.join(root, 'lib')
    if os.path.isdir(lib):
        for name in sorted(os.listdir(lib)):
            d = os.path.join(lib, name)
            if os.path.isdir(d) and not os.path.islink(d):
                dirs.append(d)
    return dirs


def strip_pycache(root):
    removed = 0
    for dirpath, dirnames, _files in os.walk(root):
        if '__pycache__' in dirnames:
            shutil.rmtree(os.path.join(dirpath, '__pycache__'))
            dirnames.remove('__pycache__')
            removed += 1
    return removed


def main(argv):
    args = [a for a in argv if a != '--no-compile']
    compile_py = len(args) == len(argv)
    if len(args) != 1 or not os.path.isdir(args[0]):
        print('usage: prepare_python_install.py [--no-compile] <root>',
              file=sys.stderr)
        return 2
    root = args[0]

    if compile_py:
        n = strip_pycache(root)
        print('prepare_python_install: removed %d __pycache__ dir(s) in %s'
              % (n, root))
        ok = compileall.compile_dir(
            root, quiet=1, force=True,
            invalidation_mode=py_compile.PycInvalidationMode.UNCHECKED_HASH)
        print('prepare_python_install: compiled unchecked-hash .pyc in %s%s'
              % (root, '' if ok else ' (some files failed; see above)'))

    total = 0
    for d in launcher_dirs(root):
        total += convert_dir(d)
    print('prepare_python_install: converted %d launcher(s) in %s'
          % (total, root))
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
