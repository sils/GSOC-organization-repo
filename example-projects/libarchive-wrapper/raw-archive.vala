// This file is part of GNOME Boxes. License: LGPLv2+

using Archive;

public errordomain Util.ArchiveError {
    FILE_NOT_FOUND,
    FILE_OPERATION_ERROR,
    UNKNOWN_ARCHIVE_TYPE,
    GENERAL_ARCHIVE_ERROR,
    UNKNOWN
}

// A non-threadsafe wrapper for libarchives read archive
public class Util.RawReadArchive : GLib.Object {
    // This is the example block size from the libarchive website
    private static const int BLOCK_SIZE = 10240;
    private Archive.Read _archive;
    public Archive.Read archive { get { return this._archive; } }

    public RawReadArchive (string filename)
        throws Util.ArchiveError {
        this._archive = new Archive.Read ();
        // let libarchive handle format and compression
        this._archive.support_format_all ();
        this._archive.support_filter_all ();

        if (this._archive.open_filename (filename, BLOCK_SIZE) != Archive.Result.OK)
            throw new Util.ArchiveError.UNKNOWN_ARCHIVE_TYPE ("Given filename is no supported archive.");
    }

    ~ReadArchive () {
        this._archive.close ();
    }
}

// A non-threadsafe wrapper for libarchives write archive
public class Util.RawWriteArchive : GLib.Object {
    private Archive.Write _archive;
    private void* mem = null;
    public Archive.Write archive { get { return this._archive; } }

    public RawWriteArchive.to_file (string filename,
                                    Archive.Format format,
                                    Archive.Filter compression)
        throws Util.ArchiveError {
        stdout.printf ("Opening RawWriteArchive.\n");
        this._archive = new Archive.Write ();
        if ( this._archive.set_format (format) != Archive.Result.OK )
            throw new Util.ArchiveError.GENERAL_ARCHIVE_ERROR ("Failed setting format (%d) for archive. Message: '%s'.",
                                                               format, this._archive.error_string ());

        add_filter (compression);
        this._archive.open_filename (filename);
    }

    ~RawWriteArchive () {
        stdout.printf ("Closing RawWriteArchive.\n");
        this._archive.close ();
        // will have no effect if mem is null
        GLib.free (this.mem);
    }

    private void add_filter (Archive.Filter compression)
        throws Util.ArchiveError
        requires ( compression == Archive.Filter.NONE     ||
                   compression == Archive.Filter.GZIP     ||
                   compression == Archive.Filter.BZIP2    ||
                   compression == Archive.Filter.COMPRESS ||
                   compression == Archive.Filter.LZMA     ||
                   compression == Archive.Filter.LZIP     ||
                   compression == Archive.Filter.XZ ) {
        Archive.Result err;
        switch ( compression ) {
        case Archive.Filter.NONE:
            err = this._archive.add_filter_none ();
            break;
        case Archive.Filter.GZIP:
            err = this._archive.add_filter_gzip ();
            break;
        case Archive.Filter.BZIP2:
            err = this._archive.add_filter_bzip2 ();
            break;
        case Archive.Filter.COMPRESS:
            err = this._archive.add_filter_compress ();
            break;
        case Archive.Filter.LZMA:
            err = this._archive.add_filter_lzma ();
            break;
        case Archive.Filter.LZIP:
            err = this._archive.add_filter_lzip ();
            break;
        case Archive.Filter.XZ:
            err = this._archive.add_filter_xz ();
            break;
        default:
            err = Archive.Result.FAILED;
            break;
        }

        if ( err != Archive.Result.OK )
            throw new Util.ArchiveError.UNKNOWN ("Failed setting archive compression (Message: %s).",
                                                 this._archive.error_string ());
    }
}

