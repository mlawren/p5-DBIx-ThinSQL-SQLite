# NAME

DBIx::ThinSQL::SQLite - add various functions to SQLite

# VERSION

0.0.4 (2013-06-11) Development release.

# SYNOPSIS

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

# DESCRIPTION

__DBIx::ThinSQL::SQLite__ adds various functions to the SQL syntax
understood by SQLite, using the _sqlite\_create\_function()_ and
_sqlite\_create\_aggregate\_function()_ methods of [DBD::SQLite](http://search.cpan.org/perldoc?DBD::SQLite). It
also adds sequence methods to [DBIx::ThinSQL](http://search.cpan.org/perldoc?DBIx::ThinSQL) database handles.

The following functions are exported on request:

- create\_sqlite\_sequence( $dbh )

    Ensure that the `sqlite_sequence` table exists.  This function must be
    called on the database (once only - the changes are permanent) before
    any of the other sequence related functions or methods will work.

    This function works by creating (and dropping) a table with an
    `INTEGER PRIMARY KEY AUTOINCREMENT` definition. If you are using the
    sequence support from this module you probably __don't__ want to be
    creating your own tables with the autoincrement feature, as it may
    clash with this module.

- create\_functions( $dbh, @functions )

    Add `@functions` to the SQL understood by SQLite for the database
    handle `$dbh`. `@functions` can be any combination of the following:

    - debug( @items )

        This function called from SQL context logs `@items` with a `debug()`
        call to a [Log::Any](http://search.cpan.org/perldoc?Log::Any) instance.  If the first item of `@items` begins
        with `/^select/i` then that statement will be run and the result
        logged using `log_debug` from [DBIx::ThinSQL](http://search.cpan.org/perldoc?DBIx::ThinSQL) instead.

    - create\_sequence( $name )

        Create a sequence in the database with name $name.

    - nextval( $name ) -> Int

        Advance the sequence to its next value and return that value.

    - currval( $name ) -> Int

        Return the current value of the sequence.

    If [Digest::SHA](http://search.cpan.org/perldoc?Digest::SHA) is installed then the following functions can also be
    created.

    - sha1( @args ) -> bytes

        Calculate the SHA digest of all arguments concatenated together and
        return it in a 20-byte binary form. Unfortunately it seems that the
        underlying SQLite C sqlite\_create\_function() provides no way to
        identify the result as a blob, so you must always manually cast the
        result in SQL like so:

            CAST(sha1(SQLITE_EXPRESSION) AS blob)

    - sha1\_hex( @args ) -> hexidecimal

        Calculate the SQLite digest of all arguments concatenated together and
        return it in a 40-character hexidecimal form.

    - sha1\_base64( @args ) -> base64

        Calculate the SQLite digest of all arguments concatenated together and
        return it in a base64 encoded form.

    - agg\_sha1( @args ) -> bytes
    - agg\_sha1\_hex( @args ) -> hexidecimal
    - agg\_sha1\_base64( @args ) -> base64

        These aggregate functions are for use with statements using GROUP BY.

    Note that user-defined SQLite functions are only valid for the current
    session.  They must be created each time you connect to the database.
    You can have this happen automatically at connect time by taking
    advantage of the [DBI](http://search.cpan.org/perldoc?DBI) `Callbacks` attribute:

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

- create\_methods( @methods )

    Add `@methods` to the DBIx::ThinSQL::db class which can be any
    combination of the following:

    - create\_sequence( $name )

        Create a sequence in the database with name $name.

    - nextval( $name ) -> Int

        Advance the sequence to its next value and return that value.

    - currval( $name ) -> Int

        Return the current value of the sequence.

    These methods are added to a Perl class and are therefore available to
    any [DBIx::ThinSQL](http://search.cpan.org/perldoc?DBIx::ThinSQL) handle.

# SEE ALSO

[Log::Any](http://search.cpan.org/perldoc?Log::Any)

# AUTHOR

Mark Lawrence <nomad@null.net>

# COPYRIGHT AND LICENSE

Copyright (C) 2013 Mark Lawrence <nomad@null.net>

This program is free software; you can redistribute it and/or modify it
under the terms of the GNU General Public License as published by the
Free Software Foundation; either version 3 of the License, or (at your
option) any later version.
