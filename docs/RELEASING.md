# Releasing FloMorphic & writing the changelog

FloMorphic is a **wrapped product**: this `getting-started` repo is the release
marker, and **a changelog commit here is a new FloMorphic version** — its git tag
names the image `mehdishokohi/flomorphic:<version>`. The source lives in component
repos that are **not** tagged per release, and every release rolls up the commits
that landed across *all* of them into one product changelog:

| Component         | Repo                                    | Local checkout            | Built from |
| ----------------- | --------------------------------------- | ------------------------- | ---------- |
| API               | `github.com/FloMorphic/morph-api`       | `../flomorphic-api`       | `main`     |
| Canvas            | `github.com/FloMorphic/morph-wapp`      | `../flomorphic-wapp`      | `main`     |
| Builtin plugins   | `github.com/FloMorphic/builtin-plugins` | `../builtin-plugins`      | `main`     |
| Plugin SDK (Go)   | `github.com/FloMorphic/inflow-plugin-sdk` | `../../inflow-plugin-sdk` | `main`   |
| Plugin SDK (node) | `github.com/FloMorphic/node-plugin-sdk` | `../../node-plugin-sdk`   | `main`     |

The changelog reports the whole team's activity for the release window regardless
of which repo (or, in future, which teammate) the commits came from. Add a repo to
the roll-up by adding it to `COMPONENTS` in `scripts/gen-changelog.sh`.

Because the components carry no per-release tags, a product changelog can't be
produced by diffing tags. Instead **each release records the exact commit each repo
baked from** in `releases/<version>.json`, and the next release diffs every repo
from those SHAs to current `main`. That lock file is the offset — it is what makes
the changelog reproducible without tagging every repo in lockstep.

## Cutting a release

1. **Draft the changelog** from what landed in the components since the last
   release:

   ```sh
   make changelog VERSION=v0.3.3          # prints a draft, doesn't touch files
   ```

   This reads the newest `releases/*.json`, lists each component's commits since
   its recorded SHA (grouped Added / Changed / Fixed / Maintenance), and prints a
   Keep-a-Changelog section plus the offset lock it *would* write.

   The generator reads history from the local checkouts in the table above.
   Override any of them with `API_DIR=… WAPP_DIR=… PLUGINS_DIR=… PSDK_DIR=…
   NSDK_DIR=…`. A repo with no local checkout is skipped with a warning, so a
   partial clone still produces a changelog for the repos you do have. Make sure
   the checkouts are on `main` and `git pull`ed first — the diff is only as current
   as your checkout.

2. **Edit `CHANGELOG.md`.** Paste the draft under a new `## [vX.Y.Z]` heading and
   rewrite the raw commit subjects into reader-facing prose. Commit messages are a
   starting point, not the deliverable — a changelog is for humans deciding
   whether to upgrade. Move the `[Unreleased]` link and add the new compare/tag
   links at the bottom.

3. **Save the offset** for the next release:

   ```sh
   make changelog-lock VERSION=v0.3.3     # writes releases/v0.3.3.json at current HEADs
   ```

4. **Tag and build** the image (existing flow):

   ```sh
   make release VERSION=v0.3.3            # multi-arch :v0.3.3 + :latest, pushed
   git tag v0.3.3 && git push --tags      # this repo is the release marker
   ```

   Pin components explicitly for a reproducible build with the SHAs from the lock,
   e.g. `make release VERSION=v0.3.3 API_REF=<sha> WAPP_REF=<sha> PLUGINS_REF=<sha>`.

## Files

- `CHANGELOG.md` — the human-facing product changelog, one section per release.
- `releases/<version>.json` — the offset lock: exact component SHAs that release
  baked from. Never hand-delete these; they are the diff boundaries.
- `scripts/gen-changelog.sh` — the generator. Read-only over git history; it never
  edits `CHANGELOG.md` or tags anything.

## Versioning

Semantic Versioning. Bump **minor** for user-visible features, **patch** for fixes
and maintenance. Versions were set by hand through v0.3.1; from v0.3.2 onward each
is git-tagged on this repo.
