# Makefile for superglue
#
# At the moment this just sets up dependencies

SG=lib/superglue

# Dependencies managed by us go inside our library directory
# to avoid colliding with other versions.

pl	  =	${SG}/perl5
pltmp	  =	${pl}/JSON ${pl}/XML

# for JANET
CASPERJS  =	${SG}/casperjs

# for RIPE
JSONPP    =	${pl}/JSON/PP.pm

# for Gandi
XMLRPC    =	${pl}/XML/RPC.pm
XMLtreePP =	${pl}/XML/TreePP.pm


all: ${CASPERJS} ${XMLRPC} ${XMLtreePP} ${JSONPP}

clean:
	rm -rf ${pltmp}
	rm -rf Maketmp/*[0-9]

realclean:
	rm -rf ${CASPERJS}
	rm -rf ${pltmp}
	rm -rf Maketmp

# Pick a fixed revision of CasperJS for stability. The most recent tag
# is 1.1-beta3 dated 29 Nov 2013 - it would be nice if they could spin
# a proper release.
CASPERJS_VER = 376d85fceb5eca63596e12e2ef6072a72422ed9b

${CASPERJS}:
	git clone git://github.com/n1k0/casperjs ${CASPERJS}
	cd ${CASPERJS} && git checkout ${CASPERJS_VER}
	: CasperJS smoke test
	${CASPERJS}/bin/casperjs --version

${JSONPP}:
	Makestuff/get-perl ${JSONPP} 2.27300

${XMLRPC}:
	Makestuff/get-perl ${XMLRPC} 0.9

${XMLtreePP}:
	Makestuff/get-perl ${XMLtreePP} 0.43
