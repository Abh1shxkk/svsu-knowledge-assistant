"""OCR for scanned pages and photos, with Tesseract. Runs once, at upload — never at search time.

The page's script is detected first, so each page is read with the right language model:
Hindi (Devanagari) pages with Hindi, English (Latin) pages with English, unclear pages with both.

Ruled tables are found from their lines and read cell by cell: read as a whole page, Tesseract mistakes
the grid lines for letters and drops the short entries (numbers) in table cells.
"""
import io
import os
import statistics

import numpy as np
import pytesseract
from PIL import Image, ImageDraw

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


# ---------- tables ----------

def _runs(dark: np.ndarray, k: int, axis: int) -> np.ndarray:
    """Pixels lying on a straight dark run at least k long along the axis (a ruled line, not a letter)."""
    a = dark if axis == 1 else dark.T
    c = np.pad(np.cumsum(a, axis=1, dtype=np.int32), ((0, 0), (1, 0)))
    full = (c[:, k:] - c[:, :-k]) == k
    s = np.pad(np.cumsum(full, axis=1, dtype=np.int32), ((0, 0), (k, 0)))
    hit = (s[:, k:] - s[:, :-k]) > 0
    hit = np.pad(hit, ((0, 0), (0, a.shape[1] - hit.shape[1])))
    return hit if axis == 1 else hit.T


def _centres(idx: np.ndarray, gap: int = 8) -> list[int]:
    """Group neighbouring indices (one thick line) and return each group's middle."""
    out, start = [], None
    for i, v in enumerate(idx):
        if start is None:
            start = v
        if i == len(idx) - 1 or idx[i + 1] - v > gap:
            out.append(int((start + v) / 2))
            start = None
    return out


def _table_rows(img: Image.Image) -> tuple[list[tuple[int, int, list[tuple[int, int]]]], np.ndarray]:
    """Rows of ruled tables on the page — (top, bottom, [(left, right) of each cell]) — and a mask of the
    rule pixels, so cells can be read without the lines (a line beside a 2 reads as a 9)."""
    g = np.asarray(img.convert("L"))
    h_img, w_img = g.shape
    dark = g < 200  # table rules are often thin and light grey on scans
    # Scans are a little tilted, so a straight rule drifts by a pixel or two: thicken across the line first.
    thick_h = dark.copy()
    thick_v = dark.copy()
    for k in (1, 2, 3):
        thick_h[k:] |= dark[:-k]
        thick_h[:-k] |= dark[k:]
        thick_v[:, k:] |= dark[:, :-k]
        thick_v[:, :-k] |= dark[:, k:]
    horiz = _runs(thick_h, max(60, w_img // 8), axis=1)
    vert = _runs(thick_v, max(40, h_img // 45), axis=0)
    ys = _centres(np.where(horiz.sum(axis=1) > w_img * 0.2)[0])
    rows = []
    for y1, y2 in zip(ys, ys[1:]):
        if not 18 < y2 - y1 < h_img / 3:
            continue
        band = vert[y1 + 4:y2 - 4]
        xs = _centres(np.where(band.mean(axis=0) > 0.8)[0])  # vertical lines crossing the whole band
        cells = [(x1, x2) for x1, x2 in zip(xs, xs[1:]) if x2 - x1 > 15]
        if len(cells) >= 2:
            rows.append((y1, y2, cells))
    return rows, (horiz | vert) & dark


def _cell(img: Image.Image, box: tuple[int, int, int, int], lang: str) -> tuple[str, list[float], list[str]]:
    crop = img.crop(box)
    if (np.asarray(crop.convert("L")) < 170).mean() < 0.003:  # empty cell
        return "", [], []
    crop = crop.resize((crop.width * 2, crop.height * 2), Image.LANCZOS)  # short entries (single digits) read better
    d = pytesseract.image_to_data(crop, lang=lang, config="--psm 6", output_type=pytesseract.Output.DICT)
    edge = crop.width - 0.08 * crop.width
    # A short, unsure mark at the right side of a cell is what's left of the ruled line, not text.
    words = [(c, w.strip()) for c, w, x, ww in zip(d["conf"], d["text"], d["left"], d["width"])
             if w.strip() and not (float(c) < 50 and len(w.strip()) <= 3 and x + ww > edge)]
    text = " ".join(w for _, w in words)
    return text, [float(c) for c, _ in words if float(c) >= 0], [w for c, w in words if 0 <= float(c) < UNSURE]


# ---------- page ----------

def _tesseract(img: Image.Image, lang: str) -> tuple[str, int, str, list[str]]:
    """Rebuild the page from where each word sits, not from Tesseract's own blocks (which read a table
    column by column): words on the same line of the page become one line, a wide gap becomes " | ",
    and a large vertical gap starts a paragraph. Table rows are read cell by cell and slotted in place."""
    table, rules = _table_rows(img)
    page = img.copy()
    paint = ImageDraw.Draw(page)
    for top, bottom, cells in table:  # the rest of the page is read without the tables
        paint.rectangle((cells[0][0], top, cells[-1][1], bottom), fill="white")
    d = pytesseract.image_to_data(page, lang=lang, output_type=pytesseract.Output.DICT)
    words = [(d["left"][i], d["top"][i], d["width"][i], d["height"][i], w.strip())
             for i, w in enumerate(d["text"]) if w.strip()]
    confs = [float(c) for c, w in zip(d["conf"], d["text"]) if w.strip() and float(c) >= 0]
    unsure = {w.strip() for c, w in zip(d["conf"], d["text"]) if 0 <= float(c) < UNSURE}
    h = statistics.median(w[3] for w in words) if words else 30  # typical word height: the yardstick for gaps

    lines: list[tuple[int, int, str]] = []  # (top, bottom, text)
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
    for row in rows:
        ws = sorted(row["words"])
        text = ws[0][4]
        for a, b in zip(ws, ws[1:]):
            text += (" | " if b[0] - (a[0] + a[2]) > 2.2 * h else " ") + b[4]  # wide gap = next column
        lines.append((row["top"], row["bottom"], text))
    clean = img
    if table:  # cells are read with the ruled lines removed
        g = np.asarray(img.convert("L")).copy()
        g[rules] = 255
        clean = Image.fromarray(g).convert("RGB")
    for top, bottom, cells in table:
        texts = []
        for x1, x2 in cells:
            text, c, u = _cell(clean, (x1 + 2, top + 2, x2 - 2, bottom - 2), lang)
            texts.append(text)
            confs += c
            unsure.update(u)
        if any(texts):
            lines.append((top, bottom, " | ".join(t for t in texts if t)))

    out, prev_bottom = [], None
    for top, bottom, text in sorted(lines):
        if prev_bottom is not None and top - prev_bottom > 1.3 * h:
            out.append("")
        out.append(text)
        prev_bottom = max(bottom, prev_bottom or 0)
    unsure_words = sorted(w for w in unsure if sum(ch.isalnum() for ch in w) >= 2)
    return "\n".join(out), round(sum(confs) / len(confs)) if confs else 0, "tesseract", unsure_words
