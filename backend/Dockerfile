FROM python:3.11-slim

WORKDIR /app

COPY app.py .

RUN pip install flask gunicorn

CMD ["gunicorn", "-w", "3", "-b", "0.0.0.0:80", "app:app"]
