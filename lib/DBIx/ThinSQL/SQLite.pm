package DBIx::ThinSQL::SQLite;
use 5.008005;
use strict;
use warnings;
use Log::Any qw/$log/;
use Exporter::Tidy all => [
    qw/sqlite_create_functions
      thinsql_create_methods/
];

our $VERSION = "0.0.3_1";

my %sqlite_functions = (
    debug => sub {
        my $dbh = shift;

        $dbh->sqlite_create_function(
            'debug', -1,
            sub {
                if ( @_ && defined $_[0] && $_[0] =~ m/^\s*select/i ) {
                    my $sql = shift;
                    my $sth = $dbh->prepare($sql);
                    $sth->execute(@_);
                    $log->debug(
                        $sql . "\n"
                          . join( "\n",
                            map { DBI::neat_list($_) }
                              @{ $sth->fetchall_arrayref } )
                    );
                }
                else {
                    $log->debug(
                        join( ' ', map { defined $_ ? $_ : 'NULL' } @_ ) );
                }
            }
        );
    },
    create_sequence => sub {
        my $dbh = shift;
        $dbh->sqlite_create_function( 'create_sequence', 1,
            sub { _create_sequence( $dbh, @_ ) } );
    },
    currval => sub {
        my $dbh = shift;
        $dbh->sqlite_create_function( 'currval', 1,
            sub { _currval( $dbh, @_ ) } );
    },
    nextval => sub {
        my $dbh = shift;
        $dbh->sqlite_create_function( 'nextval', 1,
            sub { _nextval( $dbh, @_ ) } );
    },
    sha1 => sub {
        require Digest::SHA;
        my $dbh = shift;
        $dbh->sqlite_create_function(
            'sha1', -1,
            sub {
                Digest::SHA::sha1(
                    map { utf8::is_utf8($_) ? Encode::encode_utf8($_) : $_ }
                    grep { defined $_ } @_
                );
            }
        );
    },
    sha1_hex => sub {
        require Digest::SHA;
        my $dbh = shift;
        $dbh->sqlite_create_function(
            'sha1_hex',
            -1,
            sub {
                Digest::SHA::sha1_hex(
                    map { utf8::is_utf8($_) ? Encode::encode_utf8($_) : $_ }
                    grep { defined $_ } @_
                );
            }
        );
    },
    sha1_base64 => sub {
        require Digest::SHA;
        my $dbh = shift;
        $dbh->sqlite_create_function(
            'sha1_base64',
            -1,
            sub {
                Digest::SHA::sha1_base64(
                    map { utf8::is_utf8($_) ? Encode::encode_utf8($_) : $_ }
                    grep { defined $_ } @_
                );
            }
        );
    },
    agg_sha1 => sub {
        require Digest::SHA;
        my $dbh = shift;
        $dbh->sqlite_create_aggregate( 'agg_sha1', -1,
            'DBIx::ThinSQL::SQLite::agg_sha1' );
    },
    agg_sha1_hex => sub {
        require Digest::SHA;
        my $dbh = shift;
        $dbh->sqlite_create_aggregate( 'agg_sha1_hex', -1,
            'DBIx::ThinSQL::SQLite::agg_sha1_hex' );
    },
    agg_sha1_base64 => sub {
        require Digest::SHA;
        my $dbh = shift;
        $dbh->sqlite_create_aggregate( 'agg_sha1_base64', -1,
            'DBIx::ThinSQL::SQLite::agg_sha1_base64' );
    },
);

sub _croak { require Carp; goto &Carp::croak }

sub _create_sequence {
    my $dbh = shift;
    my $name = shift || _croak('usage: create_sequence($name)');

    # The sqlite_sequence table doesn't exist until an
    # autoincrement table has been created.
    # IF NOT EXISTS is used because table_info may not return any
    # information if we are inside a transaction where the first
    # sequence was created
    if ( !$dbh->selectrow_array('PRAGMA table_info(sqlite_sequence)') ) {
        $dbh->do( 'CREATE TABLE IF NOT EXISTS '
              . 'Ekag4iiB(x integer primary key autoincrement)' );
        $dbh->do('DROP TABLE IF EXISTS Ekag4iiB');
    }

    # the sqlite_sequence table doesn't have any constraints so it
    # would be possible to insert the same sequence twice. Check if
    # one already exists
    my ($val) = (
        $dbh->selectrow_array(
            'SELECT seq FROM sqlite_sequence WHERE name = ?',
            undef, $name
        )
    );
    $val && _croak("create_sequence: sequence already exists: $name");
    $dbh->do( 'INSERT INTO sqlite_sequence(name,seq) VALUES(?,?)',
        undef, $name, 0 );
}

sub _currval {
    my $dbh = shift;
    my $name = shift || die 'usage: currval($name)';

    my ($val) = (
        $dbh->selectrow_array(
            'SELECT seq FROM sqlite_sequence WHERE name = ?',
            undef, $name
        )
    );

    if ( defined $val ) {
        $log->debug( "currval('$name') -> " . $val );
        return $val;
    }

    _croak("currval: unknown sequence: $name");
}

sub _nextval {
    my $dbh = shift;
    my $name = shift || die 'usage: nextval($name)';

    my $val;

    my $i = 0;
    while (1) {
        _croak 'could not obtain nextval' if $i++ > 10;

        my ($current) = (
            $dbh->selectrow_array(
                'SELECT seq FROM sqlite_sequence WHERE name = ?', undef,
                $name
            )
        );
        _croak("nextval: unknown sequence: $name") unless defined $current;

        next
          unless $dbh->do(
            'UPDATE sqlite_sequence SET seq = ? '
              . 'WHERE name = ? AND seq = ?',
            undef, $current + 1, $name, $current
          );

        $log->debug( "nextval('$name') -> " . ( $current + 1 ) );

        return $current + 1;
    }
}

sub sqlite_create_functions {
    _croak('usage: sqlite_create_functions($dbh,@functions)') unless @_ >= 2;

    my $dbh = shift;
    _croak('handle has no sqlite_create_function!')
      unless eval { $dbh->can('sqlite_create_function') };

    foreach my $name (@_) {
        my $subref = $sqlite_functions{$name};
        _croak( 'unknown function: ' . $name ) unless $subref;
        $subref->($dbh);
    }
}

my %thinsql_methods = (
    create_sequence => \&_create_sequence,
    currval         => \&_currval,
    nextval         => \&_nextval,
);

sub thinsql_create_methods {
    _croak('usage: thinsql_create_methods(@methods)') unless @_ >= 1;

    foreach my $name (@_) {
        my $subref = $thinsql_methods{$name};
        _croak( 'unknown method: ' . $name ) unless $subref;

        no strict 'refs';
        *{ 'DBIx::ThinSQL::db::' . $name } = $subref;
    }
}

package DBIx::ThinSQL::SQLite::agg_sha1;
our @ISA = ('Digest::SHA');

sub step {
    my $self = shift;
    $self->add(
        map { utf8::is_utf8($_) ? Encode::encode_utf8($_) : $_ }
        grep { defined $_ } @_
    );
}

sub finalize {
    $_[0]->digest;
}

package DBIx::ThinSQL::SQLite::agg_sha1_hex;
our @ISA = ('DBIx::ThinSQL::SQLite::agg_sha1');

sub finalize {
    $_[0]->hexdigest;
}

package DBIx::ThinSQL::SQLite::agg_sha1_base64;
our @ISA = ('DBIx::ThinSQL::SQLite::agg_sha1');

sub finalize {
    $_[0]->b64digest;
}

1;
__END__

=encoding utf-8

=head1 NAME

DBIx::ThinSQL::SQLite - add various functions to SQLite

=head1 VERSION

0.0.3_1 Development release.

=head1 SYNOPSIS

    use DBI;
    use DBIx::ThinSQL::SQLite
        qw/sqlite_create_functions thinsql_create_methods/;

    # Add functions on connect

    my $db = DBI->connect(
        $dsn, undef, undef,
        {
            Callbacks => {
                connected => sub {
                    my $dbh = shift;
                    sqlite_create_functions( $dbh,
                        qw/debug nextval/ );
                  }
            },

        }
    );

    # Or manually at any time
    sqlite_create_functions( $db, qw/currval/ );

    # Then in your SQL you can use those functions

    $db->do(q{
        SELECT debug('logged via Log::Any->debug');
    });

    $db->do(q{
        SELECT create_sequence('name');
    });

    $db->do(q{
        SELECT nextval('name');
    });

    # If you are using DBIx::ThinSQL instead of DBI
    # you can also use the sequence functions as methods

    thinsql_create_methods(qw/create_sequence nextval/);

    $db->create_sequence('othername');
    $db->nextval('othername');

=head1 DESCRIPTION

B<DBIx::ThinSQL::SQLite> adds various functions to the SQL syntax
understood by SQLite, using the I<sqlite_create_function()> and
I<sqlite_create_aggregate_function()> methods of L<DBD::SQLite>. It
also adds sequence methods to your database handles when you are using
L<DBIx::ThinSQL>.

Two functions are exported on request:

=over

=item sqlite_create_functions( $dbh, @functions )

Add C<@functions> to the SQL understood by SQLite for the database
handle C<$dbh>, which can be any combination of the following.

=over

=item debug( @items )

This function called from SQL context results in a C<debug()> call to a
L<Log::Any> instance. If the first item of C<@items> begins with
C</^select/i> then that statement will be run and the result included
in the output as well.

=item create_sequence( $name )

Create a sequence in the database with name $name.

=item nextval( $name ) -> Int

Advance the sequence to its next value and return that value.

=item currval( $name ) -> Int

Return the current value of the sequence.

=back

If L<Digest::SHA> is installed then the following functions can also be
created.

=over

=item sha1( @args ) -> bytes

Calculate the SHA digest of all arguments concatenated together and
return it in a 20-byte binary form. Unfortunately it seems that the
underlying SQLite C sqlite_create_function() provides no way to
identify the result as a blob, so you must always manually cast the
result in SQL like so:

    CAST(sha1(SQLITE_EXPRESSION) AS blob)

=item sha1_hex( @args ) -> hexidecimal

Calculate the SQLite digest of all arguments concatenated together and
return it in a 40-character hexidecimal form.

=item sha1_base64( @args ) -> base64

Calculate the SQLite digest of all arguments concatenated together and
return it in a base64 encoded form.

=item agg_sha1( @args ) -> bytes

=item agg_sha1_hex( @args ) -> hexidecimal

=item agg_sha1_base64( @args ) -> base64

These aggregate functions are for use with statements using GROUP BY.

=back

Note that user-defined SQLite functions are only valid for the current
session.  They must be created each time you connect to the database.

=item thinsql_create_methods( @methods )

Add C<@methods> to the DBIx::ThinSQL::db class which can be any
combination of the following.

=over

=item create_sequence( $name )

Create a sequence in the database with name $name.

=item nextval( $name ) -> Int

Advance the sequence to its next value and return that value.

=item currval( $name ) -> Int

Return the current value of the sequence.

=back

The methods are added to a Perl class and are therefore available to
any L<DBIx::ThinSQL> handle.

=back

=head1 CAVEATS

An "autoincrement" integer primary key column in SQLite automatically
creates a sequence for that table, which is incompatible with this
module. Keep the two sequence types separate.

=head1 SEE ALSO

L<Log::Any>

=head1 AUTHOR

Mark Lawrence E<lt>nomad@null.netE<gt>

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2013 Mark Lawrence <nomad@null.net>

This program is free software; you can redistribute it and/or modify it
under the terms of the GNU General Public License as published by the
Free Software Foundation; either version 3 of the License, or (at your
option) any later version.

