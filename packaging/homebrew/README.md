# Homebrew distribution

`glance.rb` in this directory is a Homebrew cask for Glance. There are two
distribution paths, and you'll almost certainly want to start with the first.

## Path 1: personal tap (available now, works unsigned or signed)

A "tap" is just a git repo named `homebrew-<name>` that Homebrew can add as a
package source. This works today, before Glance is code-signed or notarized —
Gatekeeper will just show the normal "unidentified developer" warning on
first launch until the app is notarized (see `RELEASING.md`).

1. Create a new GitHub repo named **`homebrew-tap`** under your account
   (`adikondepudi/homebrew-tap`).
2. Add this cask at `Casks/glance.rb` in that repo (copy `glance.rb` from
   here, or symlink it in via a release CI step).
3. After cutting a release, update `version` and `sha256` in the cask (see
   "Updating the sha256" below) and push.
4. Users install with:
   ```bash
   brew tap adikondepudi/tap
   brew install --cask glance
   ```
   or in one line: `brew install --cask adikondepudi/tap/glance`.

Nothing about this path requires an Apple Developer account. It's the right
home for the cask indefinitely, even after submitting to homebrew/homebrew-cask
(most projects keep their own tap as the canonical/fastest-updating source).

## Path 2: submitting to homebrew/homebrew-cask (official tap)

This gets Glance installable via plain `brew install --cask glance` with no
tap step, but it comes with real requirements. From memory, flagging what
I'm not fully certain of — verify against the current
[homebrew-cask CONTRIBUTING.md](https://github.com/Homebrew/homebrew-cask/blob/master/CONTRIBUTING.md)
before submitting, since these policies do shift:

- **Code signing + notarization is effectively required.** Homebrew-cask's
  automated audit (`brew audit --cask --online --new`) checks Gatekeeper
  acceptance, and PRs for unsigned/unnotarized macOS apps are routinely
  rejected or held up by maintainers in practice. Treat this as a hard
  prerequisite — don't submit until `./release.sh` is taking the signed +
  notarized path (see `RELEASING.md`).
- **Notability guidelines.** Homebrew-cask expects submitted software to be
  reasonably well-known rather than a brand-new/unknown project — historically
  this was framed as a rough numeric bar (I recall figures in the neighborhood
  of ~30-50 GitHub stars/forks/watchers being cited as an old rule of thumb),
  but the current guidance is more holistic/discretionary and I'm not
  confident the exact numeric thresholds I remember are still accurate or
  still enforced the same way. **Check the live CONTRIBUTING.md and recent
  merged/rejected cask PRs for similar-sized projects before assuming Glance
  qualifies.**
- The cask itself must pass `brew audit --cask --new --online Casks/glance.rb`
  with no errors (correct `sha256`, working `livecheck`, valid `url`/`homepage`,
  etc.) — the template in `glance.rb` is written to satisfy the structural
  parts of that audit.

If Glance doesn't yet meet the notability bar, the personal tap (Path 1) is
not a lesser option — plenty of well-established macOS software is
distributed solely via its own tap.

## Updating the sha256 after each release

Every release produces a new DMG, so `sha256` in the cask must be updated
each time (Homebrew verifies the download against it):

```bash
shasum -a 256 release/Glance-<version>.dmg
```

Copy the resulting hash into `sha256 "..."` in `glance.rb`, and bump
`version "..."` to match. If/when this cask lives in a tap repo with
`livecheck` wired to CI, this step can be automated with
`brew bump-cask-pr` or a small release-script addition; for now it's manual.
