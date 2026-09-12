import hashlib
import hmac
import logging
import asyncio
from contextlib import asynccontextmanager
from datetime import datetime, timedelta, timezone
from uuid import uuid4

from fastapi import Depends, FastAPI, File, Form, Header, HTTPException, UploadFile
from fastapi.middleware.cors import CORSMiddleware
from supabase import Client, create_client

from .config import Settings, get_settings
from .vision import (
    CheckFailure,
    FaceEngine,
    decode_image,
    inspect_document,
)


logger = logging.getLogger(__name__)


@asynccontextmanager
async def lifespan(_: FastAPI):
    settings = get_settings()
    _, admin = clients(settings)
    _purge_expired(admin)
    task = asyncio.create_task(_cleanup_loop(admin))
    try:
        yield
    finally:
        task.cancel()


app = FastAPI(
    title="ohMY Travel Verified Traveller Prototype",
    lifespan=lifespan,
)
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["GET", "POST"],
    allow_headers=["Authorization", "Content-Type"],
)


def clients(settings: Settings) -> tuple[Client, Client]:
    anon = create_client(settings.supabase_url, settings.supabase_anon_key)
    admin = create_client(settings.supabase_url, settings.supabase_service_role_key)
    return anon, admin


async def signed_in_user(
    authorization: str = Header(default=""),
    settings: Settings = Depends(get_settings),
) -> str:
    if not authorization.startswith("Bearer "):
        raise CheckFailure("authentication", "Please sign in again.", False)
    token = authorization.removeprefix("Bearer ").strip()
    anon, _ = clients(settings)
    try:
        response = anon.auth.get_user(token)
        if response.user is None:
            raise ValueError("No user")
        return str(response.user.id)
    except Exception as error:
        raise CheckFailure("authentication", "Your session has expired. Sign in again.", False) from error


@app.exception_handler(CheckFailure)
async def check_failure_handler(_, error: CheckFailure):
    from fastapi.responses import JSONResponse

    return JSONResponse(
        status_code=422,
        content={
            "verified": False,
            "message": error.message,
            "code": error.code,
            "retryable": error.retryable,
        },
    )


@app.get("/health")
def health():
    return {"status": "ok", "mode": "university-prototype"}


@app.post("/verify")
async def verify(
    document_type: str = Form(...),
    document_front: UploadFile = File(...),
    selfie: UploadFile = File(...),
    document_back: UploadFile | None = File(default=None),
    user_id: str = Depends(signed_in_user),
    settings: Settings = Depends(get_settings),
):
    _, admin = clients(settings)
    already_verified = (
        admin.table("identity_verifications")
        .select("id")
        .eq("user_id", user_id)
        .eq("status", "verified")
        .limit(1)
        .execute()
        .data
    )
    if already_verified:
        return {
            "verified": True,
            "message": "This account is already a Verified Traveller.",
        }

    front_bytes = await document_front.read()
    back_bytes = await document_back.read() if document_back else None
    selfie_bytes = await selfie.read()
    verification_id = str(uuid4())
    now = datetime.now(timezone.utc)
    row = {
        "id": verification_id,
        "user_id": user_id,
        "document_type": document_type,
        "status": "processing",
        "created_at": now.isoformat(),
        "updated_at": now.isoformat(),
    }
    admin.table("identity_verifications").insert(row).execute()

    try:
        face_engine = FaceEngine(settings)
        front = decode_image(front_bytes)
        back = decode_image(back_bytes) if back_bytes else None
        live_selfie = decode_image(selfie_bytes)
        document = inspect_document(
            document_type, front, back, settings, face_engine
        )
        document_hash = hmac.new(
            settings.document_hmac_secret.encode(),
            f"{document_type}:{document.identifier}".encode(),
            hashlib.sha256,
        ).hexdigest()

        duplicate = (
            admin.table("identity_verifications")
            .select("id,user_id")
            .eq("document_hash", document_hash)
            .eq("status", "verified")
            .neq("user_id", user_id)
            .limit(1)
            .execute()
            .data
        )
        if duplicate:
            raise CheckFailure(
                "identity_linked",
                "This identity document is already linked to another account.",
                retryable=False,
            )

        score = face_engine.similarity(document.portrait, live_selfie)
        if score < settings.face_match_threshold:
            raise CheckFailure(
                "face_mismatch",
                "Your selfie did not match the submitted identity document.",
            )

        admin.table("identity_verifications").update(
            {
                "document_hash": document_hash,
                "status": "verified",
                "face_match_score": score,
                "verified_at": now.isoformat(),
                "updated_at": now.isoformat(),
            }
        ).eq("id", verification_id).execute()
        admin.auth.admin.update_user_by_id(
            user_id, {"app_metadata": {"is_verified": True}}
        )
        return {
            "verified": True,
            "message": "Verification successful. You’re now a Verified Traveller.",
            "face_match_score": round(score, 4),
        }
    except CheckFailure as error:
        prefix = f"{user_id}/{verification_id}"
        try:
            _store_failed_photos(
                admin,
                prefix,
                front_bytes,
                back_bytes,
                selfie_bytes,
            )
        except Exception:
            logger.exception("Could not retain failed verification photos")
        admin.table("identity_verifications").update(
            {
                "status": "failed",
                "failure_code": error.code,
                "storage_prefix": prefix,
                "purge_after": (now + timedelta(hours=24)).isoformat(),
                "updated_at": now.isoformat(),
            }
        ).eq("id", verification_id).execute()
        return {
            "verified": False,
            "message": error.message,
            "code": error.code,
            "retryable": error.retryable,
        }
    except Exception as error:
        logger.exception("Unexpected verification failure for user %s", user_id)
        try:
            admin.table("identity_verifications").update(
                {
                    "status": "failed",
                    "failure_code": "service_error",
                    "updated_at": datetime.now(timezone.utc).isoformat(),
                }
            ).eq("id", verification_id).execute()
        except Exception:
            logger.exception("Could not mark verification %s as failed", verification_id)

        detail = "The verification service failed while processing the photos."
        if "Tesseract" in str(error):
            detail = (
                "Tesseract OCR is not installed or configured on the laptop. "
                "Install it and restart run-ohmy.ps1."
            )
        raise HTTPException(status_code=503, detail=detail) from error


def _store_failed_photos(
    admin: Client,
    prefix: str,
    front: bytes,
    back: bytes | None,
    selfie: bytes,
) -> None:
    bucket = admin.storage.from_("identity-verification-private")
    files = {
        "document-front.jpg": front,
        "selfie.jpg": selfie,
    }
    if back:
        files["document-back.jpg"] = back
    for name, contents in files.items():
        bucket.upload(
            f"{prefix}/{name}",
            contents,
            {"content-type": "image/jpeg", "upsert": "true"},
        )


async def _cleanup_loop(admin: Client) -> None:
    while True:
        await asyncio.sleep(30 * 60)
        _purge_expired(admin)


def _purge_expired(admin: Client) -> None:
    now = datetime.now(timezone.utc).isoformat()
    rows = (
        admin.table("identity_verifications")
        .select("id,storage_prefix")
        .not_.is_("storage_prefix", "null")
        .lt("purge_after", now)
        .execute()
        .data
    )
    bucket = admin.storage.from_("identity-verification-private")
    names = [
        "document-front.jpg",
        "document-back.jpg",
        "selfie.jpg",
        # Keep the old names in the purge list so attempts created by the
        # earlier three-selfie prototype are still cleaned up.
        "selfie-centre.jpg",
        "selfie-left.jpg",
        "selfie-right.jpg",
    ]
    for row in rows:
        prefix = row["storage_prefix"]
        try:
            bucket.remove([f"{prefix}/{name}" for name in names])
        finally:
            admin.table("identity_verifications").update(
                {"storage_prefix": None, "purge_after": None, "updated_at": now}
            ).eq("id", row["id"]).execute()
