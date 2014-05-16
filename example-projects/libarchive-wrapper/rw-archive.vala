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
    // if open only with write access, format have to be specified. If not they will be ignored.
    // filters will assumed NONE if not specified otherwise or information available from existent archive
    public RWArchive.from_file (string filename,
                      ArchiveAccess access,
                      Archive.Format? format = null,
                      GLib.List<Archive.Filter>? filters = null)
        throws Util.ArchiveError
        requires ( (access & 0x3) != 0 )
        requires ( (format != null) || (access != Util.ArchiveAccess.WRITE) ) {
        this.access = access;
        this.filename = filename;
        this.format = format;
        if ( filters != null )
            this.filters = filters.copy ();
        else // no filter
            this.filters = new GLib.List<Archive.Filter> ();

        if ( this.readable () ) {
            this.read_archive = new ReadArchive.from_file (filename);
            if ( this.writable () ) {
                stdout.printf ("Creating write archive from read archive.\n");
                this.write_archive = this.read_archive.create_writable (this.filename + "~");
            }
        } else {
            // due to the preconditions: writable () && (format != null) && (filters != null)
            this.write_archive = new WriteArchive.to_file (filename, format, filters);
        }
    }

    ~RWArchive () {
        if ( this.readable () && this.writable () )
            this.flush ();
    }

    // src_dst is a hash table while the key is the relative path in the archive and the val the path to extract to
    public void extract_files (HashTable<string, string> src_dst)
        throws Util.ArchiveError
        requires ( this.readable () ) {
        this.read_archive.extract_files (src_dst);
    }

    public GLib.List<string> get_file_list ()
        requires ( this.readable () ) {
        return this.read_archive.get_file_list ();
    }

    public void insert_files (HashTable<string, string> src_dst)
        throws Util.ArchiveError
        requires ( this.writable () ) {
        this.write_archive.insert_files (src_dst);
    }

    public void insert_file (string src, string dst)
        throws Util.ArchiveError
        requires ( this.writable () ) {
        this.write_archive.insert_file (src, dst);
    }

    // PUBLIC FUNCTIONS
    public bool readable () {
        return ((this.access & ArchiveAccess.READ) != 0);
    }

    public bool writable () {
        return (this.access & ArchiveAccess.WRITE) != 0;
    }

    private void flush ()
        requires ( this.readable () )
        requires ( this.writable () ) {
        var src = GLib.File.new_for_path (this.filename + "~");
        var dst = GLib.File.new_for_path (this.filename);
        try {
            src.move (dst, FileCopyFlags.OVERWRITE);
        } catch (Error e) {} // we can't do anything about this during destruction
    }
}
