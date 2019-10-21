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
	my $ns = $self->{ns} //= {};
	if (my ($name,$addr) = @_) {
		# always add the name to the list of nameservers
		$ns->{$name} //= {};
		return unless $addr;
		my $sub = '.'.$name;
		my $dom = '.'.$self->zone;
		return unless $dom eq substr $sub, -length $dom;
		# only add the address if the nameserver needs glue
		$ns->{$name}->{$addr} = ();
		return;
	} elsif (wantarray) {
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
	} else {
		return $ns;
	}
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
		if ($rr->type eq 'A' or
		    $rr->type eq 'AAAA') {
			$self->ns($rr->owner, $rr->rdstring);
		}
		if ($rr->owner eq $zone and
		    $rr->type eq 'NS') {
			push @ns, $rr->nsdname;
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
	$self->prune_ns(@ns);
	# child records override parent
	@ds = map Net::DNS::RR->new($_),
	    capturex 'dnssec-dsfromkey','-f',$file,$self->zone
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
