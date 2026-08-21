#define _GNU_SOURCE
#include <time.h>
#include "nm_engine.h"
#include "nm_neuromorph.h"
#include <arpa/inet.h>
#include <errno.h>
#include <netdb.h>
#include <pthread.h>
#include <signal.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/socket.h>
#include <sys/time.h>
#include <unistd.h>

static volatile sig_atomic_t running = 1;
static int sockfd = -1;
static pthread_mutex_t wlock = PTHREAD_MUTEX_INITIALIZER;
static char session[128];
static unsigned msgid = 1;
static unsigned long long accepted = 0, rejected = 0;

#define MAX_PENDING_SUBMITS 256
static unsigned pending_submit_ids[MAX_PENDING_SUBMITS];
static size_t pending_submit_count = 0;

static void stop_now(int s) { (void)s; running = 0; }

static int hexbyte(const char *p) {
    int a, b;
    if (sscanf(p, "%1x%1x", &a, &b) != 2) return -1;
    return (a << 4) | b;
}

static int hexbuf(const char *s, uint8_t *o, int cap) {
    size_t n = strlen(s);
    if (n % 2 || n / 2 > (size_t)cap) return -1;
    for (size_t i = 0; i < n / 2; i++) {
        int v = hexbyte(s + 2 * i);
        if (v < 0) return -1;
        o[i] = (uint8_t)v;
    }
    return (int)(n / 2);
}

static int json_str(const char *j, const char *k, char *out, size_t cap) {
    char pat[96];
    snprintf(pat, sizeof pat, "\"%s\"", k);
    const char *p = strstr(j, pat);
    if (!p) return 0;
    p += strlen(pat);
    while (*p && *p != ':') p++;
    if (*p != ':') return 0;
    p++;
    while (*p == ' ' || *p == '\t') p++;
    if (*p != '\"') return 0;
    p++;
    size_t i = 0;
    while (*p && *p != '\"' && i + 1 < cap) {
        if (*p == '\\' && p[1]) p++;
        out[i++] = *p++;
    }
    out[i] = 0;
    return 1;
}

static unsigned long long json_u64(const char *j, const char *k) {
    char pat[96];
    snprintf(pat, sizeof pat, "\"%s\"", k);
    const char *p = strstr(j, pat);
    if (!p) return 0;
    p += strlen(pat);
    while (*p && *p != ':') p++;
    if (*p != ':') return 0;
    p++;
    while (*p == ' ' || *p == '\t' || *p == '\"') p++;
    return strtoull(p, NULL, 10);
}

static int connect_tcp(const char *h, int port) {
    char ps[16];
    snprintf(ps, sizeof ps, "%d", port);
    struct addrinfo a = {0}, *r = 0;
    a.ai_socktype = SOCK_STREAM;
    a.ai_family = AF_UNSPEC;
    if (getaddrinfo(h, ps, &a, &r) != 0) return -1;
    int s = -1;
    for (struct addrinfo *p = r; p; p = p->ai_next) {
        s = socket(p->ai_family, p->ai_socktype, p->ai_protocol);
        if (s < 0) continue;
        if (connect(s, p->ai_addr, p->ai_addrlen) == 0) break;
        close(s);
        s = -1;
    }
    freeaddrinfo(r);
    return s;
}

static int send_json(const char *s) {
    pthread_mutex_lock(&wlock);
    size_t n = strlen(s);
    int ok = sockfd >= 0 &&
             send(sockfd, s, n, MSG_NOSIGNAL) == (ssize_t)n &&
             send(sockfd, "\n", 1, MSG_NOSIGNAL) == 1;
    pthread_mutex_unlock(&wlock);
    return ok;
}

static void remember_submit_id(unsigned id) {
    pthread_mutex_lock(&wlock);
    if (pending_submit_count >= MAX_PENDING_SUBMITS) {
        memmove(pending_submit_ids, pending_submit_ids + 1,
                (MAX_PENDING_SUBMITS - 1) * sizeof(pending_submit_ids[0]));
        pending_submit_count = MAX_PENDING_SUBMITS - 1;
    }
    pending_submit_ids[pending_submit_count++] = id;
    pthread_mutex_unlock(&wlock);
}

static int take_submit_id(unsigned id) {
    int found = 0;
    pthread_mutex_lock(&wlock);
    for (size_t i = 0; i < pending_submit_count; i++) {
        if (pending_submit_ids[i] == id) {
            memmove(pending_submit_ids + i, pending_submit_ids + i + 1,
                    (pending_submit_count - i - 1) * sizeof(pending_submit_ids[0]));
            pending_submit_count--;
            found = 1;
            break;
        }
    }
    pthread_mutex_unlock(&wlock);
    return found;
}

static void apply_job(const char *j) {
    char blob[512], seed[128], target[128], jid[128];
    if (!json_str(j, "blob", blob, sizeof blob) ||
        !json_str(j, "seed_hash", seed, sizeof seed) ||
        !json_str(j, "target", target, sizeof target) ||
        !json_str(j, "job_id", jid, sizeof jid)) return;

    uint8_t h[NM_HEADER_LEN], sd[32], tg[32] = {0};
    int hn = hexbuf(blob, h, sizeof h);
    int sn = hexbuf(seed, sd, sizeof sd);
    int tn = hexbuf(target, tg, sizeof tg);
    if (hn != NM_HEADER_LEN || sn != 32 || tn < 0 || tn > 32) return;
    if (tn < 32) {
        memmove(tg + 32 - tn, tg, (size_t)tn);
        memset(tg, 0, 32 - tn);
    }

    unsigned long long height = json_u64(j, "height");
    nm_engine_set_job(h, sd, height, tg, jid);
    fprintf(stderr, "\njob %s height %llu\n", jid, height);
}

static void *submit_loop(void *x) {
    (void)x;
    while (running) {
        char jid[128], hh[65], nh[17];
        uint64_t nonce;
        uint8_t hash[32];
        while (nm_engine_poll_share(jid, sizeof jid, &nonce, hash)) {
            for (int i = 0; i < 32; i++) snprintf(hh + 2 * i, 3, "%02x", hash[i]);
            hh[64] = 0;
            for (int i = 0; i < 8; i++) snprintf(nh + 2 * i, 3, "%02x", (unsigned)((nonce >> (8 * i)) & 255));
            nh[16] = 0;
            char m[768];
            unsigned id = msgid++;
            snprintf(m, sizeof m,
                     "{\"id\":%u,\"jsonrpc\":\"2.0\",\"method\":\"submit\",\"params\":{\"id\":\"%s\",\"job_id\":\"%s\",\"nonce\":\"%s\",\"result\":\"%s\"}}",
                     id, session, jid, nh, hh);
            remember_submit_id(id);
            if (!send_json(m)) {
                running = 0;
                break;
            }
        }
        usleep(150000);
    }
    return NULL;
}

static void handle_line(char *l) {
    /* Login response contains result.id (session). Server-pushed job messages
     * contain params.job. Neither should be counted as a share result. */
    const char *res = strstr(l, "\"result\"");
    if (strstr(l, "\"job\"")) {
        apply_job(l);
        if (res) {
            char sid[128];
            if (json_str(res, "id", sid, sizeof sid))
                snprintf(session, sizeof session, "%s", sid);
        }
    } else if (res && !session[0]) {
        char sid[128];
        if (json_str(res, "id", sid, sizeof sid))
            snprintf(session, sizeof session, "%s", sid);
    }

    /* Only responses to IDs generated by submit_loop are share results. */
    unsigned long long rid = json_u64(l, "id");
    if (rid > 0 && rid <= 0xffffffffULL && take_submit_id((unsigned)rid)) {
        const char *err = strstr(l, "\"error\":");
        if (err && strstr(err, "\"error\":null") == NULL) {
            rejected++;
            fprintf(stderr, "\nPOOL ERROR: %s\n", l);
        } else if (strstr(l, "\"result\":true") ||
                   strstr(l, "\"status\":\"OK\"")) {
            accepted++;
            fprintf(stderr, "\nshare accepted: %llu\n", accepted);
        } else {
            rejected++;
            fprintf(stderr, "\nPOOL RESPONSE: %s\n", l);
        }
    }
}

static int serve(const char *host, int port, const char *wallet, const char *worker) {
    sockfd = connect_tcp(host, port);
    if (sockfd < 0) return 0;

    pthread_mutex_lock(&wlock);
    pending_submit_count = 0;
    pthread_mutex_unlock(&wlock);

    struct timeval tv = {1, 0};
    setsockopt(sockfd, SOL_SOCKET, SO_RCVTIMEO, &tv, sizeof tv);

    char login[1024];
    snprintf(login, sizeof login,
             "{\"id\":%u,\"jsonrpc\":\"2.0\",\"method\":\"login\",\"params\":{\"login\":\"%s\",\"pass\":\"x\",\"agent\":\"nmminer-android/2.0\",\"rigid\":\"%s\"}}",
             msgid++, wallet, worker);
    if (!send_json(login)) goto done;

    pthread_t st;
    pthread_create(&st, 0, submit_loop, 0);

    char buf[16384];
    size_t len = 0;
    unsigned long lastka = 0;

    while (running) {
        char tmp[2048];
        ssize_t n = recv(sockfd, tmp, sizeof tmp, 0);
        if (n > 0) {
            if (len + (size_t)n >= sizeof(buf) - 1) len = 0;
            memcpy(buf + len, tmp, (size_t)n);
            len += (size_t)n;
            buf[len] = 0;

            char *start = buf;
            for (char *p = buf; *p; p++) {
                if (*p == '\n') {
                    *p = 0;
                    handle_line(start);
                    start = p + 1;
                }
            }
            len = (size_t)(buf + len - start);
            memmove(buf, start, len);
            buf[len] = 0;
        } else if (n < 0 && errno != EAGAIN && errno != EWOULDBLOCK) {
            break;
        }

        unsigned long now = (unsigned long)time(NULL);
        if (now - lastka >= 30 && session[0]) {
            char ka[256];
            snprintf(ka, sizeof ka,
                     "{\"id\":%u,\"jsonrpc\":\"2.0\",\"method\":\"keepalived\",\"params\":{\"id\":\"%s\"}}",
                     msgid++, session);
            send_json(ka);
            lastka = now;
        }

        fprintf(stderr, "\rhashes=%llu accepted=%llu rejected=%llu   ",
                (unsigned long long)nm_engine_hashes(), accepted, rejected);
        fflush(stderr);
    }

    pthread_join(st, 0);

done:
    close(sockfd);
    sockfd = -1;
    return 1;
}

int main(int argc, char **argv) {
    signal(SIGINT, stop_now);
    signal(SIGTERM, stop_now);

    const char *w = getenv("CRB_WALLET");
    const char *worker = getenv("CRB_WORKER");
    const char *h = getenv("CRB_POOL_HOST");
    int port = getenv("CRB_POOL_PORT") ? atoi(getenv("CRB_POOL_PORT")) : 3333;
    int threads = getenv("CRB_THREADS") ? atoi(getenv("CRB_THREADS")) : 0;

    if (argc > 1) w = argv[1];
    if (argc > 2) worker = argv[2];
    if (argc > 3) threads = atoi(argv[3]);

    if (!w || !*w) {
        fprintf(stderr, "Usage: cereblix-termux <wallet> [worker] [threads]\n");
        return 2;
    }
    if (!worker || !*worker) worker = "HP1";
    if (!h || !*h) h = "stratum.cereblix.com";
    if (threads <= 0) threads = nm_engine_core_count();
    if (threads > 16) threads = 16;

    fprintf(stderr,
            "Cereblix Termux — APK v2.0 native engine\n"
            "Pool: %s:%d\nWorker: %s\nThreads: %d\n",
            h, port, worker, threads);

    if (!nm_engine_selftest()) {
        fprintf(stderr, "SELFTEST FAILED\n");
        return 3;
    }
    if (nm_engine_start(threads, NM_AFFINITY_ALL) != 0) {
        fprintf(stderr, "engine start failed\n");
        return 4;
    }

    nm_engine_set_active(threads);
    while (running) {
        session[0] = 0;
        if (!serve(h, port, w, worker) && running) sleep(3);
    }

    nm_engine_stop();
    fprintf(stderr, "\nStopped.\n");
    return 0;
}
