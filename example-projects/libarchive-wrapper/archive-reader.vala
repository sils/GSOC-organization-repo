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
                          throws GLib.IOError {
        this.filename = filename;
        this.format = format;
        if (filters != null)
            this.filters = filters.copy ();

        open_archive ();
    }

    public GLib.List<string> get_file_list () throws GLib.IOError {
        var result = new GLib.List<string> ();
        unowned Archive.Entry iterator;
        while (ArchiveHelper.get_next_header (archive, out iterator))
            result.append (iterator.pathname ());

        return result;
    }

    // convenience wrapper, don't use it for extracting more than one file for performance reasons!
    public void extract_file (string src,
                              string dst,
                              bool   override_if_necessary = false,
                              uint   follow_hardlinks      = 1)
                              throws GLib.IOError {
        extract_files ({src}, {dst}, override_if_necessary, follow_hardlinks);
    }

    // src_dst is a hash table while the key is the relative path in the archive and the val the path to extract to
    public void extract_files (string[] src,
                               string[] dsts,
                               bool     override_if_necessary = false,
                               uint     follow_hardlinks = 1)
                               throws GLib.IOError
                               requires (src.length == dsts.length) {
        if (src.length == 0)
            return;

        unowned Archive.Entry iterator;
        uint i = 0;
        string[] hardlink_src = {};
        string[] hardlink_dst = {};
        while (ArchiveHelper.get_next_header (archive, out iterator) && (i < src.length)) {
            string dst = null;
            for (uint j = 0; j < src.length; j++) {
                if (src[j] == iterator.pathname ()) {
                    dst = dsts[j];

                    break;
                }
            }

            if (dst == null) {
                ArchiveHelper.handle_errors (archive, archive.read_data_skip);

                continue;
            }

            if (iterator.hardlink () != null && iterator.size () == 0) {
                debug ("Following hardlink of '%s' to '%s'.\n", iterator.pathname (), iterator.hardlink ());
                hardlink_src += iterator.hardlink ();
                hardlink_dst += dst;
                i++;

                continue;
            }

            if (!override_if_necessary && FileUtils.test (dst, FileTest.EXISTS))
                throw new GLib.IOError.EXISTS ("Destination file '%s' already exists.", dst);

            var fd = FileStream.open (dst, "w+");
            ArchiveHelper.handle_errors (archive, () => { return archive.read_data_into_fd (fd.fileno ()); });

            debug ("Extracted file '%s' from archive '%s'.", dst, filename);
            i++;
        }

        if (src.length != i)
            throw new GLib.IOError.NOT_FOUND ("At least one specified file was not found in the archive.");

        reset ();

        if (hardlink_src.length > 0) {
            if (follow_hardlinks > 0) {
                extract_files (hardlink_src, hardlink_dst, override_if_necessary, follow_hardlinks - 1);
            } else {
                var msg = "Maximum recursion depth exceeded. It is likely that a hardlink points to itself.";
                throw new GLib.IOError.WOULD_RECURSE (msg);
            }
        }
    }

    public void reset () throws GLib.IOError {
        ArchiveHelper.handle_errors (archive, archive.close);
        open_archive ();
    }

    private void open_archive () throws GLib.IOError {
        archive = new Archive.Read ();

        if (format == null)
            ArchiveHelper.handle_errors (archive, archive.support_format_all);
        else
            ArchiveHelper.handle_errors (archive, () => { return archive.set_format (format); });

        if (filters == null)
            ArchiveHelper.handle_errors (archive, archive.support_filter_all);
        else
            set_filter_stack ();

        ArchiveHelper.handle_errors (archive, () => { return archive.open_filename (filename, BLOCK_SIZE); });
    }

    private void set_filter_stack () throws GLib.IOError {
        foreach (var filter in filters)
            ArchiveHelper.handle_errors (archive, () => { return archive.append_filter (filter); });
    }
}

