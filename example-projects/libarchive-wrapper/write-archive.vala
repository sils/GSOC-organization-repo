// This file is part of GNOME Boxes. License: LGPLv2+

// A non-threadsafe wrapper for libarchives write archive
public class Util.ArchiveWriter : GLib.Object {
    private Archive.Write archive;

    public ArchiveWriter.to_file (string filename,
                                 Archive.Format format,
                                 GLib.List<Archive.Filter>? filters = null)
                                 throws Util.ArchiveError {
        archive = new Archive.Write ();
        if (archive.set_format (format) != Archive.Result.OK) {
            var msg = "Failed setting format (%d) for archive. Message: '%s'.";
            throw new Util.ArchiveError.GENERAL_ARCHIVE_ERROR (msg, format, archive.error_string ());
        }

        if (filters != null)
            add_filters (filters);
        archive.open_filename (filename);
    }

    ~WriteArchive () {
        archive.close ();
    }

    public void insert_files (string[] src, string[] dst)
                              throws Util.ArchiveError
                              requires (src.length == dst.length) {
        for (var i = 0; i < src.length; i++)
            insert_file (src[i], dst[i]);
    }

    // while dst is the destination relative to archive root
    public void insert_file (string src, string dst) throws Util.ArchiveError {
        var entry = get_entry_for_file (src, dst);
        var len = entry.size ();
        var buf = new uint8[len];
        try {
            // get file info, read data into memory
            var filestream = GLib.FileStream.open (src, "r");
            filestream.read ((uint8[]) buf, (size_t) len);
            insert_entry (entry);
            insert_data ((uint8[]) buf, len);
        } catch (GLib.Error e) {
            throw new Util.ArchiveError.FILE_OPERATION_ERROR ("Error reading from source file '%s'. Message: '%s'.",
                                                              src, e.message);
        }
    }

    public void add_filters (GLib.List<Archive.Filter> filters) throws Util.ArchiveError {
        foreach (var filter in filters) {
            if (archive.add_filter (filter) != Archive.Result.OK)
                throw new Util.ArchiveError.GENERAL_ARCHIVE_ERROR ("Failed setting filter. Message: '%s'.",
                                                                   archive.error_string ());
        }
    }

    public void insert_entry (Archive.Entry entry) throws Util.ArchiveError {
        // write header
        if (archive.write_header (entry) != Archive.Result.OK)
            throw new Util.ArchiveError.FILE_OPERATION_ERROR ("Failed writing header to archive. Message: '%s'.",
                                                              archive.error_string ());
    }

    public void insert_data (void* data, int64 len) throws Util.ArchiveError {
        // write data
        if (archive.write_data (data, (size_t) len) != len)
            throw new Util.ArchiveError.FILE_OPERATION_ERROR ("Failed writing data to archive. Message: '%s'.",
                                                              archive.error_string ());
    }

    private Archive.Entry get_entry_for_file (string filename, string dest_name) {
        Posix.Stat st;
        var result = new Archive.Entry ();

        Posix.stat (filename, out st);
        result.copy_stat (st);
        result.set_pathname (dest_name);

        return result;
    }
}

