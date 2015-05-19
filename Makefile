# Makefile for superglue
#
# At the moment this just sets up dependencies

SG=lib/superglue

# Dependencies managed by us go inside our library directory
# to avoid colliding with other versions.
CASPERJS=${SG}/casperjs
XMLRPC=${SG}/perl5/XML/RPC.pm

all: ${CASPERJS} ${XMLRPC}

# Pick a fixed revision of CasperJS for stability. The most recent tag
# is 1.1-beta3 dated 29 Nov 2013 - it would be nice if they could spin
# a proper release.
CASPERJS_VER = 376d85fceb5eca63596e12e2ef6072a72422ed9b

${CASPERJS}:
	git clone git://github.com/n1k0/casperjs ${CASPERJS}
	cd ${CASPERJS} && git checkout ${CASPERJS_VER}
	: CasperJS smoke test
	${CASPERJS}/bin/casperjs --version

# Gandi recommend this version. Old code so should be pretty stable.

XMLRPCver=XML-RPC-0.9
XMLRPCtgz=${XMLRPCver}.tar.gz
XMLRPCsrc=${SG}/${XMLRPCver}/lib/XML/RPC.pm

${XMLRPC}: ${XMLRPCsrc}
	: easier than faffing with Makefile.PL
	mkdir -p ${SG}/perl5/XML
	install -m 0644 ${XMLRPCsrc} ${XMLRPC}

${XMLRPCsrc}: ${SG}/${XMLRPCtgz}
	cd ${SG} && tar xf ${XMLRPCtgz}

${SG}/${XMLRPCtgz}:
	cd ${SG} && curl -O http://www.cpan.org/modules/by-module/XML/${XMLRPCtgz}
