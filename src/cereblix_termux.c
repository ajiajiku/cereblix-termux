#define _GNU_SOURCE
#include "nm_engine.h"
#include <arpa/inet.h>
#include <errno.h>
#include <netdb.h>
#include <signal.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/socket.h>
#include <sys/time.h>
#include <time.h>
#include <unistd.h>

static volatile sig_atomic_t stop_now;
static void on_signal(int sig) { (void)sig; stop_now = 1; }

static int tcp_connect(const char *host, int port) {
    char service[16];
    snprintf(service, sizeof service, "%d", port);
    struct addrinfo hints = {0}, *res = NULL, *p;
    hints.ai_socktype = SOCK_STREAM;
    hints.ai_family = AF_UNSPEC;
    if (getaddrinfo(host, service, &hints, &res) != 0) return -1;
    int fd = -1;
    for (p = res; p; p = p->ai_next) {
        fd = socket(p->ai_family, p->ai_socktype, p->ai_protocol);
        if (fd < 0) continue;
        if (connect(fd, p->ai_addr, p->ai_addrlen) == 0) break;
        close(fd); fd = -1;
    }
    freeaddrinfo(res);
    return fd;
}

static int send_json(int fd, const char *s) {
    size_t n = strlen(s), off = 0;
    while (off < n) {
        ssize_t w = send(fd, s + off, n - off, MSG_NOSIGNAL);
        if (w <= 0) return -1;
        off += (size_t)w;
    }
    return send(fd, "\n", 1, MSG_NOSIGNAL) == 1 ? 0 : -1;
}

static int json_string(const char *json, const char *key, char *out, size_t cap) {
    char pat[96];
    snprintf(pat, sizeof pat, "\"%s\"", key);
    const char *p = strstr(json, pat);
    if (!p) return 0;
    p += strlen(pat);
    while (*p && *p != ':') ++p;
    if (*p != ':') return 0;
    ++p;
    while (*p == ' ' || *p == '\t') ++p;
    if (*p != '\"') return 0;
    ++p;
    size_t n = 0;
    while (*p && *p != '\"' && n + 1 < cap) {
        if (*p == '\\' && p[1]) ++p;
        out[n++] = *p++;
    }
    out[n] = 0;
    return *p == '\"';
}

/* Read a string key from a specific JSON object region. For login replies we
 * must read result.id, not the top-level request id. */
static int json_object_string(const char *json, const char *object_key,
                              const char *key, char *out, size_t cap) {
    char pat[96];
    snprintf(pat, sizeof pat, "\"%s\"", object_key);
    const char *p = strstr(json, pat);
    if (!p) return 0;
    p = strchr(p + strlen(pat), '{');
    if (!p) return 0;
    return json_string(p, key, out, cap);
}

static unsigned long long json_u64(const char *json, const char *key) {
    char pat[96];
    snprintf(pat, sizeof pat, "\"%s\"", key);
    const char *p = strstr(json, pat);
    if (!p) return 0;
    p += strlen(pat);
    while (*p && *p != ':') ++p;
    if (*p != ':') return 0;
    ++p;
    while (*p == ' ' || *p == '\t' || *p == '\"') ++p;
    return strtoull(p, NULL, 10);
}

static int hex_bytes(const char *s, uint8_t *out, int cap) {
    size_t n = strlen(s);
    if ((n & 1) || (int)(n / 2) > cap) return -1;
    for (int i = 0; i < (int)(n / 2); ++i) {
        unsigned v;
        if (sscanf(s + i * 2, "%2x", &v) != 1) return -1;
        out[i] = (uint8_t)v;
    }
    return (int)(n / 2);
}

static int valid_wallet(const char *s) {
    size_t n = strlen(s);
    if (n < 5 || n > 120) return 0;
    for (size_t i = 0; i < n; ++i)
        if (!((s[i] >= 'a' && s[i] <= 'z') || (s[i] >= '0' && s[i] <= '9'))) return 0;
    return strncmp(s, "crb1", 4) == 0;
}

static int valid_worker(const char *s) {
    size_t n = strlen(s);
    if (!n || n > 32) return 0;
    for (size_t i = 0; i < n; ++i) {
        char c = s[i];
        if (!((c >= 'A' && c <= 'Z') || (c >= 'a' && c <= 'z') ||
              (c >= '0' && c <= '9') || c == '_' || c == '-' || c == '.')) return 0;
    }
    return 1;
}

static void print_stats(void) {
    static uint64_t last;
    uint64_t now = nm_engine_hashes();
    printf("hashes: %llu (+%llu/10s)\n", (unsigned long long)now,
           (unsigned long long)(now - last));
    fflush(stdout);
    last = now;
}

int main(int argc, char **argv) {
    const char *host = "stratum.cereblix.com";
    const char *wallet = NULL;
    const char *worker = "termux";
    int port = 3333, threads = 0;

    for (int i = 1; i < argc; ++i) {
        if ((!strcmp(argv[i], "-u") || !strcmp(argv[i], "--wallet")) && i + 1 < argc)
            wallet = argv[++i];
        else if ((!strcmp(argv[i], "-w") || !strcmp(argv[i], "--worker")) && i + 1 < argc)
            worker = argv[++i];
        else if (!strcmp(argv[i], "-t") && i + 1 < argc)
            threads = atoi(argv[++i]);
        else if (!strcmp(argv[i], "-o") && i + 1 < argc) {
            static char endpoint[256];
            const char *u = argv[++i];
            const char *q = strstr(u, "://");
            if (q) u = q + 3;
            snprintf(endpoint, sizeof endpoint, "%s", u);
            char *colon = strrchr(endpoint, ':');
            if (colon) { *colon = 0; port = atoi(colon + 1); }
            host = endpoint;
        } else if (!strcmp(argv[i], "-h") || !strcmp(argv[i], "--help")) {
            puts("Cereblix Termux ARM miner\n  -o stratum+tcp://host:port\n  -u crb1...\n  -w worker-name\n  -t threads");
            return 0;
        }
    }

    if (!wallet || !valid_wallet(wallet)) { fprintf(stderr, "Invalid/missing CRB wallet.\n"); return 2; }
    if (!valid_worker(worker)) { fprintf(stderr, "Invalid worker name.\n"); return 2; }

    signal(SIGINT, on_signal);
    signal(SIGTERM, on_signal);
    puts("Running NeuroMorph self-test...");
    if (!nm_engine_selftest()) { fprintf(stderr, "NeuroMorph self-test FAILED.\n"); return 3; }

    if (threads <= 0) threads = nm_engine_big_core_count();
    if (threads < 1) threads = nm_engine_core_count();
    if (threads < 1) threads = 1;
    if (threads > 16) threads = 16;
    if (nm_engine_start(threads, NM_AFFINITY_ALL) != 0) { fprintf(stderr, "Unable to start native engine.\n"); return 4; }

    printf("Cereblix Termux ARM\nPool: %s:%d\nWallet: %s\nWorker: %s\nThreads: %d\n", host, port, wallet, worker, threads);

    unsigned long long msgid = 1;
    unsigned long long accepted = 0;
    while (!stop_now) {
        int fd = tcp_connect(host, port);
        if (fd < 0) { fprintf(stderr, "Pool connection failed; retrying...\n"); sleep(3); continue; }
        struct timeval tv = {1, 0};
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, sizeof tv);

        char login[1024];
        snprintf(login, sizeof login,
            "{\"id\":%llu,\"jsonrpc\":\"2.0\",\"method\":\"login\",\"params\":{\"login\":\"%s\",\"pass\":\"x\",\"agent\":\"nmminer-android/2.0\",\"rigid\":\"nmminer-termux\"}}",
            msgid++, wallet);
        if (send_json(fd, login) < 0) { close(fd); sleep(2); continue; }

        char session[256] = "";
        char buf[32768]; size_t used = 0;
        time_t last_keepalive = time(NULL), last_stats = time(NULL);

        while (!stop_now) {
            char tmp[4096];
            ssize_t r = recv(fd, tmp, sizeof tmp, 0);
            if (r > 0) {
                if (used + (size_t)r >= sizeof buf) used = 0;
                memcpy(buf + used, tmp, (size_t)r);
                used += (size_t)r;
                buf[used] = 0;

                char *line;
                while ((line = strchr(buf, '\n')) != NULL) {
                    size_t len = (size_t)(line - buf);
                    char msg[8192];
                    if (len >= sizeof msg) len = sizeof msg - 1;
                    memcpy(msg, buf, len); msg[len] = 0;
                    size_t rem = used - ((size_t)(line - buf) + 1);
                    memmove(buf, line + 1, rem); used = rem; buf[used] = 0;

                    char blob[4096], seed[128], target[128], jobid[256];
                    if (json_string(msg, "blob", blob, sizeof blob) &&
                        json_string(msg, "seed_hash", seed, sizeof seed) &&
                        json_string(msg, "target", target, sizeof target) &&
                        json_string(msg, "job_id", jobid, sizeof jobid)) {
                        uint8_t h[124], s[32], t[32], ta[32] = {0};
                        int hn = hex_bytes(blob, h, sizeof h);
                        int sn = hex_bytes(seed, s, sizeof s);
                        int tn = hex_bytes(target, t, sizeof t);
                        if (hn == 124 && sn == 32 && tn > 0 && tn <= 32) {
                            memcpy(ta + 32 - tn, t, tn);
                            nm_engine_set_job(h, s, json_u64(msg, "height"), ta, jobid);
                            printf("job %s\n", jobid); fflush(stdout);
                        }
                    }

                    /* Critical: the login session is result.id. The old wrapper
                     * accidentally captured the top-level JSON-RPC request id,
                     * which made every submit use "1" as the session and caused
                     * every share to be rejected. */
                    if (!session[0]) {
                        char sid[256];
                        if (json_object_string(msg, "result", "id", sid, sizeof sid)) {
                            snprintf(session, sizeof session, "%s", sid);
                            fprintf(stderr, "Pool session established.\n");
                        }
                    }

                    if (strstr(msg, "\"status\":\"OK\"") || strstr(msg, "\"status\": \"OK\"")) {
                        ++accepted;
                        printf("share accepted (%llu)\n", accepted); fflush(stdout);
                    }
                    if (strstr(msg, "\"error\"")) {
                        fprintf(stderr, "pool error: %s\n", msg);
                    }
                }
            } else if (r < 0 && (errno == EAGAIN || errno == EWOULDBLOCK)) {
                /* timeout: continue hashing */
            } else {
                break;
            }

            time_t now = time(NULL);
            uint8_t hash[32]; char jid[256], hh[65], nonce_hex[17]; uint64_t nonce;
            while (nm_engine_poll_share(jid, sizeof jid, &nonce, hash)) {
                for (int k = 0; k < 32; ++k) sprintf(hh + 2 * k, "%02x", hash[k]);
                hh[64] = 0;
                for (int k = 0; k < 8; ++k) sprintf(nonce_hex + 2 * k, "%02x", (unsigned)((nonce >> (8 * k)) & 255u));
                nonce_hex[16] = 0;
                if (!session[0]) {
                    fprintf(stderr, "share ready but pool session is not established; waiting.\n");
                    continue;
                }
                char submit[1024];
                snprintf(submit, sizeof submit,
                    "{\"id\":%llu,\"jsonrpc\":\"2.0\",\"method\":\"submit\",\"params\":{\"id\":\"%s\",\"job_id\":\"%s\",\"nonce\":\"%s\",\"result\":\"%s\"}}",
                    msgid++, session, jid, nonce_hex, hh);
                if (send_json(fd, submit) < 0) break;
            }

            if (now - last_keepalive >= 30 && session[0]) {
                char keepalive[512];
                snprintf(keepalive, sizeof keepalive,
                    "{\"id\":%llu,\"jsonrpc\":\"2.0\",\"method\":\"keepalived\",\"params\":{\"id\":\"%s\"}}",
                    msgid++, session);
                send_json(fd, keepalive);
                last_keepalive = now;
            }
            if (now - last_stats >= 10) { print_stats(); last_stats = now; }
        }
        close(fd);
        if (!stop_now) { fprintf(stderr, "Pool disconnected; reconnecting...\n"); sleep(2); }
    }

    nm_engine_stop();
    puts("Stopped.");
    return 0;
}
