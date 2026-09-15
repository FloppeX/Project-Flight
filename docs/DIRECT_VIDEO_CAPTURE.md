# Direct camera video

This records the actual main game viewport, including live F1–F4 camera cuts, rendered effects, and game audio. It does not use replay subjects, a capture radius, the desktop, microphone, or other applications' audio.

## Use

1. Start Trailer Scenario. Use **Left/Right** to choose any vehicle and **Up/Down** to choose its camera. **Space** pauses/unpauses for framing.
2. Compose the camera, then press **AltGr (right Alt)** to begin video capture and unpause the action. **Ctrl+F10** is an alternative and also works outside Trailer Scenario. Alternatively choose **Pause → START VIDEO CAPTURE**, which resumes the game.
3. Switch cameras normally while recording. Main-viewport HUD/help overlays are hidden; the window title shows `VIDEO REC` and elapsed time. Cockpit and bridge instrument viewports remain part of the rendered scene.
4. Press **AltGr** (or Ctrl+F10) again. Trailer Scenario pauses immediately. Wait for **Saved video**; MP4 encoding runs in the background after capture stops.
5. **Ctrl+Shift+F10** opens the videos folder. Each recording has its own timestamped folder containing `video.mp4`, `audio.wav`, and diagnostic `capture.json`.

To record while flying yourself, cycle to **Cockpit / Pilot** with Up/Down on a controllable aircraft. This uses normal flight controls rather than cinematic camera controls; AltGr still begins/resumes and stops/pauses the shot. Switching back to a filming view returns the aircraft to AI. Radio dialogue captions are hidden throughout Trailer Scenario. Capture hides both CanvasLayer overlays and unlayered screen UI, including overlays created or re-shown mid-shot, without hiding the cockpit's instrument viewports. Opening menus/loading/editor views stops capture before their next frame is recorded.

Output is **1920×1080, 30 fps, H.264 MP4 with stereo AAC game audio**. Different viewport aspect ratios are letterboxed. The separate WAV is retained for editing. On this machine the folder is `C:/Users/jonto/AppData/Roaming/Godot/app_userdata/Land Carrier/videos`.

**Ctrl+F9 is still replay-data recording**, not direct video. Replay-data capture and direct video are kept separate; finish one before starting the other. Direct video currently captures live gameplay, not Recording Mode's replay editor.

Audio follows the in-game Master volume and mute setting. The recorder preserves floating-point peaks, applies the Master gain to its private copy, and then limits peaks to −1 dBFS before creating `audio.wav` and the MP4. This does not change live playback or boost quiet passages. Volume changes are sampled once per rendered frame and smoothed over 5 ms; the limiter's lookahead delay is compensated during finishing. Previously clipped recordings cannot be restored by lowering their volume afterward.

## Boundaries and safety

- Escape or opening the pause/camera editor stops the clip before the menu is captured. A scenario change also stops it. Trailer Scenario also pauses whenever capture stops. Space/F6 pause the *simulation*, not the recorder: frozen frames and any continuing audio become part of the video. Stop video with AltGr before spending time composing another shot. Outside Trailer Scenario, Ctrl+F10 retains its ordinary behavior without automatic game pause/unpause.
- Capture stops automatically after five wall-clock minutes to limit temporary disk usage; it is not a tested five-minute performance guarantee. Keep the game rendering; minimizing it or a rendering hitch can produce held frames.
- There is no replay radius or six-subject restriction. Everything rendered in the main viewport is captured, but naturally only from the selected live angle.
- Normal stop/quit drains the frame queue and finalizes the video. Prefer stopping and waiting for **Saved video** before closing. A forced editor stop, crash, or process kill can bypass cleanup; these are not crash-proof recordings.
- FFmpeg is required. The installed executable is discovered through the existing screenshot tool. Other machines can set `recording/ffmpeg_path` in Project Settings to an absolute executable path; it is not bundled automatically in an exported build.
- Temporary `frames.mjpeg` and `audio.f32le` are written during capture. These generated streams are removed only after successful MP4 encoding. On failure they and any WAV remain in the clip folder for recovery; originals and previous clips are never overwritten. An audio-buffer overrun or saturated writer queue stops capture with an error rather than silently discarding audio and claiming a good clip. Discarded samples cannot be recovered from the retained files.

## Implementation and measured overhead

The main thread reads back at most 30 viewport frames per second. A bounded four-frame queue sends private images to a worker for JPEG compression and sequential file writes. Final H.264/AAC encoding happens after stop. Missed sampling intervals repeat the preceding image to preserve wall-clock timing instead of speeding up the action. UI layers are discovered once and on node addition, not by scanning the whole scene every rendered frame.

At 1080p an RGBA8 frame is about 8 MiB (roughly 240 MiB/s at 30 readbacks/s), plus GPU synchronization. This is an architectural estimate, not a zero-cost feature; larger source viewports cost more even though output stays 1080p. Game audio is captured from the Master bus through [Godot's AudioEffectCapture](https://docs.godotengine.org/en/4.6/classes/class_audioeffectcapture.html). A two-second ring (rounded up by Godot) is drained every main frame, independently of image capture. A separately bounded four-second audio queue feeds float samples to the worker, which applies gain and streams them to disk. At 48 kHz stereo, float audio uses 0.384 MB/s of disk bandwidth, about 115 MB for five minutes; buffered audio stays within a few megabytes instead of retaining the whole take. Audio processing does not increase the four-image queue. Final peak protection uses [FFmpeg's lookahead limiter](https://ffmpeg.org/ffmpeg-filters.html#alimiter), without automatic makeup gain, before 16-bit conversion.

`capture.json` includes audio frame/rate totals, discarded frames, wall-clock duration difference, input/output-gain peaks and frames exceeding the limiter ceiling. Silence is legitimate data, not counted as a dropout. A zero discarded-frame count rules out capture-ring overflow, not every possible glitch in source sounds or device playback.

Verified 2026-09-14 (recording audio fix):

- `Tests/DirectVideoAudioSmoketest.gd --long` captured 37.184 seconds with a 30-second steady tone, deliberately overloaded input, Master volume changes, mute/unmute and a 250 ms main-thread hitch. Zero audio frames were discarded; audio duration differed from wall time by −1.866 ms (`captures/direct_audio_long_verified.log`). The original pre-fader peak reached 5.958, confirming float capture preserved samples that 16-bit recording would clip.
- `tools/analyze_video_audio_probe.py` checks both `audio.wav` and decoded MP4 AAC: expected recording levels, no full-scale clipping, continuous-tone residual and 100 ms amplitude windows. Both short and longer probes passed. In the longer probe, WAV peak was 0.89127 and decoded AAC peak 0.89170; ordinary-level raw PCM residual was below 0.006%. This is measured waveform validation, not a listening test or a full five-minute battle guarantee.
- `--overflow` deliberately stalled the main thread for 3.5 seconds: 37,888 discarded audio frames were detected, capture stopped with an explicit failure, and raw video/float audio were retained (`captures/direct_audio_overrun_verified.log`). The ordinary 250 ms hitch did not overflow.
- Existing direct-video/AltGr controls, pause coupling, camera cuts, UI hiding, repeated clips, silent capture, effect cleanup and missing-encoder regression passed (`captures/direct_audio_lifecycle_regression.log`). Tests exited normally with the existing ObjectDB cleanup warning. No existing user clips were modified.

Verified 2026-09-13 (before the audio fix):

- Cockpit capture and AI handback passed in the real trailer scenario; an encoded MP4 frame was inspected with instruments visible and dialogue/screen overlays absent (`captures/trailer_pilot_rendered.log`, `captures/trailer_pilot_encoded.png`). Late-created unlayered UI, UI re-shown during capture, nested instrument viewport preservation, and stop-time visibility restoration passed the rendered fixture (`captures/direct_overlay_roots.log`). The full scenario still crashed in native renderer shutdown after printing PASS; this is not a clean-exit claim.
- Rendered synthetic camera-cut test: red/blue views inspected in the encoded video; overlay absent; H.264 1080p/30 and stereo AAC confirmed with ffprobe. Generated tone measured non-silent in the encoded audio. A second silent clip, repeated start/stop, automatic stop on pause, audio-bus/UI restoration, unique output folders, and missing-encoder rejection all passed (`captures/direct_video_lifecycle.log`).
- Actual Trailer Scenario / Aircraft 5 test: 6.033-second MP4 with rear/side/front cuts inspected; 48 kHz stereo audio present, mean −18.9 dB and peak −1.9 dB. 178 readbacks produced 181 output frames (three held intervals), zero queue-full skips. Main-thread readback averaged 6.794 ms, maximum 9.500 ms (`captures/trailer_direct_video.log`). This short sample does not establish heavy-battle or long-recording performance, and audio presence/duration checks are not a perceptual lip-sync assessment.
- Existing aircraft-camera regression passed (`captures/direct_video_camera_regression.log`). Existing full-scenario warnings are still present; these tests do not establish an otherwise error-free game.
