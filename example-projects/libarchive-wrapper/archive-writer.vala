// This file is part of GNOME Boxes. License: LGPLv2+

// A non-threadsafe wrapper for libarchives write archive
public class Boxes.ArchiveWriter : GLib.Object {
    public Archive.Write archive;
    GLib.List<Archive.Filter>? filters;
    Archive.Format format;

    public ArchiveWriter (string                     filename,
                          Archive.Format             format,
                          GLib.List<Archive.Filter>? filters = null)
                          throws Util.ArchiveError {
        archive = new Archive.Write ();
        this.format  = format;
        this.filters = filters.copy ();

        prepare_archive ();
        ArchiveUtils.arg_handle_errors (archive, archive.open_filename, filename);
    }

    public ArchiveWriter.from_archive_reader (ArchiveReader archive_reader,
                                              string        filename,
                                              bool          import_contents = true)
                                              throws Util.ArchiveError {
        unowned Archive.Entry iterator;
        archive = new Archive.Write ();
        if (!ArchiveUtils.get_next_header (archive_reader.archive, out iterator)) {
            // its empty or something went wrong - throw exception
            var msg = "Error creating write archive for archive '%s'. Empty?";
            throw new Util.ArchiveError.GENERAL_ARCHIVE_ERROR (msg, filename);
        }

        format = archive_reader.archive.format ();
        get_filters (archive_reader.archive);
        prepare_archive ();
        ArchiveUtils.arg_handle_errors (archive, archive.open_filename, filename);

        archive_reader.reset ();

        if (import_contents)
            import_read_archive (archive_reader);
    }

    // FIXME if a hardlink points to an omitted file the body will not be stored, maybe iterator.nlink () helps
    public void import_read_archive (ArchiveReader archive_reader,
                                     string[]?     omit_files = null)
                                     throws Util.ArchiveError {
        unowned Archive.Entry iterator;
        while (ArchiveUtils.get_next_header (archive_reader.archive, out iterator)) {
            bool omit = false;
            foreach (var file in omit_files) {
                if (file == iterator.pathname ()) {
                    omit = true;

                    break;
                }
            }

            if (omit) {
                debug ("Omitting file '%s' on archive recreation.", iterator.pathname ());

                continue;
            }

            var len = iterator.size ();
            var buf = new uint8[len];
            archive.write_header (iterator);
            if (len > 0)
                insert_data (buf, archive_reader.archive.read_data (buf, (size_t) len));
        }

        archive_reader.reset ();
    }

    private void prepare_archive () throws Util.ArchiveError {
        if (archive.set_format (format) != Archive.Result.OK) {
            var msg = "Failed setting format (%d) for archive. Message: '%s'.";
            throw new Util.ArchiveError.GENERAL_ARCHIVE_ERROR (msg, format, archive.error_string ());
        }

        if (filters != null)
            add_filters ();
    }

    private void get_filters (Archive.Read read_archive) {
        filters = new GLib.List<Archive.Filter> ();
        for (var i = read_archive.filter_count () - 1; i > 0; i--)
            filters.append (read_archive.filter_code (i - 1));
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
            archive.write_header(entry);
            insert_data ((uint8[]) buf, len);
        } catch (GLib.Error e) {
            throw new Util.ArchiveError.FILE_OPERATION_ERROR ("Error reading from source file '%s'. Message: '%s'.",
                                                              src, e.message);
        }
    }

    public void add_filters () throws Util.ArchiveError {
        foreach (var filter in filters)
            ArchiveUtils.arg_handle_errors (archive, archive.add_filter, filter);
    }

    private void insert_data (void* data, int64 len) throws Util.ArchiveError {
        if (archive.write_data (data, (size_t) len) != len)
            throw new Util.ArchiveError.FILE_OPERATION_ERROR ("Failed writing data to archive. Message: '%s'.",
                                                              archive.error_string ());
    }

    private Archive.Entry get_entry_for_file (string filename, string dest_name) {
        Posix.Stat st;
        var result = new Archive.Entry ();

        Posix.stat (filename, out st);
        // these functions doesnt return errors
        result.copy_stat (st);
        result.set_pathname (dest_name);

        return result;
    }
}

