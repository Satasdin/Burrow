"""Builds the scratch project every arm of the session-context runs works on (D-116 evidence).

Deterministic (seeded), so every arm gets byte-identical files. It is a small Python package with large files and noisy
tools, so a session that reads and runs things fills its context the way real work does.
"""
import os, random, sys, textwrap

root = sys.argv[1]
random.seed(20261117)
os.makedirs(f"{root}/ledgerly", exist_ok=True)
os.makedirs(f"{root}/tools", exist_ok=True)
os.makedirs(f"{root}/tests", exist_ok=True)
os.makedirs(f"{root}/data", exist_ok=True)

open(f"{root}/ledgerly/__init__.py", "w").write("")
open(f"{root}/ledgerly/parse.py", "w").write(textwrap.dedent('''
    """Parses statement lines: 'date,reference,amount'."""

    def parse_line(line):
        date, reference, amount = line.strip().split(",")
        return {"date": date, "reference": reference, "amount": float(amount)}
    '''))
open(f"{root}/ledgerly/reconcile.py", "w").write(textwrap.dedent('''
    from .parse import parse_line

    def reconcile_batch(lines, tickets):
        """Matches each statement line to a ticket by reference."""
        matched, suspense = [], []
        for line in lines:
            row = parse_line(line)
            ticket = tickets.get(row["reference"])
            (matched if ticket else suspense).append(row)
        return matched, suspense
    '''))

# A large module: 2,600 lines of fixtures, so a whole-file read is heavy.
rows = []
for i in range(2600):
    rows.append(f"    ('TKT{i:05d}', '{random.choice(['46','23','111','8'])}', {random.randint(50, 900)}.00, '{random.choice(['paid','open','void'])}'),")
open(f"{root}/data/fixtures.py", "w").write("FIXTURES = [\n" + "\n".join(rows) + "\n]\n")

# A long module of helpers, ~1,800 lines.
funcs = []
for i in range(300):
    funcs.append(textwrap.dedent(f'''
        def rule_{i:03d}(row):
            """Rule {i}: flags rows whose amount is a multiple of {i % 17 + 2}."""
            if row["amount"] % {i % 17 + 2} == 0:
                return "rule_{i:03d}"
            return None
        '''))
open(f"{root}/ledgerly/rules.py", "w").write("\n".join(funcs))

# A report tool whose output is long, with one fatal line in the middle and a count at the end.
open(f"{root}/tools/gen_report.py", "w").write(textwrap.dedent('''
    import random
    random.seed(7)
    for i in range(2200):
        level = random.choice(["INFO"] * 9 + ["WARN"])
        print(f"2026-11-17T09:{i // 60 % 60:02d}:{i % 60:02d} {level} shard-{i % 13:02d} reconciled {random.randint(10, 99)} rows in {random.randint(3, 400)}ms")
        if i == 1234:
            print("2026-11-17T09:20:34 FATAL shard 0x5F3A checksum mismatch (expected 9c41 got 77e2)")
    print("SUMMARY processed 48213 records, 1 fatal, 214 warnings")
    '''))

# A noisy test run.
open(f"{root}/tools/run_checks.py", "w").write(textwrap.dedent('''
    import random
    random.seed(11)
    for i in range(1500):
        print(f"check_{i:04d} ... ok ({random.randint(1, 90)} ms) [{'x' * random.randint(5, 40)}]")
    print("1500 checks passed")
    '''))
open(f"{root}/tests/test_parse.py", "w").write(textwrap.dedent('''
    from ledgerly.parse import parse_line

    def test_parse():
        assert parse_line("2026-11-01,TKT00001,120.00")["amount"] == 120.0
    '''))
print("project ready at", root)
