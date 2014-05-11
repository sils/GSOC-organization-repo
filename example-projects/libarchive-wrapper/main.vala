int main () {
    try {
        stdout.printf ("Extracting initrd.lz out of iso...\n"); stdout.flush ();
        var tbl = new GLib.HashTable<string, string> (str_hash, str_equal);

        var extract = new Util.Archivist ("testfiles/testiso.iso", Util.ArchiveAccess.READ);
        tbl.insert ("initrd.lz", "testfiles/initrd");
        tbl.insert ("md5sum.txt", "testfiles/md5sum.txt");
        extract.extract_files.begin (tbl);
        yield;

        stdout.printf ("Constructing second archivist...\n"); stdout.flush ();
        var arch = new Util.Archivist ("testfiles/initrd", Util.ArchiveAccess.READWRITE);
        tbl = new GLib.HashTable<string, string> (str_hash, str_equal);
        tbl.insert ("testfiles/preseed.cfg", "preseednew.cfg");
        arch.insert_files.begin (tbl, false);
        yield;

        arch = null;
    } catch (Util.ArchiveError e) {
        stdout.printf ("Exception with message: '%s'.\n", e.message);
        return 1;
    }

    return 0;
}

