"""QueueFlow TV — local Kokoro TTS microservice (127.0.0.1:5050)."""

from __future__ import annotations

import os
import threading

from dotenv import load_dotenv
from fastapi import FastAPI
from pydantic import BaseModel, Field

load_dotenv()

import tts_engine  # noqa: E402

app = FastAPI(title="QueueFlow Kokoro TTS", version="1.0.0")
_speak_lock = threading.Lock()


class SpeakRequest(BaseModel):
    text: str = Field(..., min_length=1)


@app.get("/health")
def health():
    return {"status": "ok", "voice": os.environ.get("TTS_VOICE", "pf_dora")}


@app.post("/speak")
def speak(req: SpeakRequest):
    """Synthesize PT text and play on local audio device (blocking until done)."""
    with _speak_lock:
        tts_engine.speak(req.text)
    return {"ok": True}


@app.post("/stop")
def stop():
    tts_engine.stop_playback()
    return {"ok": True}


if __name__ == "__main__":
    import uvicorn

    host = os.environ.get("TTS_HOST", "127.0.0.1")
    port = int(os.environ.get("TTS_PORT", "5050"))
    uvicorn.run(app, host=host, port=port, log_level="info")
