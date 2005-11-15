use strict;
use warnings;
use lib 'lib';
use Test::More tests => 8;

use_ok('File::Stream');
use File::Stream;

my $start = tell DATA;

my ($handler, $stream) = File::Stream->new(\*DATA, separator => ' ');
ok(ref($stream) eq 'FileHandle',
'object creation');

my $read = readline($stream);
ok($read eq 'thisisastream ', 'Literal separator');

$read = $handler->readline();
ok($read eq 'a ', 'Literal separator');

$handler->{separator} = qr/test\s+/;
$read = <$stream>;
ok($read eq 'test ', 'Regex separator');

seek DATA, $start, 0;
ok(
	eq_array(
		[$handler->find(qr/,\s*/, 'blah')],
		['stream', ', ']
	),
	'find()'
);

ok(
	eq_array(
		[$handler->find(qr/l+y\./, 'blah')],
		['actua', 'lly.']
	),
	'find()'
);

ok(
	eq_array(
		[$handler->find(qr/l+y\./, 'blah')],
		[' Blah ', 'blah']
	),
	'find()'
);

__DATA__
thisisastream a test stream, actually. Blah blah blah!
