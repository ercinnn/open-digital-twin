"""Re-apply supabase/seed.sql to the remote database (resets ALL demo projects).

The Supabase CLI runs a seed file only once (later pushes merely record the new
hash). This script executes seed.sql directly over the session pooler, then the
demo assets must be re-linked (documents / GLB URLs) - pass --publish to run
`scripts.publish_sample_assets` afterwards.

Connection: supabase/.temp/pooler-url (written by `supabase link`) + the
SUPABASE_DB_PASSWORD from the root .env. Requires `psycopg[binary]`
(requirements-deploy.txt).

Run from backend/:
    .venv\\Scripts\\python -m scripts.reset_demo_data [--publish]
"""

from __future__ import annotations

import argparse
import os
import sys
from pathlib import Path
from urllib.parse import quote, urlsplit, urlunsplit

from app.config import get_settings  # noqa: F401  (loads the root .env into os.environ)

REPO_ROOT = Path(__file__).resolve().parents[2]
SEED_FILE = REPO_ROOT / "supabase" / "seed.sql"
POOLER_FILE = REPO_ROOT / "supabase" / ".temp" / "pooler-url"


def connection_url() -> str:
    password = os.environ.get("SUPABASE_DB_PASSWORD", "").strip().strip('"')
    if not password:
        raise SystemExit("SUPABASE_DB_PASSWORD is missing in the root .env")
    if not POOLER_FILE.exists():
        raise SystemExit(f"{POOLER_FILE} not found - run `supabase link` first")
    parts = urlsplit(POOLER_FILE.read_text(encoding="utf-8").strip())
    netloc = f"{parts.username}:{quote(password, safe='')}@{parts.hostname}:{parts.port or 5432}"
    query = parts.query or "sslmode=require"
    return urlunsplit((parts.scheme, netloc, parts.path or "/postgres", query, ""))


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--publish", action="store_true", help="Run scripts.publish_sample_assets afterwards.")
    args = parser.parse_args()

    try:
        import psycopg
    except ImportError as exc:  # pragma: no cover - tooling dependency
        raise SystemExit("psycopg is not installed: pip install -r requirements-deploy.txt") from exc

    sql = SEED_FILE.read_text(encoding="utf-8")
    print(f"Applying {SEED_FILE.relative_to(REPO_ROOT)} ({len(sql) // 1024} KB) ...")
    with psycopg.connect(connection_url(), autocommit=False) as conn:
        conn.execute(sql)
        conn.commit()
        rows = conn.execute(
            "select (select count(*) from public.components), (select count(*) from public.telemetry_logs)"
        ).fetchone()
    print(f"Seed applied: {rows[0]} components, {rows[1]} telemetry rows in the database.")

    if args.publish:
        from scripts import publish_sample_assets

        sys.argv = [sys.argv[0]]
        return publish_sample_assets.main()
    return 0


if __name__ == "__main__":
    sys.exit(main())
