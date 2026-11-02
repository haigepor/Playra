# Lumina Dart + C engine

This package consumes the native engine shipped in SDK `d3d7d93` (2026-11-02). It has no Python, JNI emulation, adb bridge, or Python service dependency. Dart implements authentication assembly, RSA envelopes, the verified AES/F primitives, HTTP, playback source routing, resolver parsing, and the seven-operation adapter. The supplier C engine computes the proprietary block-chain calibration and encryption/decryption.

The request envelope and the response envelope use **two independent RSA key pairs**. `_SERVER_PUB_B64` must carry the server's request public key; deriving it from the response private key still lets every GET succeed but makes every POST fail with `BUSINESS_REJECTED`. See `docs/analysis/lumina-source-sync-20261103.zh.md` for the full sync record.

`include/lumina_used_abi.h` documents the **integration declarations** transcribed from the SDK's ctypes bindings. It is not a supplier header or a claim that the engine is open source. Only seven verified symbols are used. C `long` is bound as Dart FFI `Long`; buffers remain caller-owned and are released after synchronous completion. The library has process-global state and must be owned by one long-lived isolate. Request cancellation discards results; it does not interrupt native execution.

Private files live in ignored `native/` and root `assets/lumina_private/`. `inputs.json` pins every input with SHA-256. The build hook bundles the matching prebuilt as a Flutter code asset and rejects changed inputs. Compressed runtime image data is verified and materialized in application support storage; executable libraries are never loaded from that writable data cache.

| Target | Current integration |
|---|---|
| Android arm64 | In-process supplier `libcore` response accelerator, with portable C engine fallback; no Python or device bridge |
| Android x64 | Portable C engine; no supplier x64 `libcore` artifact |
| Windows x64 | Bundled DLL; offline vectors and live seven-operation check |
| Android arm32 | Lumina not registered; base app remains available |
| iOS device/simulator | No supplier engine artifact; Lumina not registered |
| Linux/macOS | SDK has candidate binaries, but deployment/runtime compatibility is not established; not enabled |
| Web | Base app remains available; native Lumina requires a new Dart Native BFF or a supplier WASM engine; no Python fallback |

Remaining supplier requirements: authoritative versioned C header with status/ownership/threading contracts; ABI/version negotiation; iOS arm64 device and simulator arm64/x64 static archives or XCFramework with matching headers and deployment targets; reproducible source/build settings or signed pinned artifacts; macOS install-name/signing/minimum-version confirmation and Linux runtime ABI confirmation. The available macOS ARM binary targets macOS 13; it is not an iOS library. Unknown exported symbols are deliberately not bound.

The ARM64 accelerator uses the verified supplier C exports `init`, `call`, `AES_set_encrypt_key`, `AES_set_decrypt_key`, and `AES_cbc_encrypt`. `include/lumina_core.h` defines Playra adapter ABI 1; it is not an official supplier header. The adapter owns the channel encryption and native callback, preserves the initialization JSON for the process lifetime, serializes native calls, bounds buffers, and transfers output ownership through `lumina_core_free`. An active-call timeout permanently quarantines that backend until process restart. Dart cancellation discards the result and cannot stop supplier execution. Normal routing falls back to `_fuse` on a typed accelerator failure; strict diagnostic routing never silently falls back.

`api_decrypt` requires the original request path **including its encoded query string**. In particular, dropping `id`, `play`, or `part` from a playback response context makes the supplier return access-control code 300400/10032. `luminaResponsePath` preserves the wire context. A real business rejection remains a business failure and does not trigger a retry through another decoder.

Playback has two source kinds. A source starting with `http` is a direct media URL and is returned as `kind: direct` without touching the resolver; anything else (`a|b|c|d`) is an opaque token that goes through the resolver endpoint. `510423 播放遇到问题` is a transient rejection — `_play` retries it once after 600 ms and only then reports failure. Resolver decoding tries the current Lua `aes_key`/`aes_iv` first, then the historical rotation pairs, because the server has twice been observed serving a new Lua key several minutes before the resolver endpoint switched (2026-11-02, roughly four minutes). The new Lua no longer emits a `salt` field; the salt is a literal inside `sign()` (`data .. "kvdenozcjy" .. ts`), and both forms are parsed.

The vendor binary is pinned by `inputs.json` integration version 3 and loaded only as a read-only sibling of the packaged shim. Its LOAD alignment remains 4 KiB, so the accelerator rejects page sizes above 4 KiB. Android `_fuse` and the adapter are 16 KiB aligned; full app/device 16 KiB compatibility still requires device validation. Request encryption and authentication continue through the portable C engine. Removing Python does not remove fresh-key calibration cost on the fallback path.

`LuminaEngine.maxBlocks` is 1900. The portable Cb generator aborts or hangs the host process (not a Dart exception) at roughly 1944 blocks, so the fused fallback path rejects oversized responses with `RESPONSE_TOO_LARGE` before entering native code. Server pagination caps (lists ≤25, search ≤30, comments ≤50) keep normal responses far below the limit. The core backend additionally pre-checks `_CORE_CHANNEL_KEY`, `_CORE_CHANNEL_IV`, and `_CORE_TCP` and signals a non-terminal `CORE_CONFIG`, so a trimmed profile falls back to `_fuse` instead of failing the whole worker with `ENGINE_UNAVAILABLE`.

Calibration now uses a bounded same-key cache (eight keys, 2 MiB of chain tables). A cache miss still calls `lumafuse_calib_direct` once for the complete chain, as the reference `EBlock.calibrate` does. `CbQuery` uses the same primitive. Fresh response keys do not benefit from reuse of a previous key. Diagnostic stages distinguish calibration, a calibration cache hit, and final native decryption.

Developer commands (run package commands from this directory):

```text
dart run bin/check.dart <private-fixture.json> <profile.json> <image.bin> [more-vectors.json]
dart run bin/live.dart <profile.json> <image.bin> <private-report.json>
dart run bin/benchmark.dart <image.bin> <private-report.json>
```

The optional vector file contains eleven synthetic block-chain cases and three fixed authentication cases generated by the external reference SDK. It stays outside tracked source. Do not publish private fixtures or input bundles.

Android verification entry points (same package/signature/version, preserve app data): `tool/lumina_android_smoke.dart` exercises all seven operations; `tool/lumina_core_compare.dart` compares both backends against one in-memory encrypted response, twenty samples each. `tool/test-lumina-core-contract.ps1` builds standalone native contract tests and runs them through adb as test transport; adb is not an application dependency. Diagnostic builds accept only `auto`, `core`, or `fuse` in the app external-files `lumina-backend.txt`, read at process startup. Production builds ignore that file. `LUMINA_RESPONSE_BACKEND` provides the equivalent compile-time selection. Initialization, HTTP, response backend, decryption, resolver, address-ready, and first-frame timings are separate; no keys, authentication headers, or full media URLs are logged.
