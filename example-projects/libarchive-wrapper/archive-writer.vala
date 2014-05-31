// This file is part of GNOME Boxes. License: LGPLv2+

// A non-threadsafe wrapper for libarchives write archive
public class Boxes.ArchiveWriter : GLib.Object {
    public Archive.Write archive;
    private GLib.List<Archive.Filter>? filters;
    private Archive.Format format;

    public ArchiveWriter (string                     filename,
                          Archive.Format             format,
                          GLib.List<Archive.Filter>? filters = null)
                          throws GLib.IOError {
        archive = new Archive.Write ();
        this.format  = format;
        this.filters = filters.copy ();

        prepare_archive ();
        ArchiveErrorCatcher.handle_errors (archive, () => { return archive.open_filename (filename); });
    }

    public ArchiveWriter.from_archive_reader (ArchiveReader archive_reader,
                                              string        filename,
                                              bool          import_contents = true)
                                              throws GLib.IOError {
        unowned Archive.Entry iterator;
        archive = new Archive.Write ();
        if (!ArchiveErrorCatcher.get_next_header (archive_reader.archive, out iterator)) {
            var msg = "Error creating write archive for archive '%s'. It is probably empty.";
            throw new GLib.IOError.FAILED (msg, filename);
        }

        format = archive_reader.archive.format ();
        get_filters (archive_reader.archive);
        prepare_archive ();
        ArchiveErrorCatcher.handle_errors (archive, () => { return archive.open_filename (filename); });

        archive_reader.reset ();

        if (import_contents)
            import_read_archive (archive_reader);
    }

    // if omit_hardlinked_files is true a file body will be omitted if its on the list independently from it having a
    // hardlink pointing to it or not. If it is set to false a file body with a hardlink on the omittion list will
    // result in the file NOT being omitted.
    public void import_read_archive (ArchiveReader archive_reader,
                                     string[]?     omit_files = null,
                                     bool          omit_hardlinked_files = false)
                                     throws GLib.IOError {
        unowned Archive.Entry iterator;
        while (ArchiveErrorCatcher.get_next_header (archive_reader.archive, out iterator)) {
            var omit = false;
            foreach (var file in omit_files) {
                if (file == iterator.pathname ()) {
                    omit = true;

                    break;
                }
            }

            if (omit) {
                if (omit_hardlinked_files || iterator.nlink () == 1 || iterator.hardlink () == null) {
                    debug ("Omitting file '%s' on archive recreation.", iterator.pathname ());

                    continue;
                } else {
                    warning ("File '%s' cannot be omitted since a hardlink points to it.", iterator.pathname ());
                }
            }

            var len = iterator.size ();
            ArchiveErrorCatcher.handle_errors (archive, () => { return archive.write_header (iterator); });
            if (len > 0) {
                var buf = new uint8[len];
                insert_data (buf, archive_reader.archive.read_data (buf, (size_t) len));
            }
        }

        archive_reader.reset ();
    }

    private void prepare_archive () throws GLib.IOError {
        ArchiveErrorCatcher.handle_errors (archive, () => { return archive.set_format (format); });

        if (filters != null)
            add_filters ();
    }

    private void get_filters (Archive.Read read_archive) {
        filters = new GLib.List<Archive.Filter> ();
        for (var i = read_archive.filter_count () - 1; i > 0; i--)
            filters.append (read_archive.filter_code (i - 1));
    }

    public void insert_files (string[] src, string[] dst)
                              throws GLib.IOError
                              requires (src.length == dst.length) {
        for (uint i = 0; i < src.length; i++)
            insert_file (src[i], dst[i]);
    }

    // while dst is the destination relative to archive root
    public void insert_file (string src, string dst) throws GLib.IOError {
        var entry = get_entry_for_file (src, dst);
        if (entry.hardlink () != null && entry.size () == 0)
            throw new GLib.IOError.NOT_SUPPORTED ("Inserting hardlinks is currently not supported.");

        var len = entry.size ();
        var buf = new uint8[len];

        // get file info, read data into memory
        var filestream = GLib.FileStream.open (src, "r");
        filestream.read ((uint8[]) buf, (size_t) len);
        ArchiveErrorCatcher.handle_errors (archive, () => { return archive.write_header(entry); });
        insert_data ((uint8[]) buf, len);
    }

    public void add_filters () throws GLib.IOError {
        foreach (var filter in filters)
            ArchiveErrorCatcher.handle_errors (archive, () => { return archive.add_filter (filter); });
    }

    private void insert_data (void* data, int64 len) throws GLib.IOError {
        if (archive.write_data (data, (size_t) len) != len)
            throw new GLib.IOError.FAILED ("Failed writing data to archive. Message: '%s'.",
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

