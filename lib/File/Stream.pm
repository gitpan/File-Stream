=head1 NAME

File::Stream - Regular expression delimited records from streams

=head1 SYNOPSIS

  use File::Stream;
  my $stream = File::Stream->new($filehandle);
  
  $/ = qr/\s*,\s*/;
  print "$_\n" while <$stream>;

  # or:
  ($handler, $stream) = File::Stream->new(
    $filehandle,
    read_length => 1024,
    separator => qr{to_be_used_instead_of_$/},
  );
  
  while(<$stream>) {...}
  my $line = $stream->readline(); # similar
  
  # extended usage:
  use URI;
  my $uri = URI->new('http://steffen-mueller.net');
  my ($pre_match, $match) =
    $handler->find('literal_string', qr/regex/, $uri);
  
  # $match contains whichever argument to find() was found first.
  # $pre_match contains all that was before the first token that was found.
  # both the contents of $match and $pre_match have been removed from the
  # data stream (buffer).

=head1 DESCRIPTION

Perl filehandles are streams, but sometimes they just aren't powerful enough.
This module offers to have streams from filehandles searched with regexes
and allows the global input record separator variable to contain regexes.

Thus, readline() and the <> operator can now return records delimited
by regular expression matches.

There are some very important gripes with applying regular expressions to
(possibly infinite) streams. Please read the CAVEATS section of this
documentation carfully.

=head2 EXPORT

None.

=cut

package File::Stream;

use 5.006;
use strict;
use warnings;

use FileHandle;
use Carp;

our $VERSION = '1.00';

=head2 new

The new() constructor takes a filehandle (or a glob reference) as first
argument. The following arguments are interpreted as key/value pairs with
the following parameters being defined:

=over 4

=item separator

This may be set to either a string, a compiled regular expression (qr//), or
an object which is overloaded in stringification context to return a string.

If separator is set, its value will be used in calls to readline() (including
the <> diamond operator which calls readline internally) instead of $/,
the global input record separator.

String will be interpreted as literal strings, not regular expressions.

=item read_length

Defaults to 1024 bytes. Sets the number of bytes to read into the internal
buffer at once. Large values may speed up searching considerably, but
increase memory usage.

=back

The new() method returns a fresh File::Stream object that has been tied to
be a filehandle and a filehandle. All the usual file operations should work
on the filehandle and the File::Stream methods should work on the object.

=cut

sub new {
    my $proto = shift;
    my $class = ref($proto) || $proto;

    my $filehandle = new FileHandle;
    my $handler = tie *$filehandle => $class, @_;
    return ($handler, $filehandle);
}

=head2 readline

The readline method on a File::Stream object works just like the
builtin except that it uses the objects record separator instead
of $/ if it has been set via new() and honours regular expressions.

This is also internally used when readline() is called on the tied
filehandle.

=cut

sub readline {
    my $self      = shift;
    my $separator = $self->{separator};
    $separator = $/ if not defined $separator;
    my ( $pre_match, $match ) = $self->find($separator);
    if (not defined $pre_match) {
        my $buf = $self->{buffer};
        $self->{buffer} = '';
        return undef if $buf eq '';
        return $buf;
    }
    return $pre_match . $match;
}


=head2 find

Finds the first occurrance one of its arguments in the stream. For example,

  $stream_handler->find('a', 'b');

finds the first character 'a' or 'b' in the stream whichever comes first.
Returns two strings: The data read from the stream I<before> the match
and the match itself. The arguments to find() may be regular expressions,
but please see the CAVEATS section of this documentation about that.
If any of the arguments is an object, it will be evaluated in stringification
context and the result of that will be matched I<literally>, ie. not as a
regular expression.

As with readline(), this is a method on the stream handler object.

=cut

sub find {
    my $self         = shift;
    my @terms        = @_;
    my @regex_tokens =
      map {
        if ( not ref($_) )
        {
            qr/\Q$_\E/;
        }
        elsif ( ref($_) eq 'Regexp' ) {
            $_;
        }
        else {
            my $string = "$_";
            qr/\Q$string\E/;
        }
      } @terms;
    my $re = '(' . join( ')|(', @regex_tokens ) . ')';
    my $compiled = qr/$re/s;
    while (1) {
        my @matches = $self->{buffer} =~ $compiled;
        if ( not @matches ) {
            return undef unless $self->fill_buffer();
            next;
        }
        else {
            my $index = undef;
            for ( 0 .. $#matches ) {
                $index = $_, last if defined $matches[$_];
            }
            die if not defined $index;    # sanity check
            my $match = $matches[$index];
            $self->{buffer} =~ s/^(.*?)\Q$match\E//s or die;
            return ( $1, $match );
        }
    }
}

=head2 fill_buffer

It is unlikely that you will need to call this method directly.
Reads more data from the internal filehandle into the buffer.
First argument may be the number of bytes to read, otherwise the
'read_length' attribute is used.

Again, call this on the handler object, not the file handle.

=cut

sub fill_buffer {
    my $self = shift;
    my $length = shift || $self->{read_length};
    my $data;
    my $bytes = read( $self->{fh}, $data, $length );
    return 0 if not $bytes;
    $self->{buffer} .= $data;
    return $bytes;
}

sub TIEHANDLE {
    my $class = shift;
    my $fh    = shift;
    my $self  = {
        fh          => $fh,
        read_length => 1024,
        separator   => undef,
        buffer      => '',
        @_
    };
    bless $self => $class;
}

sub READLINE { goto &readline; }

sub PRINT {
    my $self = shift;
    my $buf = join( defined $, ? $, : "", @_ );
    $buf .= $\ if defined $\;
    $self->WRITE( $buf, length($buf), 0 );
}

sub PRINTF {
    my $self = shift;

    my $buf = sprintf( shift, @_ );
    $self->WRITE( $buf, length($buf), 0 );
}

sub GETC {
    my $self = shift;

    my $buf;
    $self->READ( $buf, 1 );
    return $buf;
}

sub READ {
    croak if @_ < 3;
    my $self   = shift;
    my $bufref = \$_[0];
    $$bufref = '' if not defined $$bufref;
    my ( undef, $len, $offset ) = @_;
    $offset = 0 if not defined $offset;
    if ( length $self->{buffer} < $len ) {
        my $bytes = 0;
        while ( $bytes = $self->fill_buffer()
            and length( $self->{buffer} ) < $len )
        {
        }

        if ( not $bytes ) {
            my $length_avail = length( $self->{buffer} );
            substr( $$bufref, $offset, $length_avail,
                substr( $self->{buffer}, 0, $length_avail, '' ) );
            return $length_avail;
        }
        # only reached if buffer long enough.
    }
    substr( $$bufref, $offset, $len, substr( $self->{buffer}, 0, $len, '' ) );
    return $len;
}

sub WRITE {
    my $self = $_[0];
    my $fh   = $self->{fh};
    print $fh substr( $_[1], 0, $_[2] );
}


sub TELL   { croak "tell() not implemented for File::Stream objects." }
sub SEEK   { croak "seek() not implemented for File::Stream objects." }

sub EOF { not length( $_[0]->{buffer} ) and eof( *{$_[0]->{fh}} ) }
sub FILENO { fileno( *{ $_[0]->{fh} } ) }
sub BINMODE { binmode( *{ $_[0]->{fh} }, @_ ) }

sub CLOSE   { close( *{ $_[0]->{fh} } ) }
sub UNTIE   { close( *{ $_[0]->{fh} } ) }
sub DESTROY { close( *{ $_[0]->{fh} } ) }


1;
__END__

=head1 CAVEATS

There are several important issues to keep in mind when using this module.
First, setting $/ to a regular expression will most certainly break badly
when $/ is used on filehandles that are not File::Stream object.
Please consider setting the "separator" attribute of the File::Stream object
instead for a more robust solution.

Most importantly, however, there are some inherent problems with regular
expressions applied to (possibly infinite) streams. The implementation of
Perl's regular expression engine requires that the string you apply a regular
expression to be in memory completely. That means applying a regular
expression that matches infinitely long strings (like .*) to a stream will
lead to the module reading in the whole file, or worse yet, an infinite
string. B<So don't do that!>

=head1 AUTHOR

Steffen Mueller, E<lt>stream-module at steffen-mueller dot netE<gt>

Many thanks to Simon Cozens for his advice and the original idea.

=head1 SEE ALSO

L<perltie>, L<Tie::Handle>, L<perlre>

=cut
