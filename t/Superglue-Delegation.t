#!/usr/bin/perl

use strictures 2;
use warnings;

use FindBin;
use lib "$FindBin::Bin/../lib";

use IO::Scalar;
use Test::More;

require_ok('Superglue::Delegation');

my $cam_ac_uk = <<END;
cam.ac.uk.                        NS      authdns0.csx.cam.ac.uk.
cam.ac.uk.                        NS      sns-pb.isc.org.
cam.ac.uk.                        NS      dns0.eng.cam.ac.uk.
cam.ac.uk.                        NS      dns0.cl.cam.ac.uk.
cam.ac.uk.                        NS      ns2.ic.ac.uk.
dns0.cl.cam.ac.uk.                AAAA    2001:630:212:200::d:a0
ns2.ic.ac.uk.                     A       155.198.142.82
dns0.cl.cam.ac.uk.                A       128.232.0.19
dns0.eng.cam.ac.uk.               A       129.169.8.8
auth0.dns.cam.ac.uk.              A       131.111.8.37
auth0.dns.cam.ac.uk.              AAAA    2001:630:212:8::d:a0
auth1.dns.cam.ac.uk.              A       131.111.12.37
auth1.dns.cam.ac.uk.              AAAA    2001:630:212:12::d:a1
authdns0.csx.cam.ac.uk.           A       131.111.8.37
authdns0.csx.cam.ac.uk.           AAAA    2001:630:212:8::d:a0
authdns1.csx.cam.ac.uk.           A       131.111.12.37
authdns1.csx.cam.ac.uk.           AAAA    2001:630:212:12::d:a1
END

tie *HANDLE, 'IO::Scalar', \$cam_ac_uk;

my $z = Superglue::Delegation->new(zone => 'cam.ac.uk');
$z->read(\*HANDLE);

ok($z, 'loaded delegation');

done_testing;

exit;
