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
#include <unistd.h>

static volatile sig_atomic_t stop_now = 0;
static void on_signal(int s){ (void)s; stop_now = 1; }

static int tcp_connect(const char *host, int port){
    char service[16]; snprintf(service, sizeof service, "%d", port);
    struct addrinfo hints = {0}, *res = NULL, *p = NULL;
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

static int send_json(int fd, const char *s){
    size_t n = strlen(s), off = 0;
    while (off < n) {
        ssize_t w = send(fd, s + off, n - off, 0);
        if (w <= 0) return -1;
        off += (size_t)w;
    }
    return send(fd, "\n", 1, 0) == 1 ? 0 : -1;
}

static int json_string(const char *j, const char *key, char *out, size_t cap){
    char pat[96]; snprintf(pat, sizeof pat, "\"%s\"", key);
    const char *p = strstr(j, pat); if (!p) return 0;
    p += strlen(pat); while (*p && *p != ':') p++; if (*p != ':') return 0; p++;
    while (*p == ' ' || *p == '\t') p++;
    if (*p != '"') return 0; p++;
    size_t n = 0;
    while (*p && *p != '"' && n + 1 < cap) {
        if (*p == '\\' && p[1]) p++;
        out[n++] = *p++;
    }
    out[n] = 0; return *p == '"';
}

static unsigned long long json_u64(const char *j, const char *key){
    char pat[96]; snprintf(pat, sizeof pat, "\"%s\"", key);
    const char *p = strstr(j, pat); if (!p) return 0;
    p += strlen(pat); while (*p && *p != ':') p++; if (*p != ':') return 0; p++;
    while (*p == ' ' || *p == '\t' || *p == '"') p++;
    return strtoull(p, NULL, 10);
}

static int hex_bytes(const char *s, uint8_t *out, int cap){
    size_t n = strlen(s); if (n & 1) return -1;
    int bytes = (int)(n / 2); if (bytes > cap) return -1;
    for (int i = 0; i < bytes; i++) {
        unsigned v = 0;
        if (sscanf(s + i * 2, "%2x", &v) != 1) return -1;
        out[i] = (uint8_t)v;
    }
    return bytes;
}

static int valid_token(const char *s, int wallet){
    size_t n = strlen(s); if (!n || n > (wallet ? 120u : 32u)) return 0;
    for (size_t i = 0; i < n; i++) {
        char c = s[i];
        if (wallet) { if (!(c >= 'a' && c <= 'z') && !(c >= '0' && c <= '9')) return 0; }
        else if (!(c >= 'A' && c <= 'Z') && !(c >= 'a' && c <= 'z') && !(c >= '0' && c <= '9') && c != '_' && c != '-' && c != '.') return 0;
    }
    return 1;
}

static void print_stats(void){
    static uint64_t last = 0;
    uint64_t now = nm_engine_hashes();
    printf("hashes: %llu (+%llu)\n", (unsigned long long)now, (unsigned long long)(now-last));
    last = now;
    fflush(stdout);
}

int main(int argc, char **argv){
    const char *host = "stratum.cereblix.com";
    int port = 3333, threads = 0;
    const char *wallet = NULL, *worker = "termux";
    for (int i = 1; i < argc; i++) {
        if ((!strcmp(argv[i], "-u") || !strcmp(argv[i], "--wallet")) && i + 1 < argc) wallet = argv[++i];
        else if ((!strcmp(argv[i], "-w") || !strcmp(argv[i], "--worker")) && i + 1 < argc) worker = argv[++i];
        else if (!strcmp(argv[i], "-t") && i + 1 < argc) threads = atoi(argv[++i]);
        else if (!strcmp(argv[i], "-o") && i + 1 < argc) {
            const char *u = argv[++i];
            const char *p = strstr(u, "://"); if (p) u = p + 3;
            static char hostbuf[256]; snprintf(hostbuf, sizeof hostbuf, "%s", u);
            char *colon = strrchr(hostbuf, ':'); if (colon) { *colon = 0; port = atoi(colon + 1); }
            host = hostbuf;
        } else if (!strcmp(argv[i], "-h") || !strcmp(argv[i], "--help")) {
            printf("Cereblix Termux ARM miner\n  -o stratum+tcp://host:port\n  -u crb1...\n  -w worker-name\n  -t threads\n"); return 0;
        }
    }
    if (!wallet || !valid_token(wallet, 1)) { fprintf(stderr, "Invalid/missing CRB wallet.\n"); return 2; }
    if (!valid_token(worker, 0)) { fprintf(stderr, "Invalid worker name. Use A-Z a-z 0-9 _ - .\n"); return 2; }

    signal(SIGINT, on_signal); signal(SIGTERM, on_signal);
    if (!nm_engine_selftest()) { fprintf(stderr, "NeuroMorph self-test FAILED.\n"); return 3; }
    if (threads <= 0) threads = nm_engine_big_core_count();
    if (threads < 1) threads = 1;
    if (threads > 16) threads = 16;
    if (nm_engine_start(threads, NM_AFFINITY_ALL) != 0) { fprintf(stderr, "Unable to start native engine.\n"); return 4; }
    printf("Cereblix Termux ARM\nPool: %s:%d\nWallet: %s\nWorker: %s\nThreads: %d\n", host, port, wallet, worker, threads);

    uint64_t msgid = 1, accepted = 0, rejected = 0;
    while (!stop_now) {
        int fd = tcp_connect(host, port);
        if (fd < 0) { fprintf(stderr, "Pool connection failed; retrying...\n"); sleep(3); continue; }
        struct timeval tv = {1, 0}; setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, sizeof tv);
        printf("Pool connected.\n"); fflush(stdout);
        char login[700];
        snprintf(login, sizeof login, "{\"id\":%llu,\"jsonrpc\":\"2.0\",\"method\":\"login\",\"params\":{\"login\":\"%s\",\"pass\":\"x\",\"agent\":\"nmminer-termux/1.0\",\"rigid\":\"%s\"}}", (unsigned long long)msgid++, wallet, worker);
        if (send_json(fd, login) < 0) { close(fd); sleep(2); continue; }
        char buf[32768]; size_t used = 0; time_t last_keep = time(NULL), last_stats = time(NULL);
        while (!stop_now) {
            char tmp[4096]; ssize_t r = recv(fd, tmp, sizeof tmp, 0);
            if (r > 0) {
                if (used + (size_t)r >= sizeof buf) used = 0;
                memcpy(buf + used, tmp, (size_t)r); used += (size_t)r; buf[used] = 0;
                char *line;
                while ((line = strchr(buf, '\n')) != NULL) {
                    size_t len = (size_t)(line - buf); char msg[8192]; if (len >= sizeof msg) len = sizeof msg - 1;
                    memcpy(msg, buf, len); msg[len] = 0;
                    size_t remain = used - ((size_t)(line - buf) + 1);
                    memmove(buf, line + 1, remain); used = remain; buf[used] = 0;
                    char blob[4096], seed[128], target[128], jobid[256];
                    if (json_string(msg, "blob", blob, sizeof blob) && json_string(msg, "seed_hash", seed, sizeof seed) && json_string(msg, "target", target, sizeof target) && json_string(msg, "job_id", jobid, sizeof jobid)) {
                        uint8_t h[124], s[32], t[32]; int hn=hex_bytes(blob,h,sizeof h), sn=hex_bytes(seed,s,sizeof s), tn=hex_bytes(target,t,sizeof t);
                        if (hn == 124 && sn == 32 && tn > 0 && tn <= 32) {
                            uint8_t ta[32] = {0}; memcpy(ta + 32 - tn, t, tn);
                            nm_engine_set_job(h, s, (uint64_t)json_u64(msg,"height"), ta, jobid);
                            printf("job %s\n", jobid); fflush(stdout);
                        }
                    }
                    if (strstr(msg, "\"status\":\"OK\"") || strstr(msg, "\"status\": \"OK\"")) { accepted++; printf("share accepted (%llu)\n", (unsigned long long)accepted); fflush(stdout); }
                    if (strstr(msg, "\"error\"") && strstr(msg, "submit")) { rejected++; printf("share rejected (%llu)\n", (unsigned long long)rejected); fflush(stdout); }
                }
            } else if (r < 0 && (errno == EAGAIN || errno == EWOULDBLOCK)) {
                /* timeout: normal */
            } else { break; }
            time_t now = time(NULL);
            if (now - last_keep >= 30) {
                char ka[256]; snprintf(ka,sizeof ka,"{\"id\":%llu,\"jsonrpc\":\"2.0\",\"method\":\"keepalived\",\"params\":{\"id\":\"\"}}",(unsigned long long)msgid++);
                send_json(fd, ka); last_keep = now;
            }
            char sid[256], hash[65]; uint64_t nonce;
            while (nm_engine_poll_share(sid,sizeof sid,&nonce,(uint8_t*)hash)) {
                /* Re-fetching the hash bytes into the string buffer is intentional below. */
                uint8_t hb[32]; uint64_t n2; char jid2[256];
                if (!nm_engine_poll_share(jid2,sizeof jid2,&n2,hb)) break;
                (void)sid; (void)hash; nonce=n2; snprintf(sid,sizeof sid,"%s",jid2);
                for(int k=0;k<32;k++) sprintf(hash+2*k,"%02x",hb[k]);
                char nh[17]; for(int k=0;k<8;k++) sprintf(nh+2*k,"%02x",(unsigned)((nonce>>(8*k))&255u));
                char sub[700]; snprintf(sub,sizeof sub,"{\"id\":%llu,\"jsonrpc\":\"2.0\",\"method\":\"submit\",\"params\":{\"id\":\"\",\"job_id\":\"%s\",\"nonce\":\"%s\",\"result\":\"%s\"}}",(unsigned long long)msgid++,sid,nh,hash);
                send_json(fd,sub);
            }
            if (now - last_stats >= 10) { print_stats(); last_stats = now; }
        }
        close(fd);
        if (!stop_now) { fprintf(stderr,"Pool disconnected; reconnecting...\n"); sleep(2); }
    }
    nm_engine_stop(); printf("Stopped.\n"); return 0;
}
