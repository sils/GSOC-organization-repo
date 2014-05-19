// This file is part of GNOME Boxes. License: LGPLv2+

// A non-threadsafe wrapper for libarchives write archive
public class Util.ArchiveWriter : GLib.Object {
    private Archive.Write archive;

    public ArchiveWriter.to_file (string filename,
                                 Archive.Format format,
                                 GLib.List<Archive.Filter>? filters = null)
                                 throws Util.ArchiveError {
        archive = new Archive.Write ();
        prepare_archive (format, filters);
        archive.open_filename (filename);
    }

    public ArchiveWriter.from_raw_read_archive (Archive.Read read_archive,
                                                string filename,
                                                GLib.List<string>? omit_files = null)
                                                throws Util.ArchiveError {
        unowned Archive.Entry iterator;
        archive = new Archive.Write ();
        if (read_archive.next_header (out iterator) != Archive.Result.OK) {
            // its empty or something went wrong - throw exception
            var msg = "Error creating write archive for archive '%s'. Empty?";
            throw new Util.ArchiveError.GENERAL_ARCHIVE_ERROR (msg, filename);
        }

        prepare_archive (read_archive.format (), get_filters (read_archive));
        archive.open_filename (filename);

        do {
            bool omit = false;
            foreach (var file in omit_files) {
                if (file == iterator.pathname ()) {
                    omit = true;
                    break;
                }
            }

            if (!omit) {
                var len = iterator.size ();
                if (len > 0) {
                    var buf = new uint8[len];
                    insert_entry (iterator);
                    insert_data (buf, read_archive.read_data (buf, (size_t) len));
                }
            }
        } while (read_archive.next_header (out iterator) == Archive.Result.OK);
    }

    private void prepare_archive (Archive.Format format, GLib.List<Archive.Filter>? filters = null)
                                  throws Util.ArchiveError {
        if (archive.set_format (format) != Archive.Result.OK) {
            var msg = "Failed setting format (%d) for archive. Message: '%s'.";
            throw new Util.ArchiveError.GENERAL_ARCHIVE_ERROR (msg, format, archive.error_string ());
        }

        if (filters != null)
            add_filters (filters);
    }

    private GLib.List<Archive.Filter> get_filters (Archive.Read read_archive) {
        var filters = new GLib.List<Archive.Filter> ();
        for (var i = read_archive.filter_count () - 1; i > 0; i--)
            filters.append (read_archive.filter_code (i - 1));
        return filters;
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

    private void insert_entry (Archive.Entry entry) throws Util.ArchiveError {
        // write header
        if (archive.write_header (entry) != Archive.Result.OK)
            throw new Util.ArchiveError.FILE_OPERATION_ERROR ("Failed writing header to archive. Message: '%s'.",
                                                              archive.error_string ());
    }

    private void insert_data (void* data, int64 len) throws Util.ArchiveError {
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

