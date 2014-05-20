// This file is part of GNOME Boxes. License: LGPLv2+

class Util.Archivist : GLib.Object {
    // PUBLIC MEMBERS
    public string filename { get; protected set; }

    // PRIVATE MEMBERS
    private Archive.Format? format;
    private GLib.List<Archive.Filter> filters;
    private ArchiveAccess access;
    // Archives
    private ArchiveReader? archive_reader = null;
    private ArchiveWriter? archive_writer = null;

    // CONSTRUCTION|DESTRUCTION
    // if open only with write access, format have to be specified. If not they will be ignored.
    // filters will assumed NONE if not specified otherwise or information available from existent archive
    public Archivist.from_file (string filename,
                                ArchiveAccess access,
                                Archive.Format? format = null,
                                GLib.List<Archive.Filter>? filters = null)
                                throws Util.ArchiveError
                                requires ((access & 0x3) != 0)
                                requires ((format != null) || (access != Util.ArchiveAccess.WRITE)) {
        this.access = access;
        this.filename = filename;
        this.format = format;
        if (filters != null)
            this.filters = filters.copy ();
        else // no filter
            this.filters = new GLib.List<Archive.Filter> ();

        if (readable ()) {
            archive_reader = new ArchiveReader.from_file (filename);
            if (writable ()) {
                archive_writer = archive_reader.create_writable (filename + "~");
            }
        } else {
            // due to the preconditions: writable () && (format != null) && (filters != null)
            archive_writer = new ArchiveWriter.to_file (filename, format, filters);
        }
    }

    ~Archivist () {
        /*if (readable () && writable ())
            flush ();*/
    }

    // src_dst is a hash table while the key is the relative path in the archive and the val the path to extract to
    public void extract_files (string[] src, string[] dst)
                               throws Util.ArchiveError
                               requires (readable ()) {
        archive_reader.extract_files (src, dst);
    }

    public void extract_file (string src, string dst) throws Util.ArchiveError {
        extract_files ({src}, {dst});
    }

    public GLib.List<string> get_file_list () requires (readable ()) {
        return archive_reader.get_file_list ();
    }

    public void insert_files (string[] src, string[] dst)
                              throws Util.ArchiveError
                              requires (writable ()) {
        archive_writer.insert_files (src, dst);
    }

    public void insert_file (string src, string dst)
                             throws Util.ArchiveError
                             requires (writable ()) {
        archive_writer.insert_file (src, dst);
    }

    // PUBLIC FUNCTIONS
    public bool readable () {
        return ((access & ArchiveAccess.READ) != 0);
    }

    public bool writable () {
        return (access & ArchiveAccess.WRITE) != 0;
    }

    private void flush () {
        var src = GLib.File.new_for_path (filename + "~");
        var dst = GLib.File.new_for_path (filename);
        try {
            src.move (dst, FileCopyFlags.OVERWRITE);
        } catch (Error e) {} // we can't do anything about this during destruction
    }
}
