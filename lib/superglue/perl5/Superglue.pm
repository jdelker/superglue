package Superglue;

use warnings;
use strict;

use Cwd qw(realpath);
use Exporter qw(import);
use Getopt::Long qw{:config gnu_getopt posix_default};
use Pod::Usage;

# monkey patch to fix help text markup
sub Pod::Usage::cmd_b { return $_[2] }
sub Pod::Usage::cmd_c { return $_[2] }
sub Pod::Usage::cmd_i { return "<$_[2]>" }

our @EXPORT = qw{
	%opt
	$libdir
	$zone
	usage
};

our %opt;
our $zone;

our $libdir = realpath("$FindBin::Bin/../lib/superglue");

sub usage {
	my $v = shift // 0;
	pod2usage( -exit => $v != 2, -verbose => $v );
}

sub getopt {
	GetOptions(\%opt, qw{
		creds|c
		debug|d
		h|?
		help
		not-really|n
		verbose|v
	}) or exit 1;

	usage 1 if $opt{h};
	usage 2 if $opt{help};

	usage unless $opt{creds};
	usage unless @ARGV == 1;

	$zone = shift @ARGV;
}

1;
