#!/usr/bin/env python3
import argparse
import os
from pathlib import Path

import yaml


def load_yaml(p: Path) -> dict:
    with p.open("r", encoding="utf-8") as f:
        return yaml.safe_load(f) or {}


def save_yaml(p: Path, data: dict) -> None:
    with p.open("w", encoding="utf-8") as f:
        yaml.safe_dump(data, f, sort_keys=False)


def autodetect_device() -> tuple[str, bool]:
    try:
        import torch  # type: ignore

        if torch.cuda.is_available():
            return "cuda", True
        # macOS MPS not explicitly supported in tts config; fallback to cpu
    except Exception:
        pass
    return "cpu", False


def main():
    ap = argparse.ArgumentParser(description="Update GPT-SoVITS TTS infer config")
    ap.add_argument("--config", default="GPT_SoVITS/configs/tts_infer.yaml", help="Path to tts_infer.yaml")
    ap.add_argument("--device", choices=["cpu", "cuda"], help="Force device; omit to autodetect")
    ap.add_argument("--is-half", dest="is_half", action="store_true", help="Force fp16")
    ap.add_argument("--no-half", dest="no_half", action="store_true", help="Force fp32")
    ap.add_argument("--version", choices=["v1", "v2", "v2Pro", "v2ProPlus", "v3", "v4"], help="Model preset version")
    args = ap.parse_args()

    cfg_path = Path(args.config)
    data = load_yaml(cfg_path)

    custom = data.get("custom")
    if not isinstance(custom, dict):
        data["custom"] = custom = {}

    # Device and precision
    if args.device:
        device, half = args.device, None
    else:
        device, half = autodetect_device()

    custom["device"] = device

    if args.is_half:
        custom["is_half"] = True
    elif args.no_half:
        custom["is_half"] = False
    elif half is not None:
        custom["is_half"] = half

    # Version selection (keeps paths unless user updates)
    if args.version:
        custom["version"] = args.version

    save_yaml(cfg_path, data)
    print(f"Updated {cfg_path} -> device={custom.get('device')} is_half={custom.get('is_half')} version={custom.get('version')}")


if __name__ == "__main__":
    main()

