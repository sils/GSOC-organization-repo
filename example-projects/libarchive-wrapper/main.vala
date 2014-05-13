int main () {
    try {
        var tst = new Util.RWArchive.from_file ("testfiles/testiso.iso", Util.ArchiveAccess.READ);
        var tbl = new GLib.HashTable<string, string> (str_hash, str_equal);
        tbl.insert ("casper/initrd.lz", "testfiles/initrd");
        tst.extract_files (tbl);
        tst = null;

        Timer timer = new Timer ();
        tst = new Util.RWArchive.from_file ("testfiles/initrd", Util.ArchiveAccess.READWRITE);
        tst.insert_file ("testfiles/preseed.cfg", "preseed.cfg");
        tst = null;
        timer.stop ();
        stdout.printf ("Time: %f s\n", timer.elapsed (null));

        tst = new Util.RWArchive.from_file ("testfiles/initrd~", Util.ArchiveAccess.READ);
        //tst.list_files ();
    } catch (Util.ArchiveError e) {
        stdout.printf ("Exception with message: '%s'.\n", e.message);
        return 1;
    }

    return 0;
}

