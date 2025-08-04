module xsr1app.app;

import xsr1core.base;
import std.stdio;

int main(string[] args) {
    if (args.length != 3) {
        stderr.writeln("usage: xsr1app <input_filename> <output_filename>");
        return 1;
    }
    File f = File(args[1], "rb");
    File wf = File(args[2], "wb");
    parseImage(f, wf);

    return 0;
}
