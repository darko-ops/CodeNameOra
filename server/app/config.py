"""Runtime configuration. Postgres in production; SQLite for local/dev/tests."""
import os


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
