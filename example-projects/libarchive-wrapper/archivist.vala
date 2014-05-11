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

    // PRIVATE MEMBERS
    private RawWriteArchive write_archive = null;
    private Archive.Format? format;
    private GLib.List<Archive.Filter> filters;
    private ArchiveAccess access;

    // CONSTRUCTION|DESTRUCTION
    // if open only with write access, format and filters have to be specified. If not they will be ignored.
    public Archivist (string filename,
                      ArchiveAccess access,
                      Archive.Format? format = null,
                      GLib.List<Archive.Filter>? filters = null)
        throws Util.ArchiveError
        requires ( (access & 0x3) != 0 )
        requires ( (format != null && filters != null) || (access != Util.ArchiveAccess.WRITE) ) {
        stdout.printf ("CONSTRUCT Archivist for file '%s'\n", filename); stdout.flush ();
        this.access = access;
        this.filename = filename;

        // TODO: check if file exists
        if ( writable () ) {
            if (format != null && filters != null) {
                this.format = format;
                this.filters = filters.copy ();
            }
            open_write_archive ();
        }
    }

    ~Archivist () {
        stdout.printf ("DESTRUCT: Destroying archivist for file '%s'.\n", this.filename); stdout.flush ();
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
                               src, this.write_archive.archive.error_string ()); stdout.flush ();

            // write data
            stdout.printf ("Reading file '%s'...\n", src); stdout.flush ();
            var file = GLib.File.new_for_path (src);
            try {
                var stream = file.read ();
                var len = stream.read (buf);
                while ( len > 0 ) {
                    stdout.printf ("Writing %u bytes...\n", (uint)len); stdout.flush ();
                    if ( this.write_archive.archive.write_data (buf, len) != len )
                        stdout.printf ("Failed writing data for file '%s' into write archive. Message: '%s'.\n",
                                       src, this.write_archive.archive.error_string ()); stdout.flush ();
                    len = stream.read (buf);
                }
            } catch ( GLib.Error e ) {
                throw new Util.ArchiveError.FILE_OPERATION_ERROR ("Error reading from source file '%s'.", src);
            }
        }

        if (flush) {
            stdout.printf ("Invoking flush..."); stdout.flush ();
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
        stdout.printf ("Invoking simple_flush...\n"); stdout.flush ();
        simple_flush ();

        stdout.printf ("Reopening archive...\n"); stdout.flush ();
        open_write_archive ();

        // the written thing is readable now and we need to invoke copy_from_read on future flushes
        this.access |= Util.ArchiveAccess.READ;
    }

    // PRIVATE FUNCTIONS
    private void open_write_archive ()
        throws Util.ArchiveError
        requires ( this.writable () )
        requires ( this.readable () || (this.format != null && this.filters != null) )
        requires ( this.write_archive == null )
        ensures  ( this.write_archive != null ) {

        stdout.printf ("open_write_archive invoked.\n"); stdout.flush ();
        if ( this.readable () && ((this.filters == null) || (this.format != null)) ) {
            stdout.printf ("Auto-determine format and compression...\n"); stdout.flush ();
            var arch = new RawReadArchive (this.filename);
            unowned Archive.Entry unused;
            stdout.printf ("Reading one header for format detection...\n"); stdout.flush ();
            if ( arch.archive.next_header (out unused) != Archive.Result.OK )
                throw new Util.ArchiveError.GENERAL_ARCHIVE_ERROR ("Unable to read header for format determination.");

            this.format = arch.archive.format ();
            this.filters = new GLib.List<Archive.Filter> ();
            stdout.printf ("There are %d filters.\n", arch.archive.filter_count ()); stdout.flush ();
            for (int i = arch.archive.filter_count () - 1; i > 0; i--) {
                stdout.printf ("Appending filter '%s' (%d).\n", arch.archive.filter_name (i - 1), i-1); stdout.flush ();
                this.filters.append (arch.archive.filter_code (i - 1));
            }
            stdout.printf ("Finished filter determination.\n"); stdout.flush ();
        }

        stdout.printf ("Open archive '%s~' for writing.\n", this.filename); stdout.flush ();
        this.write_archive = new RawWriteArchive.to_file (this.filename + "~", this.format, this.filters);
    }

    private Archive.Entry get_entry_for_file (string filename, string dest_name)
        requires ( filename  != "" )
        requires ( dest_name != "" ) {
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
        stdout.printf ("Reading archive '%s' for copying...\n", this.filename); stdout.flush ();
        RawReadArchive arch = new RawReadArchive (this.filename);
        unowned Archive.Read rawread = arch.archive;
        unowned Archive.Write rawwrite = this.write_archive.archive;
        unowned Archive.Entry iterator;

        // TODO log errors and throw an exception at the end
        while ( rawread.next_header (out iterator) == Archive.Result.OK ) {
            var s = (size_t) iterator.size ();
            if ( rawwrite.write_header (iterator) != Archive.Result.OK ) {
                stdout.printf ("Failed writing header for file '%s' into write archive. Message: '%s'.\n",
                               iterator.pathname (), rawwrite.error_string ());
                continue;
            }
            if ( s == 0 ) {
                stdout.printf ("File's empty! :(\n");
                continue;
            }
            //stdout.printf ("Copying file '%s' to write archive (%d bytes)...\n", iterator.pathname (), (int)s);
            void * buf = GLib.malloc (s);
            if ( rawread.read_data (buf, s) != s ) {
                stdout.printf ("Failed reading file '%s' for copying!\n", iterator.pathname ());
                continue;
            }
            if ( rawwrite.write_data (buf, s) != s ) {
                stdout.printf ("Failed writing file '%s' for copying! Msg: '%s'.\n", iterator.pathname (), rawwrite.error_string ()); stdout.flush ();
                continue;
            }
            stdout.flush ();

            free (buf);
        }
        stdout.printf ("Finished copy_from_read.\n");
    }

    // TODO make this private
    public void simple_flush () throws Util.ArchiveError {
        debug ("Flushing changes to archive '%s'.", this.filename);

        if ( readable () )
            copy_from_read ();

        this.write_archive = null; // destroy old archive so it gets closed
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

