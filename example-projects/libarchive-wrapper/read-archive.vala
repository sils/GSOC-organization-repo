// This file is part of GNOME Boxes. License: LGPLv2+

class Util.ArchiveReader : GLib.Object {
    // This is the block size used by example code on the libarchive website
    private static const int BLOCK_SIZE = 10240;
    private Archive.Read archive;
    private string filename;
    private Archive.Format? format = null;
    private GLib.List<Archive.Filter>? filters = null;


    public ArchiveReader.from_file (string                     filename,
                                    Archive.Format?            format  = null,
                                    GLib.List<Archive.Filter>? filters = null)
                                    throws Util.ArchiveError {
        this.filename = filename;
        this.format = format;
        if (filters != null)
            this.filters = filters.copy ();

        this.open_archive ();
    }

    public GLib.List<string> get_file_list () {
        var result = new GLib.List<string> ();
        unowned Archive.Entry iterator;
        while (archive.next_header (out iterator) == Archive.Result.OK)
            result.append (iterator.pathname ());

        return result;
    }

    // src_dst is a hash table while the key is the relative path in the archive and the val the path to extract to
    public void extract_files (string[] src, string[] dsts)
                               throws Util.ArchiveError
                               requires (src.length == dsts.length) {
        if (src.length == 0)
            return;

        unowned Archive.Entry iterator;
        uint i = 0;
        while (archive.next_header (out iterator) == Archive.Result.OK) {
            string dst = null;
            for (uint j = 0; j < src.length; j++) {
                if (src[j] == iterator.pathname ()) {
                    dst = dsts[j];
                    break;
                }
            }
            if (dst != null) {
                var fd = FileStream.open (dst, "w+");
                if (archive.read_data_into_fd (fd.fileno ()) != Archive.Result.OK)
                    throw new Util.ArchiveError.FILE_OPERATION_ERROR ("Unable to extract file '%s'. Message: '%s'.",
                                                                      dst, archive.error_string ());

                debug ("Extracted file '%s' from archive '%s'.", dst, filename);
                i++;
            } else {
                archive.read_data_skip ();
            }
        }

        if (src.length != i)
            throw new Util.ArchiveError.FILE_NOT_FOUND ("At least one specified file was not found in the archive.");

        reset_iterators ();
    }

    // creates a new archive in that you can write but that has the same format, filter and contents as this
    public ArchiveWriter create_writable (string filename) throws Util.ArchiveError {
        return new ArchiveWriter.from_raw_read_archive (archive, filename, {"preseed.cfg"});
    }

    private void reset_iterators () throws Util.ArchiveError {
        // reopen archive to reset header iterator - FIXME better possibility?
        if (archive.close () != Archive.Result.OK) {
            var msg = "Unable to reset iterators for archive '%s'. Error on trying to close, message: '%s'.";
            throw new Util.ArchiveError.GENERAL_ARCHIVE_ERROR (msg, filename, archive.error_string ());
        }
        open_archive ();
    }

    private void open_archive () throws Util.ArchiveError {
        archive = new Archive.Read ();
        if (format == null)
            archive.support_format_all ();
        else
            archive.set_format (format);
        if (filters == null)
            archive.support_filter_all ();
        else
            set_filter_stack ();

        if (archive.open_filename (filename, BLOCK_SIZE) != Archive.Result.OK)
            throw new Util.ArchiveError.UNKNOWN_ARCHIVE_TYPE ("Given filename is no supported archive. Error: '%s'.",
                                                              archive.error_string ());
    }

    private void set_filter_stack () throws Util.ArchiveError {
        foreach (var filter in filters) {
            if (archive.append_filter (filter) != Archive.Result.OK)
                throw new Util.ArchiveError.GENERAL_ARCHIVE_ERROR ("Failed appending filter. Message: '%s'.",
                                                                   archive.error_string ());
        }
    }
}

