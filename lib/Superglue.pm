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

Used to read encrypted credentials. It provides a C<login> attribute
that you use to access the registration update interface.

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
use FindBin;
use Getopt::Long;
use IO::String;
use JSON;
use Moo;
use POSIX;
use Pod::Find;
use Pod::Usage;
use ReGPG::Login;
use Superglue::Contact;
use Superglue::Delegation;
use Sys::Syslog qw(:macros);
use Time::HiRes qw(gettimeofday);

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
				return $script_self->$name(@_);
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

The C<@module> list says which of the following optional features to
include:

=over

=item * restful

=item * webdriver

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
		contact|C=s
		debug|d
		delegation|D=s
		h|?
		help
		login|L=s
		not_really|not-really|n
		verbose|v
		zone|Z=s
	};
	for my $module (@_) {
		push @opt, @{ $optional{$module}->{SUPERGLUE_GETOPT} };
	}

	my %opt;
	Getopt::Long::Configure qw(posix_default gnu_getopt);
	GetOptions(\%opt, @opt) or exit 1;

	usage @_ if $opt{h};
	pod2usage -exit => 0, -verbose => 2 if $opt{help};

	# check that optional modules will work after construction
	$opt{$_} = 1 for @_;

	my $sg = eval { Superglue->new(%opt) };
	return $sg if $sg;

	$@ =~ s{ at \S+ line [0-9.]+$}{};
	print STDERR "$FindBin::Script: $@\n";
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
	handles => [@Superglue::Contact::SUPERGLUE_EXPORT],
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
	handles => [@Superglue::Delegation::SUPERGLUE_EXPORT],
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
	handles => {
		'login_check' => 'check',
		'auth_basic' => 'auth_basic',
	    },
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

	$args{delegation} = Superglue::Delegation->new(
		zone => $args{zone},
		file => $args{delegation},
	    ) if exists $args{delegation} and not ref $args{delegation};

	$args{login} = ReGPG::Login->new(
		filename => $args{login},
	    ) if exists $args{login} and not ref $args{login};

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
	auth_basic
	debug
	debug_f
	error
	error_f
	has_contact
	has_delegation
	login
	login_check
	verbose
	verbose_f
	warning
	warning_f
	zone
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

=item $sg->zone

The zone we are dealing with

=back

=head2 Login credentials

=over

=item $sg->login_check(@fields)

Handled by ReGPG::Login->check

Unlike most methods, this one is renamed by Superglue to be less
ambiguous in this context.

=item $sg->auth_basic(@fields)

Handled by ReGPG::Login->auth_basic

=back

=head2 Logging

The logging methods use the L<ScriptDie> package to print messages
to C<STDERR> prefixed by the name of the script.

=over

=item $sg->log($message, @objects)

Print the C<$message> unconditionally. In debug mode it is decorated
with a timestamp, otherwise it is decorated with the script name. The
objects are pretty-printed as JSON, after the header line containing
the message.

=cut

sub log {
	my $self = shift;
	my $message = shift;
	if ($self->{verbosity} < LOG_DEBUG) {
		print "$FindBin::Script: $message\n";
	} else {
		my ($seconds, $microseconds) = gettimeofday;
		my $stamp = strftime "%F %T", localtime $seconds;
		printf "%s.%03d %s\n", $stamp, $microseconds/1000, $message;
	}
	return unless @_;
	print to_json @_ > 1 ? [ @_ ] : $_[0],
	    { allow_nonref => 1, canonical => 1, pretty => 1 };
}

=item $sg->log_f($fmt, @args)

Print a message formatted using C<sprintf>

=cut

sub log_f {
	return shift->log(sprintf shift, @_);
}

=item $sg->debug($message, @json)

=item $sg->debug_f($message, @json)

Print the C<$message> if the verbosity is C<LOG_DEBUG>.

=cut

sub debug {
	my $self = shift;
	return $self->log(@_)
	    unless $self->{verbosity} < LOG_DEBUG;
}

sub debug_f {
	return shift->debug(sprintf shift, @_);
}

=item $sg->verbose($message)

=item $sg->verbose_f($message)

Print the C<$message> if the verbosity is C<LOG_INFO> or higher.

=cut

sub verbose {
	my $self = shift;
	return $self->log(@_)
	    unless $self->{verbosity} < LOG_INFO;
}

sub verbose_f {
	return shift->verbose(sprintf shift, @_);
}

=item $sg->warning($message)

=item $sg->warning_f($message)

Print the C<$message> if the verbosity is C<LOG_WARNING> or higher.

=cut

sub warning {
	my $self = shift;
	return $self->log(@_)
	    unless $self->{verbosity} < LOG_WARNING;
}

sub warning_f {
	return shift->warning(sprintf shift, @_);
}

=item $sg->error($message)

=item $sg->error_f($message)

Print the C<$message> and exits

=cut

sub error {
	shift->log(@_);
	exit 1;
}

sub error_f {
	return shift->error(sprintf shift, @_);
}

=back

=cut

1;
