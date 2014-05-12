// This file is part of GNOME Boxes. License: LGPLv2+

class Util.RWArchive : GLib.Object {
    // PUBLIC MEMBERS
    public string filename { get; protected set; }

    // PRIVATE MEMBERS
    private Archive.Format? format;
    private GLib.List<Archive.Filter> filters;
    private ArchiveAccess access;
    // Archives
    private ReadArchive? read_archive = null;
    private WriteArchive? write_archive = null;

    // CONSTRUCTION|DESTRUCTION
    // if open only with write access, format and filters have to be specified. If not they will be ignored.
    public RWArchive.from_file (string filename,
                      ArchiveAccess access,
                      Archive.Format? format = null,
                      GLib.List<Archive.Filter>? filters = null)
        throws Util.ArchiveError
        requires ( (access & 0x3) != 0 )
        requires ( (format != null && filters != null) || (access != Util.ArchiveAccess.WRITE) ) {
        stdout.printf ("CONSTRUCT Archivist for file '%s'\n", filename); stdout.flush ();
        this.access = access;
        this.filename = filename;
        this.format = format;
        this.filters = filters.copy ();

        if ( this.readable () ) {
            this.read_archive = new ReadArchive.from_file (filename);
            if ( this.writable () ) {
                // TODO
            }
        } else {
            // due to the preconditions: writable () && (format != null) && (filters != null)
            this.write_archive = new WriteArchive.to_file (filename, format, filters);
        }
    }
    
    ~RWArchive () {
        stdout.printf ("DESTROY Archivist for file '%s'\n", filename); stdout.flush ();
    }
    
    // src_dst is a hash table while the key is the relative path in the archive and the val the path to extract to
    public void extract_files (HashTable<string, string> src_dst)
        throws Util.ArchiveError
        requires ( this.readable () ) {
        read_archive.extract_files (src_dst);
    }

    // PUBLIC FUNCTIONS
    public bool readable () {
        return ((this.access & ArchiveAccess.READ) != 0);
    }

    public bool writable () {
        return (this.access & ArchiveAccess.WRITE) != 0;
    }
    // TODO
}
