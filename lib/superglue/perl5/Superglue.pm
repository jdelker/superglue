package Superglue;

use warnings;
use strict;

use Cwd qw(realpath);
use Exporter qw(import);
use Getopt::Long qw{:config gnu_getopt posix_default};
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

our $lib = realpath("$FindBin::Bin/../lib/superglue");
our $CasperJS = "$lib/casperjs/bin/casperjs";

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

	redefine 'debug',   \&ScriptDie::swarn if $opt{debug};
	redefine 'verbose', \&ScriptDie::swarn if $opt{verbose};

	return %opt;
}

sub load_kv {
	my $fn = shift;
	my %h;
	eopen my $fh, '<', $fn;
	while (<$fh>) {
		next if m{^\s*$|^\s*#};
		my ($key,$val) = split;
		$h{$key} = $val;
	}
	return %h
}

1;
