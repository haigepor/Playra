#include "lumina_core.h"
#include <assert.h>
#include <dlfcn.h>
#include <pthread.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <unistd.h>
static double now_ms(void) {
  struct timespec t; clock_gettime(CLOCK_MONOTONIC, &t);
  return t.tv_sec * 1000.0 + t.tv_nsec / 1000000.0;
}
static int exchange(const char *json, unsigned timeout, const char *expected) {
  uint8_t *output = NULL; size_t n = 0;
  int rc = lumina_core_call((const uint8_t *)json, strlen(json), timeout, &output, &n);
  if (expected) {
    assert(rc == 0 && output && n < 1024);
    char result[1024]; memcpy(result, output, n); result[n] = 0;
    assert(strstr(result, expected));
  } else assert(!output && n == 0);
  lumina_core_free(output); return rc;
}
static void *concurrent(void *token) {
  assert(exchange(token, 2000, token) == 0); return NULL;
}
static void *long_call(void *unused) {
  (void)unused;
  assert(exchange("alpha_late", 1000, "alpha") == 0); return NULL;
}
int main(int argc, char **argv) {
  assert(argc == 3);
  const char *test = argv[2]; uint8_t key[16] = {0}, iv[16] = {0};
  assert(lumina_core_abi_version() == 1);
  assert(exchange("before_init", 20, NULL) == LUMINA_CORE_NOT_READY);
  if (!strcmp(test, "missing")) {
    assert(lumina_core_init("/not/a/library.so", "{}", key, iv) == LUMINA_CORE_LOAD);
    puts("PASS missing library"); return 0;
  }
  if (!strcmp(test, "selftest")) {
    setenv("CORE_TEST_BAD_AES", "1", 1);
    assert(lumina_core_init(argv[1], "{}", key, iv) == LUMINA_CORE_SELFTEST);
    puts("PASS selftest fails closed"); return 0;
  }
  char *config = strdup("{\"test\":true}");
  assert(lumina_core_init(argv[1], config, key, iv) == 0);
  memset(config, 0, strlen(config)); free(config);
  assert(lumina_core_init(argv[1], "{\"test\":true}", key, iv) == 0);
  assert(lumina_core_init(argv[1], "{}", key, iv) == LUMINA_CORE_IDENTITY);
  if (!strcmp(test, "late") || !strcmp(test, "blocking") || !strcmp(test, "never")) {
    double start = now_ms();
    assert(exchange(test, 10, NULL) == LUMINA_CORE_TIMEOUT);
    assert(now_ms() - start < 100.0);
    assert(lumina_core_state() == 2);
    assert(exchange("beta", 1000, NULL) == LUMINA_CORE_QUARANTINED);
    usleep(180000);
    assert(exchange("beta", 1000, NULL) == LUMINA_CORE_QUARANTINED);
    assert(lumina_core_init(argv[1], "{\"test\":true}", key, iv) == LUMINA_CORE_QUARANTINED);
  } else if (!strcmp(test, "queue")) {
    void *handle = dlopen(argv[1], RTLD_NOW | RTLD_LOCAL);
    int (*active_count)(void) = (int (*)(void))dlsym(handle, "test_active");
    assert(active_count);
    pthread_t a; pthread_create(&a, NULL, long_call, NULL);
    double start = now_ms();
    while (active_count() == 0 && now_ms() - start < 1000) usleep(1000);
    assert(active_count() == 1);
    start = now_ms();
    assert(exchange("beta", 5, NULL) == LUMINA_CORE_BUSY);
    assert(now_ms() - start < 100.0);
    pthread_join(a, NULL);
    assert(lumina_core_state() == 1);
    assert(exchange("beta", 1000, "beta") == 0);
  } else if (!strcmp(test, "concurrent")) {
    pthread_t a, b;
    pthread_create(&a, NULL, concurrent, "alpha");
    pthread_create(&b, NULL, concurrent, "beta");
    pthread_join(a, NULL); pthread_join(b, NULL);
  } else if (!strcmp(test, "malformed") || !strcmp(test, "padding")) {
    assert(exchange(test, 1000, NULL) == LUMINA_CORE_REPLY);
    assert(exchange("alpha", 1000, "alpha") == 0);
  } else {
    assert(exchange("alpha", 1000, "alpha") == 0);
    assert(exchange("beta", 1000, "beta") == 0);
    uint8_t *output = NULL; size_t n = 0;
    assert(lumina_core_call(NULL, 1, 20, &output, &n) == LUMINA_CORE_ARGUMENT);
    assert(lumina_core_call((uint8_t *)"x", 4u*1024u*1024u, 20, &output, &n) == LUMINA_CORE_ARGUMENT);
  }
  printf("PASS %s\n", test); return 0;
}
