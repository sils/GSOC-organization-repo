// This file is part of GNOME Boxes. License: LGPLv2+

// A non-threadsafe wrapper for libarchives write archive
public class Util.WriteArchive : GLib.Object {
    public Archive.Write archive;

    public WriteArchive.to_file (string filename,
                                    Archive.Format format,
                                    GLib.List<Archive.Filter>? filters = null)
        throws Util.ArchiveError {
        this.archive = new Archive.Write ();
        if ( this.archive.set_format (format) != Archive.Result.OK )
            throw new Util.ArchiveError.GENERAL_ARCHIVE_ERROR ("Failed setting format (%d) for archive. Message: '%s'.",
                                                               format, this.archive.error_string ());

        if ( filters != null )
            this.add_filters (filters);
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
            if ( readlen != len )
                throw new Util.ArchiveError.FILE_OPERATION_ERROR ("Failed reading file '%s'.", src);
            this.insert_entry (entry);
            this.insert_data (buf, len);
        } catch ( GLib.Error e ) {
            throw new Util.ArchiveError.FILE_OPERATION_ERROR ("Error reading from source file '%s'.", src);
        } finally {
            free (buf);
        }
    }

    public void add_filters (GLib.List<Archive.Filter> filters) throws Util.ArchiveError {
        foreach ( var filter in filters ) {
            if ( this.archive.add_filter (filter) != Archive.Result.OK )
                throw new Util.ArchiveError.GENERAL_ARCHIVE_ERROR ("Failed setting filter. Message: '%s'.",
                                                                   this.archive.error_string ());
        }
    }

    public void insert_entry (Archive.Entry entry) throws Util.ArchiveError {
        // write header
        if ( this.archive.write_header (entry) != Archive.Result.OK )
            throw new Util.ArchiveError.FILE_OPERATION_ERROR ("Failed writing header to archive. Message: '%s'.",
                                                              this.archive.error_string ());
    }

    public void insert_data (void* data, int64 len) throws Util.ArchiveError {
        // write data
        if ( this.archive.write_data (data, (size_t) len) != len )
            throw new Util.ArchiveError.FILE_OPERATION_ERROR ("Failed writing data to archive. Message: '%s'.",
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

