# Sounds

NotchMeow's own sounds: 48 kHz, 16-bit, mono WAVs, one per slot and named after it, played at volume 0.12. This folder
holds those files and this README, nothing else (`build_pack.py` and `tests/test_sound_shipped.py` check it).

They are built from CC0 clips, which are credited in `docs/SOUND-CREDITS.md`. Every recorded clip was decoded from its
Freesound HQ preview (MP3); no original WAV was downloaded. Four sounds and part of the hairball are made in code.
To rebuild them, set `NM_SOUND_HQ_PREVIEWS` to
the folder holding the HQ previews (or pass `--hq-previews DIR`) and run
`python3 tools/sounds/build_pack.py --set mine --originals --out NotchBuddy/Resources/sounds --report`
(see `docs/superpowers/specs/2026-10-04-sounds-design.md`). Don't edit the WAVs by hand: rebuild them.
Coucou's sounds are © Louis Raillé and must never be added back.

Both players skip missing files, so a slot without a WAV is simply silent:
`SoundEngine.swift` (macOS) and `windows/src/core/sound.ts` (Windows, Linux).

Slots:
peek open close hover blip slap annoyed dizzy greet work finish error approval
question approve gulp tick send love pop proud wink yawn attach think search rate sleep hairball
