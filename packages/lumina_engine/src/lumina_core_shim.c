#define _GNU_SOURCE
#include "lumina_core.h"
#include <dlfcn.h>
#include <errno.h>
#include <pthread.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <unistd.h>

#define CORE_MAX_INPUT (3u * 1024u * 1024u)
#define CORE_MAX_REPLY (8u * 1024u * 1024u)
typedef const char *(*reply_fn)(void *, void *);
typedef void (*supplier_call_fn)(const char *, reply_fn);
typedef int (*aes_key_fn)(const unsigned char *, int, void *);
typedef void (*aes_cbc_fn)(const unsigned char *, unsigned char *, size_t,
                           const void *, unsigned char *, int);
typedef union { max_align_t alignment; uint8_t bytes[256]; } aes_schedule;
static pthread_mutex_t call_lock = PTHREAD_MUTEX_INITIALIZER;
static pthread_mutex_t result_lock = PTHREAD_MUTEX_INITIALIZER;
static pthread_once_t condition_once = PTHREAD_ONCE_INIT;
static pthread_cond_t condition;
static int condition_ready, state, armed, callback_done, thread_done, reply_error;
static void *library_handle;
static supplier_call_fn supplier_call;
static aes_key_fn aes_encrypt_key, aes_decrypt_key;
static aes_cbc_fn aes_cbc;
static uint8_t channel_key[16], channel_iv[16];
static char *init_keep, *input_keep, *reply;

static struct timespec deadline_after(uint32_t ms) {
  struct timespec deadline;
  clock_gettime(CLOCK_MONOTONIC, &deadline);
  deadline.tv_sec += ms / 1000;
  deadline.tv_nsec += (long)(ms % 1000) * 1000000;
  if (deadline.tv_nsec >= 1000000000) { deadline.tv_sec++; deadline.tv_nsec -= 1000000000; }
  return deadline;
}
static int expired(const struct timespec *deadline) {
  struct timespec now; clock_gettime(CLOCK_MONOTONIC, &now);
  return now.tv_sec > deadline->tv_sec ||
      (now.tv_sec == deadline->tv_sec && now.tv_nsec >= deadline->tv_nsec);
}
static int lock_before(const struct timespec *deadline) {
  const struct timespec pause = {0, 1000000};
  while (pthread_mutex_trylock(&call_lock) != 0) {
    if (expired(deadline)) return 0;
    nanosleep(&pause, NULL);
  }
  return 1;
}

static void init_condition(void) {
  pthread_condattr_t attr;
  if (pthread_condattr_init(&attr) != 0) return;
  if (pthread_condattr_setclock(&attr, CLOCK_MONOTONIC) == 0 &&
      pthread_cond_init(&condition, &attr) == 0) condition_ready = 1;
  pthread_condattr_destroy(&attr);
}
static const char alphabet[] =
    "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
static char *b64_encode(const uint8_t *data, size_t n) {
  size_t size = ((n + 2) / 3) * 4, p = 0;
  char *out = malloc(size + 1);
  if (!out) return NULL;
  for (size_t i = 0; i < n; i += 3) {
    unsigned v = ((unsigned)data[i] << 16) |
        (i + 1 < n ? (unsigned)data[i + 1] << 8 : 0) |
        (i + 2 < n ? data[i + 2] : 0);
    out[p++] = alphabet[(v >> 18) & 63];
    out[p++] = alphabet[(v >> 12) & 63];
    out[p++] = i + 1 < n ? alphabet[(v >> 6) & 63] : '=';
    out[p++] = i + 2 < n ? alphabet[v & 63] : '=';
  }
  out[p] = 0;
  return out;
}
static int b64_value(unsigned char c) {
  if (c >= 'A' && c <= 'Z') return c - 'A';
  if (c >= 'a' && c <= 'z') return c - 'a' + 26;
  if (c >= '0' && c <= '9') return c - '0' + 52;
  return c == '+' ? 62 : c == '/' ? 63 : -1;
}
static uint8_t *b64_decode(const char *input, size_t *length) {
  const size_t n = strlen(input);
  if (!n || n % 4 || n > CORE_MAX_REPLY) return NULL;
  uint8_t *out = malloc(n / 4 * 3);
  if (!out) return NULL;
  size_t p = 0;
  for (size_t i = 0; i < n; i += 4) {
    int a = b64_value(input[i]), b = b64_value(input[i + 1]);
    int c = b64_value(input[i + 2]), d = b64_value(input[i + 3]);
    int pad_c = input[i + 2] == '=', pad_d = input[i + 3] == '=';
    if (a < 0 || b < 0 || (!pad_c && c < 0) || (!pad_d && d < 0) ||
        (pad_c && !pad_d) || ((pad_c || pad_d) && i + 4 != n)) {
      free(out); return NULL;
    }
    out[p++] = (uint8_t)((a << 2) | (b >> 4));
    if (!pad_c) out[p++] = (uint8_t)((b << 4) | (c >> 2));
    if (!pad_d) out[p++] = (uint8_t)((c << 6) | d);
  }
  *length = p;
  return out;
}
static int selftest(void) {
  static const uint8_t plain[16] = {
    0x00,0x11,0x22,0x33,0x44,0x55,0x66,0x77,
    0x88,0x99,0xaa,0xbb,0xcc,0xdd,0xee,0xff};
  static const uint8_t expected[16] = {
    0x69,0xc4,0xe0,0xd8,0x6a,0x7b,0x04,0x30,
    0xd8,0xcd,0xb7,0x80,0x70,0xb4,0xc5,0x5a};
  uint8_t key[16], iv[16] = {0}, result[16], decoded[16];
  aes_schedule schedule;
  for (int i = 0; i < 16; i++) key[i] = (uint8_t)i;
  if (aes_encrypt_key(key, 128, &schedule) != 0) return 0;
  aes_cbc(plain, result, 16, &schedule, iv, 1);
  if (memcmp(expected, result, 16)) return 0;
  memset(iv, 0, sizeof(iv));
  if (aes_decrypt_key(key, 128, &schedule) != 0) return 0;
  aes_cbc(result, decoded, 16, &schedule, iv, 0);
  return memcmp(plain, decoded, 16) == 0;
}

static const char *receive_reply(void *payload, void *context) {
  (void)context;
  pthread_mutex_lock(&result_lock);
  if (armed && !callback_done) {
    size_t n = payload ? strnlen((const char *)payload, CORE_MAX_REPLY + 1) : 0;
    if (!n || n > CORE_MAX_REPLY) reply_error = LUMINA_CORE_REPLY;
    else {
      reply = malloc(n + 1);
      if (!reply) reply_error = LUMINA_CORE_MEMORY;
      else memcpy(reply, payload, n + 1);
    }
    callback_done = 1;
    pthread_cond_signal(&condition);
  }
  pthread_mutex_unlock(&result_lock);
  return "{\"code\":200}";
}
static void *dispatch(void *unused) {
  (void)unused;
  supplier_call(input_keep, receive_reply);
  pthread_mutex_lock(&result_lock);
  thread_done = 1;
  pthread_cond_signal(&condition);
  pthread_mutex_unlock(&result_lock);
  return NULL;
}

int lumina_core_abi_version(void) { return 1; }
int lumina_core_state(void) {
  pthread_mutex_lock(&result_lock);
  int value = state;
  pthread_mutex_unlock(&result_lock);
  return value;
}
void lumina_core_free(void *pointer) { free(pointer); }

int lumina_core_init(const char *path, const char *json,
                     const uint8_t key[16], const uint8_t iv[16]) {
  if (!json || !key || !iv || !*json || strnlen(json, 16385) > 16384)
    return LUMINA_CORE_ARGUMENT;
  pthread_mutex_lock(&call_lock);
  int rc = LUMINA_CORE_OK, previous = lumina_core_state();
  if (previous == 2) { rc = LUMINA_CORE_QUARANTINED; goto done; }
  if (previous == 1) {
    rc = strcmp(init_keep, json) || memcmp(channel_key, key, 16) ||
        memcmp(channel_iv, iv, 16) ? LUMINA_CORE_IDENTITY : LUMINA_CORE_OK;
    goto done;
  }
  /* 供应商库仍为 4 KiB LOAD；此处拒绝在大页设备尝试加载。 */
  if (sysconf(_SC_PAGESIZE) > 4096) { rc = LUMINA_CORE_PAGE_SIZE; goto done; }
  pthread_once(&condition_once, init_condition);
  if (!condition_ready) { rc = LUMINA_CORE_NOT_READY; goto done; }
  char sibling[4096];
  if (!path) {
    Dl_info info;
    if (!dladdr((void *)lumina_core_init, &info) || !info.dli_fname) {
      rc = LUMINA_CORE_LOAD; goto done;
    }
    const char *slash = strrchr(info.dli_fname, '/');
    if (!slash || slash - info.dli_fname > 3900) { rc = LUMINA_CORE_LOAD; goto done; }
    snprintf(sibling, sizeof(sibling), "%.*s/liblumina_core_vendor.so",
             (int)(slash - info.dli_fname), info.dli_fname);
    path = sibling;
  }
  library_handle = dlopen(path, RTLD_NOW | RTLD_LOCAL);
  if (!library_handle) { rc = LUMINA_CORE_LOAD; goto done; }
  supplier_call = (supplier_call_fn)dlsym(library_handle, "call");
  void (*initialize)(const char *, reply_fn) =
      (void (*)(const char *, reply_fn))dlsym(library_handle, "init");
  aes_encrypt_key = (aes_key_fn)dlsym(library_handle, "AES_set_encrypt_key");
  aes_decrypt_key = (aes_key_fn)dlsym(library_handle, "AES_set_decrypt_key");
  aes_cbc = (aes_cbc_fn)dlsym(library_handle, "AES_cbc_encrypt");
  if (!supplier_call || !initialize || !aes_encrypt_key || !aes_decrypt_key || !aes_cbc) {
    rc = LUMINA_CORE_SYMBOL; goto done;
  }
  if (!selftest()) { rc = LUMINA_CORE_SELFTEST; goto done; }
  init_keep = strdup(json);
  if (!init_keep) { rc = LUMINA_CORE_MEMORY; goto done; }
  memcpy(channel_key, key, 16); memcpy(channel_iv, iv, 16);
  /* init 会保存 JSON 指针；库和该缓冲均随进程常驻，不能 dlclose。 */
  initialize(init_keep, receive_reply);
  pthread_mutex_lock(&result_lock);
  state = 1;
  pthread_mutex_unlock(&result_lock);
done:
  pthread_mutex_unlock(&call_lock);
  return rc;
}

int lumina_core_call(const uint8_t *json, size_t length, uint32_t timeout_ms,
                     uint8_t **output, size_t *output_length) {
  if (!output || !output_length) return LUMINA_CORE_ARGUMENT;
  *output = NULL; *output_length = 0;
  if (!json || !length || length > CORE_MAX_INPUT || !timeout_ms || timeout_ms > 30000)
    return LUMINA_CORE_ARGUMENT;
  const struct timespec deadline = deadline_after(timeout_ms);
  if (!lock_before(&deadline)) return LUMINA_CORE_BUSY;
  int rc = LUMINA_CORE_OK, current = lumina_core_state();
  if (current != 1) {
    rc = current == 2 ? LUMINA_CORE_QUARANTINED : LUMINA_CORE_NOT_READY;
    goto done;
  }
  size_t padded = (length / 16 + 1) * 16;
  uint8_t *plain = malloc(padded), *cipher = malloc(padded);
  if (!plain || !cipher) {
    free(plain); free(cipher); rc = LUMINA_CORE_MEMORY; goto done;
  }
  memcpy(plain, json, length);
  memset(plain + length, (int)(padded - length), padded - length);
  aes_schedule schedule;
  uint8_t iv[16]; memcpy(iv, channel_iv, 16);
  if (aes_encrypt_key(channel_key, 128, &schedule) != 0) {
    free(plain); free(cipher); rc = LUMINA_CORE_SELFTEST; goto done;
  }
  aes_cbc(plain, cipher, padded, &schedule, iv, 1);
  free(plain);
  input_keep = b64_encode(cipher, padded);
  free(cipher);
  if (!input_keep) { rc = LUMINA_CORE_MEMORY; goto done; }
  if (expired(&deadline)) {
    free(input_keep); input_keep = NULL; rc = LUMINA_CORE_BUSY; goto done;
  }
  pthread_mutex_lock(&result_lock);
  callback_done = thread_done = reply_error = 0;
  reply = NULL; armed = 1;
  pthread_mutex_unlock(&result_lock);
  pthread_t thread;
  if (pthread_create(&thread, NULL, dispatch, NULL) != 0) {
    pthread_mutex_lock(&result_lock); armed = 0; pthread_mutex_unlock(&result_lock);
    free(input_keep); input_keep = NULL; rc = LUMINA_CORE_THREAD; goto done;
  }
  pthread_detach(thread);
  pthread_mutex_lock(&result_lock);
  int wait_rc = 0;
  while ((!callback_done || !thread_done) && wait_rc == 0)
    wait_rc = pthread_cond_timedwait(&condition, &result_lock, &deadline);
  armed = 0;
  if (!callback_done || !thread_done) {
    /* 迟到回调无法归属下一请求：此进程永久隔离，输入保留防异步 use-after-free。 */
    state = 2;
    free(reply); reply = NULL;
    pthread_mutex_unlock(&result_lock);
    rc = LUMINA_CORE_TIMEOUT; goto done;
  }
  pthread_mutex_unlock(&result_lock);
  free(input_keep); input_keep = NULL;
  if (reply_error) { rc = reply_error; free(reply); reply = NULL; goto done; }
  size_t decoded_size = 0;
  uint8_t *decoded = b64_decode(reply, &decoded_size);
  free(reply); reply = NULL;
  if (!decoded || !decoded_size || decoded_size % 16) {
    free(decoded); rc = LUMINA_CORE_REPLY; goto done;
  }
  uint8_t *result = malloc(decoded_size);
  if (!result) { free(decoded); rc = LUMINA_CORE_MEMORY; goto done; }
  memcpy(iv, channel_iv, 16);
  if (aes_decrypt_key(channel_key, 128, &schedule) != 0) {
    free(decoded); free(result); rc = LUMINA_CORE_SELFTEST; goto done;
  }
  aes_cbc(decoded, result, decoded_size, &schedule, iv, 0);
  free(decoded);
  unsigned pad = result[decoded_size - 1];
  if (!pad || pad > 16) { free(result); rc = LUMINA_CORE_REPLY; goto done; }
  for (unsigned i = 0; i < pad; i++) {
    if (result[decoded_size - 1 - i] != pad) {
      free(result); rc = LUMINA_CORE_REPLY; goto done;
    }
  }
  *output = result; *output_length = decoded_size - pad;
done:
  pthread_mutex_unlock(&call_lock);
  return rc;
}
