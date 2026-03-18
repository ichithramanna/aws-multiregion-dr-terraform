FROM python:3.11-slim

WORKDIR /app

COPY requirements.txt .
RUN pip install -r requirements.txt

COPY app.py .

EXPOSE 80

CMD ["gunicorn", "--bind", "0.0.0.0:80", "--workers", "1", "--timeout", "120", "app:app"]

