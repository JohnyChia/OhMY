import os
from dataclasses import dataclass
from pathlib import Path

from dotenv import load_dotenv


BASE_DIR = Path(__file__).resolve().parent.parent
load_dotenv(BASE_DIR / ".env")


@dataclass(frozen=True)
class Settings:
    supabase_url: str
    supabase_anon_key: str
    supabase_service_role_key: str
    document_hmac_secret: str
    face_match_threshold: float
    tesseract_cmd: str | None
    max_attempts: int = 3


def get_settings() -> Settings:
    required = {
        "SUPABASE_URL": os.getenv("SUPABASE_URL", ""),
        "SUPABASE_ANON_KEY": os.getenv("SUPABASE_ANON_KEY", ""),
        "SUPABASE_SERVICE_ROLE_KEY": os.getenv("SUPABASE_SERVICE_ROLE_KEY", ""),
        "DOCUMENT_HMAC_SECRET": os.getenv("DOCUMENT_HMAC_SECRET", ""),
    }
    missing = [name for name, value in required.items() if not value]
    if missing:
        raise RuntimeError(f"Missing backend settings: {', '.join(missing)}")
    return Settings(
        supabase_url=required["SUPABASE_URL"],
        supabase_anon_key=required["SUPABASE_ANON_KEY"],
        supabase_service_role_key=required["SUPABASE_SERVICE_ROLE_KEY"],
        document_hmac_secret=required["DOCUMENT_HMAC_SECRET"],
        face_match_threshold=float(os.getenv("FACE_MATCH_THRESHOLD", "0.42")),
        tesseract_cmd=os.getenv("TESSERACT_CMD") or None,
    )
