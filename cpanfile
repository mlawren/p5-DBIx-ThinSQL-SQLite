requires 'perl', '5.008001';
requires 'DBD::SQLite';
requires 'DBIx::ThinSQL';
requires 'Exporter::Tidy';

on 'test' => sub {
    requires 'File::chdir', 0;
    requires 'Log::Any::Adapter', 0;
    requires 'Path::Tiny', 0;
    requires 'Test::Fatal', 0;
    requires 'Test::More', '0.98';
};

