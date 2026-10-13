# SVSU Knowledge Assistant

Ask questions about official university documents and get answers grounded in those documents,
with citations to the exact paragraph. See [docs/](docs/) for `instructions.md`, `design.md`, `rules.md`.

## How it works

1. **Upload, once per document.** Text is read from the file. Scanned PDFs and photos go through
   **OCR**: Tesseract for Hindi pages, and AWS Textract for other pages when AWS keys are set
   (Tesseract otherwise). The text is split into paragraphs.
2. **Embed and store.** Each paragraph is turned into an embedding (OpenAI) and stored in
   **PostgreSQL with pgvector**, next to the document's details.
3. **Ask.** A question is embedded and matched against the stored paragraphs — only in documents the
   person may see and has in scope. GPT-4o answers from those paragraphs, citing each one.
   **No OCR or re-reading of files happens at question time.**

## Where data lives

Everything is in one PostgreSQL database, `svsu_assistant`:

| Table | Holds |
|-------|-------|
| `records` | documents, collections, deadlines, chats, bookmarks, users, audit log, settings (JSONB) |
| `credentials` | bcrypt password hashes — never sent to the browser |
| `blocks` | every document paragraph with its embedding (pgvector, HNSW index) |

Locally, leave `DATABASE_URL` blank and a PostgreSQL 16 server starts with its data in
`D:\PostgreSQL\data`. In production set `DATABASE_URL=postgresql://user:pass@host:5432/svsu_assistant`
on a server with the `vector` extension.

## Run it

```bash
# backend
cd backend
python -m venv .venv && .venv\Scripts\activate
pip install -r requirements.txt
copy .env.example .env          # fill in OPENAI_API_KEY (and AWS keys for Textract)
uvicorn app.main:app --port 8000

# frontend
cd frontend
npm install
npm run dev                     # http://localhost:3000
```

Needs Tesseract installed, with `eng`, `hin` and `osd` language files in `TESSDATA_DIR`.
