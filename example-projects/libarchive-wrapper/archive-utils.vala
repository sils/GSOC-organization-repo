// This file is part of GNOME Boxes. License: LGPLv2+

using Archive;

public errordomain Util.ArchiveError {
    FILE_NOT_FOUND,
    FILE_OPERATION_ERROR,
    UNKNOWN_ARCHIVE_TYPE,
    GENERAL_ARCHIVE_ERROR,
    UNKNOWN
}

public class Boxes.ArchiveUtils {
    // This class is not inteneded to be created
    private ArchiveUtils () {}

    public static bool get_next_header (Archive.Read              archive,
                                        out unowned Archive.Entry iterator,
                                        uint                      retry = 1)
                                        throws Util.ArchiveError {
        switch (archive.next_header (out iterator)) {
        case Archive.Result.OK:
            return true;

        case Archive.Result.EOF:
            return false;

        case Archive.Result.RETRY:
            if (retry > 0)
                break;

            return get_next_header (archive, out iterator, retry - 1);

        case Archive.Result.WARN:
            warning ("%s", archive.error_string ());
            return true;

        default:
            break;
        }
        // TODO better error handling
        throw new Util.ArchiveError.GENERAL_ARCHIVE_ERROR ("Failed to retrieve header.");
    }

    public delegate Archive.Result libarchive_function ();
    public delegate Archive.Result arg_libarchive_function<T> (T arg);

    public static void handle_errors (Archive.Archive     archive,
                                      libarchive_function function,
                                      uint                retry = 1)
                                      throws Util.ArchiveError {
        switch (function ()) {
        case Archive.Result.OK:
            return;

        case Archive.Result.RETRY:
            if (retry > 0)
                break;

            handle_errors (archive, function, retry - 1);
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

    public static void arg_handle_errors<T> (Archive.Archive            archive,
                                             arg_libarchive_function<T> function,
                                             T                          arg,
                                             uint                       retry = 1)
                                             throws Util.ArchiveError {
        switch (function (arg)) {
        case Archive.Result.OK:
            return;

        case Archive.Result.RETRY:
            if (retry > 0)
                break;

            arg_handle_errors (archive, function, arg, retry - 1);
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
}

