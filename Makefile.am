SUBDIRS = src
dist_doc_DATA = README


datarootdir= ${prefix}/share
csndir= ${datarootdir}/csn
GM2LIBDIR = /opt/gm2

LIBS=-L$(GM2LIBDIR)/lib \
     src/.libs/libcsn.a -lm2iso -lm2pim -lm2cor -lm -lpthread -lstdc++

all-local: force
	cd src ; make libcsn nameserver


doc: force
	if [ ! -d doc ] ; then mkdir -p doc ; fi

documentation: doc doc/csn.info doc/csn.ps doc/csn.pdf

doc/csn.info: $(srcdir)/doc/csn.texi
	cd doc ; makeinfo ../$(srcdir)/doc/csn.texi

doc/csn.html: $(srcdir)/doc/csn.texi
	$(TEXI2HTML) ../$(srcdir)/doc/csn.texi

doc/csn.ps: $(srcdir)/doc/csn.texi
	cd doc ; texi2dvi ../$(srcdir)/doc/csn.texi
	cd doc ; dvips csn.dvi -o csn.ps

doc/csn.pdf: doc/csn.ps
	ps2pdf doc/csn.ps $@

clean-local: force
	$(RM) config.log config.cache config.status
	$(RM) *.o speed ex1 ex2 csnnameserver */*.o *.a
	$(RM) doc/*.ps doc/*.html doc/*.pdf doc/*.info

distclean-local: clean force
	$(RM) config.log config.cache config.status
	$(RM) -rf download sources

install-exec-local: force
	mkdir -p $(bindir) $(csndir)
	$(INSTALL_PROGRAM) mrun/mrun $(bindir)
	$(INSTALL_PROGRAM) $(srcdir)/mrun/mrex $(bindir)
	$(INSTALL_PROGRAM) $(srcdir)/mrun/mrun.py $(csndir)
	$(INSTALL_PROGRAM) $(srcdir)/mrun/csnobfuscate.py $(csndir)
	$(INSTALL_PROGRAM) $(srcdir)/mrun/csnremote.py $(csndir)
	$(INSTALL_PROGRAM) $(srcdir)/mrun/csnresources.py $(csndir)
	$(INSTALL_PROGRAM) mrun/csnconfig.py $(csndir)
	$(INSTALL_PROGRAM) $(srcdir)/src/csn.h $(prefix)/include
	python3 $(srcdir)/setup.py install --home=$(prefix)

examples: force
	./libtool --tag=CC --mode=compile gcc -g -c $(srcdir)/examples/txhello.c -o txhello.lo
	./libtool --tag=CC --mode=link  gcc -g txhello.lo $(LIBS) -o txhello
	./libtool --tag=CC --mode=compile gcc -g -c $(srcdir)/examples/rxhello.c -o rxhello.lo
	./libtool --tag=CC --mode=link  gcc -g rxhello.lo $(LIBS) -o rxhello

manager: force
	./libtool --tag=CC --mode=compile gcc -g -c $(srcdir)/examples/manager.c -o manager.lo
	./libtool --tag=CC --mode=link  gcc -g manager.lo $(LIBS) -lgcrypt -o manager

worker: force
	./libtool --tag=CC --mode=compile gcc -g -c $(srcdir)/examples/worker.c -o worker.lo
	./libtool --tag=CC --mode=link  gcc -g worker.lo $(LIBS) -lgcrypt -o worker

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
