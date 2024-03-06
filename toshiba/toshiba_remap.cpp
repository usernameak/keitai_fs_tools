#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <vector>

// clang-format off
static const uint8_t nand_ecc_precalc_table[] = {
    0x00, 0x55, 0x56, 0x03, 0x59, 0x0c, 0x0f, 0x5a,
    0x5a, 0x0f, 0x0c, 0x59, 0x03, 0x56, 0x55, 0x00,
    0x65, 0x30, 0x33, 0x66, 0x3c, 0x69, 0x6a, 0x3f,
    0x3f, 0x6a, 0x69, 0x3c, 0x66, 0x33, 0x30, 0x65,
    0x66, 0x33, 0x30, 0x65, 0x3f, 0x6a, 0x69, 0x3c,
    0x3c, 0x69, 0x6a, 0x3f, 0x65, 0x30, 0x33, 0x66,
    0x03, 0x56, 0x55, 0x00, 0x5a, 0x0f, 0x0c, 0x59,
    0x59, 0x0c, 0x0f, 0x5a, 0x00, 0x55, 0x56, 0x03,
    0x69, 0x3c, 0x3f, 0x6a, 0x30, 0x65, 0x66, 0x33,
    0x33, 0x66, 0x65, 0x30, 0x6a, 0x3f, 0x3c, 0x69,
    0x0c, 0x59, 0x5a, 0x0f, 0x55, 0x00, 0x03, 0x56,
    0x56, 0x03, 0x00, 0x55, 0x0f, 0x5a, 0x59, 0x0c,
    0x0f, 0x5a, 0x59, 0x0c, 0x56, 0x03, 0x00, 0x55,
    0x55, 0x00, 0x03, 0x56, 0x0c, 0x59, 0x5a, 0x0f,
    0x6a, 0x3f, 0x3c, 0x69, 0x33, 0x66, 0x65, 0x30,
    0x30, 0x65, 0x66, 0x33, 0x69, 0x3c, 0x3f, 0x6a,
    0x6a, 0x3f, 0x3c, 0x69, 0x33, 0x66, 0x65, 0x30,
    0x30, 0x65, 0x66, 0x33, 0x69, 0x3c, 0x3f, 0x6a,
    0x0f, 0x5a, 0x59, 0x0c, 0x56, 0x03, 0x00, 0x55,
    0x55, 0x00, 0x03, 0x56, 0x0c, 0x59, 0x5a, 0x0f,
    0x0c, 0x59, 0x5a, 0x0f, 0x55, 0x00, 0x03, 0x56,
    0x56, 0x03, 0x00, 0x55, 0x0f, 0x5a, 0x59, 0x0c,
    0x69, 0x3c, 0x3f, 0x6a, 0x30, 0x65, 0x66, 0x33,
    0x33, 0x66, 0x65, 0x30, 0x6a, 0x3f, 0x3c, 0x69,
    0x03, 0x56, 0x55, 0x00, 0x5a, 0x0f, 0x0c, 0x59,
    0x59, 0x0c, 0x0f, 0x5a, 0x00, 0x55, 0x56, 0x03,
    0x66, 0x33, 0x30, 0x65, 0x3f, 0x6a, 0x69, 0x3c,
    0x3c, 0x69, 0x6a, 0x3f, 0x65, 0x30, 0x33, 0x66,
    0x65, 0x30, 0x33, 0x66, 0x3c, 0x69, 0x6a, 0x3f,
    0x3f, 0x6a, 0x69, 0x3c, 0x66, 0x33, 0x30, 0x65,
    0x00, 0x55, 0x56, 0x03, 0x59, 0x0c, 0x0f, 0x5a,
    0x5a, 0x0f, 0x0c, 0x59, 0x03, 0x56, 0x55, 0x00,
};
// clang-format on

bool g_w54tMode = false;

uint32_t popCnt(uint32_t value) {
    uint32_t result = 0;
    while (value) {
        result += value & 1;
        value >>= 1;
    }
    return result;
}

void eccDoDecode(uint8_t lp0, uint8_t lp1, uint8_t *output) {
    *output = 0;
    if (lp1 << 31)
        *output = 2;
    if ((lp0 & 1) != 0)
        *output |= 1u;
}

void eccDecode(uint8_t *samples, uint8_t *output) {
    uint8_t cp = 0, lp0 = 0, lp1 = 0;

    for (uint32_t i = 0; i < 2; i++) {
        uint8_t idx = nand_ecc_precalc_table[samples[i]];
        cp ^= idx & 0x3f;
        if (idx & 0x40) {
            lp0 ^= ~i;
            lp1 ^= i;
        }
    }

    eccDoDecode(lp0, lp1, output);
    *output = ~((*output << 6) | cp);
}

int eccCorrect(uint8_t *data, uint8_t *data2, uint8_t mask) {
    uint32_t tmp = *data2 ^ mask;
    if (!tmp || popCnt(tmp) == 1) {
        return 0;
    }
    if ((~((tmp >> 1) ^ tmp) & 0x55) != 0) {
        return -1;
    }
    uint32_t v6 = 0;
    uint32_t v7 = 1;
    do {
        tmp >>= 1;
        uint8_t v8 = tmp & v7;
        v7         = (uint8_t)(2 * v7);
        v6 |= v8;
    } while (v7 < 0x10);
    data[v6 >> 3] ^= 1 << (v6 & 7);
    return 0;
}

int decodeSpare(uint8_t *spare, uint16_t *block_index) {
    uint32_t mergedWord = (spare[13] << 16) + (spare[14] << 8) + spare[15];
    if (!mergedWord || mergedWord == 0xFFFFFF) {
        return 2;
    }

    uint8_t decodeResult;
    eccDecode(spare + 13, &decodeResult);
    if (eccCorrect(spare + 13, spare + 15, decodeResult) != 0) {
        return -1;
    }
    uint16_t val = (spare[13] << 8) + (spare[14]);
    if (!g_w54tMode) {
        if ((val & 0x8000) == 0) {
            return -1;
        }
        *block_index = (val & 0x7FFF) >> 1;
    } else {
        *block_index = val;
    }
    return 0;
}

struct NANDImage {
    FILE *fp;
    uint32_t fullImageSize;
    uint32_t numPages;
    uint32_t numBlocks;
    uint32_t spareOrigin;
};

struct NANDBlockIndex {
    uint16_t imageIndex;
    uint16_t blockIndex;

    NANDBlockIndex()
        : imageIndex(0),
          blockIndex(0xFFFF) {}

    bool operator==(const NANDBlockIndex &o) const {
        return imageIndex == o.imageIndex && blockIndex == o.blockIndex;
    }

    bool operator!=(const NANDBlockIndex &o) const {
        return !operator==(o);
    }
};

int main(int argc, char **argv) {
    unsigned long blockMapSize = 0x3000;

    const char *outFileName = "out.bin";
    std::vector<NANDImage> images;
    for (int i = 1; i < argc; i++) {
        if (strcmp(argv[i], "-in") == 0) {
            NANDImage &image = images.emplace_back();

            image.fp = fopen(argv[++i], "rb");
            fseek(image.fp, 0, SEEK_END);

            image.fullImageSize = static_cast<uint32_t>(ftell(image.fp));

            image.numPages  = image.fullImageSize / 528;
            image.numBlocks = image.numPages / 32;

            image.spareOrigin = image.numPages * 512;

            printf("image %s spare origin: %08x\n", argv[i], image.spareOrigin);
        } else if (strcmp(argv[i], "-out") == 0) {
            outFileName = argv[++i];
        } else if (strcmp(argv[i], "-w54t") == 0) {
            g_w54tMode = true;
        } else if (strcmp(argv[i], "-bmsize") == 0) {
            blockMapSize = strtoul(argv[++i], nullptr, 10);
        }
    }

    auto *nandBlockMap = new NANDBlockIndex[blockMapSize];

    for (int imageIndex = 0; imageIndex < images.size(); imageIndex++) {
        NANDImage *image = &images[imageIndex];

        for (uint32_t i = 0; i < image->numBlocks; i++) {
            fseek(image->fp, image->spareOrigin + i * 0x200, SEEK_SET);
            uint8_t spare[16];
            fread(spare, 1, 16, image->fp);

            fseek(image->fp, image->spareOrigin + i * 0x200 + 0x1F0, SEEK_SET);
            uint8_t spare2[16];
            fread(spare2, 1, 16, image->fp);

            uint16_t block_index, block_index2;
            int status2 = decodeSpare(spare2, &block_index2);
            if (status2 != -4 && status2 != 2) {
                int status = decodeSpare(spare, &block_index);
                if (status != -4 && status != 2) {
                    if (status == -1 && status2 == -1) {
                        continue;
                    }
                    if (block_index != block_index2) {
                        printf("%04x: block index mismatch\n", i);
                        return 1;
                    }
                    if (block_index >= blockMapSize) {
                        printf("%04x: block index %04x OUT OF BOUNDS\n", i, block_index);
                        continue;
                    }
                    NANDBlockIndex old_block = nandBlockMap[block_index];
                    if (old_block.blockIndex == 0xFFFF) {
                        nandBlockMap[block_index].imageIndex = imageIndex;
                        nandBlockMap[block_index].blockIndex = i;

                        // printf("DETECTED %04x %04x\n", i, block_index);
                    } else {
                        printf("%04x: duplicate block\n", i);
                        return 1;
                    }
                }
            }
        }
    }

    FILE *wfp = fopen(outFileName, "wb");

    for (uint32_t i = 0; i < blockMapSize; i++) {
        // printf("%04x: image %02x, block %04x\n", i, nandBlockMap[i].imageIndex, nandBlockMap[i].blockIndex);

        const NANDBlockIndex &idx = nandBlockMap[i];

        uint8_t buf[16384];
        if (nandBlockMap[i].blockIndex != 0xFFFF) {
            fseek(images[idx.imageIndex].fp, nandBlockMap[i].blockIndex * 16384, SEEK_SET);
            fread(buf, 1, 16384, images[idx.imageIndex].fp);
        } else {
            memset(buf, 0xFF, 16384);
        }
        fwrite(buf, 1, 16384, wfp);
    }

    fclose(wfp);

    printf("DUMPING SUCCESSFUL\n");

    return 0;
}