/* SPDX-License-Identifier: MIT: synthetic metadata only; no game data. */
#define _POSIX_C_SOURCE 200809L
#include <stdint.h>
#include <stdio.h>
#include <string.h>
#include <unistd.h>
#include <sys/prctl.h>

static void put32(unsigned char *p, uint32_t value)
{
    for (unsigned int i = 0; i < 4; ++i) p[i] = (unsigned char)(value >> (i * 8));
}

int main(int argc, char **argv)
{
    if (argc == 2 && !strcmp(argv[1], "--running-game")) {
        if (prctl(PR_SET_NAME, "HeavenBurnsRed.", 0, 0, 0)) return 1;
        sleep(30);
        return 0;
    }
    if (argc != 3) return 1;
    unsigned char data[720] = {0};
    put32(data, UINT32_C(0xfab11baf));
    put32(data + 4, !strcmp(argv[1], "unsupported") ? 32 : 31);
    put32(data + 24, 256); put32(data + 28, 12);
    put32(data + 48, 268); put32(data + 52, 108);
    put32(data + 160, 376); put32(data + 164, 264);
    put32(data + 168, 640); put32(data + 172, 80);
    memcpy(data + 256, "A.dll\0B.dll\0", 12);
    if (!strncmp(argv[1], "updated", 7)) data[256] = 'C';
    /* The first type has no methods; the next two belong to different assemblies. */
    put32(data + 376 + 36, UINT32_MAX);
    put32(data + 376 + 88 + 36, 0); data[376 + 88 + 64] = 2;
    put32(data + 376 + 176 + 36, 2); data[376 + 176 + 64] = 1;
    put32(data + 640 + 8, 0); put32(data + 640 + 12, 2);
    put32(data + 680, 6); put32(data + 680 + 8, 2); put32(data + 680 + 12, 1);
    put32(data + 268 + 4, 1); put32(data + 304 + 4, 1); put32(data + 340 + 4, 2);
    if (strstr(argv[1], "expected")) {
        put32(data + 268 + 24, UINT32_C(0x06000001));
        put32(data + 304 + 24, UINT32_C(0x06000002));
        put32(data + 340 + 24, UINT32_C(0x06000001));
    } else {
        put32(data + 268 + 24, UINT32_C(0x06000041));
        put32(data + 304 + 24, UINT32_C(0x06000021));
        put32(data + 340 + 24, UINT32_C(0x06001234));
    }
    if (!strcmp(argv[1], "overlap")) put32(data + 376 + 176 + 36, 1);
    if (!strcmp(argv[1], "truncated")) put32(data + 52, 1000000);
    FILE *out = fopen(argv[2], "wb");
    if (!out) return 1;
    size_t written = fwrite(data, 1, sizeof(data), out);
    int result = fclose(out);
    return written == sizeof(data) && result == 0 ? 0 : 1;
}
