// smcdump: dump all Apple SMC keys on macOS (read-only), same TSV idea as tools/smc-dump.py.
// build: clang -O2 -framework IOKit -o smcdump smcdump.c
// usage: smcdump <out.tsv>                 one dump
//        smcdump -loop <dir> <label> <n>   dumps for n seconds, about one per second
//        smcdump -plimit                   print the SMC power limit record (cmd 11)
#include <IOKit/IOKitLib.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <unistd.h>

typedef struct { char major, minor, build, reserved; UInt16 release; } vers_t;
typedef struct { UInt16 version, length; UInt32 cpuPLimit, gpuPLimit, memPLimit; } plimit_t;
typedef struct { UInt32 dataSize, dataType; char dataAttributes; } keyinfo_t;
typedef struct {
    UInt32 key; vers_t vers; plimit_t pLimitData; keyinfo_t keyInfo;
    char result, status, data8; UInt32 data32; unsigned char bytes[32];
} smc_t;

enum { READ_BYTES = 5, READ_INDEX = 8, READ_KEYINFO = 9, READ_PLIMIT = 11 };
static io_connect_t conn;

static int call(smc_t *in, smc_t *out) {
    size_t sz = sizeof(smc_t);
    return IOConnectCallStructMethod(conn, 2, in, sizeof(smc_t), out, &sz) == kIOReturnSuccess
           && out->result == 0 ? 0 : -1;
}
static void k2s(UInt32 k, char *s) { for (int i = 0; i < 4; i++) s[i] = k >> (24 - 8 * i); s[4] = 0; }
static UInt32 s2k(const char *s) { return (UInt32)s[0] << 24 | s[1] << 16 | s[2] << 8 | s[3]; }

static int read_key(UInt32 key, char *type, unsigned char *buf, UInt32 *len) {
    smc_t in = {0}, out = {0};
    in.key = key; in.data8 = READ_KEYINFO;
    if (call(&in, &out)) return -1;
    *len = out.keyInfo.dataSize; k2s(out.keyInfo.dataType, type);
    in.keyInfo.dataSize = *len; in.data8 = READ_BYTES;
    memset(&out, 0, sizeof out);
    if (call(&in, &out)) return -2;
    memcpy(buf, out.bytes, *len > 32 ? 32 : *len);
    return 0;
}

static void decode(const char *t, unsigned char *b, UInt32 n, char *o) {
    o[0] = 0;
    if (!strcmp(t, "flt ") && n == 4) { float f; memcpy(&f, b, 4); sprintf(o, "%.4g", f); }
    else if (!strcmp(t, "ui8 ") || !strcmp(t, "flag")) sprintf(o, "%u", b[0]);
    else if (!strcmp(t, "si8 ")) sprintf(o, "%d", (signed char)b[0]);
    else if (!strcmp(t, "sp78") && n == 2) sprintf(o, "%.3g", (short)(b[0] << 8 | b[1]) / 256.0);
    else if (!strcmp(t, "fpe2") && n == 2) sprintf(o, "%.4g", (b[0] << 8 | b[1]) / 4.0);
    else if (!strcmp(t, "si16") && n == 2) sprintf(o, "%d", (short)(b[0] << 8 | b[1]));
}

static int dump(const char *path) {
    FILE *f = fopen(path, "w");
    if (!f) return -1;
    unsigned char buf[32]; char type[5], key[5], dec[64]; UInt32 len, count = 0;
    if (!read_key(s2k("#KEY"), type, buf, &len)) count = buf[0] << 24 | buf[1] << 16 | buf[2] << 8 | buf[3];
    fprintf(f, "idx\tkey\ttype\tlen\thex\tdecoded\n");
    for (UInt32 i = 0; i < count; i++) {
        smc_t in = {0}, out = {0};
        in.data8 = READ_INDEX; in.data32 = i;
        if (call(&in, &out)) continue;
        k2s(out.key, key);
        int r = read_key(out.key, type, buf, &len);
        fprintf(f, "%u\t%s\t%s\t%d\t", i, key, r == -1 ? "????" : type, r ? -1 : (int)len);
        if (r) { fprintf(f, "ERR\tERR\n"); continue; }
        for (UInt32 j = 0; j < len && j < 32; j++) fprintf(f, "%02x", buf[j]);
        decode(type, buf, len, dec);
        fprintf(f, "\t%s\n", dec);
    }
    fclose(f);
    return 0;
}

int main(int argc, char **argv) {
    io_service_t svc = IOServiceGetMatchingService(MACH_PORT_NULL,IOServiceMatching("AppleSMC"));
    if (!svc || IOServiceOpen(svc, mach_task_self(), 0, &conn)) { fprintf(stderr, "cannot open AppleSMC\n"); return 1; }
    if (argc == 2 && !strcmp(argv[1], "-plimit")) {
        smc_t in = {0}, out = {0}; in.data8 = READ_PLIMIT;
        int r = call(&in, &out);
        printf("plimit r=%d ver=%u len=%u cpu=%u gpu=%u mem=%u\n", r, out.pLimitData.version,
               out.pLimitData.length, out.pLimitData.cpuPLimit, out.pLimitData.gpuPLimit, out.pLimitData.memPLimit);
        return 0;
    }
    if (argc == 5 && !strcmp(argv[1], "-loop")) {
        time_t stop = time(NULL) + atoi(argv[4]); char p[1024], ts[32];
        for (int i = 0; time(NULL) < stop; i++) {
            time_t t = time(NULL); strftime(ts, sizeof ts, "%Y%m%d-%H%M%S", localtime(&t));
            snprintf(p, sizeof p, "%s/%s-%s-%04d.tsv", argv[2], ts, argv[3], i);
            dump(p); usleep(1000000);
        }
        return 0;
    }
    if (argc == 2) return dump(argv[1]) ? 1 : 0;
    fprintf(stderr, "usage: smcdump <out.tsv> | -loop <dir> <label> <n> | -plimit\n");
    return 1;
}
