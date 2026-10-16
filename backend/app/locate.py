"""Where a cited passage sits on a page of the original file, so the viewer can highlight it on the scan
or PDF itself, not only in the text read from it.

Word positions come from the PDF's own text layer when the page has one. Scanned pages and photos have
none, so the page is read with OCR — once, the first time a citation on it is opened — and the positions
are kept next to the file. A quote is then matched to the page's words loosely, because OCR misreads some
of them, and the matched words are merged into one box per line.
"""
import io
import json
import re
import unicodedata
from difflib import SequenceMatcher

import pymupdf
import pytesseract
from PIL import Image

from . import ocr, store

_DPI = 200          # enough for Tesseract to read circulars, a few seconds a page
_MIN_TEXT_WORDS = 8  # a PDF page with fewer words of its own than this is treated as a scan

Word = tuple[str, float, float, float, float]  # text, then x0, y0, x1, y1 as fractions of the page size


def _norm(s: str) -> str:
    """Compare words by their letters and digits only, in lower case: OCR and quotes differ in punctuation."""
    s = unicodedata.normalize("NFKC", s).lower()
    return "".join(ch for ch in s if unicodedata.category(ch)[0] in "LMN")


def _pdf_words(page: pymupdf.Page) -> list[Word]:
    w, h = page.rect.width, page.rect.height
    return [(t, x0 / w, y0 / h, x1 / w, y1 / h) for x0, y0, x1, y1, t, *_ in page.get_text("words") if _norm(t)]


def _ocr_words(img: Image.Image) -> list[Word]:
    img = img.convert("RGB")
    lang = ocr._LANG.get(ocr._script(img), "hin+eng")
    d = pytesseract.image_to_data(img, lang=lang, output_type=pytesseract.Output.DICT)
    w, h = img.size
    out = []
    for t, x, y, bw, bh in zip(d["text"], d["left"], d["top"], d["width"], d["height"]):
        if _norm(t or ""):
            out.append((t, x / w, y / h, (x + bw) / w, (y + bh) / h))
    return out


def words_key(file_key: str, n: int) -> str:
    """Where page n's word positions are kept: next to the file, within the 64 characters a key may have."""
    return f"{file_key[:56]}.w{n:03d}"


def page_words(file_key: str, mime: str, data: bytes, n: int) -> list[Word]:
    """All words on page n (from 1) with their positions; computed once per page and kept."""
    key = words_key(file_key, n)
    if cached := store.get_file(key):
        return [tuple(x) for x in json.loads(cached[2])]
    if mime == "application/pdf":
        page = pymupdf.open(stream=data, filetype="pdf")[n - 1]
        words = _pdf_words(page)
        if len(words) < _MIN_TEXT_WORDS:  # a scan: read the picture of the page
            pix = page.get_pixmap(dpi=_DPI)
            words = _ocr_words(Image.open(io.BytesIO(pix.tobytes("png"))))
    else:
        words = _ocr_words(Image.open(io.BytesIO(data)))
    store.put_file(key, f"words-{n}.json", "application/json", json.dumps(words).encode())
    return words


def match(words: list[Word], quote: str) -> list[list[float]]:
    """Boxes ([x0, y0, x1, y1], fractions of the page) covering the quote, one per line; [] if not found."""
    q = [t for t in (_norm(x) for x in re.split(r"[\s|]+", quote.replace("…", " "))) if t]
    page = [_norm(w[0]) for w in words]
    if not q or not page:
        return []
    hits = sorted(i for a, _, size in SequenceMatcher(None, page, q, autojunk=False).get_matching_blocks()
                  for i in range(a, a + size))
    if not hits:
        return []
    # The densest run of matched words no longer than the quote (plus slack for OCR splitting words):
    # stray matches of common words elsewhere on the page fall outside it.
    span = len(q) + max(3, len(q) // 3)
    best, lo = (0, 0, 0), 0
    for hi in range(len(hits)):
        while hits[hi] - hits[lo] >= span:
            lo += 1
        if hi - lo + 1 > best[0]:
            best = (hi - lo + 1, hits[lo], hits[hi])
    found, first, last = best
    if found < (len(q) if len(q) <= 3 else max(3, 0.4 * len(q))):
        return []
    return _lines(words[first:last + 1])


def _lines(words: list[Word]) -> list[list[float]]:
    """Merge words into one box per line (words whose vertical middles are close), slightly padded."""
    rows: list[list[float]] = []
    for _, x0, y0, x1, y1 in sorted(words, key=lambda w: ((w[2] + w[4]) / 2, w[1])):
        mid, h = (y0 + y1) / 2, y1 - y0
        row = next((r for r in rows if abs((r[1] + r[3]) / 2 - mid) < max(h, r[3] - r[1]) * 0.6), None)
        if row:
            row[0], row[1], row[2], row[3] = min(row[0], x0), min(row[1], y0), max(row[2], x1), max(row[3], y1)
        else:
            rows.append([x0, y0, x1, y1])
    pad = 0.003
    return [[round(max(0, a - pad), 4), round(max(0, b - pad), 4), round(min(1, c + pad), 4), round(min(1, d + pad), 4)]
            for a, b, c, d in sorted(rows, key=lambda r: r[1])]


def locate(file_key: str, mime: str, data: bytes, n: int, quote: str) -> list[list[float]]:
    return match(page_words(file_key, mime, data, n), quote)
