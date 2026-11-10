# Blot — One task. A whole team.

30-second English product film. Landscape 1920×1080 at 30 fps, music and interface sounds, no narration.

- `brag.mp4`: final delivery, with a selected poster baked into frame zero.
- `brag.jpg`: standalone cover.
- `brag-plan.md`: creative plan and storyboard.
- `composition-brief.md`: production brief.
- `share-copy.txt`: English launch caption.
- `validation.md`: verification results and advisory findings.
- `composition/`: self-contained editable Hyperframes project.

To edit, change `composition/film.js` (motion), `composition/film.css` (design), or `composition/build_film.py` (copy and markup). From `composition/`, run `python3 build_film.py`, then `npm run check` and `npm run dev`. Render with `npm run render -- --quality delivery --fps 30 --output ../brag.mp4`. Dependencies and fonts used by the film are local; the package scripts pin Hyperframes 0.9.23.

The user supplied the Tuple style reference. Real character silhouettes and mascot motion come from the Blot repository. The research task is an illustrative product demonstration. The shared-document reveal adapts the Hyperframes registry card-resize choreography with transform-only motion. Music and SFX come from the locally installed brag skill.
