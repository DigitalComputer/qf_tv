"""Kokoro ONNX TTS — synthesize and play on local ALSA/PulseAudio."""

from __future__ import annotations

import os
import re
import subprocess
import tempfile
from pathlib import Path

import numpy as np
from num2words import num2words

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
    # 0.88 reads more natural than 1.0 for PT ticket announcements.
    try:
        return float(os.environ.get("TTS_SPEED", "0.88"))
    except ValueError:
        return 0.88


def _gain() -> float:
    # +10% loudness by default (TV analog jack was too quiet).
    try:
        return float(os.environ.get("TTS_GAIN", "1.1"))
    except ValueError:
        return 1.1


def preprocess_text(text: str) -> str:
    """Make raw text sound more human:
    - spell bare digits in pt-BR ("balcão 1" → "balcão um")
    - keep existing spelled codes ("G P V zero zero um") untouched
    - punctuation (commas/periods) is preserved so Kokoro breathes there
    """
    if not text:
        return text

    def _number(match: re.Match) -> str:
        raw = match.group(0)
        try:
            n = int(raw)
        except ValueError:
            return raw
        if 0 <= n <= 999999:
            return num2words(n, lang="pt_BR")
        return raw

    text = re.sub(r"\b\d{1,6}\b", _number, text)
    text = re.sub(r"[ ]{2,}", " ", text).strip()
    return text


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

    subprocess.run(["pkill", "-f", "(aplay|paplay).*qf_kokoro"], check=False)


def _pulse_socket() -> str | None:
    """Find the kiosk session's PulseAudio unix socket, best effort."""
    candidates: list[Path] = []
    runtime = os.environ.get("XDG_RUNTIME_DIR")
    if runtime:
        candidates.append(Path(runtime) / "pulse" / "native")
    candidates.append(Path(f"/run/user/{os.getuid()}") / "pulse" / "native")
    for p in candidates:
        if p.exists():
            return f"unix:{p}"
    # Fallback: scan other user runtime dirs (e.g. service env has wrong uid).
    for p in sorted(Path("/run/user").glob("*/pulse/native")):
        if p.exists():
            return f"unix:{p}"
    return None


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
        print(f"kokoro-tts: sounddevice failed ({exc}), trying paplay")

    with tempfile.NamedTemporaryFile(suffix=".wav", prefix="qf_kokoro_", delete=False) as tmp:
        wav_path = Path(tmp.name)

    try:
        _write_wav(wav_path, audio, sample_rate)

        # Prefer the kiosk session's PulseAudio (paplay): PortAudio's pulse
        # backend can't find the server, and the ALSA device is held by
        # wireplumber in the graphical session ("Device or resource busy").
        pulse_env = os.environ.copy()
        pulse_socket = _pulse_socket()
        if pulse_socket:
            pulse_env["PULSE_SERVER"] = pulse_socket
            sock_path = Path(pulse_socket.removeprefix("unix:"))
            pulse_env["XDG_RUNTIME_DIR"] = str(sock_path.parent.parent)

        global _playback_proc
        paplay_err = b""
        _playback_proc = subprocess.Popen(
            ["paplay", str(wav_path)],
            env=pulse_env,
            stderr=subprocess.PIPE,
        )
        try:
            _playback_proc.wait(timeout=120)
        except subprocess.TimeoutExpired:
            _playback_proc.kill()
            _playback_proc.wait(timeout=5)
        paplay_err = _playback_proc.stderr.read() if _playback_proc.stderr else b""
        if _playback_proc.returncode == 0:
            _playback_proc = None
            return

        print(
            f"kokoro-tts: paplay exited {_playback_proc.returncode} "
            f"({paplay_err.decode(errors='replace').strip()}), trying aplay"
        )
        cmd = ["aplay", "-q"]
        if device:
            cmd.extend(["-D", device])
        cmd.append(str(wav_path))
        _playback_proc = subprocess.Popen(cmd)
        try:
            _playback_proc.wait(timeout=120)
        except subprocess.TimeoutExpired:
            _playback_proc.kill()
            _playback_proc.wait(timeout=5)
        if _playback_proc.returncode != 0:
            raise RuntimeError(f"aplay exited {_playback_proc.returncode}")
        _playback_proc = None
    finally:
        wav_path.unlink(missing_ok=True)


def speak(text: str) -> None:
    text = preprocess_text(text)
    if not text:
        return
    audio, sr = synthesize(text)
    gain = _gain()
    if gain != 1.0:
        audio = np.clip(audio * gain, -1.0, 1.0)
    play_audio(audio, sr)
