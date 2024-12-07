module source.main;

import std.stdio;
import std.getopt;
import std.conv;
import std.algorithm.iteration;
import std.algorithm.sorting;
import std.csv;
import bytesize;

immutable uint BLOCKS_PER_TABLE = 166;

struct RemappingTableInfo {
    uint physicalBlockIndex;
    uint generation;
    uint lba;
}

struct RemappingTable {
    uint physicalBlockIndex = uint.max;
    uint currentGeneration = uint.max;
    uint[] availableGenerations;
    uint[BLOCKS_PER_TABLE] remappedBlocks;
}

class RemappingManager {
    File f;
    RemappingTable[] remappingTables;
    uint[] forcedGenerations;
    RemappingTableInfo[][] phyHistory;
    uint lba0Phy;
    uint blockOffset;

    this(ref File f) {
        this.f = f;
    }

    void close() {
        f.close();
    }

    static bool isRemappingTable(ref ubyte[512] buffer) {
        return buffer[0x0] == 0x04 && buffer[0x1] == 0x19 && buffer[0xA] == 0x55 && buffer[0xB] == 0xAA;
    }

    void scanForRemappingTables() {
        ubyte[512] buffer;
        uint idx = 0;

        phyHistory.length = f.size() / 512;

        f.seek(0, SEEK_SET);
        while (f.rawRead(buffer).length == buffer.length) {
            if (isRemappingTable(buffer)) {
                uint blockGen = (buffer[0x4] << 24) |
                                (buffer[0x5] << 16) |
                                (buffer[0x6] << 8 ) |
                                (buffer[0x7] << 0 );

                uint blockIndex = (buffer[0x8] << 8) | buffer[0x9];

                if (blockIndex >= remappingTables.length) {
                    remappingTables.length = blockIndex + 1;
                }

                RemappingTable* tab = &remappingTables[blockIndex];
                tab.availableGenerations ~= blockGen;
                if (
                    (blockGen <= tab.currentGeneration) && 
                    (!forcedGenerations || blockGen >= forcedGenerations[blockIndex])
                ) {
                    tab.currentGeneration = blockGen;
                    tab.physicalBlockIndex = idx;
                }
            } else if (buffer[0x20..0x3B] == "Fugue FAT File System(NAND)") {
                lba0Phy = idx;
            }
            idx++;
        }
    
        foreach (i, ref tab; remappingTables) {
            if (tab.physicalBlockIndex == uint.max) continue;
            tab.availableGenerations.sort();
            f.seek(tab.physicalBlockIndex * 512, SEEK_SET);
            f.rawRead(buffer);
            foreach (j, ref blockIndex; tab.remappedBlocks) {
                blockIndex =    (buffer[0xE + j * 3 + 0] << 16) |
                                (buffer[0xE + j * 3 + 1] << 8 ) |
                                (buffer[0xE + j * 3 + 2] << 0 );
            }
        }

        writefln!"LBA 0 PHY: 0x%08x"(lba0Phy);

        blockOffset = lba0Phy == 0 ? 0 : lba0Phy - findBlock(0);
        writefln!"Filesystem start in 512-byte blocks: 0x%08x"(blockOffset);

        uint maxBlock = 0;
    
        f.seek(0, SEEK_SET);
        while (f.rawRead(buffer).length == buffer.length) {
            if (isRemappingTable(buffer)) {
                uint blockGen = (buffer[0x4] << 24) |
                                (buffer[0x5] << 16) |
                                (buffer[0x6] << 8 ) |
                                (buffer[0x7] << 0 );
                uint blockIndex = (buffer[0x8] << 8) | buffer[0x9];
                
                foreach (j; 0..BLOCKS_PER_TABLE) {
                    RemappingTableInfo info;
                    info.physicalBlockIndex = idx;
                    info.generation = blockGen;
                    info.lba = blockIndex * BLOCKS_PER_TABLE + j;
                    uint phyBlockIndex = (buffer[0xE + j * 3 + 0] << 16) |
                                         (buffer[0xE + j * 3 + 1] << 8 ) |
                                         (buffer[0xE + j * 3 + 2] << 0 );
                    if (phyBlockIndex == 0xFFFFFF) continue;
                    uint phyBlockIndexRaw = phyBlockIndex + blockOffset;
                    if (phyBlockIndexRaw >= phyHistory.length) {
                        if (phyBlockIndexRaw > maxBlock) {
                            maxBlock = phyBlockIndexRaw + 1;
                        }
                        // writefln!"Missing physical block 0x%08x"(phyBlockIndexRaw);
                        continue;
                    }
                    phyHistory[phyBlockIndexRaw] ~= info;
                }
            }
            idx++;
        }
        writefln!"Done scanning remapping tables: max block 0x%08x, expected max block 0x%08x"(
            maxBlock,
            phyHistory.length
        );
    }

    void dumpPhyHistory(string dstFilename) {
        File wf = File(dstFilename, "w");
        foreach (i, ref arr; phyHistory) {
            if (arr.length == 0) continue;
            wf.writefln!"0x%08x:"(i);
            foreach (j, ref info; arr) {
                wf.writefln!"    0x%08x gen 0x%08x lba 0x%08x"(info.physicalBlockIndex, info.generation, info.lba);
            }
        }
        
    }

    void dumpBlockGenerations(string dstFilename) {
        File wf = File(dstFilename, "w");
        wf.writeln("remap_table_index,generation,available_generations");
        foreach (i, ref tab; remappingTables) {
            wf.writef!"%08x,%08x,"(i, tab.currentGeneration);
            
            foreach (gen; tab.availableGenerations) {
                wf.writef!"%08x "(gen);
            }
            wf.writeln;
        }
    }

    void loadForcedGenerationInfo(string csvFilename) {
        File cf = File(csvFilename, "r");
        forcedGenerations = [];
        foreach (record; csvReader!(string[string])(cf.byLine.joiner("\n"), null)) {
            uint remapTableIndex = record["remap_table_index"].to!uint(16);
            uint generation = record["generation"].to!uint(16);
            if (forcedGenerations.length <= remapTableIndex) {
                forcedGenerations.length = remapTableIndex + 1;
            }
            forcedGenerations[remapTableIndex] = generation;
        }
    }

    void printDump() const {
        foreach (ref tab; remappingTables) {
            writefln!"0x%08x gen 0x%08x"(tab.physicalBlockIndex, tab.currentGeneration);
            foreach (i, blockIndex; tab.remappedBlocks) {
                writefln!"    %06x %06x"(i, blockIndex);
            }
        }
    }

    uint findBlock(uint blockIndex) const {
        return remappingTables[blockIndex / BLOCKS_PER_TABLE]
                    .remappedBlocks[blockIndex % BLOCKS_PER_TABLE];
    }

    uint numBlocks() const {
        return cast(uint)(remappingTables.length * BLOCKS_PER_TABLE);
    }
}

int main(string[] args) {
    string sourceFile;
    string destinationFile;
    string genInfoLoadFile;
    string genInfoDumpFile;
    string phyHistDumpFile;
    bool verbose = false;

    auto helpInformation = getopt(
        args,

        std.getopt.config.required,
        "src|s", "The source filesystem image", &sourceFile,
        // std.getopt.config.required,
        "dst|d", "The destination filesystem image", &destinationFile,
        "dump-gen|g", "File to dump generation info into", &genInfoDumpFile,
        "load-gen|l", "File to load generation info from", &genInfoLoadFile,
        "dump-phy-history|p", "File to dump PHY history", &phyHistDumpFile,

        "verbose|v", "Verbose log messages", &verbose
    );

    if (helpInformation.helpWanted) {
        defaultGetoptPrinter("FSRecovery - tool to dump Fugue FAT NAND filesystem", helpInformation.options);
        return 1;
    }

    File f = File(sourceFile, "rb");
    
    RemappingManager remappingManager = new RemappingManager(f);

    if (genInfoLoadFile) {
        writeln("Loading forced generation info!");
        remappingManager.loadForcedGenerationInfo(genInfoLoadFile);
    }

    ubyte[512] buffer;
    remappingManager.scanForRemappingTables();

    if (phyHistDumpFile) {
        remappingManager.dumpPhyHistory(phyHistDumpFile);
    }

    if (verbose) {
        remappingManager.printDump();
    }

    if (destinationFile) {
        File wf = File(destinationFile, "wb");
        foreach (i; 0..remappingManager.numBlocks) {
            f.seek((remappingManager.findBlock(i) + remappingManager.blockOffset) * 512, SEEK_SET);
            f.rawRead(buffer);
            wf.rawWrite(buffer);
        }
        wf.close();

        writefln!"Dumped %s of data"((remappingManager.numBlocks * 512).bytes);
    }

    if (genInfoDumpFile) {
        remappingManager.dumpBlockGenerations(genInfoDumpFile);
    }

    return 0;
}
