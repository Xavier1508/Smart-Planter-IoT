#!/usr/bin/env python3
"""Train the Moss XGBoost demo on explicitly synthetic rule-based samples.

Run from the repository using tools/ml/requirements.txt. This model imitates
specified thresholds; it is not a diagnosis, calibrated probability, or relay
controller. No real observation is turned into a labelled training row.
"""

from __future__ import annotations

import argparse
import csv
import hashlib
import io
import json
import math
import random
from pathlib import Path

import numpy as np
import xgboost as xgb

ROOT = Path(__file__).resolve().parents[2]
RUN = ROOT / "analysis/ml/xgboost-synthetic-rules-v2"
ASSET = ROOT / "mobile/assets/ml/pattern-models.json"
GOLDEN = ROOT / "mobile/test/fixtures/pattern-model-golden.json"
SCHEMA = "moss-synthetic-rule-xgboost-v1"
SEED = 20261031
ROWS = 60000
TRAIN_ROWS = 48000
FEATURES = ["soil_relative_percent", "water_observation_percent", "light_relative_percent", "uv_index"]
CLASSES = [
    "soil_relative_low",
    "water_near_low_reference",
    "no_synthetic_alert",
    "uv_unavailable",
    "light_hold_band",
    "light_relative_low",
]


def sha256(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest().upper()


def synthetic_label(soil: int, water: int, light: int, uv: int | None) -> int:
    """Artificial labels are rules, not independent plant observations."""
    if soil < 50:
        return 0
    if water < 20:
        return 1
    if light >= 70 or (uv is not None and uv > 7):
        return 2
    if uv is None:
        return 3
    if light >= 65 or uv == 7:
        return 4
    return 5


def generate_rows() -> list[dict]:
    rng = random.Random(SEED)
    rows = []
    for _ in range(ROWS):
        soil = rng.randrange(101)
        water = rng.randrange(101)
        light = rng.randrange(101)
        # UV index is invented only for synthetic rows; actual device UV is
        # unavailable until independently calibrated. Include missing cases.
        uv = None if rng.random() < 0.5 else rng.randint(1, 14)
        label = synthetic_label(soil, water, light, uv)
        rows.append(
            {
                "source_type": "synthetic_rules_v1",
                "soil_relative_percent": soil,
                "water_observation_percent": water,
                "light_relative_percent": light,
                "uv_index_synthetic": uv,
                # These extra values are plausible demonstration ranges only.
                # They do not affect the label and are not model features.
                "temperature_c_synthetic": round(rng.uniform(20.0, 35.0), 1),
                "humidity_percent_synthetic": rng.randint(40, 90),
                "mq135_adc_synthetic": None if rng.random() < 0.5 else rng.randint(1, 4094),
                "label_synthetic": CLASSES[label],
                "class_index": label,
            }
        )
    rng.shuffle(rows)
    for index, row in enumerate(rows):
        row["split"] = "train" if index < TRAIN_ROWS else "synthetic_holdout"
    return rows


def feature_values(row: dict) -> list[float]:
    return [
        float(row["soil_relative_percent"]),
        float(row["water_observation_percent"]),
        float(row["light_relative_percent"]),
        float("nan") if row["uv_index_synthetic"] is None else float(row["uv_index_synthetic"]),
    ]


def matrix(rows: list[dict]) -> xgb.DMatrix:
    data = np.asarray([feature_values(row) for row in rows], dtype=np.float32)
    labels = np.asarray([row["class_index"] for row in rows], dtype=np.float32)
    return xgb.DMatrix(data, label=labels, feature_names=FEATURES, missing=np.nan)


def flatten_tree(root: dict) -> list[dict]:
    nodes: dict[int, dict] = {}

    def visit(node: dict) -> None:
        node_id = node["nodeid"]
        if node_id in nodes:
            raise ValueError("Duplicate XGBoost node")
        if "leaf" in node:
            nodes[node_id] = {"leaf": float(node["leaf"])}
            return
        if node["split"] not in FEATURES:
            raise ValueError("Unexpected feature in XGBoost tree")
        nodes[node_id] = {
            "feature": FEATURES.index(node["split"]),
            "threshold": float(node["split_condition"]),
            "yes": int(node["yes"]),
            "no": int(node["no"]),
            "missing": int(node["missing"]),
        }
        for child in node["children"]:
            visit(child)

    visit(root)
    if sorted(nodes) != list(range(len(nodes))):
        raise ValueError("Non-contiguous tree nodes")
    return [nodes[index] for index in range(len(nodes))]


def portable_scores(trees: list[list[dict]], values: list[float]) -> list[float]:
    # XGBoost uses an equal base margin for these multiclass outputs, so it
    # cancels under softmax; trees are ordered round-major then class-major.
    margins = [0.0] * len(CLASSES)
    for tree_number, tree in enumerate(trees):
        index = 0
        for _ in range(len(tree)):
            node = tree[index]
            if "leaf" in node:
                margins[tree_number % len(CLASSES)] += node["leaf"]
                break
            value = values[node["feature"]]
            index = node["missing"] if math.isnan(value) else node["yes"] if value < node["threshold"] else node["no"]
        else:
            raise ValueError("Invalid XGBoost tree traversal")
    largest = max(margins)
    weights = [math.exp(value - largest) for value in margins]
    total = sum(weights)
    return [value / total for value in weights]


def write_new(path: Path, data: bytes) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("xb") as stream:
        stream.write(data)


def output_path(value: str, allowed_roots: tuple[Path, ...]) -> Path:
    path = Path(value)
    resolved = (path if path.is_absolute() else ROOT / path).resolve()
    if not any(resolved != base.resolve() and resolved.is_relative_to(base.resolve()) for base in allowed_roots):
        raise ValueError(f"Output is outside the allowed workspace categories: {value}")
    return resolved


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--run-dir", default=str(RUN))
    parser.add_argument("--asset", default=str(ASSET))
    parser.add_argument("--golden", default=str(GOLDEN))
    args = parser.parse_args()
    scratch = ROOT / ".opencode-tmp"
    run = output_path(args.run_dir, (ROOT / "analysis/ml", scratch))
    asset_path = output_path(args.asset, (ROOT / "mobile/assets/ml", scratch))
    golden_path = output_path(args.golden, (ROOT / "mobile/test/fixtures", scratch))
    if run.exists() or asset_path.exists() or golden_path.exists():
        raise SystemExit("Output already exists; refusing to overwrite user data.")
    rows = generate_rows()
    training, holdout = rows[:TRAIN_ROWS], rows[TRAIN_ROWS:]
    params = {
        "objective": "multi:softprob",
        "num_class": len(CLASSES),
        "base_score": 0.5,
        "max_depth": 5,
        "eta": 0.25,
        "tree_method": "hist",
        "nthread": 1,
        "seed": SEED,
        "subsample": 1.0,
        "colsample_bytree": 1.0,
    }
    booster = xgb.train(params, matrix(training), num_boost_round=40)
    reference = booster.predict(matrix(holdout))
    trees = [flatten_tree(json.loads(tree)) for tree in booster.get_dump(dump_format="json")]
    if len(trees) % len(CLASSES):
        raise ValueError("Unexpected multiclass tree count")
    correct = sum(int(np.argmax(p) == row["class_index"]) for p, row in zip(reference, holdout))
    # Independent portable evaluator parity, including missing UV and edges.
    golden_rows = holdout[:100]
    golden = []
    max_error = 0.0
    for row, expected in zip(golden_rows, reference[: len(golden_rows)]):
        actual = portable_scores(trees, feature_values(row))
        max_error = max(max_error, max(abs(a - float(b)) for a, b in zip(actual, expected)))
        golden.append({"features": [None if math.isnan(v) else v for v in feature_values(row)], "scores": [float(x) for x in expected]})
    if max_error > 0.00001:
        raise ValueError(f"Portable XGBoost evaluator parity failed: {max_error}")

    asset = {
        "schema": SCHEMA,
        "training_data": "synthetic_rule_labels_only",
        "not_for_plant_health_or_relay_control": True,
        "features": FEATURES,
        "classes": CLASSES,
        "trees": trees,
    }
    asset_bytes = (json.dumps(asset, sort_keys=True, separators=(",", ":")) + "\n").encode()
    golden_bytes = (json.dumps({"schema": SCHEMA, "vectors": golden}, indent=2) + "\n").encode()
    buffer = io.StringIO(newline="")
    fields = ["source_type", "soil_relative_percent", "water_observation_percent", "light_relative_percent", "uv_index_synthetic", "temperature_c_synthetic", "humidity_percent_synthetic", "mq135_adc_synthetic", "label_synthetic", "class_index", "split"]
    writer = csv.DictWriter(buffer, fieldnames=fields, lineterminator="\n")
    writer.writeheader()
    writer.writerows(rows)
    dataset_bytes = buffer.getvalue().encode()
    class_counts = {name: sum(row["label_synthetic"] == name for row in rows) for name in CLASSES}
    report = {
        "schema": SCHEMA,
        "seed": SEED,
        "xgboost_version": xgb.__version__,
        "numpy_version": np.__version__,
        "features": FEATURES,
        "synthetic_training_rows": len(training),
        "synthetic_holdout_rows": len(holdout),
        "synthetic_class_counts": class_counts,
        "synthetic_holdout_accuracy": correct / len(holdout),
        "rule_baseline_accuracy_on_same_synthetic_labels": 1.0,
        "portable_vs_xgboost_max_error_on_100_synthetic_vectors": max_error,
        "independent_real_validation": False,
        "synthetic_csv_sha256": sha256(dataset_bytes),
        "asset_sha256": sha256(asset_bytes),
        "golden_sha256": sha256(golden_bytes),
        "assumptions": [
            "Soil <50 and water display <20 are pre-existing prototype thresholds, not verified plant needs or empty-tank levels.",
            "LDR >=70 or UV index >7 indicates sufficient light; LDR <65 and UV index <7 produces a light-low synthetic label; 65..69 or exactly UV 7 holds when inputs are present.",
            "UV 1..14 exists only as synthetic examples; an uncalibrated live UV ADC is never converted to a fabricated index.",
            "Synthetic DHT and MQ values are demonstration inputs, do not affect labels and are not model features.",
        ],
        "limitations": [
            "All examples and labels are synthetic and encode the chosen rules, not independent plant-health labels.",
            "Synthetic holdout accuracy measures imitation of synthetic rules; it does not measure real-world predictive accuracy.",
            "The resulting scores are not calibrated probabilities of plant health or measured soil moisture.",
            "The model is diagnostic only and cannot issue any relay command.",
        ],
    }
    notes = (
        "# XGBoost on synthetic prototype rules\n\n"
        "60,000 generated rows cover relative soil/water/light 0–100 and optional synthetic UV index 1–14. "
        "Rows, labels, DHT and MQ examples are synthetic; they are not real observations. "
        "The model imitates the declared thresholds, so synthetic accuracy is not evidence "
        "of plant health, real-world accuracy or suitability for controlling a relay.\n\n"
        f"Synthetic CSV SHA-256: `{sha256(dataset_bytes)}`. Model SHA-256: `{sha256(asset_bytes)}`. "
        f"Golden vectors SHA-256: `{sha256(golden_bytes)}`. See `metrics.json` for details.\n"
    ).encode()
    write_new(run / "synthetic-observations.csv", dataset_bytes)
    write_new(run / "metrics.json", (json.dumps(report, indent=2) + "\n").encode())
    write_new(run / "notes.md", notes)
    write_new(asset_path, asset_bytes)
    write_new(golden_path, golden_bytes)
    print(json.dumps({"rows": len(rows), "train": len(training), "holdout": len(holdout), "classes": class_counts, "synthetic_accuracy": correct / len(holdout), "baseline_accuracy": 1.0, "max_portable_error": max_error, "trees": len(trees), "dataset_sha256": sha256(dataset_bytes), "asset_sha256": sha256(asset_bytes), "golden_sha256": sha256(golden_bytes)}, indent=2))


if __name__ == "__main__":
    main()
