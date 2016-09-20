package Rplus::Model::MediaImportError;

use strict;

use base qw(Rplus::DB::Object);

__PACKAGE__->meta->setup(
    table   => 'media_import_errors',

    columns => [
        id_import_stat => { type => 'integer', not_null => 1 },
        url            => { type => 'varchar', length => 2044, not_null => 1 },
        error_text     => { type => 'varchar', length => 2044, not_null => 1 },
        id             => { type => 'serial', not_null => 1 },
    ],

    primary_key_columns => [ 'id' ],

    foreign_keys => [
        media_import_statistic => {
            class       => 'Rplus::Model::MediaImportStatistic',
            key_columns => { id_import_stat => 'id' },
        },
    ],
);

1;

