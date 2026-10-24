// cpuburn: N threads of double-precision matrix multiply for S seconds (same load on macOS and Linux).
// build: cc -O2 -pthread -o cpuburn cpuburn.c
// usage: cpuburn <threads> <seconds>
#include <pthread.h>
#include <stdlib.h>
#include <time.h>

#define N 128
static double secs;

static void *work(void *arg) {
    static __thread double a[N][N], b[N][N], c[N][N];
    for (int i = 0; i < N; i++)
        for (int j = 0; j < N; j++) a[i][j] = b[i][j] = (i + j) * 1e-3;
    time_t end = time(NULL) + (time_t)secs;
    while (time(NULL) < end)
        for (int i = 0; i < N; i++)
            for (int k = 0; k < N; k++)
                for (int j = 0; j < N; j++) c[i][j] += a[i][k] * b[k][j];
    return (void *)(long)c[1][1];
}

int main(int argc, char **argv) {
    int n = argc > 1 ? atoi(argv[1]) : 16;
    secs = argc > 2 ? atof(argv[2]) : 60;
    pthread_t t[256];
    for (int i = 0; i < n && i < 256; i++) pthread_create(&t[i], NULL, work, NULL);
    for (int i = 0; i < n && i < 256; i++) pthread_join(t[i], NULL);
    return 0;
}
