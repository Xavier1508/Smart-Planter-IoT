"""Shared feature schema and labels for the Tunas plant-condition model."""
from __future__ import annotations

FEATURES = [
    "soil_percent",
    "water_percent",
    "light_percent",
    "temperature_c",
    "humidity_percent",
    "uv_index",
    "mq_gas_index",
    "soil_water_interaction",
    "soil_trend",
    "water_trend",
    "pump_lockout",
    "sensor_count",
]

CLASSES = ["healthy", "watch", "dry", "heat", "air"]
SCHEMA = "tunas-plant-health-tree-v3"
TRAINING_DATA = "synthetic_plus_observed_patterns_v3"


def features_for(
    soil: float,
    water: float,
    light: float,
    temp: float,
    humidity: float,
    uv: float,
    gas: float,
    soil_trend: float = 0.0,
    water_trend: float = 0.0,
    pump_lockout: int = 0,
    sensor_count: int = 3,
) -> list[float]:
    return [
        soil,
        water,
        light,
        temp,
        humidity,
        uv,
        gas,
        soil * water / 100.0,
        soil_trend,
        water_trend,
        float(pump_lockout),
        float(sensor_count),
    ]


def label_for(
    soil: float,
    water: float,
    light: float,
    temp: float,
    humidity: float,
    uv: float,
    gas: float,
    soil_trend: float = 0.0,
    water_trend: float = 0.0,
    pump_lockout: int = 0,
    sensor_count: int = 3,
) -> str:
    """Holistic class used by the presentation layer.

    There is no separate overwatering class. Very moist soil stays a watch
    condition, never an automatic "too wet" emergency. This keeps normal wet
    soil from being presented as a fault while still asking the user to watch.
    """
    if sensor_count < 2:
        return "watch"
    if soil < 22.0 or water < 10.0:
        return "dry"
    if temp >= 38.0 or (temp >= 34.0 and humidity < 30.0):
        return "heat"
    if gas >= 80.0:
        return "air"
    if (
        soil < 48.0
        or soil >= 88.0
        or water < 22.0
        or water >= 92.0
        or temp >= 32.0
        or temp <= 12.0
        or humidity < 32.0
        or humidity > 85.0
        or gas >= 65.0
        or light < 12.0
        or abs(soil_trend) >= 8.0
        or abs(water_trend) >= 12.0
        or pump_lockout
        or sensor_count < 3
    ):
        return "watch"
    return "healthy"
