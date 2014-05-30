// This file is part of GNOME Boxes. License: LGPLv2+

class Boxes.ArchiveReader : GLib.Object {
    // This is the block size used by example code on the libarchive website
    private static const int BLOCK_SIZE = 10240;
    public Archive.Read archive;
    private string filename;
    private Archive.Format? format = null;
    private GLib.List<Archive.Filter>? filters = null;


    public ArchiveReader (string                     filename,
                          Archive.Format?            format  = null,
                          GLib.List<Archive.Filter>? filters = null)
                          throws Util.ArchiveError {
        this.filename = filename;
        this.format = format;
        if (filters != null)
            this.filters = filters.copy ();

        open_archive ();
    }

    public GLib.List<string> get_file_list () throws Util.ArchiveError {
        var result = new GLib.List<string> ();
        unowned Archive.Entry iterator;
        while (get_next_header (out iterator)) {
            result.append (iterator.pathname ());}

        return result;
    }

    // just a convenience wrapper, don't use it for extracting several files for performance reasons!
    public void extract_file (string src, string dst) throws Util.ArchiveError {
        extract_files ({src}, {dst});
    }

    // src_dst is a hash table while the key is the relative path in the archive and the val the path to extract to
    public void extract_files (string[] src, string[] dsts)
                               throws Util.ArchiveError
                               requires (src.length == dsts.length) {
        if (src.length == 0)
            return;

        unowned Archive.Entry iterator;
        uint i = 0;
        while (get_next_header (out iterator) && (i < src.length)) {
            string dst = null;
            for (uint j = 0; j < src.length; j++) {
                if (src[j] == iterator.pathname ()) {
                    dst = dsts[j];

                    break;
                }
            }

            if (dst == null) {
                handle_errors (archive.read_data_skip);

                continue;
            }

            if (iterator.hardlink () != null) {
                extract_file (iterator.hardlink (), dst);

                continue;
            }

            var fd = FileStream.open (dst, "w+");
            // TODO error handling
            if (archive.read_data_into_fd (fd.fileno ()) != Archive.Result.OK)
                throw new Util.ArchiveError.FILE_OPERATION_ERROR ("Unable to extract file '%s'. Message: '%s'.",
                                                                  dst, archive.error_string ());

            debug ("Extracted file '%s' from archive '%s'.", dst, filename);
            i++;
        }

        if (src.length != i)
            throw new Util.ArchiveError.FILE_NOT_FOUND ("At least one specified file was not found in the archive.");

        reset_iterators ();
    }

    private void open_archive () throws Util.ArchiveError {
        archive = new Archive.Read ();
        if (format == null)
            handle_errors (archive.support_format_all);
        else
            arg_handle_errors<Archive.Format> (archive.set_format, format);

        if (filters == null)
            handle_errors (archive.support_filter_all);
        else
            set_filter_stack ();

        open_filename ();
    }

    private void open_filename (uint retry = 1) throws Util.ArchiveError {
        switch (archive.open_filename (filename, BLOCK_SIZE)) {
        case Archive.Result.OK:
            return;

        case Archive.Result.RETRY:
            if (retry > 0) {
                open_filename (retry - 1);

                return;
            }
            break;

        case Archive.Result.WARN:
            warning ("%s", archive.error_string ());
            return;

        default:
            break;
        }
        // TODO better error handling
        throw new Util.ArchiveError.UNKNOWN_ARCHIVE_TYPE ("Given filename is no supported archive. Error: '%s'.",
                                                          archive.error_string ());
    }

    private bool get_next_header (out unowned Archive.Entry iterator, uint retry = 1) throws Util.ArchiveError {
        switch (archive.next_header (out iterator)) {
        case Archive.Result.OK:
            return true;

        case Archive.Result.EOF:
            return false;

        case Archive.Result.RETRY:
            if (retry > 0)
                break;

            return get_next_header (out iterator, retry - 1);

        case Archive.Result.WARN:
            warning ("%s", archive.error_string ());
            return true;

        default:
            break;
        }
        // TODO better error handling
        throw new Util.ArchiveError.GENERAL_ARCHIVE_ERROR ("Failed to retrieve header.");
    }

    private delegate Archive.Result libarchive_function ();
    private delegate Archive.Result arg_libarchive_function<T> (T arg);

    private void handle_errors (libarchive_function function, uint retry = 1) throws Util.ArchiveError {
        switch (function ()) {
        case Archive.Result.OK:
            return;

        case Archive.Result.RETRY:
            if (retry > 0)
                break;

            handle_errors (function, retry - 1);
            return;

        case Archive.Result.WARN:
            warning ("%s", archive.error_string ());
            return;

        default: // EOF error doesnt make sense, throw an error too
            break;
        }
        // TODO better error handling
        throw new Util.ArchiveError.GENERAL_ARCHIVE_ERROR ("Unable to execute function.");
    }

    private void arg_handle_errors<T> (arg_libarchive_function<T> function,
                                       T                          arg,
                                       uint                       retry = 1)
                                       throws Util.ArchiveError {
        switch (function (arg)) {
        case Archive.Result.OK:
            return;

        case Archive.Result.RETRY:
            if (retry > 0)
                break;

            arg_handle_errors (function, arg, retry - 1);
            return;

        case Archive.Result.WARN:
            warning ("%s", archive.error_string ());
            return;

        default: // EOF error doesnt make sense, throw an error too
            break;
        }
        // TODO better error handling
        throw new Util.ArchiveError.GENERAL_ARCHIVE_ERROR ("Unable to execute function.");
    }

    private void reset_iterators () throws Util.ArchiveError {
        handle_errors (archive.close);
        open_archive ();
    }

    private void set_filter_stack () throws Util.ArchiveError {
        foreach (var filter in filters)
            arg_handle_errors (archive.append_filter, filter);
    }
}

