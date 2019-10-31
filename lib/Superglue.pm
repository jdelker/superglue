package Superglue;

=head1 NAME

Superglue - framework for domain registration management scripts

=head1 COMMAND FLAGS

  [--contact <filename.yml>]
  [--delegation <filename.db>]
   --login <filename.yml>
   --zone <example.com>

=head1 SYNOPSIS

  # object-oriented

  use Superglue;

  my $sg = Superglue->new(...);

  # script-style

  use Superglue qw(:script);

=cut

use strictures 2;
use warnings;

use Carp;
use Getopt::Long;
use Moo;
use Pod::Find;
use Pod::Usage;
use ReGPG::Login;
use ScriptDie;
use Superglue::Contact;
use Superglue::Delegation;
use Sys::Syslog qw(:macros);

use namespace::clean;

# used for exporting subroutines in script mode, and for extending
# command line options, We reach over into the symbol table to find
# the relevant variables in each module.
our %optional = (
	restful => \%Superglue::Restful::,
	webdriver => \%Superglue::WebDriver::,
);

=head1 SCRIPT MODE



=cut

our $script_self;

sub import {
	my $class = shift;
	my %tag; @tag{@_} = @_;
	my $script = delete $tag{':script'};
	# command line parser options
	my @getopt;
	# packages from which we export methods
	my @pkg = (
		\%Superglue::,
		\%Superglue::Contact::,
		\%Superglue::Delegation::,
	);
	for my $module (keys %optional) {
		next unless delete $tag{":$module"};
		push @pkg, $optional{$module};
		push @getopt, $module;
	}
	my @tag = keys %tag;
	croak "unknown Superglue import tags @tag" if @tag;
	# export nothing unless we are in script mode
	return unless $script;
	# wrap exported methods with the implicit script self
	for my $pkg (@pkg) {
		my $methods = $pkg->{SUPERGLUE_EXPORT};
		for my $name (@$methods) {
			my $ref = $pkg->{$name};
			$main::{$name} = sub {
				# like return $script_self->$name(@_)
				unshift @_, $script_self;
				goto &$ref;
			};
		}
	}
	$script_self = Superglue::getopt(@getopt);
}

sub usage {
	pod2usage
	    -exit => 'NOEXIT',
	    -verbose => 99,
	    -sections => 'NAME|SYNOPSIS';
	for my $pkg (\%Superglue::, @optional{@_}) {
		# get the package name from a symbol table entry that
		# we know exists, so we can find the package's file,
		# so we can extract the relevant bit of documentation
		my $name = *{ $pkg->{SUPERGLUE_EXPORT} }{PACKAGE};
		my $path = Pod::Find::pod_where { -inc => 1 }, $name;
		pod2usage
		    -exit => 'NOEXIT',
		    -input => $path,
		    -verbose => 99,
		    -sections => 'COMMAND FLAGS';
	}
	exit 1;
}

sub getopt {
	my @opt = qw{
		debug|d
		h|?
		help
		login|l=s
		not_really|not-really|n
		verbose|v
	};
	for my $module (@_) {
		push @opt, $optional{$module}->{SUPERGLUE_GETOPT};
	}
	my %opt;

	GetOptions(\%opt, @opt) or exit 1;

	usage @_ if $opt{h};
	pod2usage -exit => 0, -verbose => 2 if $opt{help};

	my $sg = eval { Superglue->new(%opt) };
	return $sg if $sg;

	$@ =~ s{ at \S+ line [0-9.]+$}{};
	swarn $@;
	usage @_;
}

=head1 ATTRIBUTES

The following options can be passed to Superglue's C<new> method. Many
of them also have accessor methods

=over

=item contact => $filename

(optional)

The C<$filename> is a YAML file containing the desired registration
contact details. See L<Superglue::Contact> for details of the file
format and the methods that the contact object handles.

=cut

has contact => (
	is => 'ro',
	predicate => 1,
	handles => [@Superglue::Contact::EXPORT_SUPERGLUE],
	trigger => sub { Superglue::Contact->new(@_) },
    );

=item debug => 1

Equivalent to C<verbosity =E<gt> LOG_DEBUG>

=item delegation => $filename

(optional)

The C<$filename> is a standard DNS zone file from which the zone's
desired delegation records are extracted. See L<Superglue::Delegation>
for details of the file format and the methods that the contact object
handles.

=cut

has delegation => (
	is => 'ro',
	predicate => 1,
	handles => [@Superglue::Delegation::EXPORT_SUPERGLUE],
    );

=item login => $filename

(required)

The C<$filename> is a YAML file containing login credentials with
encrypted secrets. See L<ReGPG::Login> for details of the file format.
The C<login> accessor method returns the loaded login file.

=cut

has login => (
	is => 'ro',
	predicate => 1,
	required => 1,
    );

=item login_fields => [qw(username password)]

(optional)

When loading the C<login> file, the C<login_fields> list is passed to
L<ReGPG::Login> to check that all the required fields are present.

=cut

has login_fields => (
	is => 'ro',
    );

=item verbose => 1

Equivalent to C<verbosity =E<gt> LOG_INFO>

=item verbosity => $level

(optional)

Set the verbosity to a L<Sys::Syslog> level.

=cut

has verbosity => (
	is => 'rw',
	default => LOG_NOTICE,
    );

=back

=cut

around BUILDARGS => sub {
	my $orig = shift;
	my $class = shift;
	my %args = @_;

	# Contact, Delegation, Login objects are constructed
	# from their filenames.

	$args{contact} = Superglue::Contact->new($args{contact})
	    if exists $args{contact};

	$args{delegation} = Superglue::Delegation->new($args{delegation})
	    if exists $args{delegation};

	my $fields = $args{login_fields} // [];
	$args{login} = read_login $args{login}, @$fields
	    if exists $args{login};

	# Convert boolean `verbose` and `debug` settings
	# into a `verbosity` level.

	$args{verbosity} = LOG_INFO
	    if delete $args{verbose};
	$args{verbosity} = LOG_DEBUG
	    if delete $args{debug};

	return $class->$orig(%args);
};

=head1 METHODS

The methods described below are available as subroutines in
scripting mode.

Additional methods are provided by L<Superglue::Contact> and
L<Superglue::Delegation>. See the documentation for those modules for
details.

=cut

our @SUPERGLUE_EXPORT = qw(
	contact
	debug
	delegation
	has_contact
	has_delegation
	login
	notice
	verbose
	warning
);

=head2 Accessors

=over

=item has_contact

The C<contact> accessor itself is not exported in script mode, but its
predicate is exported for checking whether the L<Superglue::Contact>
methods will work.

=item has_delegation

The C<delegation> accessor itself is not exported in script mode, but its
predicate is exported for checking whether the L<Superglue::Delegation>
methods will work.

=item login

The L<ReGPG::Login> credentials.

=back

=head2 Logging

The logging methods use the L<ScriptDie> package to print messages
to C<STDERR> prefixed by the name of the script.

=over

=item $sg->debug($message)

Print the C<$message> if the verbosity is C<LOG_DEBUG>.

=cut

sub debug {
	my $self = shift;
	return swarn @_
	    unless $self->{verbosity} < LOG_DEBUG;
}

=item $sg->verbose($message)

Print the C<$message> if the verbosity is C<LOG_INFO> or higher.

=cut

sub verbose {
	my $self = shift;
	return swarn @_
	    unless $self->{verbosity} < LOG_INFO;
}

=item $sg->notice($message)

Print the C<$message> if the verbosity is C<LOG_NOTICE> or higher.

=cut

sub notice {
	my $self = shift;
	return swarn @_
	    unless $self->{verbosity} < LOG_NOTICE;
}

=item $sg->warning($message)

Print the C<$message> if the verbosity is C<LOG_WARNING> or higher.

=cut

sub warning {
	my $self = shift;
	return swarn @_
	    unless $self->{verbosity} < LOG_WARNING;
}

=back

=cut

1;
