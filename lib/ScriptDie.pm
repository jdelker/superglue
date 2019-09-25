package ScriptDie;

use warnings;
use strict;

use Exporter qw(import);
use FindBin;
use Scalar::Util;

our @EXPORT = qw{
	edie
	eopen
	ewarn
	sdie
	swarn
};

sub edie {
	my $x = Scalar::Util::looks_like_number($_[0]) ? shift : 1;
	print STDERR "$FindBin::Script: @_: $!\n";
	exit $x;
}
sub ewarn {
	print STDERR "$FindBin::Script: @_: $!\n";
}
sub sdie {
	my $x = Scalar::Util::looks_like_number($_[0]) ? shift : 1;
	print STDERR "$FindBin::Script: @_\n";
	exit $x;
}
sub swarn {
	print STDERR "$FindBin::Script: @_\n";
}

sub eopen {
	return if open $_[0], $_[1], $_[2];
	edie "open $_[1] $_[2]";
}

1;
