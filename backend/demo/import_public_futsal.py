r"""
공공데이터(국민체육진흥공단 '전국체육시설 정보' API)에서 실제 풋살장을 골라
F-Mate DB 에 넣을 SQL 파일(public_futsal.sql)을 만든다.

- 실제 시설의 이름·주소·위치·실내외는 공공데이터 그대로 쓴다.
- 코트·운영시간·가격은 전시 시연용 예시이며, 구장 설명에 그 사실을 적는다 (실제 예약 아님).
- 표준 라이브러리만 사용 (설치할 것 없음).

실행 (C:\dev\fmate 에서, PowerShell):
  docker run --rm -e DATA_GO_KR_KEY="인증키" -v "C:\dev\fmate\backend\demo:/work" python:3.12-slim python -u /work/import_public_futsal.py

특정 지역만 넣기 (쉼표 구분, 시도 이름 그대로):
  ... -e REGIONS="서울특별시,경기도" ...
"""
import json
import os
import sys
import time
import urllib.parse
import urllib.request

ENDPOINT = "https://apis.data.go.kr/B551014/SRVC_API_SFMS_FACI/TODZ_API_SFMS_FACI"
PAGE_SIZE = 1000
OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "public_futsal.sql")

# 시도 이름 → 행정구역 코드 앞 2자리 (앱의 지역 필터와 같은 기준)
SIDO_CODES = {
    "서울특별시": "11", "부산광역시": "26", "대구광역시": "27", "인천광역시": "28",
    "광주광역시": "29", "대전광역시": "30", "울산광역시": "31", "세종특별자치시": "36",
    "경기도": "41", "강원도": "42", "강원특별자치도": "51", "충청북도": "43", "충청남도": "44",
    "전라북도": "45", "전북특별자치도": "52", "전라남도": "46", "경상북도": "47", "경상남도": "48",
    "제주특별자치도": "50",
}

DESCRIPTION = ("공공데이터(국민체육진흥공단 전국체육시설 정보) 기준의 실제 시설이에요. "
               "아직 F-Mate 제휴 구장이 아니며, 예약 시간표와 가격은 전시 시연용 예시라 실제로 예약되지 않아요.")
# 이전에 넣은 공공데이터 구장(과 그 구장에서 생긴 시연 예약·결제)을 지운다
_PV = "SELECT id FROM futsal_venues WHERE data_source = 'PARTNER_API'"
_PR = f"SELECT id FROM reservations WHERE venue_id IN ({_PV})"
_PP = f"SELECT id FROM payments WHERE reservation_id IN ({_PR})"
CLEANUP = [
    f"DELETE FROM refunds WHERE payment_id IN ({_PP});",
    f"DELETE FROM payment_audit_logs WHERE payment_id IN ({_PP});",
    f"DELETE FROM payments WHERE reservation_id IN ({_PR});",
    f"DELETE FROM reservation_status_history WHERE reservation_id IN ({_PR});",
    f"DELETE FROM reservations WHERE venue_id IN ({_PV});",
    "DELETE FROM futsal_venues WHERE data_source = 'PARTNER_API';",
]

RULES = "시연용 안내: 실제 이용 규칙·가격은 시설에 직접 문의해 주세요."


def build_url(key: str, page: int) -> str:
    # 인증키: Encoding 키(이미 %가 들어 있음)는 그대로, Decoding 키는 인코딩해서 붙인다
    k = key if "%" in key else urllib.parse.quote(key, safe="")
    return f"{ENDPOINT}?serviceKey={k}&pageNo={page}&numOfRows={PAGE_SIZE}&resultType=json&type=json"


def fetch(key: str, page: int) -> dict:
    last = None
    for attempt in range(4):
        try:
            with urllib.request.urlopen(build_url(key, page), timeout=60) as r:
                text = r.read().decode("utf-8")
            data = json.loads(text)
            header = data.get("response", {}).get("header", {})
            if header.get("resultCode") not in (None, "00"):
                raise RuntimeError(f"API 오류: {header.get('resultCode')} {header.get('resultMsg')}")
            return data["response"]["body"]
        except json.JSONDecodeError:
            # 키 오류 등은 XML 로 온다
            raise SystemExit("API 가 JSON 이 아닌 응답을 줬어요 (인증키 확인 필요):\n" + text[:300])
        except Exception as e:  # 네트워크 오류는 잠시 후 재시도
            last = e
            time.sleep(2 * (attempt + 1))
    raise SystemExit(f"{page}페이지를 받지 못했어요: {last}")


def items_of(body: dict) -> list:
    items = body.get("items") or {}
    if isinstance(items, dict):
        items = items.get("item") or []
    if isinstance(items, dict):
        items = [items]
    return items


def region_code(sido: str, it: dict) -> str:
    """시도 이름 → 코드 앞 2자리. 통합·개편된 시도는 주소로 옛 시도를 판단한다."""
    if sido in SIDO_CODES:
        return SIDO_CODES[sido]
    if "광주" in sido and ("전남" in sido or "전라남" in sido):
        # 전남광주 통합: 자치구(○○구)는 옛 광주광역시, 시·군은 옛 전라남도
        district = (it.get("cpb_nm") or it.get("addr_cpb_nm") or "").strip()
        if not district:
            parts = (it.get("faci_road_addr") or it.get("faci_addr") or "").split()
            district = parts[1] if len(parts) > 1 else ""
        return "29" if district.endswith("구") else "46"
    UNKNOWN_SIDO.add(sido or "(없음)")
    return "00"


UNKNOWN_SIDO = set()


def is_futsal(it: dict) -> bool:
    return "풋살" in (it.get("ftype_nm") or "") or "풋살" in (it.get("faci_nm") or "")


def resolve_address(it: dict):
    """(주소, 상세주소). 도로명 → 지번 → 상세주소/시도·시군구 순으로 채운다. 아무것도 없으면 ("", None)."""
    road = (it.get("faci_road_addr") or "").strip()
    jibun = (it.get("faci_addr") or "").strip()
    detail = (it.get("faci_road_daddr") or it.get("faci_daddr") or "").strip()
    addr = road or jibun
    if not addr:
        # 상세주소 칸에 주소가 들어 있는 경우가 있다 (예: "군포시 부곡동 1226번지")
        sido = (it.get("cp_nm") or it.get("addr_ctpv_nm") or "").strip()
        district = (it.get("cpb_nm") or it.get("addr_cpb_nm") or "").strip()
        parts = [p for p in (sido, detail or district) if p]
        if detail and district and district.split()[0] not in detail:
            parts = [p for p in (sido, district, detail) if p]
        addr = " ".join(parts)
        detail = ""
    return addr, (detail or None)


def to_float(v):
    try:
        return float(v)
    except (TypeError, ValueError):
        return None


def sql_str(v) -> str:
    if v is None or str(v).strip() == "":
        return "NULL"
    return "'" + str(v).strip().replace("'", "''") + "'"


def main():
    key = os.environ.get("DATA_GO_KR_KEY", "").strip()
    if not key:
        raise SystemExit('DATA_GO_KR_KEY 가 비어 있어요. -e DATA_GO_KR_KEY="인증키" 를 넣어 주세요.')
    regions = {r.strip() for r in os.environ.get("REGIONS", "").split(",") if r.strip()}

    first = fetch(key, 1)
    total = int(first.get("totalCount") or 0)
    pages = (total + PAGE_SIZE - 1) // PAGE_SIZE
    print(f"전체 체육시설 {total:,}곳, {pages}페이지를 확인합니다 (몇 분 걸려요)")

    found = {}
    skipped = {"폐업·휴업": 0, "위치 없음": 0, "이름·주소 없음": 0, "지역 제외": 0}
    for page in range(1, pages + 1):
        body = first if page == 1 else fetch(key, page)
        for it in items_of(body):
            if not is_futsal(it):
                continue
            if (it.get("faci_stat_nm") or "").strip() != "정상운영":
                skipped["폐업·휴업"] += 1
                continue
            lat, lng = to_float(it.get("faci_lat")), to_float(it.get("faci_lot"))
            if lat is None or lng is None or not (33 <= lat <= 39.5 and 124 <= lng <= 132):
                skipped["위치 없음"] += 1
                continue
            if not (it.get("faci_nm") or "").strip() or not resolve_address(it)[0]:
                skipped["이름·주소 없음"] += 1
                continue
            sido = (it.get("cp_nm") or it.get("addr_ctpv_nm") or "").strip()
            if regions and sido not in regions:
                skipped["지역 제외"] += 1
                continue
            found[it.get("faci_cd") or f"{it.get('faci_nm')}|{lat}|{lng}"] = it
        if page % 10 == 0 or page == pages:
            print(f"  {page}/{pages}페이지 — 지금까지 풋살장 {len(found)}곳")

    print(f"정상운영 중이고 위치가 있는 풋살장: {len(found)}곳 (제외: {skipped})")
    if not found:
        raise SystemExit("넣을 풋살장이 없어요.")

    by_region = {}
    lines = [
        "-- 공공데이터(국민체육진흥공단 전국체육시설 정보)로 만든 실제 풋살장 목록",
        "-- 코트·운영시간·가격은 전시 시연용 예시. 다시 만들면 이전에 넣은 공공데이터 구장은 지워지고 새로 들어간다.",
        "BEGIN;",
    ] + CLEANUP + [
    ]
    for it in found.values():
        sido = (it.get("cp_nm") or it.get("addr_ctpv_nm") or "").strip()
        code = region_code(sido, it) + "000"
        by_region[sido or "기타"] = by_region.get(sido or "기타", 0) + 1
        inout = (it.get("inout_gbn_nm") or "").strip()
        indoor = "true" if "실내" in inout else "false"
        day_price, night_price = (60000, 80000) if indoor == "true" else (40000, 55000)
        addr, detail = resolve_address(it)
        phone = it.get("faci_tel_no") or it.get("faci_telno")
        lines.append(
            "WITH v AS (INSERT INTO futsal_venues (name, description, road_address, detail_address, region_code, "
            "latitude, longitude, phone, rules, verification_status, verified_at, data_source) VALUES ("
            f"{sql_str((it.get('faci_nm') or '')[:100])}, {sql_str(DESCRIPTION)}, {sql_str(addr[:200])}, "
            f"{sql_str((detail or '')[:100])}, '{code}', {to_float(it.get('faci_lat'))}, {to_float(it.get('faci_lot'))}, "
            f"{sql_str((phone or '')[:20])}, {sql_str(RULES)}, 'VERIFIED', now(), 'PARTNER_API') RETURNING id), "
            "c AS (INSERT INTO courts (venue_id, name, is_indoor, surface, size_class) "
            f"SELECT id, '코트 1', {indoor}, 'ARTIFICIAL_TURF', '5V5' FROM v RETURNING id) "
            "INSERT INTO operating_hours (court_id, day_of_week, open_minute, close_minute, slot_minutes, price_per_slot) "
            f"SELECT c.id, d, 360, 1080, 60, {day_price} FROM c, generate_series(0, 6) d "
            f"UNION ALL SELECT c.id, d, 1080, 1440, 60, {night_price} FROM c, generate_series(0, 6) d;"
        )
    # 예약 가능 시간: 우선 14일치 (서버가 매일 새벽 30일치까지 자동으로 채운다)
    lines.append(
        "SELECT count(*) AS courts, sum(generate_time_slots(c.id, (now() AT TIME ZONE 'Asia/Seoul')::date, 14)) AS slots "
        "FROM courts c JOIN futsal_venues v ON v.id = c.venue_id WHERE v.data_source = 'PARTNER_API';")
    lines.append("COMMIT;")
    # 시연용 편의시설 (public_futsal_facilities.sql 과 같은 내용)
    fac = os.path.join(os.path.dirname(os.path.abspath(__file__)), "public_futsal_facilities.sql")
    if os.path.exists(fac):
        with open(fac, encoding="utf-8") as f:
            lines.append(f.read())

    with open(OUT, "w", encoding="utf-8") as f:
        f.write("\n".join(lines) + "\n")
    print("지역별:", ", ".join(f"{k} {v}" for k, v in sorted(by_region.items(), key=lambda x: -x[1])))
    if UNKNOWN_SIDO:
        print("주의: 지역 코드를 모르는 시도 →", ", ".join(sorted(UNKNOWN_SIDO)), "(앱의 '전체'에서만 보여요)")
    print(f"완료: {OUT} 를 만들었어요. 이제 DB 에 넣으면 돼요.")


if __name__ == "__main__":
    sys.exit(main())
