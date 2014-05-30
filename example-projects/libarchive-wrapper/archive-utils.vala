// This file is part of GNOME Boxes. License: LGPLv2+

using Archive;

public errordomain Util.ArchiveError {
    FILE_NOT_FOUND,
    FILE_OPERATION_ERROR,
    UNKNOWN_ARCHIVE_TYPE,
    GENERAL_ARCHIVE_ERROR,
    UNKNOWN
}

public enum Boxes.ArchiveAccess {
    READ = 1,
    WRITE = 2,
    READWRITE = 3
}

