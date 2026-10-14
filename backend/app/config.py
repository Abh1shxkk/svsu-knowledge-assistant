from pydantic_settings import BaseSettings, SettingsConfigDict


DEFAULT_SECRET = "change-me-in-production"


class Settings(BaseSettings):
    openai_api_key: str = ""
    chat_model: str = "gpt-4o"
    fast_model: str = "gpt-4o-mini"  # routine steps, e.g. rewriting a question into search queries
    embed_model: str = "text-embedding-3-small"  # 1536 dims
    embed_dim: int = 1536
    top_k: int = 8  # paragraphs read per answer

    # The project's own PostgreSQL database. In production set DATABASE_URL; locally, leave it blank
    # and a PostgreSQL server is started with its data in PG_DATA_DIR.
    database_url: str = ""
    pg_data_dir: str = "D:/PostgreSQL/data"
    db_name: str = "svsu_assistant"

    # OCR (Tesseract) runs once, at upload. Needs the eng, hin and osd language files in tessdata_dir.
    tesseract_cmd: str = r"C:\Program Files\Tesseract-OCR\tesseract.exe"
    tessdata_dir: str = "D:/Tesseract-OCR/tessdata"

    # Load the prototype's sample documents into an empty database (development only).
    demo_data: bool = False

    jwt_secret: str = DEFAULT_SECRET
    token_hours: int = 12
    cors_origins: str = "http://localhost:3000,http://127.0.0.1:3000"  # the web app's address(es), comma-separated

    # Deadline reminder emails. Leave SMTP_HOST blank to show reminders in the app only.
    # Run the background worker (bulk imports, quality tests) inside the API. Turn off when separate
    # workers run with `python -m app.cli worker`.
    run_worker: bool = True

    smtp_host: str = ""
    smtp_port: int = 587
    smtp_user: str = ""
    smtp_pass: str = ""
    smtp_from: str = ""
    # Local test admin (dev only). Leave blank in production.
    dev_admin_user: str = ""
    dev_admin_pass: str = ""

    model_config = SettingsConfigDict(env_file=".env", extra="ignore")


settings = Settings()
if settings.jwt_secret == DEFAULT_SECRET and not settings.dev_admin_user:
    raise SystemExit("Set JWT_SECRET in backend/.env to a long random value before running in production.")
