import std.stdio;
import std.algorithm;

immutable uint BYTES_PER_PAGE = 0x200;
immutable uint PAGES_PER_BLOCK = 0x100;

struct MasterBlock {
    uint magic;
    uint field_4;
    uint field_8;
    ushort pages_per_midblock;
    ushort field_E;
    uint max_device_blk;
    uint midblocks_per_block;
    uint field_18;
    uint field_1C;
    uint num_block_maps;
    uint field_24;
    uint field_28;
    uint field_2C;
    ushort max_map_index;
    ushort field_32;
    uint field_34;
    uint num_lba_sectors;
    uint[108] map_blocks;
    ushort lba_shift_a;
    ushort lba_shift_b;
    uint generation;
    uint field_1F4;
    uint field_1F8;
    uint checksum;
}

struct MapBlock {
    ubyte[64][7] page_map;
    ushort[7] block_map;
    ushort field_1CE;
    uint field_1D0;
    uint field_1D4;
    uint field_1D8;
    uint field_1DC;
    uint field_1E0;
    uint field_1E4;
    uint field_1E8;
    uint field_1EC;
    uint generation;
    uint field_1F4;
    ubyte field_1F8;
    ubyte check_flag;
    ushort index;
    uint checksum;
}

struct MapInfo {
    uint block, page;
    MapBlock map;
}

static assert(MapBlock.sizeof == 512);

void findNewestMaster(ref File f, out uint masterBlock, out uint masterPage) {
    f.seek(0);

    uint[BYTES_PER_PAGE / 4] buffer;

    uint maxBlock = 0, maxPage = 0, maxGeneration = 0;
    for (uint block = 0; block < 2; block++) {
        for (uint page = 0; page < PAGES_PER_BLOCK; page++) {
            f.rawRead(buffer);
            if (all!"a == 0xFF"(buffer[0..128])) continue;
            if (sum(buffer[0..127]) != buffer[127]) continue;
            
            if (buffer[0x7C] > maxGeneration) {
                maxBlock = block;
                maxPage = page;
                maxGeneration = buffer[0x7C];
            }
        }
    }

    writefln!"max master gen %#x, block %#x, page %#x"(maxGeneration, maxBlock, maxPage);

    masterBlock = maxBlock;
    masterPage = maxPage;
}

void scanMaps(ref File f, ref MasterBlock master, ref MapInfo[] maps, uint mapIndex) {
	if (master.map_blocks[mapIndex] == 0) return;
	
	writefln!"map %#x at block %#x, offs %#x"(mapIndex, master.map_blocks[mapIndex], master.map_blocks[mapIndex] * PAGES_PER_BLOCK * BYTES_PER_PAGE);
	
    f.seek(master.map_blocks[mapIndex] * PAGES_PER_BLOCK * BYTES_PER_PAGE);

    uint[BYTES_PER_PAGE / 4] buffer;

    uint maxPage = 0, maxGeneration = 0;
    for (uint page = 0; page < PAGES_PER_BLOCK; page++) {
        f.rawRead(buffer);
        if (all!"a == 0xFF"(buffer[0..128])) continue;
        if (sum(buffer[0..127]) != buffer[127]) continue;
        if ((cast(ubyte[])buffer)[0x1F9] > 2) continue;
        if (buffer[0x7C] > maxGeneration) {
            maxPage = page;
            maxGeneration = buffer[0x7C];
        }
        MapBlock* map = cast(MapBlock*)buffer;
        if (map.generation >= maps[map.index].map.generation) {
            maps[map.index].block = master.map_blocks[mapIndex];
            maps[map.index].page = page;
            maps[map.index].map = *map;
        }
    }
}

int main(string[] args) {
    File f = File(args[1], "rb");

    uint masterBlock, masterPage;
    findNewestMaster(f, masterBlock, masterPage);

    f.seek((masterBlock * PAGES_PER_BLOCK + masterPage) * BYTES_PER_PAGE);

    MasterBlock master;
    f.rawRead((&master)[0..1]);
	
	writefln!"partition size (PHY) %d blocks (%d bytes)"(master.max_device_blk, master.max_device_blk * PAGES_PER_BLOCK * BYTES_PER_PAGE);
	writefln!"LBA partition size (LBA) %d sectors (%d bytes)"(master.num_lba_sectors, master.num_lba_sectors * BYTES_PER_PAGE);

    MapInfo[] maps = new MapInfo[master.max_map_index];

    foreach (uint i; 0..master.num_block_maps) {
        scanMaps(f, master, maps, i);
    }

    File wf = File(args[2], "wb");
    ubyte[2048] buffer;
    foreach (ref MapInfo mapInfo; maps) {
        writefln!"map %d: block %#x, page %#x"(mapInfo.map.index, mapInfo.block, mapInfo.page);
        foreach (uint i; 0..7) {
            uint block = mapInfo.map.block_map[i];
            foreach (uint j; 0..64) {
                uint page = mapInfo.map.page_map[i][j] * 4;
                f.seek((block * PAGES_PER_BLOCK + page) * BYTES_PER_PAGE);
                f.rawRead(buffer);
                wf.rawWrite(buffer);
            }
        }
    }

    f.close();
    wf.close();

    return 0;
}
