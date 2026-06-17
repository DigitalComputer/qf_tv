"""Kokoro ONNX TTS — synthesize and play on local ALSA/PulseAudio."""

from __future__ import annotations

import os
import subprocess
import tempfile
from pathlib import Path

import numpy as np

_engine = None
_playback_proc: subprocess.Popen | None = None


def _voice() -> str:
    return os.environ.get("TTS_VOICE", "pf_dora")


def _lang() -> str:
    return os.environ.get("TTS_LANG", "pt-br")


def _speed() -> float:
    try:
        return float(os.environ.get("TTS_SPEED", "1.0"))
    except ValueError:
        return 1.0


def _audio_device() -> str | None:
    dev = os.environ.get("AUDIO_DEVICE", "").strip()
    return dev or None


def get_engine():
    """Lazy init — downloads ONNX model to ~/.cache/kokoro-onnx/ on first use."""
    global _engine
    if _engine is not None:
        return _engine

    from kokoro_onnx import Kokoro

    print("kokoro-tts: loading Kokoro ONNX model (first run may download ~310MB)...")
    _engine = Kokoro.from_pretrained()
    print("kokoro-tts: engine ready")
    return _engine


def synthesize(text: str) -> tuple[np.ndarray, int]:
    engine = get_engine()
    samples, sample_rate = engine.create(
        text,
        voice=_voice(),
        speed=_speed(),
        lang=_lang(),
    )
    if samples is None or len(samples) == 0:
        raise RuntimeError("Kokoro produced no audio")
    return np.asarray(samples, dtype=np.float32), int(sample_rate)


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

    subprocess.run(["pkill", "-f", "aplay.*qf_kokoro"], check=False)


def play_audio(audio: np.ndarray, sample_rate: int) -> None:
    stop_playback()

    device = _audio_device()

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
