# Releasing sunset

Operator runbook for cutting and publishing a sunset release.  This document
governs the path from a validated commit on `main` to an immutable public
release.

> **Who can run this.**  Promoting a release to "published" requires
> maintainer authorization.  Tasks that publish or move tags are gated on
> explicit approval and must not be automated away.

## 1. Governance prerequisites

Before starting a release, confirm every prerequisite is met.  Do not proceed
if any item is unchecked.

- [ ] The module path is canonical: `go list -m` prints
      `github.com/enolalabs/sunset`.
- [ ] The version resolver is in place (`internal/version`) and the Makefile
      `RELEASE_LDFLAGS` target
      `-X github.com/enolalabs/sunset/internal/version.BuildVersion=<version>`
      is wired.
- [ ] The release helper scripts exist under `.github/scripts/release/`
      (`smoke.sh`, `smoke.ps1`, `package-and-verify.sh`,
      `package-and-verify.ps1`, `verify-consumer.sh`).
- [ ] The install snippets under `docs/snippets/<version>/` exist and
      `bash .github/scripts/release/check-doc-snippets.sh` passes.
- [ ] Release notes exist under `.github/release-notes/<version>.md` and are
      normalized to UTF-8 with LF line endings (`file` reports
      `ASCII text` / `UTF-8 Unicode text`, never `CRLF`).
- [ ] Maintainer authorization to cut the release has been recorded.

## 2. Validation-run evidence

A release is built from an exact commit.  Capture the evidence that the commit
is release-worthy before binding a tag to it.

1. Record the candidate commit SHA.
2. For each of the five targets, build with the release ldflags and run
   `package-and-verify.sh` (or `.ps1` on Windows):

   ```bash
   make release VERSION=<version>            # builds bin/sunset
   bash .github/scripts/release/package-and-verify.sh \
       bin/sunset <version> <os> <arch> \
       testdata/go-sample <archive-output-dir>
   ```

   Each helper prints exactly one absolute archive path on success and exits
   non-zero with diagnostics on stderr otherwise.
3. Run the consumer import check to confirm the public API resolves at the
   intended tag:

   ```bash
   bash .github/scripts/release/verify-consumer.sh v<version> <work-dir>
   ```

4. Retain the archive paths, smoke output, and consumer result as the
   validation-run evidence for this release.  Promotion in §5 depends on it.

## 3. Exact tag binding

- The release tag is `v<version>` (e.g. `v1.0.1`) and **must** point at the
  exact commit validated in §2.
- Create the tag as an annotated tag on that commit only.  Do not create the
  tag from a different commit, branch tip, or working tree with uncommitted
  changes.
- The tag binds the version string to the artifact set: the archives, the
  checksums, and the release notes are all identified by this tag.

## 4. Expected draft assets

A draft release for `v<version>` must contain exactly these assets, named per
the rule `sunset_<version>_<os>_<arch>.<format>`:

| Archive | Format |
|---|---|
| `sunset_<version>_linux_amd64.tar.gz` | tar.gz |
| `sunset_<version>_linux_arm64.tar.gz` | tar.gz |
| `sunset_<version>_darwin_amd64.tar.gz` | tar.gz |
| `sunset_<version>_darwin_arm64.tar.gz` | tar.gz |
| `sunset_<version>_windows_amd64.zip` | zip |

Plus:

- `checksums.txt` — one `<sha256>  <filename>` line per archive, five lines
  total, sorted by filename.
- The release notes body from `.github/release-notes/<version>.md`.

If the draft is missing any asset, or contains an asset not in this list, do
not approve (§5).

## 5. Approval

- A release is created as a **draft** first.  Nothing public resolves until the
  draft is explicitly published.
- Only a maintainer with authorization may flip the draft to published.
- Before approving, re-verify:
  - all five archives plus `checksums.txt` are attached (§4);
  - the draft tag matches `v<version>` and points at the validated commit (§3);
  - the release notes are the UTF-8/LF-normalized file from §1;
  - `check-doc-snippets.sh` still passes against the published README.

## 6. Draft rerun and stale asset behavior

- **Rerunning the pipeline** before publishing replaces the draft assets for
  the tag.  A new draft supersedes the previous draft; the previous draft's
  artifacts are discarded.
- **Stale assets** from a failed or abandoned run must be removed before a new
  draft is created.  Do not layer new archives onto a draft that already
  carries mismatched files.
- **A published release is never modified by a rerun.**  Once the release is
  published (§7), pipeline reruns have no effect on it.  If the pipeline is
  re-triggered after publishing, it must target a new version, not the
  published tag.

## 7. Published immutability

- Once published, the release tag, archives, and `checksums.txt` are
  **immutable**.  Do not force-push the tag, re-upload assets, or edit the
  published release body.
- Public URLs are version-explicit and stable:
  `https://github.com/enolalabs/sunset/releases/download/v<version>/<archive>`.
  Do **not** use `/releases/latest/download/` with versioned filenames — the
  `latest` alias moves when a newer release publishes, which would silently
  break pinned checksum verification.

## 8. Public verification

After publishing, confirm the release is consumable by the public:

1. Fetch each archive and `checksums.txt` from the version-explicit URL.
2. Run the matching install snippet from `docs/snippets/<version>/` against the
   public URL (no `SUNSET_BASE_URL` override).
3. Confirm `sunset version` prints `<version>` for every target that can be
   tested locally.
4. Confirm an external module can `go get
   github.com/enolalabs/sunset@v<version>` and compile.

If any step fails after publishing, treat it as a defect and recover via §9.

## 9. Recovery (v1.0.2 and later)

Published releases are immutable (§7), so recovery means cutting a **new**
version, never republishing the broken one.

1. Fix the defect on a new commit on `main`.
2. Choose the next version (e.g. `v1.0.2` for a patch).
3. Author `docs/snippets/v1.0.2/` install snippets and
   `.github/release-notes/v1.0.2.md`, and re-run `check-doc-snippets.sh`.
4. Repeat §1–§8 for the new version.
5. In the new release notes, state that the previous published version is
   retained (immutable) and identify what the new version fixes.  Do not
   delete or hide the prior release.
