package Superglue::Test::Delegation;

=head1 NAME

Superglue::Test::Delegation - test harness for Superglue::Delegation

=head1 DESCRIPTION

This module is a Moo class that provides just enough to get the
L<Superglue::Delegation> role working without the rest of
L<Superglue>.

=head2 Attributes

=over

=item zone

Name of the zone. Required argument to the C<new> method.

=back

=head1 SEE ALSO

L<Superglue>, L<Superglue::Delegation>, L<Moo>

=cut

use strictures 2;
use warnings;

use Moo;

has zone => (
	is => 'ro',
	required => 1,
    );

with 'Superglue::Delegation';

1;
