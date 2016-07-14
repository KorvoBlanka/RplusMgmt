package Rplus::Model::MediaImportTask;

use strict;

use base qw(Rplus::DB::Object);

__PACKAGE__->meta->setup(
    table   => 'media_import_tasks',

    columns => [
        id          => { type => 'serial', not_null => 1 },
        source_name => { type => 'varchar', not_null => 1 },
        source_url  => { type => 'varchar', not_null => 1 },
        add_date    => { type => 'timestamp with time zone', default => 'now()', not_null => 1 },
        delete_date => { type => 'date' },
    ],

    primary_key_columns => [ 'id' ],

    allow_inline_column_values => 1,
);

1;

