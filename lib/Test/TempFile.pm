package Test::TempFile;

use strictures 2;
use warnings;

use Exporter qw(import);
use File::Temp;
use Test::TempDir::Tiny;

our @EXPORT = qw{
	tempfile
};

our $tempdir = tempdir "tempfile";

# rely on Test::TempDir::Tiny to clean up files
$File::Temp::KEEP_ALL = 1;

sub tempfile {
	my $template = shift // 'XXXXXXXX';
	return File::Temp::tempfile(
		$template,
		DIR => $tempdir,
	    );
}
