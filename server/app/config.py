"""Runtime configuration. Postgres in production; SQLite for local/dev/tests."""
import os

try:
    # Optional: load server/.env for local runs (uvicorn --reload). No-op if the
    # package or file is absent — Docker/CI pass DATABASE_URL via the environment.
    from dotenv import load_dotenv

    load_dotenv()
except ModuleNotFoundError:
    pass


class Settings:
    # Default to a local SQLite file so the app runs with zero infra.
    # Production sets DATABASE_URL to a Postgres async DSN, e.g.
    #   postgresql+asyncpg://dromo:dromo@db:5432/dromo
    database_url: str = os.getenv(
        "DATABASE_URL", "sqlite+aiosqlite:///./dromo_tracktable.db"
    )
    # Bump when the *server-side* contract changes; the device stamps its own
    # analysis_version per record (ARCHITECTURE §7 bookkeeping).
    api_version: str = "v1"


settings = Settings()
