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

## Boundaries and safety

- Escape or opening the pause/camera editor stops the clip before the menu is captured. A scenario change also stops it. Trailer Scenario also pauses whenever capture stops. Space/F6 pause the *simulation*, not the recorder: frozen frames and any continuing audio become part of the video. Stop video with AltGr before spending time composing another shot. Outside Trailer Scenario, Ctrl+F10 retains its ordinary behavior without automatic game pause/unpause.
- Capture stops automatically after five wall-clock minutes. This limits in-memory audio and temporary disk usage; it is not a tested five-minute performance guarantee. Keep the game rendering; minimizing it or a rendering hitch can produce held frames.
- There is no replay radius or six-subject restriction. Everything rendered in the main viewport is captured, but naturally only from the selected live angle.
- Normal stop/quit drains the frame queue and finalizes the video. Prefer stopping and waiting for **Saved video** before closing. A forced editor stop, crash, or process kill can bypass cleanup; these are not crash-proof recordings.
- FFmpeg is required. The installed executable is discovered through the existing screenshot tool. Other machines can set `recording/ffmpeg_path` in Project Settings to an absolute executable path; it is not bundled automatically in an exported build.
- Temporary `frames.mjpeg` is written during capture. It can use substantial disk space for long/high-detail clips. Only this generated stream is removed after successful encoding. On failure it and any WAV remain in the clip folder for recovery; the error is shown rather than claiming success.

## Implementation and measured overhead

The main thread reads back at most 30 viewport frames per second. A bounded four-frame queue sends private images to a worker for JPEG compression and sequential file writes. Final H.264/AAC encoding happens after stop. Missed sampling intervals repeat the preceding image to preserve wall-clock timing instead of speeding up the action. UI layers are discovered once and on node addition, not by scanning the whole scene every rendered frame.

At 1080p an RGBA8 frame is about 8 MiB (roughly 240 MiB/s at 30 readbacks/s), plus GPU synchronization. This is an architectural estimate, not a zero-cost feature; larger source viewports cost more even though output stays 1080p. Game audio is recorded from the Master bus through [Godot's AudioEffectRecord](https://docs.godotengine.org/en/4.6/classes/class_audioeffectrecord.html); the image stream and audio are encoded with [FFmpeg](https://ffmpeg.org/ffmpeg-formats.html#image2pipe).

Verified 2026-09-13:

- Cockpit capture and AI handback passed in the real trailer scenario; an encoded MP4 frame was inspected with instruments visible and dialogue/screen overlays absent (`captures/trailer_pilot_rendered.log`, `captures/trailer_pilot_encoded.png`). Late-created unlayered UI, UI re-shown during capture, nested instrument viewport preservation, and stop-time visibility restoration passed the rendered fixture (`captures/direct_overlay_roots.log`). The full scenario still crashed in native renderer shutdown after printing PASS; this is not a clean-exit claim.
- Rendered synthetic camera-cut test: red/blue views inspected in the encoded video; overlay absent; H.264 1080p/30 and stereo AAC confirmed with ffprobe. Generated tone measured non-silent in the encoded audio. A second silent clip, repeated start/stop, automatic stop on pause, audio-bus/UI restoration, unique output folders, and missing-encoder rejection all passed (`captures/direct_video_lifecycle.log`).
- Actual Trailer Scenario / Aircraft 5 test: 6.033-second MP4 with rear/side/front cuts inspected; 48 kHz stereo audio present, mean −18.9 dB and peak −1.9 dB. 178 readbacks produced 181 output frames (three held intervals), zero queue-full skips. Main-thread readback averaged 6.794 ms, maximum 9.500 ms (`captures/trailer_direct_video.log`). This short sample does not establish heavy-battle or long-recording performance, and audio presence/duration checks are not a perceptual lip-sync assessment.
- Existing aircraft-camera regression passed (`captures/direct_video_camera_regression.log`). Existing full-scenario warnings are still present; these tests do not establish an otherwise error-free game.
