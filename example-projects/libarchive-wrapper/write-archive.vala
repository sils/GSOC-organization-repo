// This file is part of GNOME Boxes. License: LGPLv2+

// A non-threadsafe wrapper for libarchives write archive
public class Util.WriteArchive : GLib.Object {
    public Archive.Write archive;

    public WriteArchive.to_file (string filename,
                                    Archive.Format format,
                                    GLib.List<Archive.Filter> filters)
        throws Util.ArchiveError {
        this.archive = new Archive.Write ();
        if ( this.archive.set_format (format) != Archive.Result.OK )
            throw new Util.ArchiveError.GENERAL_ARCHIVE_ERROR ("Failed setting format (%d) for archive. Message: '%s'.",
                                                               format, this.archive.error_string ());

        foreach (var filter in filters)
            add_filter (filter);
        this.archive.open_filename (filename);
    }

    ~WriteArchive () {
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

