FROM python:3.11-slim

# Tesseract with English, Hindi and script detection (OCR runs once, at upload).
RUN apt-get update && apt-get install -y --no-install-recommends \
        tesseract-ocr tesseract-ocr-eng tesseract-ocr-hin tesseract-ocr-osd \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
COPY seed.json .
COPY app ./app

ENV TESSERACT_CMD=/usr/bin/tesseract TESSDATA_DIR=/usr/share/tesseract-ocr/5/tessdata
RUN test -f "$TESSDATA_DIR/hin.traineddata" && test -f "$TESSDATA_DIR/osd.traineddata"
EXPOSE 8000
CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8000", "--workers", "1"]
