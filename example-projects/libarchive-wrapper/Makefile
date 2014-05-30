# makefile doesn't look good without a comment here :-)

default: build

run: build
	./main

build:
	valac main.vala archive-utils.vala archive-reader.vala archive-writer.vala --pkg libarchive --pkg glib-2.0 --pkg gio-unix-2.0
