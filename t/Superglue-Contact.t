#!/usr/bin/perl

use strictures 2;
use warnings;

use FindBin;
use lib "$FindBin::Bin/../lib";

use Test::Exception;
use Test::More;

require_ok('Superglue::Contact');

throws_ok {
	Superglue::Contact->new({ unknown => 'value' });
} qr{unknown contact field}, 'unknown contact field';

throws_ok {
	Superglue::Contact->new({
		name => "First Last",
		Name => "Given Family",
	});
} qr{conflicting values}, 'unknown contact field';

throws_ok {
	Superglue::Contact->new({
		name => "First Last",
		Given => "Given",
		Family => "Family",
	});
} qr{conflicting values}, 'unknown contact field';

my $c;

lives_ok {
	$c = Superglue::Contact->new({
		name => "First Last",
	});
} 'loaded simple name';

is $c->get('Name'), "First Last", 'title case';
is $c->get('NAME'), "First Last", 'upper case';
is $c->get('first'), "First", 'split name (first)';
is $c->get('last'), "Last", 'split name (last)';

lives_ok {
	$c = Superglue::Contact->new({
		Given => "Given",
		Family => "Family",
	});
} 'loaded split name';

is $c->get('name'), "Given Family", 'joined name';

done_testing;

exit;
