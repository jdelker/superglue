package Superglue;

=head1 NAME

Superglue - framework for domain registration management scripts

=head1 SYNOPSIS

  # object-oriented

  use Superglue;

  my $sg = Superglue->new(...);

  # script-style

  use Superglue qw(:script);

=head1 DESCRIPTION

The Superglue package collects together support code for scripting
domain registration update clients. A Superglue object is built from
the following modules. See their documentation for full details; here
we mainly explain how they fit together.

=over

=item L<ReGPG::Login>

Used to read encrypted credentials. It only provides a C<login>
attribute containing plain data that you use to access the
registration update interface.

=item L<Superglue::Contact>

=item L<Superglue::Delegation>

Used to represent the domain's registration details. You construct a
Superglue object with either or both of C<contact> and C<delegation>
attributes, representing the desired state of the domain's
registration. As a shorthand, the Superglue::Contact and
Superglue::Delegation methods are available on the Superglue object
itself.

You can also construct separate Superglue::Contact and
Superglue::Delegation objects to represent the current state of the
domain's registration, to compare with the desired state when working
out if a change is needed.

=item L<Superglue::Restful>

Optional support for JSON-over-HTTP interfaces that provides handy
C<get> and C<post> methods on the Superglue object.

=item L<Superglue::WebDriver>

Optional support for scripting a website, as a last resort when a
domain registration service doesn't provide enough of an API.

=back

=cut

use strictures 2;
use warnings;

use Carp;
use Getopt::Long;
use IO::String;
use Moo;
use Pod::Find;
use Pod::Usage;
use ReGPG::Login;
use ScriptDie;
use Superglue::Contact;
use Superglue::Delegation;
use Sys::Syslog qw(:macros);

use namespace::clean;

our @optional = qw( Superglue::Restful );

# Mix in optional parts, before we try to grab their symbol tables.
with @optional;

# For exporting subroutines in script mode, and for extending command
# line options, we reach over into the symbol table to find the
# relevant variables in each module.
our %optional;
$optional{lc $_} = $Superglue::{$_.'::'}
    for map s{.*::}{}r, @optional;

=head1 SCRIPT MODE

As well as a conventional object-oriented interface, Superglue can
also be used in script mode by using it with the C<:script> import
tag. This has some radical effects:

=over

=item Implicit Superglue object

Rather than passing around a C<$sg> object and invoking methods on it,
you can call the methods like subroutines and they will use a hidden
global Superglue object.

=item Automatic command-line handling

The global Superglue object is constructed from the command line
automatically, using C<Superglue::getopt()>.

=back

=head2 Import tags

When your script needs optional features, add these tags when using
Superglue.

    use Superglue qw(:script);

=over

=item :script

Enable script mode.

=item :restful

Add the L<Superglue::Restful> command-line options in script mode.

=item :webdriver

Add the L<Superglue::WebDriver> command-line options in script mode.

=back

=cut

our $script_self;

sub import {
	my $class = shift;
	my %tag; @tag{@_} = @_;
	my $script = delete $tag{':script'};
	# optional modules to enable
	my @module;
	# packages from which we export methods
	my @pkg = (
		\%Superglue::,
		\%Superglue::Contact::,
		\%Superglue::Delegation::,
	);
	for my $module (keys %optional) {
		next unless delete $tag{":$module"};
		push @pkg, $optional{$module};
		push @module, $module;
	}
	my @unknown = keys %tag;
	croak "unknown Superglue import tags @unknown" if @unknown;
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
	$script_self = Superglue::getopt(@module);
}

=head2 Command-line parser

The rough idea is that command-line options correspond to
attributes that you would pass to C<Superglue-E<gt>new()>.

=over

=item Superglue::getopt(@module)

Parse C<@ARGV>, construct and return a Superglue object. Uses
L<Pod::Usage> to print help text and usage messages extracted from pod
in your script, as required by the command line.

To get L<ReGPG::Login> to check credentials files in script mode, set
C<@main::LOGIN_FIELDS> to value for the C<login_fields> attribute.

The C<@module> list says which of the following optional features to
include:

=over

=item

restful

=item

webdriver

=back

Each optional module can extend the command line options by defining a
C<@SUPERGLUE_GETOPT> variable containing a L<Getopt::Long>
specification, and attributes that correspond to those options.

The synopsis for the extra options should be given in a pod subsection
like this:

=back

=head2 Command-line options

  [--contact <filename.yml>]    desired contact details
  [--debug]                     detailed trace
  [--delegation <filename.db>]  desired delegation records
  [-h]                          short usage message
  [--help]                      display manual
   --login <filename.yml>       credentials
  [--not-really]                do everything except make changes
  [--verbose]                   print old and new registration
   --zone <example.com>         domain to be updated

=cut

sub usage {
	pod2usage
	    -exit => 'NOEXIT',
	    -verbose => 99,
	    -sections => 'NAME|SYNOPSIS';
	my $h = IO::String->new(my $out);
	for my $pkg ('Superglue', @optional) {
		my $path = Pod::Find::pod_where { -inc => 1 }, $pkg;
		pod2usage
		    -exit => 'NOEXIT',
		    -input => $path,
		    -output => $h,
		    -verbose => 99,
		    -sections => '/Command-line options';
	}
	$out =~ s{\s*Command-line options:\n*}{\n}g;
	print "Options:$out" if $out;
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
		zone=s
	};
	for my $module (@_) {
		push @opt, @{ $optional{$module}->{SUPERGLUE_GETOPT} };
	}

	my %opt;
	GetOptions(\%opt, @opt) or exit 1;

	usage @_ if $opt{h};
	pod2usage -exit => 0, -verbose => 2 if $opt{help};

	# check that optional modules will work after construction
	$opt{$_} = 1 for @_;

	$opt{login_fields} = $::{LOGIN_FIELDS}
	    if exists $::{LOGIN_FIELDS};

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

=item not_really => $bool

Your script should use this attribute to enable check mode, so that it
does everything it can short of committing any changes.

=cut

has not_really => (
	is => 'rw',
	default => 0,
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

=item zone => $domain_name

The zone whose registration details we will update if necessary.

=cut

has zone => (
	is => 'ro',
	required => 1,
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
	    if exists $args{contact} and not ref $args{contact};

	$args{delegation} = Superglue::Delegation->new($args{delegation})
	    if exists $args{delegation} and not ref $args{delegation};

	my $fields = $args{login_fields} // [];
	$args{login} = read_login $args{login}, @$fields
	    if exists $args{login} and not ref $args{login};

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
	debug
	has_contact
	has_delegation
	login
	notice
	verbose
	warning
);

=head2 Accessors

=over

=item $sg->contact

=item $sg->delegation

=item $sg->has_contact

=item $sg->has_delegation

The C<contact> and C<delegation> accessors themselves are not exported
in script mode, but their predicates are exported for checking whether
the corresponding methods will work.

=item $sg->login

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
