module xsr1core.cinterface;

version (XSR1_CInterface) {
    import std.string;
    import xsr1core.base;
    import std.stdio;
    import core.runtime;

    private immutable(char)* errorMessage;
    private immutable(char)* errorStackTrace;
    private immutable(char)* errorFile;
    private int errorLine;

    private nothrow void reportError(Exception e) {
        errorMessage = e.msg.toStringz();
        try {
            errorStackTrace = e.info.toString().toStringz();
        } catch(Exception ee) {
            errorStackTrace = "error caught getting stack trace";
        }
        errorFile = e.file.toStringz();
        errorLine = cast(int)e.line;
    }

    /++ 
    + Returns the last error
    + Params:
    +   ppErrorMessage = pointer to error message string pointer, thread-local
    +   ppErrorStackTrace = pointer to error stack trace string pointer, thread-local
    +   ppErrorFile = pointer to error file string pointer, thread-local
    +   ppErrorLine = pointer to error line number pointer, thread-local
    +/
    extern(C) export nothrow void xsr1coreGetLastError(
        immutable(char)** ppErrorMessage,
        immutable(char)** ppErrorStackTrace,
        immutable(char)** ppErrorFile,
        int* ppErrorLine)
    {
        *ppErrorMessage = errorMessage;
        *ppErrorStackTrace = errorStackTrace;
        *ppErrorFile = errorFile;
        *ppErrorLine = errorLine;
    }

    /++ 
    + Processes an XSR1 image
    + Params:
    +   inputFileName = input disk image file name
    +   outputFileName = output disk image file name
    + Returns: 
    + zero on success, non-zero on failure
    +/
    extern(C) export nothrow int xsr1coreParseImage(immutable(char)* inputFileName, immutable(char)* outputFileName) {
        try {
            File f = File(fromStringz(inputFileName), "rb");
            File wf = File(fromStringz(outputFileName), "wb");
            parseImage(f, wf);
        } catch (Exception e) {
            reportError(e);
            return 1;
        }

        return 0;
    }

    extern(C) export void xsr1coreInit() {
        Runtime.initialize();
    }

    extern(C) export void xsr1coreTerm() {
        Runtime.terminate();
    }
}
