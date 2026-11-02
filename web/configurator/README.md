# Crossover Face configurator

Every setting of the face, plus a custom theme, in a browser — and a code to carry them
to the watch. The code goes into **Config code** in the face's Garmin Connect settings;
`docs/config-code.md` is the format.

```sh
npm ci
npm run dev        # http://localhost:5173
npm test           # codec vectors, palette and luminance against the watch's figures
npm run e2e        # builds, then drives the page in the installed Chrome
npm run build      # static site in dist/, relative paths, host anywhere
```

Nothing about the face is written here by hand. `src/generated/face-schema.json` and
`public/geometry/*.json` are generated from the watch's own sources by
`tools/face_schema_export.py` and `tools/geometry_export.py`; re-run them after a settings
or lattice change (`make test-simctl` fails while they are stale).

The preview draws the field at the watch's native resolution with sample readings. Hands,
the date and over-goal laps are the watch's own and are not drawn.
