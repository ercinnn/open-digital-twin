"""Service-role Supabase client (bypasses RLS; backend only - never ship to clients)."""

from __future__ import annotations

from functools import lru_cache

from supabase import Client, create_client

from app.config import get_settings


class SupabaseNotConfiguredError(RuntimeError):
    pass


@lru_cache(maxsize=1)
def get_supabase() -> Client:
    settings = get_settings()
    if not settings.supabase_configured:
        raise SupabaseNotConfiguredError(
            "SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY must be set in the repository root .env"
        )
    return create_client(settings.supabase_url, settings.supabase_service_role_key)


def public_url(bucket: str, path: str) -> str:
    """Public object URL without the trailing '?' some storage3 versions append."""
    return get_supabase().storage.from_(bucket).get_public_url(path).rstrip("?")


def upload_bytes(bucket: str, path: str, data: bytes, content_type: str) -> None:
    get_supabase().storage.from_(bucket).upload(
        path=path,
        file=data,
        file_options={"content-type": content_type, "upsert": "true", "cache-control": "60"},
    )
