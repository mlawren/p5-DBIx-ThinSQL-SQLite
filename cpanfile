on 'runtime' => sub {
    requires 'perl', '5.008001';
    requires 'DBD::SQLite';
    requires 'DBIx::ThinSQL', '0.0.8';
    requires 'Exporter::Tidy';
};

on 'test' => sub {
    requires 'File::chdir';
    requires 'Log::Any::Adapter';
    requires 'Path::Tiny';
    requires 'Test::Fatal';
    requires 'Test::More', '0.98';
};

