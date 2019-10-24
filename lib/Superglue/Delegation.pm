package Superglue::Delegation;

=head1 NAME

Superglue::Delegation - DNS delegation records

=head1 DESCRIPTION

Superglue::Delegation loads a zone file and works out what the zone's
delegation records should be.

=head1 BUGS

At the moment this doesn't help with getting delegation information
from the registr* or with comparing delegations, so more thinking
needed.

=cut

use warnings;
use strictures 2;

use IPC::System::Simple qw(capturex);
use Net::DNS;
use Net::DNS::ZoneFile;

our @EXPORT_SUPERGLUE = qw(
	ds
	ns
);

sub ds {
	my $self = shift;
	my $ds = $self->{DS} // [];
	return @$ds if wantarray;
	return join '', map $_->string."\n", @$ds;
}

sub ns {
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
	my $zonefile = Net::DNS::ZoneFile->new($file,$zone);
	my (@ns,@ds,$dnssec);
	while (my $rr = $zonefile->read) {
		if ($rr->owner eq $zone and
		    $rr->type eq 'NS') {
			$self->{ns}->{$rr->nsdname} = {};
		}
		if ($rr->type eq 'A' or
		    $rr->type eq 'AAAA') {
			my $sub = '.'.$rr->owner;
			my $dom = '.'.$zone;
			$self->{ns}->{$rr->owner}->{$rr->rdstring} = ()
			    if exists $self->{ns}->{$rr->owner}
			    and $dom eq substr $sub, -length $dom;
		}
		if ($rr->owner eq $zone and
		    $rr->type eq 'DS') {
			push @ds, $rr;
		}
		if ($rr->owner eq $zone and
		    $rr->type =~ m{^(CDS|DNSKEY|CDNSKEY)$}) {
			$dnssec = 1;
		}
	}
	# child records override parent
	@ds = map Net::DNS::RR->new($_),
	    capturex 'dnssec-dsfromkey', '-f', $file, $zone
	    if $dnssec;
	$self->{DS} = \@ds;
	return $self;
}

1;
