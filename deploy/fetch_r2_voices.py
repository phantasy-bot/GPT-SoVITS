#!/usr/bin/env python3
import argparse
import json
import os
import sys
from pathlib import Path

import yaml


def eprint(*args, **kwargs):
    print(*args, file=sys.stderr, **kwargs)


def load_env():
    # Optional python-dotenv support without hard dependency
    try:
        from dotenv import load_dotenv  # type: ignore

        load_dotenv()
    except Exception:
        pass

    cfg = {
        "endpoint_url": os.getenv("R2_ENDPOINT_URL"),
        "region": os.getenv("R2_REGION", "auto"),
        "access_key": os.getenv("R2_ACCESS_KEY_ID"),
        "secret_key": os.getenv("R2_SECRET_ACCESS_KEY"),
        "bucket": os.getenv("R2_BUCKET"),
        "prefix": os.getenv("R2_PREFIX", ""),
    }
    return cfg


def normalize_lang(lang: str) -> str:
    if not lang:
        return lang
    alias = {
        "jp": "ja",
        "ja": "ja",
        "kr": "ko",
        "ko": "ko",
        "cn": "zh",
        "zh": "zh",
        "en": "en",
        "yue": "yue",  # supported by v2
    }
    return alias.get(lang.lower().strip(), lang.lower())


def ensure_boto3():
    try:
        import boto3  # noqa: F401
        return True
    except Exception:
        eprint("boto3 not installed. Install with: pip install boto3 python-dotenv")
        return False


def ensure_requests():
    try:
        import requests  # noqa: F401
        return True
    except Exception:
        eprint("requests not installed. Install with: pip install requests python-dotenv")
        return False


def read_yaml(path: Path) -> dict:
    with path.open("r", encoding="utf-8") as f:
        return yaml.safe_load(f) or {}


def join_key(prefix: str, key: str) -> str:
    if not prefix:
        return key
    return f"{prefix.rstrip('/')}/{key.lstrip('/')}"


def join_url(base: str, key: str) -> str:
    return f"{base.rstrip('/')}/{key.lstrip('/')}"


def download_voices(config_path: Path, out_dir: Path, overwrite: bool = False, dry_run: bool = False) -> Path:
    y = read_yaml(config_path)
    characters = y.get("characters") or {}
    if not isinstance(characters, dict):
        eprint("voices.yaml 'characters' must be a mapping of character -> languages -> samples")
        sys.exit(2)

    http_base = y.get("base_url") or (y.get("http", {}) or {}).get("base_url")
    use_http = bool(http_base)

    s3 = None
    cfg = None
    r2_prefix = None
    if not use_http:
        if not ensure_boto3():
            sys.exit(2)
        import boto3
        from botocore.client import Config as BotoConfig

        cfg = load_env()
        if not all([cfg.get("endpoint_url"), cfg.get("access_key"), cfg.get("secret_key"), cfg.get("bucket")]):
            eprint(
                "Missing R2 environment variables. Required: R2_ENDPOINT_URL, R2_ACCESS_KEY_ID, R2_SECRET_ACCESS_KEY, R2_BUCKET"
            )
            sys.exit(2)
        r2_prefix = (y.get("r2", {}) or {}).get("prefix", cfg.get("prefix", ""))

        s3 = boto3.client(
            "s3",
            endpoint_url=cfg["endpoint_url"],
            aws_access_key_id=cfg["access_key"],
            aws_secret_access_key=cfg["secret_key"],
            region_name=cfg.get("region") or "auto",
            config=BotoConfig(signature_version="s3v4"),
        )
    else:
        if not ensure_requests():
            sys.exit(2)
        import requests  # noqa

    out_dir.mkdir(parents=True, exist_ok=True)
    index = []

    for character, langs in characters.items():
        if not isinstance(langs, dict):
            eprint(f"Skip character '{character}': expected mapping of languages")
            continue
        for lang_raw, samples in langs.items():
            lang = normalize_lang(lang_raw)
            if not samples:
                continue
            if isinstance(samples, dict):
                # Support shorthand mapping name->key
                samples_iter = [{"name": k, "key": v} for k, v in samples.items()]
            else:
                samples_iter = list(samples)

            for s in samples_iter:
                name = s.get("name")
                key = s.get("key")
                if not (name and key):
                    # allow auto key if only 'name' given
                    if name and not key:
                        key = f"{character}/{character}-{lang}-{name}.wav"
                    else:
                        eprint(f"Skip invalid sample under {character}/{lang_raw}: {s}")
                        continue

                dest_dir = out_dir / character / lang
                dest_dir.mkdir(parents=True, exist_ok=True)
                ext = Path(key).suffix or ".wav"
                dest = dest_dir / f"{name}{ext}"

                item = {
                    "character": character,
                    "lang": lang,
                    "name": name,
                    "r2_key": None,
                    "path": str(dest.as_posix()),
                }

                if use_http:
                    url = join_url(http_base, key)
                    item["url"] = url
                    if dest.exists() and not overwrite:
                        eprint(f"Exists: {dest}")
                    else:
                        eprint(f"Downloading {url} -> {dest}")
                        if not dry_run:
                            tmp = dest.with_suffix(dest.suffix + ".part")
                            import requests

                            with requests.get(url, stream=True, timeout=60) as r:
                                r.raise_for_status()
                                with open(tmp, "wb") as f:
                                    for chunk in r.iter_content(chunk_size=8192):
                                        if chunk:
                                            f.write(chunk)
                            tmp.replace(dest)
                else:
                    obj_key = join_key(r2_prefix or "", key)
                    item["r2_key"] = obj_key
                    if dest.exists() and not overwrite:
                        eprint(f"Exists: {dest}")
                    else:
                        eprint(f"Downloading s3://{cfg['bucket']}/{obj_key} -> {dest}")
                        if not dry_run:
                            tmp = dest.with_suffix(dest.suffix + ".part")
                            s3.download_file(cfg["bucket"], obj_key, str(tmp))
                            tmp.replace(dest)

                index.append(item)

    index_path = out_dir / "voices_index.json"
    with index_path.open("w", encoding="utf-8") as f:
        json.dump(index, f, ensure_ascii=False, indent=2)

    return index_path


def main():
    ap = argparse.ArgumentParser(description="Fetch voice samples from Cloudflare R2 (S3-compatible)")
    ap.add_argument("--config", required=True, help="Path to voices.yaml")
    ap.add_argument("--out", default="assets/voices", help="Output directory for voice samples")
    ap.add_argument("--overwrite", action="store_true", help="Overwrite existing files")
    ap.add_argument("--dry-run", action="store_true", help="List actions without downloading")
    args = ap.parse_args()

    config_path = Path(args.config).resolve()
    out_dir = Path(args.out).resolve()
    index = download_voices(config_path, out_dir, overwrite=args.overwrite, dry_run=args.dry_run)
    print(index)


if __name__ == "__main__":
    main()
