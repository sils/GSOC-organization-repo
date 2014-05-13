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
        while ( this.archive.next_header (out iterator) == Archive.Result.OK ) {
            var dst = src_dst.get (iterator.pathname ());
            if ( dst != null ) {
                // w+, rewrite whole file
                var fd = FileStream.open (dst, "w+");
                if ( this.archive.read_data_into_fd (fd.fileno ()) != Archive.Result.OK )
                    throw new Util.ArchiveError.FILE_OPERATION_ERROR ("Unable to extract file '%s'. Message: '%s'.",
                                                                      dst, this.archive.error_string ());
                debug ("Extracted file '%s' from archive '%s'.", dst, this.filename);

                src_dst.remove (iterator.pathname ());
            } else {
                this.archive.read_data_skip ();
            }
        }

        if ( src_dst.size () != 0 ) {
            throw new Util.ArchiveError.FILE_NOT_FOUND ("At least one specified file was not found in the archive.");
        }
        
        this.reset_iterators ();
    }

    // creates a new archive in that you can write but that has the same format, filter and contents as this
    public WriteArchive create_writable (string filename) throws Util.ArchiveError {
        unowned Archive.Entry iterator;
        if ( archive.next_header (out iterator) != Archive.Result.OK ) {
            // its empty or something went wrong - throw exception
            var msg = "Error creating write archive for archive '%s'. Empty?";
            throw new Util.ArchiveError.GENERAL_ARCHIVE_ERROR (msg, filename);
        }
        var result = new WriteArchive.to_file (this.filename + "~", this.archive.format ());

        do {
            var len = iterator.size ();
            void* buf = GLib.malloc ((size_t) len);
            try {
                this.archive.read_data (buf, (size_t) len);
                result.insert_entry (iterator);
                result.insert_data (buf, len);
            } finally {
                free (buf);
            }
        } while ( archive.next_header (out iterator) == Archive.Result.OK );

        this.reset_iterators ();
        return result;

/*
        // OLD CODE
        stdout.printf ("Reading one header for format detection...\n"); stdout.flush ();
        if ( this.archive.archive.next_header (out unused) != Archive.Result.OK )
            throw new Util.ArchiveError.GENERAL_ARCHIVE_ERROR ("Unable to read header for format determination.");

        this.filters = new GLib.List<Archive.Filter> ();
        stdout.printf ("There are %d filters.\n", arch.archive.filter_count ()); stdout.flush ();
        for (int i = arch.archive.filter_count () - 1; i > 0; i--) {
            stdout.printf ("Appending filter '%s' (%d).\n", arch.archive.filter_name (i - 1), i-1); stdout.flush ();
            this.filters.append (arch.archive.filter_code (i - 1));
        }*/

    }

    // TODO find a better name for this
    private void reset_iterators () throws Util.ArchiveError {
        // reopen archive to reset header iterator - TODO better possibility?
        if ( this.archive.close () != Archive.Result.OK ) {
            var msg = "Unable to reset iterators for archive '%s'. Error on trying to close, message: '%s'.";
            throw new Util.ArchiveError.GENERAL_ARCHIVE_ERROR (msg, this.filename, this.archive.error_string ());
        }
        if ( this.archive.open_filename (this.filename, BLOCK_SIZE) != Archive.Result.OK ) {
            var msg = "Error reopening file for iterator reset for archive '%s'. Message: '%s'.";
            throw new Util.ArchiveError.GENERAL_ARCHIVE_ERROR (msg, this.filename, this.archive.error_string ());
        }
    }
}

