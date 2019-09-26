package Superglue;

# TODO: sub compare_delegation

use warnings;
use strict;

use Cwd qw(realpath);
use Exporter qw(import);
use Getopt::Long qw{:config gnu_getopt posix_default};
use IPC::Open2;
use Pod::Usage;
use ScriptDie;

# monkey patch to fix help text markup
sub Pod::Usage::cmd_b { return $_[2] }
sub Pod::Usage::cmd_c { return $_[2] }
sub Pod::Usage::cmd_i { return "<$_[2]>" }

our @EXPORT = qw{
	debug
	usage
	verbose
};

our $re_label = qr/[a-z0-9](?:[a-z0-9-]*[a-z0-9])?/;
our $re_dname = qr/^(?:$re_label\.)+$re_label$/;
our $re_ipv6 = qr/^(?:[0-9a-f]{1,4}:)+(?::|(?::[0-9a-f]{1,4})+|[0-9a-f]{1,4})$/;
our $re_ipv4 = qr/^\d+\.\d+\.\d+\.\d+$/;

sub verbose {
	1;
}

sub debug {
	1;
}

sub usage {
	my $v = shift // 0;
	pod2usage( -exit => $v != 2, -verbose => $v );
}

sub redefine {
	my $name= shift;
	my $ref = shift;
	my $pkg = caller(1);
	no strict 'refs';
	no warnings;
	*{$pkg."::".$name} = *{$name} = $ref;
}

sub getopt {
	my %opt;

	GetOptions(\%opt, qw{
		creds|c=s
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

	$opt{zone} = shift @ARGV;
	sdie "bad domain name: $opt{zone}"
	  unless $opt{zone} =~ $re_dname;

	redefine 'debug',   \&ScriptDie::swarn if $opt{debug};
	redefine 'verbose', \&ScriptDie::swarn if $opt{debug} or $opt{verbose};

	return %opt;
}

1;
