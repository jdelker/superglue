package Superglue::Delegation;

=head1 NAME

Superglue::Delegation - DNS delegation records

=head1 DESCRIPTION

Superglue::Delegation loads a zone file and works out what the zone's
delegation records should be.

=cut

use strictures 2;
use warnings;

use Carp;
use IPC::System::Simple qw(capturex);
use Net::DNS;
use Net::DNS::SEC;
use Net::DNS::ZoneFile;

our @SUPERGLUE_EXPORT = ();

sub add_ds {
	my $self = shift;
	my $zone = $self->{zone};
	my $sha1 = 1;
	my $zsk = 1;
	for my $ds (@_) {
		$sha1 = 0 if ref $ds
		    and $ds->type =~ m{^C?DS$}
		    and $ds->digtype != 1;
		$zsk = 0 if ref $ds
		    and $ds->type =~ m{^C?DNSKEY$}
		    and $ds->sep;
	}
	for my $ds (@_) {
		if (not ref $ds) {
			$ds = Net::DNS::RR->new("$zone DS $ds");
		} elsif ($ds->type eq 'CDS') {
			$ds = Net::DNS::RR->new("$zone DS ".$ds->rdstring);
		} elsif ($ds->type =~ m{^C?DNSKEY$}) {
			next if $ds->revoke;
			next unless $ds->sep or $zsk;
			$ds = Net::DNS::RR::DS->create($ds, digtype => 2);
		} elsif ($ds->type ne 'DS') {
			croak "not a DS record: $ds\n";
		}
		$self->{ds}->{$ds->rdstring} = {}
		    if $sha1 or $ds->digtype != 1;
	}
}

sub get_ds {
	my $self = shift;
	my $ds = $self->{ds};
	return unless $ds;
	return $ds unless wantarray;
	my $zone = $self->{zone};
	return map Net::DNS::RR->new("$zone DS $_"),
	    sort keys %$ds;
}

sub add_ns {
	my $self = shift;
	my $sub = '.'.$_[0];
	my $dom = '.'.$self->{zone};
	if ($_[1] and $dom eq substr $sub, -length $dom) {
		$self->{ns}->{$_[0]}->{$_[1]} = {};
	} else {
		$self->{ns}->{$_[0]} //= {};
	}
}

sub get_ns {
	my $self = shift;
	my $ns = $self->{ns};
	return unless $ns;
	return $ns unless wantarray;
	my @ns;
	for my $name (sort keys %$ns) {
		my $addr = $ns->{$name};
		my @addr = sort keys %$addr;
		if (@addr) {
			push @ns, $name, $_ for @addr;
		} else {
			push @ns, $name, '';
		}
	}
	return @ns;
}

sub new {
	my $class = shift;
	my $self = bless { @_ }, $class;
	my $file = $self->{file};
	my $zone = $self->{zone};
	return $self unless $file;
	my $zonefile = Net::DNS::ZoneFile->new($file,$zone);
	my (@ns,$dnssec);
	while (my $rr = $zonefile->read) {
		if ($rr->owner eq $zone and
		    $rr->type eq 'NS') {
			$self->add_ns($rr->nsdname);
		}
		if ($rr->type eq 'A' or
		    $rr->type eq 'AAAA') {
			$self->add_ns($rr->owner, $rr->rdstring)
			    if exists $self->{ns}->{$rr->owner};
		}
		if ($rr->owner eq $zone and
		    $rr->type =~ m{^(CDS|CDNSKEY|DS|DNSKEY)$}) {
			push @{ $dnssec->{$rr->type} }, $rr;
		}
	}
	# set DS records using the first of these types
	# listed in order of preference
	for my $type (qw(CDS CDNSKEY DS DNSKEY)) {
		my $ds = $dnssec->{$type} // [];
		next unless @$ds;
		$self->add_ds(@$ds);
		last;
	}
	return $self;
}

1;
