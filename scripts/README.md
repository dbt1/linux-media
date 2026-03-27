# Scripts Layout

`scripts/` contains version-controlled helper scripts.

Generated files and package-local loader scripts do **not** belong here; they
stay under `out/<profile>/`.

## Layout

- `scripts/<profile>/rebuild.sh`
  Rebuild the modules/package for one tuner profile and the current kernel.
- `scripts/<profile>/install-*.sh`
  Optional, manually-invoked host integration helpers that should be kept under
  version control.
- `scripts/common/`
  Reserved for shared shell helpers once multiple profile scripts need common
  logic.

## Conventions

- Keep scripts profile-specific unless they are clearly shared.
- Resolve the repo root relative to the script location, not the current shell
  directory.
- Write build outputs to `out/`, not to `scripts/`.
- Do not install into `/lib/modules` from these scripts.
- Keep generated/package-adjacent runtime scripts in `out/<profile>/`.
