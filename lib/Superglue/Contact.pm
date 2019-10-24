package Superglue::Contact;

=head1 NAME

Superglue::Contact - domain registration contact information

=head1 SYNOPSIS

  use Superglue::Contact;

  my $contact = Superglue::Contact->new($filename);

  for my $field (qw( Org Name Email )) {
    $api->set($field => $contact->whois($field));
  }

=head1 DESCRIPTION

Superglue::Contact loads domain registration contact details (name,
address, etc.) from a L<YAML(3pm)> file, and does field name
conversion between various different providers' APIs.

Registr*s represent contact details in similar but not entirely
consistent ways. The main difference is that some registries keep
separate contact details for the owner, billing contact,
administrative contact, and technical contact, whereas some only use
one set of contact details.

When Superglue updates a domain it sets the same details for all
contacts.

Superglue can report discrepancies in the domain owner, but may be
unable to change the owner if that is restricted by the registry.

Superglue does not have built-in knowledge of which fields are
required and which are optional, but instead relies on the registr*'s
error handling.

=head2 Contact field aliases

In the input YAML file, each field must be defined at most once using
any of the following field names. A Superglue client script can access
loaded contact details using any of the aliases. Field names are
matched case-insensitively.

=over

=item org / orgname / owner / company

=item first / given

=item last / family

=item name

=item add1 / street0

=item add2 / street1

=item add3 / street2

=item city / town

=item county / state / province / sp

=item postcode / pc

=item country / cc

=item phone / tel / voice

=item fax

=item email

=item lock / loctite

=item privacy

=back

=head2 Names

The "org" field must be used for the owner, if that is different from
the contact name.

In some cases, registr* APIs require the contact name to be provided
in two parts, so the "name" field must have two words so it can be
split into "first" / "last".

=head2 Phone numbers

The standard format for phone numbers is "+CC.NNNNNNNN" where CC is
the international dialling code (e.g. 44 for the UK, 1 for North
America) and NNNNNNNN is the combined area code and local number.

=head2 Registry transfer lock

The "lock" field is not strictly part of the contact information, but
it can be used to disable the registry transfer lock. Superglue
normally ensures the domain is locked against transfers.

=head2 Whois privacy

The "privacy" field is for controlling whether contact details appear
in C<whois>. Superglue is designed for corporate domains whose contact
details are not personal data, so Superglue turns whois privacy off by
default. (However due to GDPR fears, many registries do not publish
contact details even when whois privacy is disabled.)

=cut

use strictures 2;
use warnings;

use Carp;
use YAML;

our @EXPORT_SUPERGLUE_SCRIPT = qw(
	whois
);

our $fields = [
	[qw[ _filename ]], # for error reporting
	[qw[ org orgname owner company ]],
	[qw[ first given ]],
	[qw[ last family ]],
	[qw[ name ]],
	[qw[ add1 street0 ]],
	[qw[ add2 street1 ]],
	[qw[ add3 street2 ]],
	[qw[ city town ]],
	[qw[ county state province sp ]],
	[qw[ postcode pc ]],
	[qw[ country cc ]],
	[qw[ phone tel voice ]],
	[qw[ fax ]],
	[qw[ email ]],
	[qw[ lock loctite ]],
	[qw[ privacy ]],
    ];

# map from field names to a list of aliases

our %aliases;

for my $aliases (@$fields) {
	for my $field (@$aliases) {
		$aliases{$field} = $aliases;
	}
}

=head1 METHODS

=over

=item $contact = Superglue::Contact->new($filename);

Load the YAML file C<$filename> and check that the field names are
known and consistent. If C<$filename> is a reference to a hash then
that is used directly as the contact object.

Returns a Superglue::Contact object.

=cut

sub new {
	my ($class,$yml) = @_;
	my $self = ref $yml ? $yml : YAML::LoadFile $yml;
	bless $self, $class;
	$self->{_filename} = ref $yml ? "domain contact" : $yml;
	$self->whois($_ => $self->{$_}) for keys %$self;
	if (defined $self->{name} and
	    $self->{name} =~ m{^\s*(\S+)\s+(\S+)\s*$}) {
		$self->whois(first => $1);
		$self->whois(last => $2);
	}
	if ($self->{first} and $self->{last}) {
		$self->whois(name => "$self->{first} $self->{last}");
	}
	return $self;
}

=item $value = $contact->whois($field)

With one argument, get a field of a contact, matching field names
case-insensitively. Returns the empty string if the field is not set.

=item $contact->whois($field => $value)

With two arguments, set a field of a contact, ensuring that the field
name is known and that it has not previously been set to a different
value.

=cut

sub whois {
	my ($self,$Field,$value) = @_;
	return $self->{lc $Field} // ''
	    unless defined $value;
	my $yml = $self->{_filename};
	my $field = lc $Field;
	my $aliases = $aliases{$field};
	croak "$yml: unknown contact field $Field\n"
	    unless defined $aliases;
	for my $alias (@$aliases) {
		my $other = $self->{$alias};
		croak "$yml: conflicting values "
		    ."for $Field:$value "
		    ."and $alias:$other\n"
		    if defined $other and $other ne $value;
		$self->{$alias} = $value;
	}
}

=head1 AUTHOR

  Written by Tony Finch <fanf2@cam.ac.uk> <dot@dotat.at>
  at Cambridge University Information Services
  You may do anything with this. It has no warranty.
  <https://creativecommons.org/publicdomain/zero/1.0/>

=head1 SEE ALSO

superglue(1), YAML(3pm)

=cut

1;
