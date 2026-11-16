#!/usr/bin/env python3
"""Turn pmaports' kconfigcheck.toml into a config fragment, and check a .config.

  kconfig-frag.py frag  <kconfigcheck.toml> <kver> <arch> <alias|category>...  > frag
  kconfig-frag.py check <kconfigcheck.toml> <kver> <arch> <.config> <alias|category>...
"""
import re
import sys
import tomllib


def ver(s):
    return tuple(int(x) for x in re.findall(r"\d+", s)[:3])


def ver_ok(rule, kver):
    for part in rule.split(","):
        m = re.match(r"\s*(>=|<=|<|>|==)?\s*([\d.]+)", part)
        op, v = m.group(1) or "==", ver(m.group(2))
        k = ver(kver)
        if not {">=": k >= v, "<=": k <= v, "<": k < v, ">": k > v, "==": k == v}[op]:
            return False
    return True


def rules(toml, kver, arch, names):
    cats = []
    for n in names:
        cats += toml["aliases"].get(n, ["category:" + n])
    out = {}
    for cat in cats:
        for vrule, by_arch in toml.get(cat, {}).items():
            if not ver_ok(vrule, kver):
                continue
            for archs, opts in by_arch.items():
                if archs != "all" and arch not in archs.split():
                    continue
                out.update(opts)
    return out


def main():
    mode, path, kver, arch = sys.argv[1:5]
    with open(path, "rb") as f:
        toml = tomllib.load(f)
    if mode == "frag":
        for k, v in sorted(rules(toml, kver, arch, sys.argv[5:]).items()):
            if isinstance(v, list):
                print('CONFIG_%s="%s"' % (k, ",".join(v)))
            elif v == "n":
                print("# CONFIG_%s is not set" % k)
            elif v in ("y", "m"):
                print("CONFIG_%s=%s" % (k, v))
            else:
                print('CONFIG_%s="%s"' % (k, v))
        return
    cfg = {}
    for line in open(sys.argv[5]):
        m = re.match(r"CONFIG_(\w+)=(.*)", line.strip())
        if m:
            cfg[m.group(1)] = m.group(2).strip('"')
    bad = 0
    for k, v in sorted(rules(toml, kver, arch, sys.argv[6:]).items()):
        have = cfg.get(k)
        if isinstance(v, list):
            ok = have is not None and all(x in have.split(",") for x in v)
        elif v == "n":
            ok = have is None
        elif v in ("y", "m"):
            ok = have in ("y", "m")
        else:
            ok = have == v
        if not ok:
            bad += 1
            print("UNMET %s: want %r, have %r" % (k, v, have))
    print("%d unmet" % bad)


main()
