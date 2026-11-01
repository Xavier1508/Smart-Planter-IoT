#!/usr/bin/env python3
"""Extract representative observed patterns from local serial-monitor logs.

The generated JSON is a small, committed fixture used by the training script.
It does not contain raw serial logs, passwords, or device identifiers.
"""
from __future__ import annotations

import argparse
import json
import math
from collections import Counter
from pathlib import Path

from plant_health_common import CLASSES, features_for, label_for


def number(value) -> float | None:
    return float(value) if isinstance(value, (int, float)) and math.isfinite(value) else None


def water_percent(raw: float) -> float:
    return max(0.0, min(100.0, (raw - 450.0) * 100.0 / 900.0))


def rows_from_log(path: Path) -> list[dict]:
    samples = []
    for line in path.read_text(encoding="utf-8", errors="replace").splitlines():
        line = line.strip()
        if not line.startswith("{"):
            continue
        try:
            item = json.loads(line)
        except json.JSONDecodeError:
            continue
        if item.get("type") == "sample":
            samples.append(item)
    rows: list[dict] = []
    for index, item in enumerate(samples):
        adc = item.get("adc") or {}
        water = item.get("water_level") or {}
        dht = item.get("dht") or {}
        mq = item.get("mq135") or {}
        soil = number(adc.get("soil_relative_percent"))
        raw = number(water.get("adc_raw"))
        light = number(adc.get("light_relative_percent"))
        temp = number(dht.get("temperature_c"))
        humidity = number(dht.get("humidity_percent"))
        uv_raw = number(adc.get("uv_raw"))
        gas = number(mq.get("adc_percent"))
        if None in (soil, raw, light, temp, humidity, gas):
            continue
        if raw <= 0 or raw >= 4095:
            continue
        soil = max(0.0, min(100.0, soil))
        light = max(0.0, min(100.0, light))
        gas = max(0.0, min(100.0, gas))
        uv = 0.0 if uv_raw is None else max(0.0, min(14.0, uv_raw * 14.0 / 4095.0))
        water_pct = water_percent(raw)
        previous = samples[max(0, index - 6)]
        previous_adc = previous.get("adc") or {}
        previous_water = previous.get("water_level") or {}
        soil_before = number(previous_adc.get("soil_relative_percent"))
        raw_before = number(previous_water.get("adc_raw"))
        soil_trend = 0.0 if soil_before is None else max(-100.0, min(100.0, soil - soil_before))
        water_trend = (
            0.0
            if raw_before is None
            else max(-100.0, min(100.0, water_pct - water_percent(raw_before)))
        )
        pump_lockout = 1 if item.get("pump_reason") == "runtime_limit" else 0
        sensor_count = 3
        label = label_for(
            soil,
            water_pct,
            light,
            temp,
            humidity,
            uv,
            gas,
            soil_trend,
            water_trend,
            pump_lockout,
            sensor_count,
        )
        rows.append(
            {
                "features": features_for(
                    soil,
                    water_pct,
                    light,
                    temp,
                    humidity,
                    uv,
                    gas,
                    soil_trend,
                    water_trend,
                    pump_lockout,
                    sensor_count,
                ),
                "label": label,
                "source": path.name,
                "uptime_ms": item.get("uptime_ms"),
            }
        )
    return rows


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--logs", default=".opencode-tmp/serial-monitor/logs")
    parser.add_argument("--out", default="tools/ml/real-patterns.json")
    parser.add_argument("--per-class", type=int, default=80)
    args = parser.parse_args()

    all_rows: list[dict] = []
    for path in sorted(Path(args.logs).glob("*.log")):
        all_rows.extend(rows_from_log(path))

    # Keep a bounded, varied sample per class. A stable stride avoids taking
    # only the first minutes of a long log.
    buckets: dict[str, list[dict]] = {name: [] for name in CLASSES}
    for row in all_rows:
        buckets.setdefault(row["label"], []).append(row)
    selected: list[dict] = []
    for name in CLASSES:
        rows = buckets.get(name, [])
        if len(rows) > args.per_class:
            step = max(1, len(rows) // args.per_class)
            rows = rows[::step][: args.per_class]
        selected.extend(rows)

    output = Path(args.out)
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(
        json.dumps(
            {
                "schema": "tunas-observed-patterns-v1",
                "source": "local serial-monitor logs, derived features only",
                "rows": selected,
            },
            indent=2,
            sort_keys=True,
        )
        + "\n",
        encoding="utf-8",
    )
    print(
        json.dumps(
            {
                "input_rows": len(all_rows),
                "selected": len(selected),
                "counts": dict(Counter(row["label"] for row in selected)),
                "bytes": output.stat().st_size,
            },
            indent=2,
        )
    )


if __name__ == "__main__":
    main()
