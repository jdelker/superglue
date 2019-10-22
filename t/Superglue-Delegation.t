#!/usr/bin/perl

use strictures 2;
use warnings;

use FindBin;
use lib "$FindBin::Bin/../lib";

use File::Slurp;
use File::Temp qw(tempfile);
use Test::More;

require_ok('Superglue::Delegation');

my ($fh,$fn) = tempfile $FindBin::Script.'XXXXXXXX', UNLINK => 1;
write_file $fh, read_file \*DATA;

my $z = Superglue::Delegation->new(zone => 'cam.ac.uk');
$z->read($fn);

ok($z, 'loaded delegation');

my $ns = $z->ns;
is scalar keys %$ns, 5,
    'found 5 NS records';

my $auth0 = $ns->{'authdns0.csx.cam.ac.uk'};
is scalar keys %$auth0, 2,
    '2 glue addrs for authdns0';

for my $host (qw(ns2.ic.ac.uk sns-pb.isc.org)) {
	my $addr = $ns->{$host};
	ok exists $ns->{$host}, "$host exists";
	ok defined $addr, "$host is a thing";
	is ref $addr, 'HASH', "$host is a hash ref";
	is scalar keys %$addr, 0,
	    "no glue for $host";
}

my $ds = $z->ds;
like $ds, qr(\s+52543\s+5\s+2\s+),
    'calculated DS record';

done_testing;

exit;


__DATA__
$TTL 3600

cam.ac.uk.                        NS      authdns0.csx.cam.ac.uk.
cam.ac.uk.                        NS      sns-pb.isc.org.
cam.ac.uk.                        NS      dns0.eng.cam.ac.uk.
cam.ac.uk.                        NS      dns0.cl.cam.ac.uk.
cam.ac.uk.                        NS      ns2.ic.ac.uk.
dns0.cl.cam.ac.uk.                A       128.232.0.19
dns0.cl.cam.ac.uk.                AAAA    2001:630:212:200::d:a0
dns0.eng.cam.ac.uk.               A       129.169.8.8
auth0.dns.cam.ac.uk.              A       131.111.8.37
auth0.dns.cam.ac.uk.              AAAA    2001:630:212:8::d:a0
auth1.dns.cam.ac.uk.              A       131.111.12.37
auth1.dns.cam.ac.uk.              AAAA    2001:630:212:12::d:a1
authdns0.csx.cam.ac.uk.           A       131.111.8.37
authdns0.csx.cam.ac.uk.           AAAA    2001:630:212:8::d:a0
authdns1.csx.cam.ac.uk.           A       131.111.12.37
authdns1.csx.cam.ac.uk.           AAAA    2001:630:212:12::d:a1
ns2.ic.ac.uk.           86393   IN      A       155.198.142.82
ns2.ic.ac.uk.           893     IN      AAAA    2001:630:12:600:1::82

cam.ac.uk.              790 IN DNSKEY 257 3 5 (
                                AwEAAe9CQ5E0MbMr7AGMTmlzpyLrh+JJxjITH77T6cEx
                                vk69Fqon41u/PWRi+XOKWjHO5d/ffqSLAs+K+SswQwZR
                                G2FyVieRWXQDoLt1bDRrjNqjM+ursG1TNMUE0jZDiFRp
                                iHxDE+qhWLOJXwwMarkOw8QFa4U3VirMTROZkeTqyp5P
                                MLnB/cBzqLdiHN2VVElYd53tt5Z/OP8cSt7T9SFAXp8=
                                ) ; KSK; alg = RSASHA1 ; key id = 52543
cam.ac.uk.              790 IN DNSKEY 256 3 5 (
                                AwEAAeLp2pz1QdR2SFNYchAkLery5BowFfv6N1l6hxPP
                                ESXTSGzKZ43fIfeMo6Ky+Mr7e0yuXLrLzbGVzzgFxsXj
                                yrqMH571BqR61d9vSh+GBXMUK/K959ZrRmIkcTz9dA/p
                                ueufCTe3CxNWbT3wPuIfuqQprosBcIU=
                                ) ; ZSK; alg = RSASHA1 ; key id = 17997
