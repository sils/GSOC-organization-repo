// This file is part of GNOME Boxes. License: LGPLv2+

class Util.ReadArchive : GLib.Object {
    // This is the example block size from the libarchive website
    private static const int BLOCK_SIZE = 10240;
    public Archive.Read archive;
    private string filename;

    // TODO supported filters and formats
    public ReadArchive.from_file (string filename)
        throws Util.ArchiveError {
        this.archive = new Archive.Read ();
        // let libarchive handle format and compression
        this.archive.support_format_all ();
        this.archive.support_filter_all ();

        if (this.archive.open_filename (filename, BLOCK_SIZE) != Archive.Result.OK)
            throw new Util.ArchiveError.UNKNOWN_ARCHIVE_TYPE ("Given filename is no supported archive.");
        this.filename = filename;
    }

    ~ReadArchive () {
        this.archive.close ();
    }

    
    // src_dst is a hash table while the key is the relative path in the archive and the val the path to extract to
    public void extract_files (HashTable<string, string> src_dst)
        throws Util.ArchiveError {
        if ( src_dst.size () == 0 )
            return;

        unowned Archive.Entry iterator;
        while ( archive.next_header (out iterator) == Archive.Result.OK ) {
            var dst = src_dst.get (iterator.pathname ());
            if ( dst != null ) {
                // w+, rewrite whole file
                var fd = FileStream.open (dst, "w+");
                archive.read_data_into_fd (fd.fileno ());
                debug ("Extracted file '%s' from archive '%s'.", dst, this.filename);

                src_dst.remove (iterator.pathname ());
            } else {
                archive.read_data_skip ();
            }
        }

        if ( src_dst.size () != 0 ) {
            throw new Util.ArchiveError.FILE_NOT_FOUND ("At least one specified file was not found in the archive.");
        }
        
        this.reset_iterators ();
    }

/* TODO
    // creates a new archive in that you can write but that has the same format, filter and contents as this
    public RawWriteArchive create_writable () throws Util.ArchiveError {
        var format = archive.archive.format ();
        Archive.Entry entry;



        // OLD CODE
        stdout.printf ("Reading one header for format detection...\n"); stdout.flush ();
        if ( this.archive.archive.next_header (out unused) != Archive.Result.OK )
            throw new Util.ArchiveError.GENERAL_ARCHIVE_ERROR ("Unable to read header for format determination.");

        this.filters = new GLib.List<Archive.Filter> ();
        stdout.printf ("There are %d filters.\n", arch.archive.filter_count ()); stdout.flush ();
        for (int i = arch.archive.filter_count () - 1; i > 0; i--) {
            stdout.printf ("Appending filter '%s' (%d).\n", arch.archive.filter_name (i - 1), i-1); stdout.flush ();
            this.filters.append (arch.archive.filter_code (i - 1));
        }
        
        this.reset_iterators ();
    }*/

    // TODO find a better name for this
    private void reset_iterators () throws Util.ArchiveError {
        // reopen archive to reset header iterator - TODO better possibility?
        this.archive.close ();
        this.archive.open_filename (this.filename, BLOCK_SIZE);
    }
}

