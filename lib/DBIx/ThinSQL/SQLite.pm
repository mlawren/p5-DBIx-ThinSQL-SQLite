package DBIx::ThinSQL::SQLite;
use 5.008005;
use strict;
use warnings;
use Log::Any qw/$log/;
use Exporter::Tidy all =>
  [qw/create_sqlite_sequence create_functions create_methods/];

our $VERSION = "0.0.5";

my %sqlite_functions = (
    debug => sub {
        my $dbh = shift;

        $dbh->sqlite_create_function(
            'debug', -1,
            sub {
                if ( @_ && defined $_[0] && $_[0] =~ m/^\s*select/i ) {
                    $dbh->log_debug(@_);
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

sub create_sqlite_sequence {
    my $dbh = shift;

    local $dbh->{RaiseError} = 1;
    local $dbh->{PrintError} = 0;

    my $temp = '_temp' . join( '', map { int( rand($_) ) } 1000 .. 1005 );
    $dbh->do("CREATE TABLE $temp(x integer primary key autoincrement)");
    $dbh->do("DROP TABLE $temp");

    return;
}

sub _create_sequence {
    my $dbh = shift;
    my $name = shift || _croak('usage: create_sequence($name)');

    local $dbh->{RaiseError} = 1;
    local $dbh->{PrintError} = 0;

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
    $log->debug("INSERT INTO sqlite_sequence VALUES('$name',0)");
    $dbh->do( 'INSERT INTO sqlite_sequence(name,seq) VALUES(?,?)',
        undef, $name, 0 );
}

sub _currval {
    my $dbh = shift;
    my $name = shift || die 'usage: currval($name)';

    local $dbh->{RaiseError} = 1;
    local $dbh->{PrintError} = 0;

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

    local $dbh->{RaiseError} = 1;
    local $dbh->{PrintError} = 0;
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

sub create_functions {
    _croak('usage: create_functions($dbh,@functions)') unless @_ >= 2;

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
    create_sqlite_sequence => \&_create_sqlite_sequence,
    create_sequence        => \&_create_sequence,
    currval                => \&_currval,
    nextval                => \&_nextval,
);

sub create_methods {
    _croak('usage: create_methods(@methods)') unless @_ >= 1;

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

0.0.5 (2013-12-15) Development release.

=head1 SYNOPSIS

    use DBIx::ThinSQL;
    use DBIx::ThinSQL::SQLite
        qw/create_functions
           create_methods
           create_sqlite_sequence/;

    my $db = DBIx::ThinSQL->connect('dbi:SQLite:dbname=...');

    # Call once only to initialize permanently
    create_sqlite_sequence($db);

    # Call after every connect to the database
    create_functions( $db, qw/ debug create_sequence currval / );

    # Call once every program run
    create_methods(qw/create_sequence nextval/);

    # Then use SQL functions or Perl methods as required
    $db->do(q{ SELECT debug('logged via Log::Any->debug'); });
    $db->do(q{ SELECT create_sequence('name'); });
    $db->do(q{ SELECT nextval('name'); });
    $db->create_sequence('othername');
    $db->nextval('othername');

=head1 DESCRIPTION

B<DBIx::ThinSQL::SQLite> adds various functions to the SQL syntax
understood by SQLite, using the I<sqlite_create_function()> and
I<sqlite_create_aggregate_function()> methods of L<DBD::SQLite>. It
also adds sequence methods to L<DBIx::ThinSQL> database handles.

The following functions are exported on request:

=over

=item create_sqlite_sequence( $dbh )

Ensure that the C<sqlite_sequence> table exists.  This function must be
called on the database (once only - the changes are permanent) before
any of the other sequence related functions or methods will work.

This function works by creating (and dropping) a table with an
C<INTEGER PRIMARY KEY AUTOINCREMENT> definition. If you are using the
sequence support from this module you probably B<don't> want to be
creating your own tables with the autoincrement feature, as it may
clash with this module.

=item create_functions( $dbh, @functions )

Add C<@functions> to the SQL understood by SQLite for the database
handle C<$dbh>. C<@functions> can be any combination of the following:

=over

=item debug( @items )

This function called from SQL context logs C<@items> with a C<debug()>
call to a L<Log::Any> instance.  If the first item of C<@items> begins
with C</^select/i> then that statement will be run and the result
logged using C<log_debug> from L<DBIx::ThinSQL> instead.

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
You can have this happen automatically at connect time by taking
advantage of the L<DBI> C<Callbacks> attribute:

    my $db = DBI::ThinSQL->connect(
        $dsn, undef, undef,
        {
            Callbacks => {
                connected => sub {
                    my $dbh = shift;
                    create_functions( $dbh,
                        qw/debug nextval/ );
                  }
            },

        }
    );

=item create_methods( @methods )

Add C<@methods> to the DBIx::ThinSQL::db class which can be any
combination of the following:

=over

=item create_sequence( $name )

Create a sequence in the database with name $name.

=item nextval( $name ) -> Int

Advance the sequence to its next value and return that value.

=item currval( $name ) -> Int

Return the current value of the sequence.

=back

These methods are added to a Perl class and are therefore available to
any L<DBIx::ThinSQL> handle.

=back

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

