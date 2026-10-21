FROM python:3.13-slim
WORKDIR /app
COPY requirements.lock.txt ./
RUN pip install --no-cache-dir -r requirements.lock.txt
COPY server.py ./
RUN useradd --create-home --uid 10001 chat && mkdir /data && chown chat:chat /data
USER chat
ENV CHAT_DB=/data/chat.sqlite3
EXPOSE 8000
CMD ["uvicorn", "server:create_app", "--factory", "--host", "0.0.0.0", "--port", "8000", "--workers", "1", "--no-access-log", "--proxy-headers", "--forwarded-allow-ips", "*"]
