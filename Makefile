# Makefile for superglue
#
# At the moment this just sets up dependencies

# Put CasperJS inside our library directory to avoid colliding with
# other versions.
CASPERJS=lib/superglue/casperjs

# Pick a fixed revision of CasperJS for stability. The most recent tag
# is 1.1-beta3 dated 29 Nov 2013 - it would be nice if they could spin
# a proper release.
CASPERJS_VER = 376d85fceb5eca63596e12e2ef6072a72422ed9b

all: ${CASPERJS}

${CASPERJS}:
	git clone git://github.com/n1k0/casperjs ${CASPERJS}
	cd ${CASPERJS} && git checkout ${CASPERJS_VER}
	: CasperJS smoke test
	${CASPERJS}/bin/casperjs --version
