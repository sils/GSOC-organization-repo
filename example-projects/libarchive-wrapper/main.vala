int main () {
    try {
        Timer timer = new Timer ();
        var read = new Boxes.ArchiveReader ("testfiles/ubuntu_initrd");

        var write = new Boxes.ArchiveWriter.from_archive_reader (read, "testfiles/ubuntu_initrd~");
        write.insert_file ("testfiles/preseed.cfg", "preseed.cfg");
        write = null;

        timer.stop ();
        stdout.printf ("Time: %f s\n", timer.elapsed (null));

        read = new Boxes.ArchiveReader ("testfiles/ubuntu_initrd~");
        foreach (var file in read.get_file_list ()) {
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

