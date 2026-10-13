#!/usr/bin/env python3
"""
Java 코드 안의 SQL 문을 모두 뽑아 실제 PostgreSQL 에 PREPARE 해 본다 (실행하지 않음).
테이블·컬럼 이름, 함수 시그니처, 타입 오류를 서버 빌드 없이 잡기 위한 검사.

사용: PGHOST=... PGPORT=... PGUSER=... python3 check_java_sql.py <마이그레이션이 적용된 DB 이름>
"""
import os
import re
import subprocess
import sys

ROOT = os.path.join(os.path.dirname(__file__), "..", "src", "main", "java")
DB = sys.argv[1] if len(sys.argv) > 1 else "fmate_sqlcheck"

TEXT_BLOCK = re.compile(r'"""\n(.*?)"""', re.S)
STRING = re.compile(r'"((?:[^"\\\n]|\\.)*)"')
SQL_START = re.compile(r"^\s*(SELECT|INSERT|UPDATE|DELETE|WITH)\b", re.I)


def java_unescape(s):
    return s.replace('\\"', '"').replace("\\\\", "\\").replace("\\n", "\n")


def to_positional(sql):
    """? 와 :name 을 $1.. 로 바꾼다 (:: 캐스트와 문자열 리터럴은 건드리지 않음)"""
    out, n, names, i = [], 0, {}, 0
    in_str = False
    while i < len(sql):
        c = sql[i]
        if c == "'" :
            in_str = not in_str
            out.append(c); i += 1; continue
        if in_str:
            out.append(c); i += 1; continue
        if c == "?":
            n += 1; out.append(f"${n}"); i += 1; continue
        if c == ":" and i + 1 < len(sql) and sql[i + 1] == ":":
            out.append("::"); i += 2
            continue
        if c == ":" and i + 1 < len(sql) and (sql[i + 1].isalpha() or sql[i + 1] == "_") and (i == 0 or sql[i - 1] != ":"):
            j = i + 1
            while j < len(sql) and (sql[j].isalnum() or sql[j] == "_"):
                j += 1
            name = sql[i + 1:j]
            if name not in names:
                n += 1
                names[name] = n
            out.append(f"${names[name]}")
            i = j
            continue
        out.append(c); i += 1
    return "".join(out)


def collect():
    found = []
    for dirpath, _, files in os.walk(ROOT):
        for f in files:
            if not f.endswith(".java"):
                continue
            path = os.path.join(dirpath, f)
            src = open(path, encoding="utf-8").read()
            # PostService 처럼 상수 SELECT + 텍스트 블록으로 이어 붙이는 경우
            consts = {}
            for m in re.finditer(r'private static final String (\w+) = """\n(.*?)""";', src, re.S):
                consts[m.group(1)] = m.group(2)
            for m in TEXT_BLOCK.finditer(src):
                body = m.group(1)
                before = src[max(0, m.start() - 40):m.start()]
                after = src[m.end():m.end() + 12]
                prefix = ""
                pm = re.search(r"(\w+) \+ $", before)
                if pm and pm.group(1) in consts:
                    prefix = consts[pm.group(1)]
                sql = prefix + body
                if not SQL_START.match(sql):
                    continue
                if f'String {pm.group(1) if pm else ""} = ' in before:
                    pass
                found.append((path, src[:m.start()].count("\n") + 1, sql, ".formatted" in after))
            for m in STRING.finditer(src):
                s = java_unescape(m.group(1))
                if SQL_START.match(s) and len(s) > 15:
                    found.append((path, src[:m.start()].count("\n") + 1, s, False))
    return found


def check(sql):
    stmt = "PREPARE _chk AS " + sql.strip().rstrip(";") + ";\nDEALLOCATE _chk;"
    r = subprocess.run(["psql", "-X", "-q", "-v", "ON_ERROR_STOP=1", "-d", DB, "-c", stmt],
                       capture_output=True, text=True)
    return r.returncode == 0, r.stderr.strip()


def main():
    items = collect()
    ok = skipped = 0
    failures = []
    for path, line, sql, dynamic in items:
        rel = os.path.relpath(path, ROOT)
        candidates = [sql]
        if "%s" in sql:
            # 동적으로 조합되는 SQL: 코드가 넣을 수 있는 대표값들로 채워 하나라도 통과하면 OK
            if sql.count("%s") == 1:
                candidates = [sql.replace("%s", ""), sql.replace("%s", "AND true"), sql.replace("%s", "NULL")]
            else:
                candidates = [sql.replace("%s", "NULL::float8", 1).replace("%s", "NULL::int", 1)]
        good, err = False, ""
        for cand in candidates:
            good, err = check(to_positional(cand))
            if good:
                break
        if good:
            ok += 1
        else:
            failures.append((rel, line, err.splitlines()[0] if err else "?", sql))
    for rel, line, err, sql in failures:
        print(f"✘ {rel}:{line}\n    {err}")
    print(f"\nSQL 검사: 통과 {ok} / 실패 {len(failures)} (총 {len(items)}개 문장)")
    sys.exit(1 if failures else 0)


if __name__ == "__main__":
    main()
