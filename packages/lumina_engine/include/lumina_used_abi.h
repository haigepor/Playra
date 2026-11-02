#ifndef PLAYRA_LUMINA_USED_ABI_H
#define PLAYRA_LUMINA_USED_ABI_H
#include <stdint.h>
#ifdef __cplusplus
extern "C" {
#endif
/* Integration declarations transcribed from SDK 88109b2 ctypes bindings.
 * This is NOT a supplier header. Only the verified subset is declared.
 * All input/output buffers are caller owned. No asynchronous callbacks.
 * long is platform C long (32-bit on Windows, 64-bit on Android arm64/x64).
 * The engine has process-global state: serialize ALL calls in one worker.
 * init requires an absolute UTF-8 path to the verified uncompressed image.
 * Return: init/post_init/decrypt 0 success; encryption >=0 output bytes;
 * calib_direct returns the requested block count. Negative is failure.
 */
int lumafuse_init(const char *image_path);
int lumafuse_post_init(void);
const char *lumafuse_version(void); /* borrowed NUL-terminated string */
long lumafuse_encrypt_iv(const uint8_t *key16, const uint8_t *iv16,
    const uint8_t *data, uint64_t length, uint8_t *out, uint64_t capacity);
long lumafuse_encrypt_a1(const uint8_t *key32, const uint8_t *iv16,
    const uint8_t *a1, uint64_t length, uint8_t *out, uint64_t capacity);
long lumafuse_calib_direct(const uint8_t *key16, uint64_t blocks,
    uint8_t *constants, uint8_t *tweaks);
int lumafuse_decrypt(const uint8_t *cipher, uint64_t blocks,
    const uint8_t *key16, const uint8_t *c16, const uint8_t *constants,
    const uint8_t *tweaks, uint8_t *out);
#ifdef __cplusplus
}
#endif
#endif
