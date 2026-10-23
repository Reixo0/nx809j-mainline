#!/usr/bin/env python3
"""Compare RPMh regulator voltage ranges of an upstream board dts against the
downstream (live) device tree from the phone.
Usage: compare-regulators.py <live.dts> <upstream-board.dts>"""
import re, sys
live, up = (open(p).read() for p in sys.argv[1:3])
phone = {}
for m in re.finditer(r'qcom,resource-name = "([LSB])(\d+)([A-Z])_E(\d)";(.*?)\n\t\t\t\t\};', live, re.S):
    kind, n, pid, e, body = m.groups()
    r = re.search(r'min-microvolt = <(\w+)>;.*?max-microvolt = <(\w+)>;', body, re.S)
    if r:
        phone[(kind, int(n), pid, e)] = (int(r[1], 16), int(r[2], 16))
seen = set()
for blk in re.finditer(r'qcom,pmic-id = "(\w)_E(\d)";(.*?)\n\t\};', up, re.S):
    pid, e, body = blk.groups()
    for r in re.finditer(r'(\w+): (ldo|smps|bob)(\d+) \{.*?min-microvolt = <(\d+)>;.*?max-microvolt = <(\d+)>;', body, re.S):
        lab, kind, n, mn, mx = r.groups()
        k = ({'ldo': 'L', 'smps': 'S', 'bob': 'B'}[kind], int(n), pid, e)
        seen.add(k)
        p = phone.get(k)
        flag = 'missing on phone' if p is None else ('' if p == (int(mn), int(mx)) else 'DIFF')
        print(f"{lab:16} up={int(mn):>8}-{int(mx):<8} phone={str(p):24} {flag}")
for k in sorted(set(phone) - seen):
    print(f"{'(not upstream)':16} {k[0]}{k[1]}{k[2]}_E{k[3]:<6} phone={phone[k]}")
