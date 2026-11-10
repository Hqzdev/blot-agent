# Validation — Blot launch film

- Final MP4: 1920×1080, H.264, 30 fps, 900 frames, exactly 30.000 seconds.
- AAC audio: exactly 30.000 seconds, music and local interface SFX, no narration.
- Hyperframes 0.9.23: runtime, layout, motion assertions, contrast and audio checks passed with zero errors.
- Reviewed settled poses and the file-to-document transition under timeline seeking; reviewed contact sheet extracted from the encoded MP4.
- Best settled team frame at 8.3 seconds chosen as poster and baked into frame zero without changing duration, frame count or audio.
- Remaining advisory findings: intentional reuse of agent SVGs, a monolithic editable timeline, small product UI metadata, and one small reply during its exit. Main copy has dedicated reading time.
- Static keyframe scanner cannot resolve the encapsulated FilmDirector timeline; runtime seek assertions and rendered transition snapshots provide the motion proof.
- Render: local Mac, screenshot capture with hardware GPU, two workers, 23.9 seconds. No simulator, external publication or application source changes.
- Free storage after delivery: approximately 22 GiB.
