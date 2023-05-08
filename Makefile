SHELL=/bin/bash
DISTFILES = Makefile.in configure.in configure ChangeLog \
            README version.c aclocal.m4 COPYING \
            src doc source sink examples mrun

PYTHON_VERSION=2.6
GM2GCC_VERSION=4.1.2

prefix= /usr/local
datarootdir= ${prefix}/share
srcdir= .
mandir= ${datarootdir}/man
exec_prefix=${prefix}
bindir= ${exec_prefix}/bin
csndir= ${datarootdir}/csn
INSTALL_PROGRAM= install

GM2PREFIX= /home/gaius/opt
GM2PREFIX= /opt

# TEXI2HTML= python /home/gaius/GM2/graft-4.1.2/gcc-4.1.2/gcc/gm2/www/tools/texi2tr/src/texi2tr.py -I$(srcdir)/doc
TEXI2HTML= texi2html

GM2-LIB-DIR = ${GM2PREFIX}/lib/gcc/x86_64-unknown-linux-gnu/${GM2GCC_VERSION}/gm2

GM2-LIBRARIES = ${GM2-LIB-DIR}/pim/libgm2.a \
                ${GM2-LIB-DIR}/pim-coroutine/libgm2pco.a

GM2-LIBRARIES-SO = ${GM2-LIB-DIR}/pim/SO/libgm2.a \
                   ${GM2-LIB-DIR}/pim-coroutine/SO/libgm2pco.a

CSN-MOD = Indexing.mod SymbolKey.mod NameKey.mod Lock.mod execArgs.mod \
          SysTypes.mod csn.mod nameserver.mod

CSN-C = csnwrapper.c hack.c

GM2-CSN-OBJ = $(CSN-MOD:%.mod=O/%.o) $(CSN-C:%.c=O/%.o)
GM2-CSN-OBJ-SO = $(CSN-MOD:%.mod=SO/%.o) $(CSN-C:%.c=SO/%.o) SO/csn_wrap.o

GM2FLAGS=-g -fextended-opaque -flibs=pim-coroutine,pim,iso -fsoft-check-all
CFLAGS=-g
RANLIB= ranlib

all: setup.py dirs O/libcsn.a csnnameserver documentation

# all: setup.py dirs O/libcsn.a SO/_csn.so c-examples m2-examples csnnameserver documentation

dirs: force
	mkdir -p SO O examples
	chmod 755 mrun/mrun

csn_wrap.c: csn.i
	swig -python csn.i

SO/csn_wrap.o: csn_wrap.c
	gcc -fPIC -g -c $< -o $@ -I/usr/include/python$(PYTHON_VERSION)

csn.i: $(srcdir)/src/csn.i
	cp $< $@

setup.py: $(srcdir)/src/setup.py
	cp $< $@

m2-examples: ex1 ex2 speed

ex1: $(srcdir)/src/ex1.mod O/ex1.o
	gm2 $(GM2FLAGS) -fobject-path=O -fmakeall -I$(srcdir)/src/ $(srcdir)/src/ex1.mod -lpth -o ex1

ex2: $(srcdir)/src/ex2.mod O/ex2.o
	gm2 $(GM2FLAGS) -fobject-path=O -fmakeall -I$(srcdir)/src/ $(srcdir)/src/ex2.mod -lpth -o ex2

speed: $(srcdir)/src/speed.mod O/speed.o
	gm2 $(GM2FLAGS) -fobject-path=O -fmakeall -I$(srcdir)/src/ $(srcdir)/src/speed.mod -lpth -o speed

csnnameserver: $(srcdir)/src/nameserver.mod O/nameserver.o
	gm2 $(GM2FLAGS) -fobject-path=O -fmakeall -I$(srcdir)/src/ $(srcdir)/src/nameserver.mod -lpth -o csnnameserver

c-examples: txhello rxhello worker manager breakdes.par hello.par

txhello: $(srcdir)/examples/txhello.c O/libcsn.a
	gcc -o $@ $(CFLAGS) -I$(srcdir)/src $< O/libcsn.a -lpth -lstdc++

rxhello: $(srcdir)/examples/rxhello.c O/libcsn.a
	gcc -o $@ $(CFLAGS) -I$(srcdir)/src $< O/libcsn.a -lpth -lstdc++

manager: $(srcdir)/examples/manager.c O/libcsn.a
	gcc -o $@ $(CFLAGS) -I$(srcdir)/src $< O/libcsn.a -lpth -lstdc++ -lgcrypt

worker: $(srcdir)/examples/worker.c O/libcsn.a
	gcc -o $@ $(CFLAGS) -I$(srcdir)/src $< O/libcsn.a -lpth -lstdc++ -lgcrypt

breakdes.par:  $(srcdir)/examples/breakdes.par
	cp $< $@

hello.par:  $(srcdir)/examples/hello.par
	cp $< $@

csnlinkorder: force
	gm2 $(GM2FLAGS) -c -fmakelist -I$(srcdir)/src/ $(srcdir)/src/speed.mod

O/%.o: $(srcdir)/src/%.mod
	gm2 $(GM2FLAGS) -c -I$(srcdir)/src $< -o $@

O/%.o: $(srcdir)/src/%.c
	gcc $(CFLAGS) -c -I$(srcdir)/src $< -o $@

O/libcsn.a: $(GM2-CSN-OBJ)
	$(RM) O/libcsn.a
	cd O ; \
	for lib in ${GM2-LIBRARIES}; do \
           ar x $${lib} ; \
	done ; \
	$(AR) cr libcsn.a *.o ; \
	$(RANLIB) libcsn.a

SO/%.o: $(srcdir)/src/%.mod
	gm2 $(GM2FLAGS) -fPIC -c -I$(srcdir)/src $< -o $@

SO/%.o: $(srcdir)/src/%.c
	gcc $(CFLAGS) -fPIC -c -I$(srcdir)/src $< -o $@

SO/_csn.so: $(GM2-CSN-OBJ-SO)
	$(RM) SO/_csn.so
	cd SO ; \
	for lib in ${GM2-LIBRARIES-SO}; do \
           ar x $${lib} ; \
	done ; \
	gcc -shared -Wl,-soname,_csn.so -o _csn.so *.o -lc -lstdc++ -lpth

doc: force
	if [ ! -d doc ] ; then mkdir -p doc ; fi

documentation: doc doc/csn.info doc/csn.ps doc/csn.pdf
# documentation: doc doc/csn.info doc/csn.html doc/csn.ps doc/csn.pdf

doc/csn.info: $(srcdir)/doc/csn.texi
	cd doc ; makeinfo ../$(srcdir)/doc/csn.texi

doc/csn.html: $(srcdir)/doc/csn.texi
	$(TEXI2HTML) ../$(srcdir)/doc/csn.texi

doc/csn.ps: $(srcdir)/doc/csn.texi
	cd doc ; texi2dvi ../$(srcdir)/doc/csn.texi
	cd doc ; dvips csn.dvi -o csn.ps

doc/csn.pdf: doc/csn.ps
	ps2pdf doc/csn.ps $@

install: all
	mkdir -p $(bindir) $(csndir)
	$(INSTALL_PROGRAM) mrun/mrun $(bindir)
	$(INSTALL_PROGRAM) $(srcdir)/mrun/mrex $(bindir)
	$(INSTALL_PROGRAM) $(srcdir)/mrun/mrun.py $(csndir)
	$(INSTALL_PROGRAM) $(srcdir)/mrun/csnobfuscate.py $(csndir)
	$(INSTALL_PROGRAM) $(srcdir)/mrun/csnremote.py $(csndir)
	$(INSTALL_PROGRAM) $(srcdir)/mrun/csnresources.py $(csndir)
	$(INSTALL_PROGRAM) mrun/csnconfig.py $(csndir)
	$(INSTALL_PROGRAM) csnnameserver $(bindir)
	$(INSTALL_PROGRAM) $(srcdir)/src/csn.h $(prefix)/include
	python setup.py install --home=$(prefix)
	# $(INSTALL_PROGRAM) O/libcsn.a $(prefix)/lib

clean: force
	$(RM) config.log config.cache config.status
	$(RM) *.o speed ex1 ex2 csnnameserver */*.o *.a
	$(RM) doc/*.ps doc/*.html doc/*.pdf doc/*.info

distclean: clean force
	$(RM) config.log config.cache config.status
	$(RM) -rf download sources

release: force
	echo csn-`sed -e '/version_string/!d' \
          -e 's/[^0-9.]*\([0-9.]*\).*/\1/' -e q version.c` > .fname
	-rm -rf `cat .fname`
	mkdir `cat .fname`
	dst=`cat .fname`; for f in $(DISTFILES); do \
           cp -rp $(srcdir)/$$f $$dst/$$f ; \
        done
	tar --gzip -chf `cat .fname`.tar.gz `cat .fname`
	uuencode `cat .fname`.tar.gz `cat .fname`.tar.gz > `cat .fname`.uue
	-rm -rf `cat .fname` .fname

force:
