# Verification record

## Completed in the delivery environment

- All 20 Swift source/package files were parsed with the Swift tree-sitter grammar without syntax-error nodes.
- `bash -n script/build_and_run.sh` passed.
- `bash -n script/validate.sh` passed.
- `.github/workflows/macos.yml` parsed as valid YAML.
- `git diff --check` passed.
- Required-file and project-structure checks in `script/validate.sh` passed.

## Not executable in the delivery environment

The delivery container is Linux x86_64 and contains neither Swift nor the macOS SDK. It therefore cannot type-check SwiftUI/AppKit, link the app, exercise Apple HVF, or launch QEMU's Cocoa display.

Run these two commands on an Apple Silicon Mac before treating v0.1 as release-ready:

```bash
swift test
./script/build_and_run.sh --verify
```

Then perform one manual smoke test with a Microsoft Windows 11 ARM64 ISO: reach Windows Setup, confirm keyboard/mouse input, verify the NVMe target disk is visible, complete one reboot, request normal shutdown from WinLift, and confirm `qemu.pid` disappears.
