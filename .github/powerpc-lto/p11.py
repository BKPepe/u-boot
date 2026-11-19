#!/usr/bin/env python3
# Patch 11 check: evaluate every defconfig with kconfiglib in the tree before (A) and after (B) patch 11 and print
# every board whose resulting configuration differs, with the differing lines. Defconfigs are preprocessed like
# scripts/kconfig/Makefile does. usage: p11.py TREE-A TREE-B
import glob, os, subprocess, sys

def load(tree):
    os.chdir(tree)
    os.environ.update(srctree=tree, UBOOTVERSION="dummy", KCONFIG_OBJDIR="", CC="gcc")
    sys.path.insert(0, os.path.join(tree, "tools/buildman"))
    import kconfiglib
    del sys.modules["kconfiglib"]
    sys.path.pop(0)
    return kconfiglib.Kconfig("Kconfig", warn=False)

def config(kconf, tree, path):
    text = subprocess.run(["cpp", "-nostdinc", "-P", "-I", tree, "-undef", "-x", "assembler-with-cpp", path],
                          check=True, capture_output=True, text=True, cwd=tree).stdout
    text = "\n".join(l.lstrip() for l in text.splitlines()) + "\n"
    with open("/tmp/p11-defconfig", "w") as f:
        f.write(text)
    kconf.load_config("/tmp/p11-defconfig")
    kconf.write_config("/tmp/p11-config", header="")
    lines = [l for l in open("/tmp/p11-config").read().splitlines() if l and not l.startswith("#")]
    if not lines:
        raise RuntimeError("empty configuration")
    return set(lines)

a, b = sys.argv[1], sys.argv[2]
ka, kb = load(a), load(b)
boards = sorted(os.path.basename(p)[:-len("_defconfig")] for p in glob.glob(os.path.join(a, "configs/*_defconfig")))
n = diff = fail = 0
for board in boards:
    try:
        ca = config(ka, a, os.path.join(a, "configs", board + "_defconfig"))
        cb = config(kb, b, os.path.join(b, "configs", board + "_defconfig"))
    except Exception as e:
        fail += 1
        print(f"P11 {board} FAILED: {e}")
        continue
    n += 1
    if ca != cb:
        diff += 1
        print(f"P11 {board}: " + " ".join(["-" + l for l in sorted(ca - cb)] + ["+" + l for l in sorted(cb - ca)]))
print(f"P11 evaluated {n} defconfigs, {diff} differ, {fail} failed")
