#!/usr/bin/env python3
"""Train a compact 3-class plant-condition decision tree (standard library only).

Synthetic labels deliberately cover flood/overwatering, drought, heat and gas
extremes. This is a demo model, not agronomic validation. The CSV export from
Tunas uses the same feature names so the tree can be retrained on measured rows.
"""
from __future__ import annotations

import argparse
import json
import math
import random
from pathlib import Path

FEATURES = [
    "soil_percent",
    "water_percent",
    "light_percent",
    "temperature_c",
    "humidity_percent",
    "uv_index",
    "mq_gas_index",
    "soil_water_interaction",
]
CLASSES = ["healthy", "warning", "critical"]
SCHEMA = "tunas-plant-health-tree-v1"


def features_for(soil: float, water: float, light: float, temp: float,
                 humidity: float, uv: float, gas: float) -> list[float]:
    return [soil, water, light, temp, humidity, uv, gas, soil * water / 100.0]


def label_for(soil: float, water: float, light: float, temp: float,
              humidity: float, uv: float, gas: float) -> int:
    flood = soil >= 85.0 and water >= 75.0
    drought = soil < 18.0 or water < 8.0
    heat = temp >= 40.0 or temp <= 6.0
    gas_critical = gas >= 85.0
    if flood or drought or heat or gas_critical:
        return 2
    if (soil < 35.0 or soil >= 78.0 or water < 25.0 or water >= 88.0
            or temp >= 34.0 or temp <= 12.0 or gas >= 65.0 or light < 8.0):
        return 1
    return 0


def candidate_row(rng: random.Random) -> tuple[list[float], int]:
    soil = rng.uniform(0.0, 100.0)
    water = rng.uniform(0.0, 100.0)
    light = rng.uniform(0.0, 100.0)
    temp = rng.uniform(6.0, 43.0)
    humidity = rng.uniform(20.0, 95.0)
    uv = rng.uniform(0.0, 14.0)
    gas = rng.uniform(0.0, 100.0)
    roll = rng.random()
    if roll < 0.14:
        soil = rng.uniform(85.0, 100.0)
        water = rng.uniform(75.0, 100.0)
    elif roll < 0.28:
        soil = rng.uniform(0.0, 22.0)
        water = rng.uniform(0.0, 35.0)
    elif roll < 0.38:
        temp = rng.uniform(38.0, 45.0)
        humidity = rng.uniform(20.0, 50.0)
    elif roll < 0.48:
        gas = rng.uniform(80.0, 100.0)
    elif roll < 0.58:
        soil = rng.uniform(35.0, 70.0)
        water = rng.uniform(40.0, 80.0)
        temp = rng.uniform(20.0, 30.0)
        humidity = rng.uniform(45.0, 75.0)
        gas = rng.uniform(0.0, 45.0)
        light = rng.uniform(25.0, 80.0)
        uv = rng.uniform(2.0, 10.0)
    label = label_for(soil, water, light, temp, humidity, uv, gas)
    return features_for(soil, water, light, temp, humidity, uv, gas), label


def balanced_dataset(total: int, rng: random.Random):
    per_class = total // len(CLASSES)
    buckets: list[list[tuple[list[float], int]]] = [[], [], []]
    while any(len(bucket) < per_class for bucket in buckets):
        row = candidate_row(rng)
        if len(buckets[row[1]]) < per_class:
            buckets[row[1]].append(row)
    rows = [row for bucket in buckets for row in bucket]
    rng.shuffle(rows)
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
    counts = [0, 0, 0]
    for _, label in rows:
        counts[label] += 1
    total = len(rows)
    return [count / total for count in counts]


def gini(probabilities: list[float]) -> float:
    return 1.0 - sum(value * value for value in probabilities)


def build_tree(rows, depth: int, max_depth: int,
               min_samples: int) -> Node:
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
            weighted = (len(left) * gini(class_probabilities(left)) +
                        len(right) * gini(class_probabilities(right))) / len(rows)
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
    best = max(range(len(CLASSES)),
               key=lambda index: node.probabilities[index])
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
    parser.add_argument("--rows", type=int, default=18000)
    parser.add_argument("--seed", type=int, default=42)
    parser.add_argument("--max-depth", type=int, default=10)
    parser.add_argument("--min-samples", type=int, default=32)
    args = parser.parse_args()

    rng = random.Random(args.seed)
    rows = balanced_dataset(args.rows, rng)
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
    counts = [sum(1 for _, label in rows if label == index)
              for index in range(len(CLASSES))]
    asset = {
        "schema": SCHEMA,
        "training_data": "synthetic_agronomic_bands_v1",
        "not_for_plant_health_or_relay_control": True,
        "features": FEATURES,
        "classes": CLASSES,
        "tree": to_json(root),
    }
    output = Path(args.out)
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(json.dumps(asset, sort_keys=True, separators=(",", ":")) + "\n",
                      encoding="utf-8")
    print(json.dumps({
        "rows": len(rows),
        "training": len(training),
        "holdout": len(holdout),
        "counts": dict(zip(CLASSES, counts)),
        "accuracy": round(accuracy, 4),
        "per_class_recall": {
            name: round(per_class_correct[i] / per_class[i], 4) if per_class[i] else 0
            for i, name in enumerate(CLASSES)
        },
        "nodes": count_nodes(root),
        "asset_bytes": output.stat().st_size,
    }, indent=2))


if __name__ == "__main__":
    main()
