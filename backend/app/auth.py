"""Editor authentication for the API.

The backend holds the Supabase service-role key, so every endpoint that reads
or writes project data must be restricted to editors. Clients send their
Supabase session token (`Authorization: Bearer <access_token>`); the token is
validated by Supabase Auth and the user must be listed in `public.app_editors`
(the same rule as the RLS helper `public.is_editor()`).
"""

from __future__ import annotations

import logging

from fastapi import Header, HTTPException, status

from app.config import get_settings
from app.services.supabase_client import SupabaseNotConfiguredError, get_supabase

logger = logging.getLogger(__name__)

LOCAL_DEV_USER = "auth-disabled"


def _unauthorized(detail: str) -> HTTPException:
    return HTTPException(
        status_code=status.HTTP_401_UNAUTHORIZED,
        detail=detail,
        headers={"WWW-Authenticate": "Bearer"},
    )


def require_editor(authorization: str | None = Header(default=None)) -> str:
    """FastAPI dependency: returns the editor's user id or raises 401/403."""
    if not get_settings().auth_required:
        return LOCAL_DEV_USER

    scheme, _, token = (authorization or "").partition(" ")
    token = token.strip()
    if scheme.lower() != "bearer" or not token:
        raise _unauthorized("Sign in with an editor account (missing bearer token).")

    try:
        client = get_supabase()
    except SupabaseNotConfiguredError as exc:
        raise HTTPException(status_code=status.HTTP_503_SERVICE_UNAVAILABLE, detail=str(exc)) from exc

    try:
        response = client.auth.get_user(token)
    except Exception as exc:  # expired / malformed / revoked tokens
        logger.info("Rejected bearer token: %s", type(exc).__name__)
        raise _unauthorized("Session expired or invalid - sign in again.") from exc
    user = getattr(response, "user", None)
    if user is None:
        raise _unauthorized("Session expired or invalid - sign in again.")

    rows = (
        client.table("app_editors").select("user_id").eq("user_id", str(user.id)).limit(1).execute().data
    )
    if not rows:
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Editor access required.")
    return str(user.id)
