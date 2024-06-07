module xsr1app.app;

import xsr1core.base;
import std.stdio;

int main(string[] args) {
    File f = File(args[1], "rb");
    File wf = File(args[2], "wb");
    parseImage(f, wf);

    return 0;
}
