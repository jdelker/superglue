# Makefile for superglue
#
# At the moment this just sets up dependencies

SG=lib/superglue

# Dependencies managed by us go inside our library directory
# to avoid colliding with other versions.

# We pick fixed revisions of git repositories for stability.
# (The most recent casperjs tag is 1.1-beta3 dated 29 Nov 2013 -
# it would be nice if they could spin a proper release.)

pl	  =	${SG}/perl5
pltmp	  =	${pl}/JSON ${pl}/Net ${pl}/XML

# for RIPE
JSONPP    =	${pl}/JSON/PP.pm

# for Nominet
NetEPP    =	${pl}/Net/EPP.pm
NetEPPsrc =	${SG}/Net-EPP
NetEPPver =	70a665971c5c83f48acc9bca0d931d34edb6fd3e

# for Gandi
XMLRPC    =	${pl}/XML/RPC.pm
XMLtreePP =	${pl}/XML/TreePP.pm

all: ${CASPERJS} ${JSONPP} ${NetEPP} ${XMLRPC} ${XMLtreePP}

clean:
	rm -rf ${pltmp}
	rm -rf ${NetEPPsrc}
	rm -rf Maketmp/*[0-9]

realclean:
	rm -rf ${CASPERJS}
	rm -rf ${pltmp}
	rm -rf Maketmp

${JSONPP}:
	Makestuff/get-perl ${JSONPP} 2.27300


${NetEPP}:
	[ -d ${NetEPPsrc} ] || \
	git clone git://git.csx.cam.ac.uk/ucs/ipreg/perl-net-epp ${NetEPPsrc}
	cd ${NetEPPsrc} && git checkout ${NetEPPver}
	mkdir -p ${pl}/Net
	ln -s ../../Net-EPP/Net-EPP/lib/Net/EPP    ${pl}/Net/EPP
	ln -s ../../Net-EPP/Net-EPP/lib/Net/EPP.pm ${pl}/Net/EPP.pm

${XMLRPC}:
	Makestuff/get-perl ${XMLRPC} 0.9

${XMLtreePP}:
	Makestuff/get-perl ${XMLtreePP} 0.43
