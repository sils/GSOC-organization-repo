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
 * flushing changes. (Write actions do this by default, this can be avoided by passing false as last parameter.)
 */
public class Util.Archivist : GLib.Object {
    // PUBLIC MEMBERS
    public string filename { get; protected set; }
    public ArchiveAccess access { get; protected set; }

    // PRIVATE MEMBERS
    private RawWriteArchive write_archive = null;
    private Archive.Format? format;
    private Archive.Filter? compression;

    // CONSTRUCTION|DESTRUCTION
    // if open only with write access, format and compression have to be specified. If not they will be ignored.
    public Archivist (string filename,
                      ArchiveAccess access,
                      Archive.Format? format = null,
                      Archive.Filter? compression = null)
        throws Util.ArchiveError
        requires ( (access & 0x3) != 0 )
        requires ( (format != null && compression != null) || (access != Util.ArchiveAccess.WRITE) )
        requires ( filename != "" ) {
        stdout.printf ("CONSTRUCT Archivist");
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
        stdout.printf ("DESTRUCT: Destroying archivist for file '%s'.", this.filename);
        if ( writable () ) {
            this.simple_flush ();
            yield;
        }
        this.write_archive = null;
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
            if ( this.write_archive.archive.write_header (entry) != Archive.Result.OK )
                stdout.printf ("Failed writing header for file '%s' into write archive. Message: '%s'.\n",
                               src, this.write_archive.archive.error_string ());

            // write data
            stdout.printf ("Reading file '%s'...\n", src);
            var file = GLib.File.new_for_path (src);
            try {
                var stream = file.read ();
                var len = stream.read (buf);
                while ( len > 0 ) {
                    stdout.printf ("Writing %u bytes...\n", (uint)len);
                    if ( this.write_archive.archive.write_data (buf, len) != len )
                        stdout.printf ("Failed writing data for file '%s' into write archive. Message: '%s'.\n",
                                       src, this.write_archive.archive.error_string ());
                    len = stream.read (buf);
                }
            } catch ( GLib.Error e ) {
                throw new Util.ArchiveError.FILE_OPERATION_ERROR ("Error reading from source file '%s'.", src);
            }
        }

        if (flush) {
            stdout.printf ("Invoking flush...");
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
            //stdout.printf ("Path: '%s'\n", iterator.pathname ());
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
            throw new Util.ArchiveError.FILE_NOT_FOUND ("At least one specified file was not found in the archive.");
        }
    }

    public async void flush ()
        throws Util.ArchiveError
        requires ( this.writable () )
        requires ( this.write_archive != null ) {
        stdout.printf ("Invoking simple_flush...\n");
        simple_flush ();

        stdout.printf ("Reopening archive...\n");
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
        stdout.printf ("Open archive '%s~' for writing.\n", this.filename);

        if ( this.readable () ) {
            var arch = new RawReadArchive (this.filename);
            unowned Archive.Entry unused;
            if ( arch.archive.next_header (out unused) != Archive.Result.OK )
                throw new Util.ArchiveError.GENERAL_ARCHIVE_ERROR ("Unable to read header for format determination.");
            stdout.printf ("Archive format is %d. (should: %d)", arch.archive.format (), Archive.Format.ISO9660_ROCKRIDGE);
            this.write_archive = new RawWriteArchive.to_file (this.filename + "~",
                                                              arch.archive.format (),
                                                              arch.archive.filter_code (0));
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
        requires ( this.readable () && this.writable () )
        requires ( this.write_archive != null ) {
        stdout.printf ("Reading archive '%s' for copying...\n", this.filename);
        RawReadArchive arch = new RawReadArchive (this.filename);
        unowned Archive.Read rawread = arch.archive;
        unowned Archive.Write rawwrite = this.write_archive.archive;
        unowned Archive.Entry iterator;

        while ( rawread.next_header (out iterator) == Archive.Result.OK ) {
            var s = (size_t) iterator.size ();
            if ( rawwrite.write_header (iterator) != Archive.Result.OK ) {
                stdout.printf ("Failed writing header for file '%s' into write archive. Message: '%s'.\n",
                               iterator.pathname (), rawwrite.error_string ());
                continue;
            }
            if ( s == 0 )
                break;
            //stdout.printf ("Copying file '%s' to write archive (%d bytes)...\n", iterator.pathname (), (int)s);
            void * buf = GLib.malloc (s);
            if ( rawread.read_data (buf, s) != s )
                stdout.printf ("Failed reading file '%s' for copying!\n", iterator.pathname ());
            if ( rawwrite.write_data (buf, s) != s )
                stdout.printf ("Failed writing file '%s' for copying! Msg: '%s'.\n", iterator.pathname (), rawwrite.error_string ());

            free (buf);
        }
        stdout.printf ("Finished copy_from_read.\n");
    }

    private void simple_flush () throws Util.ArchiveError {
        debug ("Flushing changes to archive '%s'.", this.filename);

        if ( readable () )
            copy_from_read ();

        stdout.printf ("Nulling write archive...\n");
        this.write_archive = null; // destroy old archive so it gets closed
        stdout.printf ("Nulled.\n");
       /* try {
            File buf = GLib.File.new_for_path (this.filename + "~");
            File dst = GLib.File.new_for_path (this.filename);
            if ( !buf.copy (dst, FileCopyFlags.OVERWRITE) ) {
                stdout.printf ("Error copying!");
                throw new Util.ArchiveError.FILE_OPERATION_ERROR ("Error copying buffer file '%s~' to destination '%s'.",
                                                                  this.filename, this.filename);
            }
        } catch (Error e) {
            stdout.printf ("Error copying!");
            throw new Util.ArchiveError.FILE_OPERATION_ERROR ("Error copying buffer file '%s~' to destination '%s'.",
                                                              this.filename, this.filename);
        }*/
    }
}

