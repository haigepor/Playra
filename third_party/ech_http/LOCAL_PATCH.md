# Local compatibility patch

Source: Pub `ech_http 0.2.1`, https://github.com/ech-research/ech_http.
The original package license and third-party notices are retained.

Only `src/CMakeLists.txt`, `src/ca_bundle.h.in`, and the new `src/CaBundle.cmake`
change the runtime build. The CA bundle is appended in bounded raw string chunks
to avoid MSVC C2026. The resulting string must match the original PEM byte for byte;
no certificate or TLS verification behavior is removed. MSVC compiles as UTF-8.
The local `.gitattributes` preserves upstream bytes, including the PEM line endings,
when checking out on Windows with `core.autocrlf` enabled.

Regression check: configure/build `test/native_ca_bundle` with MSVC, then run CTest.
The original template fails with C2026; the patched template compiles and preserves
the complete certificate bundle.

Official compiler limit: https://learn.microsoft.com/en-us/cpp/error-messages/compiler-errors-1/compiler-error-c2026?view=msvc-170.
