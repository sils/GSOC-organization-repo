// This file is part of GNOME Boxes. License: LGPLv2+

public class Boxes.ArchiveReader : GLib.Object {
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
        while (ArchiveUtils.get_next_header (archive, out iterator)) {
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
        string[] hardlink_src = {};
        string[] hardlink_dst = {};
        while (ArchiveUtils.get_next_header (archive, out iterator) && (i < src.length)) {
            string dst = null;
            for (uint j = 0; j < src.length; j++) {
                if (src[j] == iterator.pathname ()) {
                    dst = dsts[j];

                    break;
                }
            }

            if (dst == null) {
                ArchiveUtils.handle_errors (archive, archive.read_data_skip);

                continue;
            }

            if (iterator.hardlink () != null && iterator.size () == 0) {
                hardlink_src += iterator.pathname ();
                hardlink_dst += dst;
                i++;

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

        reset ();

        extract_files (hardlink_src, hardlink_dst);
    }

    public void reset () throws Util.ArchiveError {
        ArchiveUtils.handle_errors (archive, archive.close);
        open_archive ();
    }

    private void open_archive () throws Util.ArchiveError {
        archive = new Archive.Read ();
        if (format == null)
            ArchiveUtils.handle_errors (archive, archive.support_format_all);
        else
            ArchiveUtils.arg_handle_errors<Archive.Format> (archive, archive.set_format, format);

        if (filters == null)
            ArchiveUtils.handle_errors (archive, archive.support_filter_all);
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

    private void set_filter_stack () throws Util.ArchiveError {
        foreach (var filter in filters)
            ArchiveUtils.arg_handle_errors (archive, archive.append_filter, filter);
    }
}

