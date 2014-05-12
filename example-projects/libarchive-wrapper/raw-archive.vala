// This file is part of GNOME Boxes. License: LGPLv2+

using Archive;

public errordomain Util.ArchiveError {
    FILE_NOT_FOUND,
    FILE_OPERATION_ERROR,
    UNKNOWN_ARCHIVE_TYPE,
    GENERAL_ARCHIVE_ERROR,
    UNKNOWN
}

// A non-threadsafe wrapper for libarchives read archive
public class Util.RawReadArchive : GLib.Object {
    // This is the example block size from the libarchive website
    private static const int BLOCK_SIZE = 10240;
    public Archive.Read archive { get { return archive; } set { archive = value; } }
    private string filename;

    // TODO supported filters and formats
    public RawReadArchive (string filename)
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
/*
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

// A non-threadsafe wrapper for libarchives write archive
public class Util.RawWriteArchive : GLib.Object {
    public Archive.Write archive { get { return archive; } set { archive = value; } }

    public RawWriteArchive.to_file (string filename,
                                    Archive.Format format,
                                    GLib.List<Archive.Filter> filters)
        throws Util.ArchiveError {
        stdout.printf ("Opening RawWriteArchive.\n"); stdout.flush ();
        this.archive = new Archive.Write ();
        if ( this.archive.set_format (format) != Archive.Result.OK )
            throw new Util.ArchiveError.GENERAL_ARCHIVE_ERROR ("Failed setting format (%d) for archive. Message: '%s'.",
                                                               format, this.archive.error_string ());

        foreach (var filter in filters)
            add_filter (filter);
        this.archive.open_filename (filename);
    }

    ~RawWriteArchive () {
        stdout.printf ("Closing RawWriteArchive.\n"); stdout.flush ();
        this.archive.close ();
    }

    public void insert_files (HashTable<string, string> src_dst) throws Util.ArchiveError {
        foreach ( var src in src_dst.get_keys () )
            this.insert_file (src, src_dst.get (src));
    }

    // while dst is the destination relative to archive root
    public void insert_file (string src, string dst) throws Util.ArchiveError {
        var entry = get_entry_for_file (src, dst);
        var len = entry.size ();
        if ( len > 1024*1024*1024 )
            warning ("Be aware that this library is not optimized for use with big files.");
        void* buf = GLib.malloc ((size_t) len);
        try {
            // get file info, read data into memory
            var file = GLib.File.new_for_path (src);
            var stream = file.read ();
            var readlen = stream.read ((uint8[]) buf);
            
            
            // write header
            if ( this.archive.write_header (entry) != Archive.Result.OK )
                throw new Util.ArchiveError.FILE_OPERATION_ERROR ("Failed writing header '%s' to archive. ('%s')",
                                                                  src, dst);
            // write data
            if ( readlen != len )
                throw new Util.ArchiveError.FILE_OPERATION_ERROR ("Failed reading file '%s'.", src);
            if ( this.archive.write_data (buf, readlen) != readlen )
                throw new Util.ArchiveError.FILE_OPERATION_ERROR ("Failed writing header '%s' to archive. ('%s')",
                                                                  src, dst);
        } catch ( GLib.Error e ) {
            throw new Util.ArchiveError.FILE_OPERATION_ERROR ("Error reading from source file '%s'.", src);
        } finally {
            free (buf);
        }
    }

    private void add_filter (Archive.Filter compression)
        throws Util.ArchiveError
        requires ( compression == Archive.Filter.NONE     ||
                   compression == Archive.Filter.GZIP     ||
                   compression == Archive.Filter.BZIP2    ||
                   compression == Archive.Filter.COMPRESS ||
                   compression == Archive.Filter.LZMA     ||
                   compression == Archive.Filter.LZIP     ||
                   compression == Archive.Filter.XZ ) {
        Archive.Result err;
        stdout.printf ("Adding filter %d.\n", compression); stdout.flush ();
        switch ( compression ) {
        case Archive.Filter.NONE:
            err = Archive.Result.OK;
            break;
        case Archive.Filter.GZIP:
            err = this.archive.add_filter_gzip ();
            break;
        case Archive.Filter.BZIP2:
            err = this.archive.add_filter_bzip2 ();
            break;
        case Archive.Filter.COMPRESS:
            err = this.archive.add_filter_compress ();
            break;
        case Archive.Filter.LZMA:
            err = this.archive.add_filter_lzma ();
            break;
        case Archive.Filter.LZIP:
            err = this.archive.add_filter_lzip ();
            break;
        case Archive.Filter.XZ:
            err = this.archive.add_filter_xz ();
            break;
        default:
            err = Archive.Result.FAILED;
            break;
        }

        if ( err != Archive.Result.OK )
            throw new Util.ArchiveError.UNKNOWN ("Failed setting archive compression (Message: %s).",
                                                 this.archive.error_string ());
    }

    private Archive.Entry get_entry_for_file (string filename, string dest_name)
        requires ( filename  != "" )
        requires ( dest_name != "" ) {
        Posix.Stat st;
        var result = new Archive.Entry ();

        Posix.stat (filename, out st);
        result.copy_stat (st);
        result.set_pathname (dest_name);

        return result;
    }
}

