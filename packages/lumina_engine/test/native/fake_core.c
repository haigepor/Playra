/* Contract fixture only: identity channel except the loader's NIST self-test.
 * Never bundled; real cipher equivalence is tested separately with libcore. */
#include <pthread.h>
#include <stdatomic.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
typedef const char *(*callback_fn)(void *, void *);
static const char *initialization;
static atomic_int active;
int test_active(void) { return atomic_load(&active); }
static const unsigned char plain[16] = {
  0,0x11,0x22,0x33,0x44,0x55,0x66,0x77,0x88,0x99,0xaa,0xbb,0xcc,0xdd,0xee,0xff};
static const unsigned char cipher[16] = {
  0x69,0xc4,0xe0,0xd8,0x6a,0x7b,0x04,0x30,0xd8,0xcd,0xb7,0x80,0x70,0xb4,0xc5,0x5a};
int AES_set_encrypt_key(const unsigned char *key, int bits, void *schedule) {
  memcpy(schedule, key, 16); return bits == 128 ? 0 : -1;
}
int AES_set_decrypt_key(const unsigned char *key, int bits, void *schedule) {
  return AES_set_encrypt_key(key, bits, schedule);
}
void AES_cbc_encrypt(const unsigned char *in, unsigned char *out, size_t n,
                     const void *schedule, unsigned char *iv, int enc) {
  (void)iv;
  if (getenv("CORE_TEST_BAD_AES")) { memset(out, 0, n); return; }
  int nist = n == 16;
  for (int i = 0; i < 16; i++) nist &= ((const unsigned char *)schedule)[i] == i;
  if (nist) memcpy(out, enc ? cipher : plain, 16);
  else memcpy(out, in, n);
}
static const char alphabet[] = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
static int value(char c) {
  const char *p = strchr(alphabet, c); return p ? (int)(p - alphabet) : 0;
}
static char *decode(const char *s) {
  size_t n = strlen(s), p = 0; char *out = calloc(1, n + 1);
  for (size_t i = 0; i < n; i += 4) {
    int a = value(s[i]), b = value(s[i + 1]), c = value(s[i + 2]), d = value(s[i + 3]);
    out[p++] = (char)((a << 2) | (b >> 4));
    if (s[i + 2] != '=') out[p++] = (char)((b << 4) | (c >> 2));
    if (s[i + 3] != '=') out[p++] = (char)((c << 6) | d);
  }
  return out;
}
static char *encode(const unsigned char *s, size_t n) {
  char *out = malloc((n + 2) / 3 * 4 + 1); size_t p = 0;
  for (size_t i = 0; i < n; i += 3) {
    unsigned v = (s[i] << 16) | (i + 1 < n ? s[i + 1] << 8 : 0) | (i + 2 < n ? s[i + 2] : 0);
    out[p++] = alphabet[(v >> 18) & 63]; out[p++] = alphabet[(v >> 12) & 63];
    out[p++] = i + 1 < n ? alphabet[(v >> 6) & 63] : '=';
    out[p++] = i + 2 < n ? alphabet[v & 63] : '=';
  }
  out[p] = 0; return out;
}
struct request { const char *input; callback_fn cb; int overlap; };
static void *answer(void *raw) {
  struct request *request = raw;
  usleep(2000);
  char *json = decode(request->input); // Input must remain alive after call returns.
  if (strstr(json, "late") || strstr(json, "blocking")) usleep(120000);
  atomic_fetch_sub(&active, 1);
  if (strstr(json, "never")) { free(json); free(request); return NULL; }
  if (strstr(json, "malformed")) request->cb("not_base64!", NULL);
  else if (strstr(json, "padding")) {
    unsigned char invalid[16] = {0}; char *bad = encode(invalid, 16);
    request->cb(bad, NULL); free(bad);
  } else {
    char reply[256];
    snprintf(reply, sizeof(reply), "{\"code\":200,\"payload\":{\"data\":\"%s\"}}",
      request->overlap ? "overlap" : !initialization || strcmp(initialization, "{\"test\":true}") ?
      "bad_init_lifetime" : strstr(json, "alpha") ? "alpha" : "beta");
    size_t n = strlen(reply), padded = (n / 16 + 1) * 16;
    memset(reply + n, (int)(padded - n), padded - n);
    char *encoded = encode((unsigned char *)reply, padded);
    request->cb(encoded, NULL); free(encoded);
  }
  free(json); free(request); return NULL;
}
void init(const char *json, callback_fn callback) { (void)callback; initialization = json; }
void call(const char *input, callback_fn cb) {
  struct request *r = malloc(sizeof(*r));
  *r = (struct request){input, cb, atomic_fetch_add(&active, 1) != 0};
  char *json = decode(input);
  int blocking = strstr(json, "blocking") != NULL;
  free(json);
  if (blocking) { answer(r); return; }
  pthread_t thread; pthread_create(&thread, NULL, answer, r); pthread_detach(thread);
}
