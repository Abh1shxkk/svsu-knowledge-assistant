"""OCR for scanned pages and photos. Runs once, at upload — never at search time.

Hindi (Devanagari) pages are read by Tesseract, since AWS Textract cannot read Devanagari. Other pages
go to AWS Textract when AWS keys are configured, otherwise to Tesseract.
"""
import io
import os

import pytesseract
from PIL import Image

from .config import settings

pytesseract.pytesseract.tesseract_cmd = settings.tesseract_cmd
os.environ["TESSDATA_PREFIX"] = settings.tessdata_dir  # language files (eng, hin, osd) live on D:


def read(image: bytes) -> tuple[str, int, str]:
    """-> (text, confidence 0-100, engine) for one page image."""
    img = Image.open(io.BytesIO(image)).convert("RGB")
    script = _script(img)
    if script == "Devanagari":
        return _tesseract(img, "hin")  # the Hindi model alone reads Hindi pages best
    if settings.aws_access_key_id:
        return _textract(img)
    return _tesseract(img, "eng" if script == "Latin" else "hin+eng")


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


def _textract(img: Image.Image) -> tuple[str, int, str]:
    import boto3
    buf = io.BytesIO()
    img.convert("L").save(buf, format="PNG")  # greyscale keeps 300-dpi pages under Textract's 5 MB limit
    res = boto3.client(
        "textract", region_name=settings.aws_region,
        aws_access_key_id=settings.aws_access_key_id, aws_secret_access_key=settings.aws_secret_access_key,
    ).detect_document_text(Document={"Bytes": buf.getvalue()})
    lines = [b for b in res["Blocks"] if b["BlockType"] == "LINE"]
    conf = round(sum(b["Confidence"] for b in lines) / len(lines)) if lines else 0
    return "\n".join(b["Text"] for b in lines), conf, "textract"
