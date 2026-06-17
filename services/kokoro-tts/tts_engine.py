"""Kokoro ONNX TTS — synthesize and play on local ALSA/PulseAudio."""

from __future__ import annotations

import os
import subprocess
import tempfile
import wave
from pathlib import Path

import numpy as np

_pipeline = None
_playback_proc: subprocess.Popen | None = None


def _voice() -> str:
    return os.environ.get("TTS_VOICE", "pf_dora")


def _lang_code() -> str:
    # pt-br → Brazilian Portuguese (Kokoro code "p")
    lang = os.environ.get("TTS_LANG", "pt-br").lower()
    if lang in ("pt-br", "pt_br", "pt"):
        return "p"
    if lang.startswith("pt-pt"):
        return "p"  # no dedicated pt-PT voice — pf_dora is closest
    return "p"


def _speed() -> float:
    try:
        return float(os.environ.get("TTS_SPEED", "1.0"))
    except ValueError:
        return 1.0


def _audio_device() -> str | None:
    dev = os.environ.get("AUDIO_DEVICE", "").strip()
    return dev or None


def get_pipeline():
    global _pipeline
    if _pipeline is not None:
        return _pipeline

    from kokoro import KPipeline

    _pipeline = KPipeline(lang_code=_lang_code(), repo_id="hexgrad/Kokoro-82M")
    return _pipeline


def synthesize(text: str) -> tuple[np.ndarray, int]:
    pipe = get_pipeline()
    chunks: list[np.ndarray] = []
    for _, _, chunk in pipe(text, voice=_voice(), speed=_speed()):
        chunks.append(chunk)
    if not chunks:
        raise RuntimeError("Kokoro produced no audio")
    audio = np.concatenate(chunks)
    return audio, 24000


def _write_wav(path: Path, audio: np.ndarray, sample_rate: int) -> None:
    import soundfile as sf

    sf.write(str(path), audio, sample_rate, format="WAV")


def stop_playback() -> None:
    global _playback_proc
    if _playback_proc is not None:
        try:
            _playback_proc.terminate()
            _playback_proc.wait(timeout=2)
        except Exception:
            try:
                _playback_proc.kill()
            except Exception:
                pass
        _playback_proc = None

    # Kill stray aplay from prior speak
    subprocess.run(["pkill", "-f", "aplay.*qf_kokoro"], check=False)


def play_audio(audio: np.ndarray, sample_rate: int) -> None:
    stop_playback()

    device = _audio_device()

    # Prefer sounddevice when available
    try:
        import sounddevice as sd

        kwargs: dict = {}
        if device:
            kwargs["device"] = device
        sd.play(audio, sample_rate, **kwargs)
        sd.wait()
        return
    except Exception as exc:
        print(f"kokoro-tts: sounddevice failed ({exc}), trying aplay")

    with tempfile.NamedTemporaryFile(suffix=".wav", prefix="qf_kokoro_", delete=False) as tmp:
        wav_path = Path(tmp.name)

    try:
        _write_wav(wav_path, audio, sample_rate)
        cmd = ["aplay", "-q"]
        if device:
            cmd.extend(["-D", device])
        cmd.append(str(wav_path))
        global _playback_proc
        _playback_proc = subprocess.Popen(cmd)
        _playback_proc.wait()
        _playback_proc = None
    finally:
        wav_path.unlink(missing_ok=True)


def speak(text: str) -> None:
    text = text.strip()
    if not text:
        return
    audio, sr = synthesize(text)
    play_audio(audio, sr)
