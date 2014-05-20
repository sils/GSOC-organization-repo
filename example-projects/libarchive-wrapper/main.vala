int main () {
    try {
        Timer timer = new Timer ();
        var tst = new Util.Archivist.from_file ("testfiles/ubuntu_initrd", Util.ArchiveAccess.READWRITE);
        tst.insert_file ("testfiles/preseed.cfg", "preseed.cfg");
        tst = null;
        timer.stop ();
        stdout.printf ("Time: %f s\n", timer.elapsed (null));

        tst = new Util.Archivist.from_file ("testfiles/ubuntu_initrd~", Util.ArchiveAccess.READ);
        foreach (var file in tst.get_file_list ()) {
            if (file == "preseed.cfg") {
                stdout.printf ("Preseed.cfg is in the new archive.\n");
                break;
            }
        }
    } catch (Util.ArchiveError e) {
        stdout.printf ("Exception with message: '%s'.\n", e.message);
        return 1;
    }

    return 0;
}

