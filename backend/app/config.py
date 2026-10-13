from pydantic_settings import BaseSettings, SettingsConfigDict


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

    # OCR runs once, at upload. Hindi pages use Tesseract (Textract can't read Devanagari); other
    # pages use AWS Textract when keys are set, otherwise Tesseract.
    tesseract_cmd: str = r"C:\Program Files\Tesseract-OCR\tesseract.exe"
    tessdata_dir: str = "D:/Tesseract-OCR/tessdata"
    aws_access_key_id: str = ""
    aws_secret_access_key: str = ""
    aws_region: str = "ap-south-1"

    jwt_secret: str = "change-me-in-production"
    token_hours: int = 12
    # Local test admin (dev only). Leave blank in production.
    dev_admin_user: str = ""
    dev_admin_pass: str = ""

    model_config = SettingsConfigDict(env_file=".env", extra="ignore")


settings = Settings()
