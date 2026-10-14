"""OCR for scanned pages and photos, with Tesseract. Runs once, at upload — never at search time.

The page's script is detected first, so each page is read with the right language model:
Hindi (Devanagari) pages with Hindi, English (Latin) pages with English, unclear pages with both.
"""
import io
import os
import statistics

import pytesseract
from PIL import Image

from .config import settings

pytesseract.pytesseract.tesseract_cmd = settings.tesseract_cmd
os.environ["TESSDATA_PREFIX"] = settings.tessdata_dir  # language files (eng, hin, osd) live on D:

_LANG = {"Devanagari": "hin", "Latin": "eng"}


UNSURE = 60  # words Tesseract is less sure of than this are shown to the uploader to check


def read(image: bytes) -> tuple[str, int, str, list[str]]:
    """-> (text, confidence 0-100, engine, words read with low confidence) for one page image."""
    img = Image.open(io.BytesIO(image)).convert("RGB")
    if lang := _LANG.get(_script(img)):
        return _tesseract(img, lang)
    # Script not detectable (e.g. too little text): read with both models, see which alphabet most of
    # the text is in, and re-read with just that model — the mixed model leaks English into Hindi.
    first = _tesseract(img, "hin+eng")
    letters = [ch for ch in first[0] if ch.isalpha()]
    hindi = sum("ऀ" <= ch <= "ॿ" for ch in letters)
    return _tesseract(img, "hin" if letters and hindi / len(letters) > 0.5 else "eng") if letters else first


def _script(img: Image.Image) -> str:
    try:
        return pytesseract.image_to_osd(img, output_type=pytesseract.Output.DICT).get("script", "")
    except pytesseract.TesseractError:  # too little text to tell
        return ""


def _tesseract(img: Image.Image, lang: str) -> tuple[str, int, str, list[str]]:
    """Rebuild the page from where each word sits, not from Tesseract's own blocks: Tesseract reads a
    table column by column, which separates every date from its subject. Words on the same line of the
    page become one line (table cells joined with " | "), and a large vertical gap starts a paragraph."""
    d = pytesseract.image_to_data(img, lang=lang, output_type=pytesseract.Output.DICT)
    words = [(d["left"][i], d["top"][i], d["width"][i], d["height"][i], w.strip())
             for i, w in enumerate(d["text"]) if w.strip()]
    confs = [float(c) for c, w in zip(d["conf"], d["text"]) if w.strip() and float(c) >= 0]
    unsure = sorted({w.strip() for c, w in zip(d["conf"], d["text"])
                     if 0 <= float(c) < UNSURE and sum(ch.isalnum() for ch in w) >= 2})
    if not words:
        return "", 0, "tesseract", []
    h = statistics.median(w[3] for w in words)  # typical word height: the yardstick for gaps
    rows: list[dict] = []
    for w in sorted(words, key=lambda w: w[1] + w[3] / 2):
        mid = w[1] + w[3] / 2
        if rows and abs(mid - rows[-1]["mid"]) <= 0.55 * h:
            row = rows[-1]
            row["words"].append(w)
            row["mid"] = sum(x[1] + x[3] / 2 for x in row["words"]) / len(row["words"])
            row["bottom"] = max(row["bottom"], w[1] + w[3])
        else:
            rows.append({"mid": mid, "top": w[1], "bottom": w[1] + w[3], "words": [w]})
    lines, prev_bottom = [], None
    for row in rows:
        ws = sorted(row["words"])
        line = ws[0][4]
        for a, b in zip(ws, ws[1:]):
            line += (" | " if b[0] - (a[0] + a[2]) > 2.2 * h else " ") + b[4]  # wide gap = next column
        if prev_bottom is not None and row["top"] - prev_bottom > 1.3 * h:
            lines.append("")
        lines.append(line)
        prev_bottom = row["bottom"]
    return "\n".join(lines), round(sum(confs) / len(confs)) if confs else 0, "tesseract", unsure
