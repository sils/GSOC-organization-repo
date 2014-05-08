int main () {
    stdout.printf ("Reading archive...");
    var arch = new Util.Archivist ("testfiles/initrd.lz", Util.ArchiveAccess.READWRITE);

    var tbl = new GLib.HashTable<string, string> (str_hash, str_equal);
    tbl.insert ("initrd", "testfiles/extracted");

    arch.extract_files.begin (tbl);
    yield;

    tbl = new GLib.HashTable<string, string> (str_hash, str_equal);
    tbl.insert ("testfiles/preseed.cfg", "preseed.cfg");
    arch.insert_files.begin (tbl);
    yield;

    return 0;
}

