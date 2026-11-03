#!/usr/bin/env python3
"""Train a compact holistic plant-condition tree (standard library only).

The training set combines balanced agronomic scenarios with a small fixture of
real sensor patterns extracted from local logs. It is a presentation model, not
a validated agronomic diagnosis or a relay controller.
"""
from __future__ import annotations

import argparse
import json
import random
from pathlib import Path

from plant_health_common import (
    CLASSES,
    FEATURES,
    SCHEMA,
    TRAINING_DATA,
    features_for,
    label_for,
)


def candidate_row(rng: random.Random) -> tuple[list[float], int]:
    soil = rng.uniform(42.0, 78.0)
    water = rng.uniform(35.0, 86.0)
    light = rng.uniform(22.0, 82.0)
    temp = rng.uniform(19.0, 30.0)
    humidity = rng.uniform(42.0, 76.0)
    uv = rng.uniform(2.0, 9.0)
    gas = rng.uniform(0.0, 52.0)
    soil_trend = rng.uniform(-3.0, 3.0)
    water_trend = rng.uniform(-4.0, 4.0)
    pump_lockout = 0
    sensor_count = 3
    scenario = rng.choices(
        ["healthy", "watch", "dry", "heat", "air"],
        weights=[30, 26, 16, 16, 12],
    )[0]
    if scenario == "watch":
        target = rng.choice(
            ["soil_low", "water_low", "temp", "humidity", "gas", "light", "trend"]
        )
        if target == "soil_low":
            soil = rng.uniform(29.0, 38.0)
        elif target == "water_low":
            water = rng.uniform(18.0, 32.0)
        elif target == "temp":
            temp = rng.uniform(32.0, 35.0)
        elif target == "humidity":
            humidity = rng.uniform(27.0, 35.0)
        elif target == "gas":
            gas = rng.uniform(64.0, 76.0)
        elif target == "light":
            light = rng.uniform(4.0, 12.0)
        else:
            soil_trend = rng.uniform(-12.0, -8.0)
        if rng.random() < 0.25:
            pump_lockout = 1
        if rng.random() < 0.12:
            sensor_count = 2
    elif scenario == "dry":
        soil = rng.uniform(1.0, 22.0)
        water = rng.uniform(2.0, 32.0)
        soil_trend = rng.uniform(-20.0, -3.0)
        if rng.random() < 0.5:
            pump_lockout = 1
    elif scenario == "heat":
        temp = rng.uniform(35.0, 45.0)
        humidity = rng.uniform(18.0, 46.0)
        light = rng.uniform(55.0, 100.0)
    elif scenario == "air":
        gas = rng.uniform(80.0, 100.0)
    label = label_for(
        soil,
        water,
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
    return (
        features_for(
            soil,
            water,
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
        CLASSES.index(label),
    )


def balanced_dataset(total: int, rng: random.Random):
    per_class = total // len(CLASSES)
    buckets: list[list[tuple[list[float], int]]] = [[] for _ in CLASSES]
    while any(len(bucket) < per_class for bucket in buckets):
        row = candidate_row(rng)
        if len(buckets[row[1]]) < per_class:
            buckets[row[1]].append(row)
    rows = [row for bucket in buckets for row in bucket]
    rng.shuffle(rows)
    return rows


def load_observed(path: Path) -> list[tuple[list[float], int]]:
    if not path.exists():
        return []
    decoded = json.loads(path.read_text(encoding="utf-8"))
    rows = []
    for item in decoded.get("rows", []):
        features = item.get("features")
        label = item.get("label")
        if (
            isinstance(features, list)
            and len(features) == len(FEATURES)
            and all(isinstance(value, (int, float)) for value in features)
            and isinstance(label, str)
        ):
            # The old six-class dataset used "wet". On this probe, high soil
            # ADC is normal wet soil, so keep those real patterns as healthy.
            if label == "wet":
                label = "healthy"
            if label in CLASSES:
                rows.append(([float(value) for value in features], CLASSES.index(label)))
    return rows


class Node:
    __slots__ = ("feature", "threshold", "left", "right", "probabilities")

    def __init__(self, probabilities=None, feature=None, threshold=None,
                 left=None, right=None):
        self.feature = feature
        self.threshold = threshold
        self.left = left
        self.right = right
        self.probabilities = probabilities


def class_probabilities(rows) -> list[float]:
    counts = [0] * len(CLASSES)
    for _, label in rows:
        counts[label] += 1
    total = len(rows)
    return [count / total for count in counts]


def gini(probabilities: list[float]) -> float:
    return 1.0 - sum(value * value for value in probabilities)


def build_tree(rows, depth: int, max_depth: int, min_samples: int) -> Node:
    probabilities = class_probabilities(rows)
    if depth >= max_depth or len(rows) < min_samples or max(probabilities) >= 0.98:
        return Node(probabilities=probabilities)
    best_gini = gini(probabilities)
    best_feature = None
    best_threshold = None
    best_left = None
    best_right = None
    for feature in range(len(FEATURES)):
        values = sorted({row[0][feature] for row in rows})
        if len(values) < 2:
            continue
        step = max(1, len(values) // 24)
        thresholds = [
            (values[index] + values[index + 1]) / 2.0
            for index in range(0, len(values) - 1, step)
        ]
        for threshold in thresholds:
            left = [row for row in rows if row[0][feature] <= threshold]
            right = [row for row in rows if row[0][feature] > threshold]
            if len(left) < min_samples or len(right) < min_samples:
                continue
            weighted = (
                len(left) * gini(class_probabilities(left))
                + len(right) * gini(class_probabilities(right))
            ) / len(rows)
            if weighted < best_gini - 1e-6:
                best_gini = weighted
                best_feature = feature
                best_threshold = threshold
                best_left = left
                best_right = right
    if best_feature is None:
        return Node(probabilities=probabilities)
    return Node(
        feature=best_feature,
        threshold=best_threshold,
        left=build_tree(best_left, depth + 1, max_depth, min_samples),
        right=build_tree(best_right, depth + 1, max_depth, min_samples),
    )


def predict(node: Node, features: list[float]) -> tuple[int, float]:
    while node.probabilities is None:
        node = node.left if features[node.feature] <= node.threshold else node.right
    best = max(range(len(CLASSES)), key=lambda index: node.probabilities[index])
    return best, node.probabilities[best]


def to_json(node: Node):
    if node.probabilities is not None:
        return {"p": [round(value, 6) for value in node.probabilities]}
    return {
        "f": node.feature,
        "t": round(node.threshold, 4),
        "y": to_json(node.left),
        "n": to_json(node.right),
    }


def count_nodes(node: Node) -> int:
    if node.probabilities is not None:
        return 1
    return 1 + count_nodes(node.left) + count_nodes(node.right)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--out", default="mobile/assets/ml/plant-health.json")
    parser.add_argument("--real", default="tools/ml/real-patterns.json")
    parser.add_argument("--rows", type=int, default=24000)
    parser.add_argument("--seed", type=int, default=42)
    parser.add_argument("--max-depth", type=int, default=12)
    parser.add_argument("--min-samples", type=int, default=28)
    args = parser.parse_args()

    rng = random.Random(args.seed)
    synthetic = balanced_dataset(args.rows, rng)
    observed = load_observed(Path(args.real))
    rows = synthetic + observed
    rng.shuffle(rows)
    split = int(len(rows) * 0.85)
    training = rows[:split]
    holdout = rows[split:]
    root = build_tree(training, 0, args.max_depth, args.min_samples)

    correct = 0
    per_class = [0] * len(CLASSES)
    per_class_correct = [0] * len(CLASSES)
    for features, target in holdout:
        predicted, _ = predict(root, features)
        per_class[target] += 1
        if predicted == target:
            correct += 1
            per_class_correct[target] += 1
    accuracy = correct / len(holdout)
    counts = [
        sum(1 for _, label in rows if label == index)
        for index in range(len(CLASSES))
    ]
    asset = {
        "schema": SCHEMA,
        "training_data": TRAINING_DATA,
        "not_for_plant_health_or_relay_control": True,
        "features": FEATURES,
        "classes": CLASSES,
        "tree": to_json(root),
    }
    output = Path(args.out)
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(
        json.dumps(asset, sort_keys=True, separators=(",", ":")) + "\n",
        encoding="utf-8",
    )
    print(
        json.dumps(
            {
                "synthetic": len(synthetic),
                "observed": len(observed),
                "rows": len(rows),
                "training": len(training),
                "holdout": len(holdout),
                "counts": dict(zip(CLASSES, counts)),
                "accuracy": round(accuracy, 4),
                "per_class_recall": {
                    name: round(per_class_correct[i] / per_class[i], 4)
                    if per_class[i]
                    else 0
                    for i, name in enumerate(CLASSES)
                },
                "nodes": count_nodes(root),
                "asset_bytes": output.stat().st_size,
            },
            indent=2,
        )
    )


if __name__ == "__main__":
    main()
