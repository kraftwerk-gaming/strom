/*
 * TENOKE SETUP.bin unpacker
 *
 * Extracts the XOR key and descramble constant from the companion SETUP.exe,
 * then unpacks the SETUP.bin archive.
 *
 * Usage: tenoke-unpack <SETUP.exe> <SETUP.bin> [output_dir]
 *
 * Format:
 *   The archive consists of sequential file entries. Each entry has:
 *   1. A 4-byte "scrambled size" marker (gives the size of the metadata record)
 *   2. The metadata record (XOR-encrypted with a 24-byte key)
 *   3. The raw file data (unencrypted)
 *
 * Record structure (after XOR decryption):
 *   +0x00: uint64  file_data_size
 *   +0x2c: uint32  data_offset (absolute offset in file where raw data starts)
 *   +0x44: wchar_t[] filename (null-terminated UTF-16LE)
 *   After filename null: wchar_t[] directory (null-terminated UTF-16LE)
 */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdint.h>
#include <sys/stat.h>
#include <errno.h>

#define XOR_KEY_LEN 24

static uint8_t xor_key[XOR_KEY_LEN];
static uint32_t descramble_sub = 0x315e4; /* default, extracted from exe */

/*
 * Extract the XOR key and descramble constant from SETUP.exe.
 *
 * Searches for the XOR decryption loop pattern:
 *   30 04 13      xor [ebx+edx], al
 *   42            inc edx
 *   83 fe 17      cmp esi, 0x17
 *
 * Then looks backwards for:
 *   8a 86 XX XX XX XX   mov al, [esi + key_va]
 *
 * And searches for the descramble add:
 *   05 XX XX XX XX      add eax, imm32  (where imm32 is negative = -descramble_sub)
 */
static int extract_key_from_exe(const char *exe_path) {
    FILE *f = fopen(exe_path, "rb");
    if (!f) { perror(exe_path); return -1; }

    fseek(f, 0, SEEK_END);
    long exe_size = ftell(f);
    fseek(f, 0, SEEK_SET);

    uint8_t *exe = malloc(exe_size);
    if (!exe) { fclose(f); return -1; }
    if ((long)fread(exe, 1, exe_size, f) != exe_size) { free(exe); fclose(f); return -1; }
    fclose(f);

    /* Verify PE signature */
    if (exe_size < 0x40 || exe[0] != 'M' || exe[1] != 'Z') {
        fprintf(stderr, "Error: %s is not a valid PE executable\n", exe_path);
        free(exe); return -1;
    }

    uint32_t pe_off = *(uint32_t *)(exe + 0x3c);
    if (pe_off + 24 + 96 > (uint32_t)exe_size || memcmp(exe + pe_off, "PE\0\0", 4) != 0) {
        fprintf(stderr, "Error: invalid PE header in %s\n", exe_path);
        free(exe); return -1;
    }

    /* Parse PE sections for VA-to-file-offset conversion */
    uint16_t num_sections = *(uint16_t *)(exe + pe_off + 6);
    uint16_t opt_hdr_size = *(uint16_t *)(exe + pe_off + 20);
    uint32_t image_base = *(uint32_t *)(exe + pe_off + 24 + 28);
    uint32_t sections_off = pe_off + 24 + opt_hdr_size;

    /* Search for XOR loop pattern: 30 04 13 42 83 fe 17 */
    static const uint8_t xor_loop_sig[] = {0x30, 0x04, 0x13, 0x42, 0x83, 0xfe, 0x17};
    long xor_loop_pos = -1;
    for (long i = 0; i < exe_size - (long)sizeof(xor_loop_sig); i++) {
        if (memcmp(exe + i, xor_loop_sig, sizeof(xor_loop_sig)) == 0) {
            xor_loop_pos = i;
            break;
        }
    }

    if (xor_loop_pos < 0) {
        fprintf(stderr, "Error: XOR decryption loop not found in %s\n", exe_path);
        free(exe); return -1;
    }

    /* Look backwards from the XOR loop for "8a 86 XX XX XX XX" (mov al, [esi+imm32])
     * or "8a 84 36 XX XX XX XX" (mov al, [esi+esi+imm32]) variant */
    uint32_t key_va = 0;
    int found_key_ref = 0;
    for (long back = 2; back < 30; back++) {
        long pos = xor_loop_pos - back;
        if (pos < 0) break;
        if (exe[pos] == 0x8a && exe[pos + 1] == 0x86 && pos + 6 <= xor_loop_pos) {
            key_va = *(uint32_t *)(exe + pos + 2);
            found_key_ref = 1;
            break;
        }
        /* Alternative encoding: 8a 84 36 XX XX XX XX */
        if (exe[pos] == 0x8a && exe[pos + 1] == 0x84 && exe[pos + 2] == 0x36
            && pos + 7 <= xor_loop_pos) {
            key_va = *(uint32_t *)(exe + pos + 3);
            found_key_ref = 1;
            break;
        }
    }

    if (!found_key_ref) {
        fprintf(stderr, "Error: could not find key address reference near XOR loop\n");
        free(exe); return -1;
    }

    /* Convert VA to file offset using PE section table */
    uint32_t key_rva = key_va - image_base;
    long key_file_offset = -1;
    for (int i = 0; i < num_sections; i++) {
        uint8_t *sec = exe + sections_off + i * 40;
        uint32_t sec_va = *(uint32_t *)(sec + 12);
        uint32_t sec_rawsize = *(uint32_t *)(sec + 16);
        uint32_t sec_rawptr = *(uint32_t *)(sec + 20);
        if (key_rva >= sec_va && key_rva < sec_va + sec_rawsize) {
            key_file_offset = sec_rawptr + (key_rva - sec_va);
            break;
        }
    }

    if (key_file_offset < 0 || key_file_offset + XOR_KEY_LEN > exe_size) {
        fprintf(stderr, "Error: key VA 0x%08x does not map to a valid file offset\n", key_va);
        free(exe); return -1;
    }

    memcpy(xor_key, exe + key_file_offset, XOR_KEY_LEN);

    /* Search for descramble constant: 05 XX XX XX XX (add eax, imm32)
     * The constant is negative (0xfffcea1c = -0x315e4).
     * Look near the XOR loop (within ~256 bytes before it). */
    int found_descramble = 0;
    for (long i = xor_loop_pos - 256; i < xor_loop_pos && i >= 0; i++) {
        if (exe[i] == 0x05) {
            uint32_t imm = *(uint32_t *)(exe + i + 1);
            /* The constant should be a large negative value (> 0xfff00000) */
            if (imm > 0xfff00000) {
                descramble_sub = (uint32_t)(-(int32_t)imm);
                found_descramble = 1;
                break;
            }
        }
    }

    printf("Extracted from %s:\n", exe_path);
    printf("  XOR key (%d bytes): ", XOR_KEY_LEN);
    for (int i = 0; i < XOR_KEY_LEN; i++) printf("%02x", xor_key[i]);
    printf("\n");
    printf("  Descramble subtract: 0x%x%s\n\n", descramble_sub,
           found_descramble ? "" : " (default, not found in exe)");

    free(exe);
    return 0;
}

static uint32_t descramble_size(const uint8_t raw[4]) {
    uint8_t b0 = ~raw[0];
    uint8_t b1 = raw[1] ^ raw[0];
    uint8_t b2 = raw[2] ^ raw[1];
    uint8_t b3 = raw[3] ^ raw[2];
    uint32_t val = (uint32_t)b0 | ((uint32_t)b1 << 8) |
                   ((uint32_t)b2 << 16) | ((uint32_t)b3 << 24);
    return val - descramble_sub;
}

static void xor_decrypt(uint8_t *data, size_t len) {
    for (size_t i = 0; i < len; i++) {
        data[i] ^= xor_key[i % XOR_KEY_LEN];
    }
}

static int utf16le_to_utf8(const uint8_t *src, size_t src_bytes, char *dst, size_t dst_size) {
    size_t di = 0;
    for (size_t si = 0; si + 1 < src_bytes; si += 2) {
        uint16_t ch = src[si] | ((uint16_t)src[si + 1] << 8);
        if (ch == 0) break;
        if (ch < 0x80) {
            if (di + 1 >= dst_size) break;
            dst[di++] = (char)ch;
        } else if (ch < 0x800) {
            if (di + 2 >= dst_size) break;
            dst[di++] = 0xC0 | (ch >> 6);
            dst[di++] = 0x80 | (ch & 0x3F);
        } else {
            if (di + 3 >= dst_size) break;
            dst[di++] = 0xE0 | (ch >> 12);
            dst[di++] = 0x80 | ((ch >> 6) & 0x3F);
            dst[di++] = 0x80 | (ch & 0x3F);
        }
    }
    dst[di] = '\0';
    return (int)di;
}

static size_t utf16le_strlen_bytes(const uint8_t *data, size_t max_bytes) {
    for (size_t i = 0; i + 1 < max_bytes; i += 2) {
        if (data[i] == 0 && data[i + 1] == 0) return i;
    }
    return max_bytes;
}

static int mkdirp(const char *path) {
    char tmp[4096];
    snprintf(tmp, sizeof(tmp), "%s", path);
    for (char *p = tmp + 1; *p; p++) {
        if (*p == '/') {
            *p = '\0';
            if (mkdir(tmp, 0755) != 0 && errno != EEXIST) return -1;
            *p = '/';
        }
    }
    if (mkdir(tmp, 0755) != 0 && errno != EEXIST) return -1;
    return 0;
}

int main(int argc, char *argv[]) {
    if (argc < 3 || argc > 4) {
        fprintf(stderr, "Usage: %s <SETUP.exe> <SETUP.bin> [output_dir]\n", argv[0]);
        return 1;
    }

    const char *exe_path = argv[1];
    const char *bin_path = argv[2];
    const char *output_dir = argc >= 4 ? argv[3] : "output";

    /* Extract key from the installer EXE */
    if (extract_key_from_exe(exe_path) != 0) {
        return 1;
    }

    FILE *fin = fopen(bin_path, "rb");
    if (!fin) {
        perror(bin_path);
        return 1;
    }

    fseek(fin, 0, SEEK_END);
    int64_t file_size = ftell(fin);
    fseek(fin, 0, SEEK_SET);

    printf("Archive: %s (%lld bytes)\n", bin_path, (long long)file_size);
    printf("Output:  %s\n\n", output_dir);

    int64_t offset = 0;
    int file_count = 0;
    int error_count = 0;

    while (offset < file_size - 4) {
        uint8_t size_raw[4];
        fseek(fin, offset, SEEK_SET);
        if (fread(size_raw, 1, 4, fin) != 4) break;

        uint32_t rec_size = descramble_size(size_raw);
        if (rec_size < 0x46 || rec_size > 100000) break;

        uint8_t *rec = malloc(rec_size);
        if (!rec) { perror("malloc"); break; }
        if (fread(rec, 1, rec_size, fin) != rec_size) { free(rec); break; }
        xor_decrypt(rec, rec_size);

        uint64_t data_size = *(uint64_t *)(rec + 0x00);
        uint32_t data_offset = *(uint32_t *)(rec + 0x2c);

        size_t fname_end = utf16le_strlen_bytes(rec + 0x44, rec_size - 0x44);
        char filename[1024] = {0};
        utf16le_to_utf8(rec + 0x44, fname_end, filename, sizeof(filename));

        size_t dir_start = 0x44 + fname_end + 2;
        char directory[2048] = {0};
        if (dir_start < rec_size) {
            size_t dir_end = utf16le_strlen_bytes(rec + dir_start, rec_size - dir_start);
            utf16le_to_utf8(rec + dir_start, dir_end, directory, sizeof(directory));
        }

        for (char *p = directory; *p; p++) if (*p == '\\') *p = '/';
        for (char *p = filename; *p; p++) if (*p == '\\') *p = '/';

        char out_path[4096];
        if (directory[0]) {
            snprintf(out_path, sizeof(out_path), "%s/%s/%s", output_dir, directory, filename);
        } else {
            snprintf(out_path, sizeof(out_path), "%s/%s", output_dir, filename);
        }

        int is_dir = (filename[0] == '\0') || (data_size == 0 && data_offset == 0);

        if (is_dir) {
            char dir_path[4096];
            if (directory[0]) {
                snprintf(dir_path, sizeof(dir_path), "%s/%s", output_dir, directory);
            } else {
                snprintf(dir_path, sizeof(dir_path), "%s/%s", output_dir, filename);
            }
            mkdirp(dir_path);
        } else {
            file_count++;
            printf("[%3d] %s (%llu bytes)\n", file_count, out_path, (unsigned long long)data_size);

            char dir_part[4096];
            snprintf(dir_part, sizeof(dir_part), "%s", out_path);
            char *last_slash = strrchr(dir_part, '/');
            if (last_slash) {
                *last_slash = '\0';
                mkdirp(dir_part);
            }

            FILE *fout = fopen(out_path, "wb");
            if (!fout) {
                fprintf(stderr, "  ERROR: cannot create %s: %s\n", out_path, strerror(errno));
                error_count++;
            } else {
                fseek(fin, data_offset, SEEK_SET);
                size_t remaining = (size_t)data_size;
                uint8_t buf[65536];
                while (remaining > 0) {
                    size_t chunk = remaining < sizeof(buf) ? remaining : sizeof(buf);
                    size_t rd = fread(buf, 1, chunk, fin);
                    if (rd == 0) break;
                    fwrite(buf, 1, rd, fout);
                    remaining -= rd;
                }
                fclose(fout);
            }
        }

        free(rec);

        int64_t next_offset = (int64_t)data_offset + (int64_t)data_size;
        if (next_offset <= offset || next_offset >= file_size) break;
        offset = next_offset;
    }

    fclose(fin);
    printf("\nDone: %d files extracted", file_count);
    if (error_count) printf(", %d errors", error_count);
    printf("\n");
    return error_count > 0 ? 1 : 0;
}
