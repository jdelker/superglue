package Superglue::Delegation;

=head1 NAME

Superglue::Delegation - DNS delegation records

=head1 DESCRIPTION

This module provides has helper routines for reading and comparing
domain delegation records - nameservers, glue addresses, and DS secure
delegation digests.

=cut

use warnings;
use strictures 2;

use IPC::System::Simple qw(capturex);
use Moo;
use Net::DNS;
use Net::DNS::ZoneFile;

has zone => (
	is => 'ro',
	required => 1,
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

sub prune_ns {
	my $self = shift;
	my $old = $self->{ns};
	my $new = $self->{ns} = {};
	@$new{@_} = @$old{@_};
}

sub read {
	my $self = shift;
	my $file = shift;
	my $zone = $self->zone;
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
			my $dom = '.'.$self->zone;
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
	    capturex 'dnssec-dsfromkey', '-f', $file, $self->zone
	    if $dnssec;
	$self->{DS} = \@ds;
	return;
}

sub print {
	my $self = shift;
	my @ns = $self->ns;
	while (my ($name,$addr) = splice @ns, 0, 2) {
		print "$name\t$addr\n";
	}
}

1;
