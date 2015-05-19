package Superglue;

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

our $lib = realpath("$FindBin::Bin/../lib/superglue");
our $CasperJS = "$lib/casperjs/bin/casperjs";

our $re_dname = qr/^(?:[a-z0-9][a-z0-9-]*[a-z0-9][.])+[a-z0-9][a-z0-9-]*[a-z0-9]$/;
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
		if ($key =~ m{^(pass|apikey)$}) {
			debug("$fn:$.: $key -> ******");
		} else {
			debug("$fn:$.: $key -> $val");
		}
		$h{$key} = $val;
	}
	return %h
}

sub read_delegation {
	my $z = shift;
	my $subdomain = quotemeta $z;
	$subdomain = qr{(^|\.)$subdomain$};
	my %d;
	sub parse_dname {
		my $origin = shift;
		my $n = lc shift;
		return $origin if $n eq '@';
		$n = "$n.$origin" unless $n =~ s{\.$}{};
		return $n if $n =~ $re_dname;
		sdie "$origin:$.: bad domain name: $n";
	};
	my ($owner,$type,$rdata) = $z;
	my %check = (
	NS	=> sub { parse_dname $z, $rdata },
	DS	=> sub { $rdata },
	DNSKEY	=> sub { $rdata },
	A	=> sub { $rdata =~ $re_ipv4 ? $rdata :
			   sdie "$z:$.: bad IPv4 address: $rdata" },
	AAAA	=> sub { $rdata =~ $re_ipv6 ? $rdata :
			   sdie "$z:$.: bad IPv6 address: $rdata" },
	);
	while (<>) {
		s{;.*}{};
		next if m{^\s*$};
		sdie "$z:$.: could not parse line: $_" unless
		    m{^(\S*)\s+
		       (?:(?:IN|\d+)\s+)*
		       (NS|DS|DNSKEY|A|AAAA)\s+
		       (.*?)\s*$}x;
		$owner = parse_dname $z, $1 if $1 ne '';
		$type = $2;
		$rdata = $3;
		if ($type =~ m{^(NS|DS|DNSKEY)$}) {
			sdie "$z:$.: $_ RRs must be owned by $z"
			    unless $owner eq $z;
			$rdata = $check{$type}->();
			$d{$type} = [] unless $d{$type};
			push @{$d{$type}}, $rdata;
			debug "parse $z $type $rdata";
		} elsif ($type =~ m{^(A|AAAA)$}) {
			sdie "$z:$.: glue $_ records must be subdomains of $z"
			    unless $owner =~ $subdomain;
			$rdata = $check{$type}->();
			$d{glue}{$owner} = [] unless $d{glue}{$owner};
			push @{$d{glue}{$owner}}, $rdata;
			debug "parse $owner $type $rdata";
		}
	}
	# TODO: generate DS from DNSKEY and accept only DNSKEY in
	# input (dnssec-dsfromkey will do syntax checks)
	sdie "$z: no delegation records in input"
	    unless $d{NS} or $d{DS} or $d{DNSKEY};
	my %ns;
	if ($d{NS}) {
		for my $ns (@{$d{NS}}) {
			sdie "$z: glue records missing for NS $ns"
		    if $ns =~ $subdomain and not $d{glue}{$ns};
			$ns{$ns} = 1;
		}
	}
	for my $ns (keys %{$d{glue}}) {
		sdie "$z: glue records for nonexistent NS $ns"
		    unless $ns{$ns};
	}
	if ($d{DNSKEY}) {
		local $SIG{PIPE} = 'IGNORE';
		my $pid = open2 my $ds_h, my $dnskey_h,
		    "dnssec-dsfromkey -2 -f /dev/stdin $z";
		print $dnskey_h map "$z. 3600 IN DNSKEY $_\n", @{$d{DNSKEY}};
		close $dnskey_h;
		print while <>;
	}
	return %d;
}

1;
