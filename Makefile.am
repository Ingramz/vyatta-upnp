opdir        = $(datadir)/vyatta-op/templates
cfgdir		 = $(datadir)/vyatta-cfg/templates
share_perl5dir   = $(datarootdir)/perl5/Vyatta

sbin_SCRIPTS = scripts/system/ubnt-upnp2.pl
sbin_SCRIPTS += scripts/system/ubnt-upnp2-show
sbin_SCRIPTS += scripts/system/ubnt-upnp2-clear

cpiop = find  . ! -regex '\(.*~\|.*\.bak\|.*\.swp\|.*\#.*\#\)' -print0 | cpio -0pd

install-exec-hook:
	mkdir -p $(DESTDIR)$(cfgdir)
	cd templates-cfg; $(cpiop) $(DESTDIR)$(cfgdir)
	cd ..
	mkdir -p $(DESTDIR)$(opdir)
	cd templates-op; $(cpiop) $(DESTDIR)$(opdir)
