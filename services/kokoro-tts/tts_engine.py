"""Kokoro ONNX TTS — synthesize and play on local ALSA/PulseAudio."""

from __future__ import annotations

import os
import subprocess
import tempfile
from pathlib import Path

import numpy as np

_engine = None
_playback_proc: subprocess.Popen | None = None

MODEL_ONNX = "kokoro-v1.0.onnx"
MODEL_VOICES = "voices-v1.0.bin"
MODEL_BASE_URL = (
    "https://github.com/thewh1teagle/kokoro-onnx/releases/download/model-files-v1.0"
)


def _model_dir() -> Path:
    return Path(os.environ.get("KOKORO_MODEL_DIR", "/opt/qf-kokoro-tts/models"))


def _voice() -> str:
    return os.environ.get("TTS_VOICE", "pf_dora")


def _lang() -> str:
    # kokoro-onnx phonemizer/espeak-ng code (VOICES.md: pt-br → pf_dora)
    return os.environ.get("TTS_LANG", "pt-br")


def _speed() -> float:
    try:
        return float(os.environ.get("TTS_SPEED", "1.0"))
    except ValueError:
        return 1.0


def _audio_device() -> str | None:
    dev = os.environ.get("AUDIO_DEVICE", "").strip()
    return dev or None


def _ensure_models(model_dir: Path) -> tuple[Path, Path]:
    model_dir.mkdir(parents=True, exist_ok=True)
    model_path = model_dir / MODEL_ONNX
    voices_path = model_dir / MODEL_VOICES

    import urllib.request

    for name, path in ((MODEL_ONNX, model_path), (MODEL_VOICES, voices_path)):
        if path.exists() and path.stat().st_size > 0:
            continue
        url = f"{MODEL_BASE_URL}/{name}"
        print(f"kokoro-tts: downloading {name} from {url} ...")
        urllib.request.urlretrieve(url, path)
        print(f"kokoro-tts: saved {path}")

    if not model_path.exists() or not voices_path.exists():
        raise FileNotFoundError(f"Kokoro model files missing under {model_dir}")

    return model_path, voices_path


def get_engine():
    """Load Kokoro ONNX engine (downloads model files on first use if needed)."""
    global _engine
    if _engine is not None:
        return _engine

    from kokoro_onnx import Kokoro

    model_path, voices_path = _ensure_models(_model_dir())
    print(f"kokoro-tts: loading {model_path.name} + {voices_path.name}")
    _engine = Kokoro(str(model_path), str(voices_path))
    print("kokoro-tts: engine ready")
    return _engine


def synthesize(text: str) -> tuple[np.ndarray, int]:
    engine = get_engine()
    voice = _voice()
    available = engine.get_voices()
    if voice not in available:
        raise ValueError(f"Voice {voice!r} not in model; try one of: {available[:8]}...")

    samples, sample_rate = engine.create(
        text,
        voice=voice,
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
        if _playback_proc.returncode != 0:
            raise RuntimeError(f"aplay exited {_playback_proc.returncode}")
        _playback_proc = None
    finally:
        wav_path.unlink(missing_ok=True)


def speak(text: str) -> None:
    text = text.strip()
    if not text:
        return
    audio, sr = synthesize(text)
    play_audio(audio, sr)
