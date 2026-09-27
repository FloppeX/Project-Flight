"""Generate original, seamless stereo grain-impact loops for the cockpit.

No external recordings: short filtered noise impulses with a faint damped
canopy resonance. Circular accumulation preserves tails across the loop seam.
"""
import array
import math
from pathlib import Path
import random
import wave

RATE = 32000
OUT = Path(__file__).resolve().parents[1] / "Audio" / "cockpit"


def generate(name, seconds, grains_per_second, seed):
    rng = random.Random(seed)
    frames = round(seconds * RATE)
    channels = [array.array("f", [0.0]) * frames for _ in range(2)]
    for _ in range(round(seconds * grains_per_second)):
        start = rng.randrange(frames)
        duration = rng.uniform(0.004, 0.019)
        count = round(duration * RATE)
        pan = rng.uniform(0.1, 0.9)
        gains = [math.sqrt(1 - pan), math.sqrt(pan)]
        amplitude = rng.uniform(0.1, 0.5) ** 1.4
        resonance = rng.uniform(1400, 4300)
        previous = 0.0
        for i in range(count):
            t = i / RATE
            noise = rng.uniform(-1, 1)
            # A dry broadband tick, without the bass of a stone or bullet hit.
            grain = (noise - previous * 0.65) * 0.8
            previous = noise
            grain += math.sin(math.tau * resonance * t) * 0.13
            envelope = min(1.0, t / 0.0003) * math.exp(-7.0 * t / duration)
            sample = grain * envelope * amplitude
            index = (start + i) % frames
            for channel in range(2):
                channels[channel][index] += sample * gains[channel]
    peak = max(max(abs(x) for x in channel) for channel in channels)
    rms = math.sqrt(sum(x * x for channel in channels for x in channel) / (frames * 2))
    gain = min(0.8 / peak, 0.10 / rms)
    pcm = array.array("h")
    for i in range(frames):
        for channel in channels:
            pcm.append(round(channel[i] * gain * 32767))
    path = OUT / name
    with wave.open(str(path), "wb") as target:
        target.setnchannels(2)
        target.setsampwidth(2)
        target.setframerate(RATE)
        target.writeframes(pcm.tobytes())
    print(f"{name}: {seconds}s peak={peak * gain:.3f} rms={rms * gain:.3f}")


if __name__ == "__main__":
    OUT.mkdir(parents=True, exist_ok=True)
    generate("canopy_sand_ticks.wav", 8.0, 65, 7319)
    generate("canopy_sand_rattle.wav", 11.3, 320, 7320)
