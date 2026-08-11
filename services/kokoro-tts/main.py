"""QueueFlow TV — local Kokoro TTS microservice (127.0.0.1:5050).

/speak returns immediately (job submitted); a background worker synthesizes
and plays. The TV app polls /status. This decouples synthesis+playback time
(slow on weak box CPU) from the client HTTP timeout — previously the app's
60s timeout killed long /speak calls and degraded to espeak (robotic).
"""

from __future__ import annotations

import os
import threading

from dotenv import load_dotenv
from fastapi import FastAPI, HTTPException
from pydantic import BaseModel, Field

load_dotenv()

import tts_engine  # noqa: E402

app = FastAPI(title="QueueFlow Kokoro TTS", version="1.1.0")

_state = {"busy": False, "pending": False}
_pending_text: str | None = None
_cond = threading.Condition()


def _worker() -> None:
    """Serialize announce jobs; newest text replaces any pending one."""
    global _pending_text
    while True:
        with _cond:
            while not _state["pending"]:
                _cond.wait()
            _state["pending"] = False
            text = _pending_text
            _pending_text = None
            _state["busy"] = True
        try:
            if text:
                tts_engine.speak(text)
        except Exception:
            import traceback

            traceback.print_exc()
        finally:
            with _cond:
                _state["busy"] = False
                _cond.notify_all()


threading.Thread(target=_worker, daemon=True).start()


class SpeakRequest(BaseModel):
    text: str = Field(..., min_length=1)


@app.get("/health")
def health():
    # Fail fast if model files are missing/corrupt so the TV app stops
    # attempting Kokoro and falls back to the neural API MP3 path.
    # kokoro-v1.0.onnx ~310MB, voices-v1.0.bin ~24MB.
    from tts_engine import _model_dir  # noqa: PLC0415

    for fname, min_size in (
        ("kokoro-v1.0.onnx", 300_000_000),
        ("voices-v1.0.bin", 20_000_000),
    ):
        path = _model_dir() / fname
        if not path.is_file() or path.stat().st_size < min_size:
            raise HTTPException(
                status_code=503,
                detail=f"{fname} missing or corrupt (health)",
            )
    return {"status": "ok", "voice": os.environ.get("TTS_VOICE", "pf_dora")}


@app.post("/speak")
def speak(req: SpeakRequest):
    """Queue PT text for synthesis+playback. Returns immediately."""
    global _pending_text
    with _cond:
        _pending_text = req.text
        _state["pending"] = True
        _cond.notify()
    return {"ok": True, "queued": True}


@app.get("/status")
def status():
    """True when the worker is synthesizing/playing or has work queued."""
    with _cond:
        return {"busy": bool(_state["busy"] or _state["pending"])}


@app.post("/stop")
def stop():
    global _pending_text
    with _cond:
        _pending_text = None
        _state["pending"] = False
    tts_engine.stop_playback()
    return {"ok": True}


if __name__ == "__main__":
    import uvicorn

    host = os.environ.get("TTS_HOST", "127.0.0.1")
    port = int(os.environ.get("TTS_PORT", "5050"))
    uvicorn.run(app, host=host, port=port, log_level="info")
