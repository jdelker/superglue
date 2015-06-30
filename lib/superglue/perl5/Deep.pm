package Deep;

use warnings;
use strict;

use Exporter qw(import);

our @EXPORT = qw{
	deepeq
};

sub deepeq {
	my $a = shift;
	my $b = shift;
	my $ra = ref $a;
	my $rb = ref $b;
	return undef if $ra ne $rb;
	no strict 'refs';
	&{"Deep::eq_$ra"}($a,$b);
}
sub eq_ {
	my ($a,$b) = @_;
	return $a eq $b;
}
sub eq_SCALAR {
	my ($a,$b) = @_;
	return $$a eq $$b;
}
sub eq_ARRAY {
	my ($a,$b) = @_;
	my $na = scalar @$a;
	my $nb = scalar @$b;
	return undef if $na ne $nb;
	for (my $i = 0; $i < $na; $i++) {
		return undef unless deepeq $a->[$i], $b->[$i];
	}
	return 1;
}
sub eq_HASH {
	my ($a,$b) = @_;
	my @ka = keys %$a;
	my @kb = keys %$b;
	return undef unless deepeq \@ka, \@kb;
	for my $i (@ka) {
		return undef unless deepeq $a->{$i}, $b->{$i};
	}
	return 1;
}

1;
