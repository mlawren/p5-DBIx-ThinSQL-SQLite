use strict;
use warnings;
use DBIx::ThinSQL;
use DBIx::ThinSQL::SQLite qw/sqlite_create_functions thinsql_create_methods/;
use File::chdir;
use Log::Any::Adapter;
use Path::Tiny;
use Test::Fatal qw/exception/;
use Test::More;

sub run_in_tempdir (&) {
    my $sub = shift;
    my $cwd = $CWD;
    my $tmp = Path::Tiny->tempdir( CLEANUP => 1 );

    local $CWD = $tmp;
    $sub->();

    $CWD = $cwd;
}

subtest "sqlite_create_functions", sub {
    isa_ok \&sqlite_create_functions, 'CODE';

    run_in_tempdir {
        my $logfile = path('log.txt');
        Log::Any::Adapter->set( 'File', $logfile );

        my $db = DBIx::ThinSQL->connect( 'dbi:SQLite:dbname=test.sqlite3',
            undef, undef, { RaiseError => 1, PrintError => 0 } );

        my @funcs = (
            qw/debug create_sequence currval nextval sha1
              sha1_hex sha1_base64 agg_sha1 agg_sha1_hex agg_sha1_base64/
        );
        foreach my $func (@funcs) {
            ok exception { $db->do("select $func()") },
              "no existing func $func";
        }

        like exception { sqlite_create_functions() }, qr/usage:/, 'usage';

        like exception { sqlite_create_functions( 1, 2 ) },
          qr/handle has no sqlite_create_function/,
          'usage no handle';

        like exception { sqlite_create_functions( $db, 'unknown' ) },
          qr/unknown function/,
          'unknown function';

        sqlite_create_functions( $db, qw/debug/ );
        my $str = 'RaNdOm';    # just a random string
        $db->do("select debug('$str')");

        my $log = $logfile->slurp;
        like $log, qr/$str/, 'debug logged to Log::Any';

        $db->do(q{select debug("select 1 || 2 || 1 || 4")});
        $log = $logfile->slurp;
        like $log, qr/select.*1214/s, 'debug select';

        sqlite_create_functions( $db, qw/create_sequence currval nextval/ );

        like exception { $db->selectrow_array("select nextval('testseq')") },
          qr/unknown sequence/, 'seq not found';

        $db->do(q{select create_sequence('testseq')});

        my ($res) = $db->selectrow_array(q{select currval('testseq')});
        is $res, 0, 'currval';

        ($res) = $db->selectrow_array(q{select nextval('testseq')});
        is $res, 1, 'nextval';

        ($res) = $db->selectrow_array(q{select currval('testseq')});
        is $res, 1, 'currval again';

        ($res) = $db->selectrow_array(q{select nextval('testseq')});
        is $res, 2, 'nextval';

        ($res) = $db->selectrow_array(q{select currval('testseq')});
        is $res, 2, 'currval again';

      SKIP: {
            plan skip_all => 'require Digest::SHA for sha functions'
              unless eval { require Digest::SHA };

            sqlite_create_functions( $db, qw/sha1 sha1_hex sha1_base64/ );

            $db->do(<<_ENDSQL_);
CREATE TABLE x(
    val varchar NOT NULL PRIMARY KEY,
    sbytes blob,
    shex char(40),
    sbase64 varchar
);
_ENDSQL_

            $db->do(<<_ENDSQL_);
CREATE TRIGGER trigx AFTER INSERT ON x
FOR EACH ROW
BEGIN
    UPDATE
        x
    SET
        sbytes = CAST(sha1(NEW.val) AS BLOB),
        shex = sha1_hex(NEW.val),
        sbase64 = sha1_base64(NEW.val)
    WHERE
        val = NEW.val
    ;
END;
_ENDSQL_

            $db->do(<<_ENDSQL_);
INSERT INTO x(val) VALUES(1);
_ENDSQL_

            my $sha1        = Digest::SHA::sha1(1);
            my $sha1_hex    = Digest::SHA::sha1_hex(1);
            my $sha1_base64 = Digest::SHA::sha1_base64(1);

            my ( $bytes, $hex, $base64 ) = $db->selectrow_array(
                q{
                select sbytes,shex,sbase64 from x where val=1    
            }
            );

            is $bytes,  $sha1,        'sha1';
            is $hex,    $sha1_hex,    'sha1_hex';
            is $base64, $sha1_base64, 'sha1_base64';
        }
    };
};

subtest "thinsql_create_methods", sub {
    isa_ok \&thinsql_create_methods, 'CODE';

    run_in_tempdir {
        my $db = DBIx::ThinSQL->connect( 'dbi:SQLite:dbname=test.sqlite3',
            undef, undef, { RaiseError => 1, PrintError => 0 } );

        my @methods = (qw/create_sequence currval nextval/);
        foreach my $method (@methods) {
            ok !$db->can($method), "no existing method $method";
        }

        like exception { thinsql_create_methods('unknown') },
          qr/unknown method/,
          'unknown method';

        thinsql_create_methods(qw/create_sequence currval nextval/);

        $db->create_sequence('testseq');

        my $res = $db->currval('testseq');
        is $res, 0, 'currval';

        $res = $db->nextval('testseq');
        is $res, 1, 'nextval';

        $res = $db->currval('testseq');
        is $res, 1, 'currval again';

        $res = $db->currval('testseq');
        is $res, 1, 'currval again';

        sqlite_create_functions( $db, qw/currval/ );

        ($res) = $db->selectrow_array(q{select currval('testseq')});
        is $res, 1, 'method/function match';

        # Can only test this after sqlite_sequence has already been created
        like exception { $db->nextval('unknown') },
          qr/unknown sequence/, 'nextval seq not found';

        like exception { $db->currval('unknown') },
          qr/unknown sequence/, 'currval seq not found';

    };
};

done_testing();
