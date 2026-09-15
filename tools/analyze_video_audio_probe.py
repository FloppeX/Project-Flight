"""Check the WAV and decoded AAC from DirectVideoAudioSmoketest, without editing either."""
import argparse
import json
from pathlib import Path
import subprocess
import wave

import numpy as np

parser = argparse.ArgumentParser()
parser.add_argument("log", type=Path)
parser.add_argument("--ffmpeg", required=True)
args = parser.parse_args()
lines = args.log.read_text(encoding="utf-8").splitlines()
result = json.loads(next(line.split("DIRECT_AUDIO_RESULT ", 1)[1] for line in lines if line.startswith("DIRECT_AUDIO_RESULT ")))
segments = json.loads(next(line.split("DIRECT_AUDIO_SEGMENTS ", 1)[1] for line in lines if line.startswith("DIRECT_AUDIO_SEGMENTS ")))
assert result["ok"] and result["audio_discarded_frames"] == 0, result
video = Path(result["path"])
with wave.open(str(video.with_name("audio.wav"))) as wav:
    rate = wav.getframerate()
    pcm = np.frombuffer(wav.readframes(wav.getnframes()), dtype="<i2").reshape(-1, 2).astype(float) / 32768.0
decoded = subprocess.run([args.ffmpeg, "-v", "error", "-i", str(video), "-vn", "-f", "f32le", "-acodec", "pcm_f32le", "-"], capture_output=True, check=True)
aac = np.frombuffer(decoded.stdout, dtype="<f4").reshape(-1, 2)
for label, samples in [("wav", pcm), ("aac", aac)]:
    assert np.isfinite(samples).all()
    peak = float(np.max(np.abs(samples)))
    assert peak < 0.999, (label, "full-scale clipping", peak)
    print(label, "peak", peak, "seconds", len(samples) / rate)
    for i, segment in enumerate(segments):
        start = segment["time"] + 0.3
        end = segments[i + 1]["time"] - 0.2 if i + 1 < len(segments) else result["audio_seconds"] - 0.2
        chunk = samples[int(start * rate):int(end * rate)].astype(float)
        rms = float(np.sqrt(np.mean(chunk ** 2)))
        name = segment["name"]
        if name == "mute":
            assert rms < 1e-4, (label, name, rms)
        elif name in ("normal", "quiet", "hitch"):
            expected = 0.75 * 10 ** (6 / 20) * (0.15 if name == "quiet" else 0.44) / np.sqrt(2)
            assert abs(rms / expected - 1) < 0.02, (label, name, rms, expected)
            # Fit the known continuous sine with arbitrary phase. Dropouts,
            # duplicated blocks and clipped waveforms increase the residual.
            t = np.arange(len(chunk)) / rate
            basis = np.column_stack([np.sin(2 * np.pi * 440 * t), np.cos(2 * np.pi * 440 * t), np.ones(len(t))])
            fit = basis @ np.linalg.lstsq(basis, chunk, rcond=None)[0]
            residual = float(np.sqrt(np.mean((chunk - fit) ** 2)) / rms)
            # AAC is lossy: allow codec noise, but demand near-exact raw PCM.
            assert residual < (0.03 if label == "aac" else 0.001), (label, name, "distortion/dropout residual", residual)
            block = rate // 10
            windows = chunk[:len(chunk) // block * block].reshape(-1, block, 2)
            levels = np.sqrt(np.mean(windows ** 2, axis=(1, 2))) / expected
            assert np.all((levels > 0.97) & (levels < 1.03)), (label, name, "100 ms amplitude dropout", levels)
            print(label, name, "rms", rms, "residual", residual)
        else:
            assert 0.3 < rms < 0.9, (label, name, rms)
print("DIRECT_AUDIO_WAVEFORM_PASS")
