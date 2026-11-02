#ifndef PLAYRA_LUMINA_CORE_H
#define PLAYRA_LUMINA_CORE_H
#include <stddef.h>
#include <stdint.h>
#if defined(__GNUC__)
#define LUMINA_API __attribute__((visibility("default")))
#else
#define LUMINA_API
#endif
#ifdef __cplusplus
extern "C" {
#endif
/* Playra adapter ABI 1, not the supplier's header.
 * All calls are process-serialized. init copies its JSON and retains it until
 * process exit, as required by the supplier. NULL library_path selects the
 * read-only sibling liblumina_core_vendor.so. No JNI, socket or device bridge.
 * call copies its input; output is owned by the adapter until core_free.
 * Active-call timeout quarantines this process; init cannot reset quarantine.
 * Waiting for the serial lock returns BUSY within the same timeout budget.
 * Dart cancellation does not interrupt an already running supplier call.
 */
enum lumina_core_error {
  LUMINA_CORE_OK = 0,
  LUMINA_CORE_ARGUMENT = -1,
  LUMINA_CORE_LOAD = -2,
  LUMINA_CORE_SYMBOL = -3,
  LUMINA_CORE_SELFTEST = -4,
  LUMINA_CORE_NOT_READY = -5,
  LUMINA_CORE_TIMEOUT = -6,
  LUMINA_CORE_QUARANTINED = -7,
  LUMINA_CORE_REPLY = -8,
  LUMINA_CORE_MEMORY = -9,
  LUMINA_CORE_THREAD = -10,
  LUMINA_CORE_PAGE_SIZE = -11,
  LUMINA_CORE_IDENTITY = -12,
  LUMINA_CORE_BUSY = -13
};
LUMINA_API int lumina_core_abi_version(void);
LUMINA_API int lumina_core_state(void); /* 0 unavailable, 1 ready, 2 quarantined */
LUMINA_API int lumina_core_init(const char *library_path, const char *init_json,
                              const uint8_t key[16], const uint8_t iv[16]);
LUMINA_API int lumina_core_call(const uint8_t *json, size_t length,
                              uint32_t timeout_ms, uint8_t **output,
                              size_t *output_length);
LUMINA_API void lumina_core_free(void *pointer);
#ifdef __cplusplus
}
#endif
#endif
