"""Upload processing: read any supported file into pages of paragraphs, suggest its details,
and find the deadlines it sets."""
import csv
import hashlib
import io
import json
import re
from pathlib import Path

import pymupdf
from docx import Document
from openpyxl import load_workbook

from . import ocr
from .llm import chat
from .rag import block_text

_KINDS = {".pdf": "pdf", ".docx": "docx", ".xlsx": "xlsx", ".csv": "xlsx", ".txt": "txt", ".md": "txt",
          ".png": "img", ".jpg": "img", ".jpeg": "img", ".webp": "img"}
_PER_PAGE = 12  # paragraphs per page when the file has no pages of its own
_MAX_OCR_PAGES = 10


def extract(filename: str, raw: bytes) -> dict:
    """-> {"kind", "pages": [[block, ...], ...], "ocr": confidence or None, "ocr_engine": name or None}

    Text is read once here; afterwards only the stored paragraphs and embeddings are used.
    """
    suffix = Path(filename).suffix.lower()
    kind = _KINDS.get(suffix)
    if not kind:
        raise ValueError(f"{suffix or 'This'} files aren't supported. Use PDF, Word (.docx), Excel (.xlsx), "
                         "CSV, an image or a text file.")
    scans: list[tuple[str, int, str]] = []  # OCR results, one per page image
    if kind == "pdf":
        pdf = pymupdf.open(stream=raw, filetype="pdf")
        pages = [_paras(p.get_text()) for p in pdf]
        if sum(map(len, pages)) == 0:  # no text layer: a scan, so OCR the page images
            scans = [ocr.read(p.get_pixmap(dpi=300).tobytes("png")) for p in list(pdf)[:_MAX_OCR_PAGES]]
            kind, pages = "scan", [_paras(t) for t, _, _ in scans]
    elif kind == "docx":
        pages = _paginate([p.text for p in Document(io.BytesIO(raw)).paragraphs])
    elif kind == "xlsx":
        pages = [_rows(raw, suffix)]
    elif kind == "img":
        scans = [ocr.read(raw)]
        pages = _paginate(_paras(scans[0][0]))
    else:
        pages = _paginate(_paras(raw.decode("utf-8", "ignore")))
    return {
        "kind": kind, "pages": _blocks(pages),
        "ocr": round(sum(c for _, c, _ in scans) / len(scans)) if scans else None,
        "ocr_engine": "+".join(sorted({e for _, _, e in scans})) or None,
    }


def text_hash(pages: list[list[dict]]) -> str:
    """Fingerprint of a document's text (case and spacing ignored), to spot the same file uploaded twice."""
    text = " ".join(block_text(b) for page in pages for b in page)
    return hashlib.sha256(" ".join(text.lower().split()).encode()).hexdigest() if text.strip() else ""


def _paras(text: str) -> list[str]:
    parts = re.split(r"\n\s*\n", text)
    if len(parts) < 3:  # no blank lines between paragraphs: fall back to lines
        parts = text.splitlines()
    return [" ".join(p.split()) for p in parts if p.strip()]


def _paginate(paras: list[str]) -> list[list[str]]:
    paras = [p for p in paras if p.strip()]
    return [paras[i:i + _PER_PAGE] for i in range(0, len(paras), _PER_PAGE)]


def _rows(raw: bytes, suffix: str) -> list[list[str]]:
    if suffix == ".csv":
        rows = csv.reader(io.StringIO(raw.decode("utf-8", "ignore")))
    else:
        rows = load_workbook(io.BytesIO(raw), read_only=True, data_only=True).active.iter_rows(values_only=True)
    return [[("" if v is None else str(v)) for v in row] for row in rows if any(v not in (None, "") for v in row)]


def _blocks(pages: list[list]) -> list[list[dict]]:
    """Give every paragraph (or sheet row) an id that is unique within the document."""
    n, out = 0, []
    for page in pages:
        blocks = []
        for text in page:
            n += 1
            if isinstance(text, list):
                blocks.append({"id": f"r{n}", "text": text, "kind": "hdr" if n == 1 else "row"})
            else:
                subj = n == 1 and text.lower().startswith(("subject", "sub:", "विषय"))
                blocks.append({"id": f"b{n}", "text": text, "kind": "subj" if subj else "p"})
        if blocks:
            out.append(blocks)
    return out


def suggest(pages: list[list[dict]], filename: str, lists: dict) -> dict:
    """Suggest the document's details, choosing only from the university's own lists."""
    choices = {k: lists.get(k, []) for k in ("TYPES", "AUTHS", "DEPTS", "AUDS", "TAGS", "VIS")}
    text = "\n".join(block_text(b) for page in pages for b in page)[:6000]
    res = chat(
        "You catalogue official documents of Swami Vivekanand Subharti University. Suggest this document's "
        "details. Reply as JSON with keys title, ref (reference or letter number exactly as printed), type, "
        "authority, dept, date, effective, expiry (dates as YYYY-MM-DD), audience (list), tags (list), "
        "visibility, description (one sentence). Pick type from TYPES, authority from AUTHS, dept from DEPTS, "
        "audience from AUDS, tags from TAGS and visibility from VIS. Use \"\" or [] when the text doesn't say.\n"
        + json.dumps(choices, ensure_ascii=False),
        f"File name: {filename}\n\n{text}", as_json=True)
    pick = {"type": "TYPES", "authority": "AUTHS", "dept": "DEPTS", "visibility": "VIS"}
    for k, lst in pick.items():  # drop anything not on the lists
        if res.get(k) not in choices[lst]:
            res[k] = ""
    for k, lst in (("audience", "AUDS"), ("tags", "TAGS")):
        res[k] = [v for v in res.get(k) or [] if v in choices[lst]]
    return {k: v for k, v in res.items() if v not in ("", [], None)}


def deadlines(doc: dict) -> list[dict]:
    """Dated actions the document sets, each pointing at the paragraph it came from."""
    blocks = {(p, b["id"]): b for p, page in enumerate(doc["pages"], 1) for b in page}
    text = "\n".join(f"[page {p}, {bid}] {block_text(b)}" for (p, bid), b in blocks.items())
    res = chat(
        "List every dated action or deadline this document sets. Reply as JSON {\"deadlines\": [{\"title\": "
        "\"short action\", \"date\": \"YYYY-MM-DD\", \"page\": n, \"block\": \"paragraph id\", \"quote\": \"the exact "
        "words from that paragraph that contain the date\", \"owner\": \"who must act\", \"aud\": \"who it "
        "applies to\"}]}. Use only dates written in the text.",
        f"Title: {doc['title']}\n{text}", as_json=True)
    return [d for d in res.get("deadlines") or [] if (d.get("page"), d.get("block")) in blocks and d.get("date")]
