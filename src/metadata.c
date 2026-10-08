/* SPDX-License-Identifier: MIT */
#include <errno.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

struct table { size_t offset, count; };
struct metadata { unsigned char *bytes; size_t size; };

static int error(const char *message)
{
    fprintf(stderr, "hbr-metadata: %s\n", message);
    return 0;
}

static uint32_t u32(const unsigned char *p)
{
    return (uint32_t)p[0] | ((uint32_t)p[1] << 8) |
           ((uint32_t)p[2] << 16) | ((uint32_t)p[3] << 24);
}

static uint16_t u16(const unsigned char *p)
{
    return (uint16_t)((uint16_t)p[0] | ((uint16_t)p[1] << 8));
}

static void put32(unsigned char *p, uint32_t value)
{
    for (unsigned int i = 0; i < 4; ++i)
        p[i] = (unsigned char)(value >> (i * 8));
}

static int table_at(const struct metadata *m, size_t header, size_t row, struct table *t)
{
    size_t offset = u32(m->bytes + header);
    size_t length = u32(m->bytes + header + 4);
    if (offset < 256 || offset > m->size || length > m->size - offset || length % row)
        return error("invalid or truncated metadata table");
    t->offset = offset;
    t->count = length / row;
    return 1;
}

static int normalize(struct metadata *m, size_t *changed, size_t *total)
{
    if (m->size < 256 || u32(m->bytes) != UINT32_C(0xfab11baf))
        return error("invalid metadata header");
    if (u32(m->bytes + 4) != 31)
        return error("unsupported metadata version; only version 31 is supported");
    struct table strings, methods, types, images;
    if (!table_at(m, 24, 1, &strings) || !table_at(m, 48, 36, &methods) ||
        !table_at(m, 160, 88, &types) || !table_at(m, 168, 40, &images))
        return 0;
    unsigned char *seen = calloc(methods.count ? methods.count : 1, 1);
    if (!seen)
        return error("out of memory");
    size_t owned = 0;
    int valid = 0;
    *changed = 0;
    *total = methods.count;
    for (size_t image = 0; image < images.count; ++image) {
        const unsigned char *definition = m->bytes + images.offset + image * 40;
        size_t name = u32(definition);
        size_t type_start = u32(definition + 8);
        size_t type_count = u32(definition + 12);
        if (name >= strings.count || !memchr(m->bytes + strings.offset + name, 0, strings.count - name) ||
            type_start > types.count || type_count > types.count - type_start) {
            error("invalid assembly name or type range");
            goto done;
        }
        size_t first = methods.count, last = 0, count = 0;
        for (size_t type = type_start; type < type_start + type_count; ++type) {
            const unsigned char *td = m->bytes + types.offset + type * 88;
            size_t start = u32(td + 36);
            size_t length = u16(td + 64);
            if (!length)
                continue;
            if (start > methods.count || length > methods.count - start) {
                error("invalid method range");
                goto done;
            }
            for (size_t method = start; method < start + length; ++method) {
                const unsigned char *md = m->bytes + methods.offset + method * 36;
                if (seen[method] || u32(md + 4) != type || (u32(md + 24) >> 24) != 6) {
                    error("overlapping methods, wrong ownership, or invalid MethodDef token");
                    goto done;
                }
                seen[method] = 1;
                if (method < first) first = method;
                if (method > last) last = method;
                ++count;
                ++owned;
            }
        }
        if (!count)
            continue;
        if (last - first + 1 != count || count > UINT32_C(0x00ffffff)) {
            error("assembly methods are not contiguous");
            goto done;
        }
        for (size_t method = first; method <= last; ++method) {
            unsigned char *token = m->bytes + methods.offset + method * 36 + 24;
            uint32_t value = UINT32_C(0x06000000) | (uint32_t)(method - first + 1);
            if (u32(token) != value) ++*changed;
            put32(token, value);
        }
    }
    if (owned != methods.count) {
        error("some methods are not owned by an assembly");
        goto done;
    }
    valid = 1;
done:
    free(seen);
    return valid;
}

int main(int argc, char **argv)
{
    if (argc == 2 && !strcmp(argv[1], "--help")) {
        puts("Usage: hbr-metadata INPUT OUTPUT\nNormalize metadata v31 MethodDef tokens. OUTPUT must not exist.");
        return 0;
    }
    if (argc != 3) {
        fputs("Usage: hbr-metadata INPUT OUTPUT\n", stderr);
        return 1;
    }
    FILE *input = fopen(argv[1], "rb");
    if (!input) { perror("hbr-metadata: input"); return 1; }
    if (fseek(input, 0, SEEK_END)) { fclose(input); return !error("cannot seek input"); }
    long length = ftell(input);
    if (length < 0 || (unsigned long)length > UINT32_MAX || fseek(input, 0, SEEK_SET)) {
        fclose(input);
        return !error("invalid input size");
    }
    struct metadata m = {NULL, (size_t)length};
    m.bytes = malloc(m.size ? m.size : 1);
    if (!m.bytes) { fclose(input); return !error("out of memory"); }
    size_t read = fread(m.bytes, 1, m.size, input);
    int read_error = ferror(input);
    int close_error = fclose(input);
    if (read != m.size || read_error || close_error) {
        free(m.bytes);
        return !error("cannot read input");
    }
    size_t changed, methods;
    if (!normalize(&m, &changed, &methods)) { free(m.bytes); return 1; }
    FILE *output = fopen(argv[2], "wbx");
    if (!output) { perror("hbr-metadata: output"); free(m.bytes); return 1; }
    size_t written = fwrite(m.bytes, 1, m.size, output);
    int write_error = ferror(output);
    close_error = fclose(output);
    free(m.bytes);
    if (written != m.size || write_error || close_error) {
        remove(argv[2]);
        return !error("cannot write complete output");
    }
    printf("Metadata v31: %zu methods; %zu tokens normalized.\n", methods, changed);
    return 0;
}
