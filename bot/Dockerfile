FROM registry.os.wiz.io/python:3.14

ENV PYTHONUNBUFFERED True

WORKDIR /app

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Remove shell and package manager for production
RUN apk del wizos-keys wizos-apk-auth apk-tools busybox

COPY . .

CMD ["gunicorn", "--bind", "0.0.0.0:8080", "main:app"]
