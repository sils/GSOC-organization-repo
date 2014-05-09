int main () {
    stdout.printf ("\n\n\nReading archive...\n");
    try {
        var tbl = new GLib.HashTable<string, string> (str_hash, str_equal);

        var extract = new Util.Archivist ("testfiles/testiso.iso", Util.ArchiveAccess.READ);
        tbl.insert ("initrd.lz", "testfiles/initrd");
        tbl.insert ("md5sum.txt", "testfiles/md5sum.txt");
        extract.extract_files.begin (tbl);
        yield;

        var arch = new Util.Archivist ("testfiles/initrd.bz2", Util.ArchiveAccess.WRITE);
        tbl = new GLib.HashTable<string, string> (str_hash, str_equal);
        tbl.insert ("testfiles/preseed.cfg", "preseednew.cfg");
        arch.insert_files.begin (tbl, false);
        yield;

        //arch.flush.begin ();
        //yield;
    } catch (Util.ArchiveError e) {
        stdout.printf ("Exception with message: '%s'.\n", e.message);
        return 1;
    }

    return 0;
}

