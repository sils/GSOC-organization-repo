// This file is part of GNOME Boxes. License: LGPLv2+

using Archive;

public errordomain Util.ArchiveError {
    FILE_NOT_FOUND,
    FILE_OPERATION_ERROR,
    UNKNOWN_ARCHIVE_TYPE,
    INVALID_PARAMETER,
    INVALID_CONTEXT,
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
        // let libarchive handle the compression and so on
        this._archive.support_compression_all ();
        this._archive.support_format_all ();
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
                                    Archive.Compression compression)
        throws Util.ArchiveError {
        this._archive = new Archive.Write ();
        this._archive.set_format (format);
        set_compression (compression);
        this._archive.open_filename (filename);
    }

    public RawWriteArchive.to_mem (size_t memory_size,
                                   Archive.Compression compression,
                                   Archive.Format format)
        throws Util.ArchiveError {
        this._archive = new Archive.Write ();
        this._archive.set_format (format);
        set_compression (compression);

        this.mem = GLib.malloc (memory_size);
        this._archive.open_memory (this.mem, memory_size, null);
    }

    ~RawWriteArchive () {
        this._archive.close ();
        // will have no effect if mem is null
        GLib.free (this.mem);
    }

    private void set_compression (Archive.Compression compression) throws Util.ArchiveError {
        Archive.Result err;
        switch (compression) {
        case Archive.Compression.NONE:
            err = this._archive.set_compression_none ();
            break;
        case Archive.Compression.GZIP:
            err = this._archive.set_compression_gzip ();
            break;
        case Archive.Compression.BZIP2:
            err = this._archive.set_compression_bzip2 ();
            break;
        case Archive.Compression.COMPRESS:
            err = this._archive.set_compression_compress ();
            break;
        case Archive.Compression.LZMA:
            err = this._archive.set_compression_lzma ();
            break;
        default:
            stdout.printf ("Unsupported archive compression (%d) .", compression);
            throw new Util.ArchiveError.INVALID_PARAMETER ("Unsupported archive compression (%d) .", compression);
        }

        if (err != Archive.Result.OK)
            throw new Util.ArchiveError.UNKNOWN ("Failed setting archive compression (err is %d).", err);
    }
}

