# Next-chat context — after the 2026-10-11 reset restore (updated ~21:20 IST, machine `arch`)

## Where things stand
The system is restored, rebooted and cleaned up. Seamless login works (verified on the 19:02 boot:
the service opened the session, SDDM stayed inactive). Packages and running processes were audited
one by one; Voxtype dictation was rebuilt for accuracy with low idle RAM.
Checkpoint note: `memory://main/sessions/2026/parm/202610111857-system-reset-restore-and-dotfiles-cleanup`

## Done
- Repos: all 10 in `repos.txt` cloned, clean, in sync. LifeOS pushed (`bbd45d0`).
- Shell: login shell `/usr/bin/zsh`; zinit; minimal Oct 11 `~/.zshrc` (`7e9398e`).
- Seamless login: `/usr/local/bin/seamless-login` + `omarchy-seamless-login.service`; SDDM disabled.
  Sources + installer in `customscripts/seamless-login/` (`a36e7f0`).
- Package cleanup (1355 -> ~1290 packages, ~3.5 GB): removed Codex desktop app, VirtualBox (+DKMS,
  `linux-lts-headers`), Podman, Ollama, Readest, Kiwix, khal/vdirsyncer, openlogi, Go/clang/llvm, CUPS,
  Alacritty, Ventoy, AUR `-debug` packages. Kept GNOME Boxes, Docker (socket-activated), Brave/Helium/Zen,
  all editors, FDM + Open Video Downloader, `google-cloud-cli` (clock), sqlitebrowser, foot only terminal.
  Package groups match this (`a36e7f0`); pacman and yay caches cleared; `~/.restore-session-20261011` deleted.
- Removing the Codex desktop app required deleting `[mcp_servers.node_repl]` from `~/.codex/config.toml`
  (backup `~/.codex/config.toml.bak-2026-10-11`).
- `~/.config/pacman/makepkg.conf` sets `!debug`, so yay stops building `-debug` packages.
- avahi daemon + socket disabled and masked (library still needed). TPM units masked: disk unlock is a
  password (`cryptdevice=`), not TPM. `systemctl --failed` is empty.
- `backup.sh` reads Omarchy 4 package lists from `/usr/share/omarchy/install`.
- Voxtype (configs in `config/.config/`, steps in README "After restore"):
  - Whisper `large-v3-turbo` on Vulkan (Iris Xe), `on_demand_loading` + `gpu_isolation`: ~140 MB idle,
    ~2.7 GB for a few seconds while transcribing, ~8–10 s per dictation.
  - Records from an RNNoise virtual mic (`rnnoise_source`) via `audio.device = "pipewire"` +
    `PIPEWIRE_NODE=rnnoise_source`. Background noise -30 dB -> -69 dB. Only Voxtype uses it.
  - Built-in mic input set to 65% (100% clipped).
  - Parakeet v3 int8 was tested: ~0.25 s and ~1 GB, but less accurate on this voice; Whisper chosen.
    Parakeet Redux (Moondream) rejected: closed Photon runtime, worse in noise, no Hindi, not in Voxtype.

## Open items
1. Dictate a few real sentences with the noise filter and confirm accuracy. If worse, roll back:
   remove `~/.config/systemd/user/voxtype.service.d/denoise.conf`, `voxtype config set audio.device default`,
   `systemctl --user daemon-reload && systemctl --user restart voxtype`.
2. Restore leftovers (confirm before deleting):
   - `~/Backup/Code` 21M — 8 items exist only here + SSD: `0context`, `1Plans`, `.commandcode`, `skills-main`,
     `skills-main.zip`, `ContentOS-indexeddb-heatmap.zip`, `CopyContentIntoFile.go`, `rently.txt`
   - `~/.zshrc.pre-merge` (identical to `~/.zshrc`)
3. No source anywhere for `AmarV3/amar-v4`, `Projects/emailos`, `Projects/FormCraft`, `Projects/Blog-CMS-ai`.
4. SSD `AMAR_WD/PARM/System-Reset-2026-10-11` was pulled uncleanly at 18:02 — re-verify
   (`zstd -t`, `fsck.exfat -n`) before trusting it.
5. Biggest RAM user is Zen (~3 GB of tabs). T3's own `cloudflared` tunnel stays (remote access is used).

## Lessons
- `~/system-dotfiles-restore-*` was a git *worktree*, which caused "main already used" and the rejected push.
- Compare against `origin/main` before merging dotfiles; a stale checkout had an older `.zshrc`.
- Unmount the SSD (`udisksctl unmount`, close Nautilus) before unplugging.
- On Omarchy, fcitx5 also powers the Compose key (`~/.XCompose` name/email snippets), so don't disable it.
- Voxtype records via ALSA; target a PipeWire node with `PIPEWIRE_NODE`, not `audio.device`.
- Back in Aug 2026 the user asked for Omarchy's always-loaded Voxtype default; with the large model that
  holds ~2.7 GB, so on-demand loading was chosen deliberately on 2026-10-11.

## Paste-ready opener for the next chat
> Read `~/system-dotfiles/docs/NEXT-CHAT-CONTEXT-2026-10-11.md` (or the Basic Memory note
> `202610111857-system-reset-restore-and-dotfiles-cleanup`) and continue from "Open items".
