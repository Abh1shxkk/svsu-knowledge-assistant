"""OCR for scanned pages and photos, with Tesseract. Runs once, at upload — never at search time.

The page's script is detected first, so each page is read with the right language model:
Hindi (Devanagari) pages with Hindi, English (Latin) pages with English, unclear pages with both.
"""
import io
import os

import pytesseract
from PIL import Image

from .config import settings

pytesseract.pytesseract.tesseract_cmd = settings.tesseract_cmd
os.environ["TESSDATA_PREFIX"] = settings.tessdata_dir  # language files (eng, hin, osd) live on D:

_LANG = {"Devanagari": "hin", "Latin": "eng"}


def read(image: bytes) -> tuple[str, int, str]:
    """-> (text, confidence 0-100, engine) for one page image."""
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


def _tesseract(img: Image.Image, lang: str) -> tuple[str, int, str]:
    """Rebuild lines and paragraphs from Tesseract's word boxes, so paragraphs survive OCR."""
    d = pytesseract.image_to_data(img, lang=lang, output_type=pytesseract.Output.DICT)
    out, line_key, para_key, confs = [], None, None, []
    for i, word in enumerate(d["text"]):
        if not word.strip():
            continue
        para, line = (d["block_num"][i], d["par_num"][i]), (d["block_num"][i], d["par_num"][i], d["line_num"][i])
        if para_key is not None and para != para_key:
            out.append("\n\n")
        elif line_key is not None and line != line_key:
            out.append("\n")
        elif out:
            out.append(" ")
        out.append(word)
        para_key, line_key = para, line
        if float(d["conf"][i]) >= 0:
            confs.append(float(d["conf"][i]))
    return "".join(out), round(sum(confs) / len(confs)) if confs else 0, "tesseract"
