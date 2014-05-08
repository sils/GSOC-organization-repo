// This file is part of GNOME Boxes. License: LGPLv2+

// This file heavily relies on raw-archive.vala

public enum Util.ArchiveAccess {
    READ = 1,
    WRITE = 2,
    READWRITE = 3
}

/**
 * Provides a class to handle archives of any format.
 *
 * This is a wrapper for libarchive that makes our usecases a bit more abstract.
 * It also allows reading and writing from and to the same archive which libarchive doesnt.
 *
 * Every change will be written in a archive with a ~ postfix in filename. The real filename will only be used when
 * flushing changes.
 */
public class Util.Archivist : GLib.Object {
    // PUBLIC MEMBERS
    public string filename { get; protected set; }
    public ArchiveAccess access { get; protected set; }

    // PRIVATE MEMBERS
    private RawWriteArchive write_archive = null;
    private Archive.Format? format;
    private Archive.Compression? compression;

    // CONSTRUCTION|DESTRUCTION
    // if open only with write access, format and compression have to be specified. If not they will be ignored.
    public Archivist (string filename,
                      ArchiveAccess access,
                      Archive.Format? format = null,
                      Archive.Compression? compression = null)
        throws Util.ArchiveError
        requires ( (access & 0x3) != 0 )
        requires ( (format != null && compression != null) || (access != Util.ArchiveAccess.WRITE) )
        requires ( filename != "" ) {
        this.access = access;
        this.filename = filename;

        // TODO: check if file exists
        if ( writable () ) {
            this.format = format;
            this.compression = compression;
            open_write_archive ();
        }
    }

    ~Archivist () {
        if ( writable () ) {
            this.flush.begin (false);
            yield;
        }
    }

    // PUBLIC FUNCTIONS
    public bool readable () {
        return (this.access & ArchiveAccess.READ) != 0;
    }

    public bool writable () {
        return (this.access & ArchiveAccess.WRITE) != 0;
    }

    public async void insert_files (HashTable<string, string> src_dst, bool flush = true)
        throws Util.ArchiveError
        requires ( this.writable () )
        requires ( this.write_archive != null ) {
        // tried to use a static private const but there was an error on c level
        uint8 buf[8192];

        foreach ( var src in src_dst.get_keys () ) {
            var dst = src_dst.get (src);

            // write header
            var entry = get_entry_for_file (src, dst);
            this.write_archive.archive.write_header (entry);

            // write data
            var file = GLib.File.new_for_path (src);
            try {
                var stream = file.read ();
                var len = stream.read (buf);
                while ( len > 0 ) {
                    this.write_archive.archive.write_data (buf, len);
                    len = stream.read (buf);
                }
            } catch ( GLib.Error e ) {
                throw new Util.ArchiveError.FILE_OPERATION_ERROR ("Error reading from source file '%s'.", src);
            }
        }

        if (flush) {
            this.flush.begin ();
            yield;
        }
    }

    // src_dst is a hash table while the key is the relative path in the archive and the val the path to extract to
    public async void extract_files (HashTable<string, string> src_dst)
        throws Util.ArchiveError
        requires ( this.readable () ) {
        if ( src_dst.size () == 0 )
            return;

        RawReadArchive arch = new RawReadArchive (this.filename);
        unowned Archive.Read raw = arch.archive;
        unowned Archive.Entry iterator;
        while ( raw.next_header (out iterator) == Archive.Result.OK ) {
            stdout.printf ("Path: '%s'\n", iterator.pathname ());
            var dst = src_dst.get (iterator.pathname ());
            if ( dst != null ) {
                // w+, rewrite whole file
                var fd = FileStream.open (dst, "w+");
                raw.read_data_into_fd (fd.fileno ());
                debug ("Extracted file '%s' from archive '%s'.", dst, this.filename);

                src_dst.remove (iterator.pathname ());
            } else {
                raw.read_data_skip ();
            }
        }

        if ( src_dst.size () != 0 ) {
            throw new Util.ArchiveError.INVALID_PARAMETER ("At least one specified file was not found in the archive.");
        }
    }

    public async void flush (bool reopen = true)
        throws Util.ArchiveError
        requires ( this.writable () )
        requires ( this.write_archive != null ) {
        debug ("Flushing changes to archive '%s'.", this.filename);

        if ( readable () )
            copy_from_read ();

        this.write_archive = null; // destroy old archive so it gets closed

        try {
            File buf = GLib.File.new_for_path (this.filename + "~");
            File dst = GLib.File.new_for_path (this.filename);
            if ( !buf.copy (dst, FileCopyFlags.OVERWRITE) ) {
                throw new Util.ArchiveError.FILE_OPERATION_ERROR ("Error copying buffer file '%s~' to destination '%s'.",
                                                                  this.filename, this.filename);
            }
        } catch (Error e) {
            throw new Util.ArchiveError.FILE_OPERATION_ERROR ("Error copying buffer file '%s~' to destination '%s'.",
                                                              this.filename, this.filename);
        }

        if ( reopen )
            open_write_archive ();

        // the written thing is readable now and we need to invoke copy_from_read on future flushes
        this.access |= Util.ArchiveAccess.READ;
    }

    // PRIVATE FUNCTIONS
    private void open_write_archive ()
        throws Util.ArchiveError
        requires ( this.writable () )
        requires ( this.readable () || (this.format != null && this.compression != null) )
        requires ( this.write_archive == null )
        ensures  ( this.write_archive != null ) {
        debug ("Open archive '%s~' for writing.", this.filename);

        if ( this.readable () ) {
            var arch = new RawReadArchive (this.filename);
            // create temporary write archive
            this.write_archive = new RawWriteArchive.to_file (this.filename + "~",
                                                              arch.archive.format (),
                                                              arch.archive.compression ());
        } else {
            this.write_archive = new RawWriteArchive.to_file (this.filename + "~", this.format, this.compression);
        }
    }

    private Archive.Entry get_entry_for_file (string filename, string dest_name)
        requires ( filename  != "" )
        requires ( dest_name != "" ){
        Posix.Stat st;
        var result = new Archive.Entry ();

        Posix.stat (filename, out st);
        result.copy_stat (st);
        result.set_pathname (dest_name);

        return result;
    }

    // copies the read archive to the write archive (should only be used for flushing)
    private void copy_from_read ()
        throws Util.ArchiveError
        requires ( readable () && writable () ) {
        RawReadArchive arch = new RawReadArchive (this.filename);
        unowned Archive.Read rawread = arch.archive;
        unowned Archive.Write rawwrite = write_archive.archive;
        unowned Archive.Entry iterator;

        while ( rawread.next_header (out iterator) == Archive.Result.OK ) {
            rawwrite.write_header (iterator);
            var s = (size_t) iterator.size ();
            void * buf = GLib.malloc (s);
            rawread.read_data (buf, s);
            rawwrite.write_data (buf, s);
            free (buf);
        }
    }
}

