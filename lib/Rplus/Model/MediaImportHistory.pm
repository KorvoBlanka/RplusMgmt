package Rplus::Model::MediaImportHistory;

use strict;

use base qw(Rplus::DB::Object);

__PACKAGE__->meta->setup(
    table   => 'media_import_history',

    columns => [
        id         => { type => 'serial', not_null => 1 },
        media_id   => { type => 'integer', not_null => 1, remarks => 'Источник СМИ' },
        media_num  => { type => 'varchar', length => 32, remarks => 'Номер, в котором вышло объявление' },
        media_text => { type => 'text', not_null => 1, remarks => 'Тест объявления' },
        realty_id  => { type => 'integer', not_null => 1, remarks => 'Связанный объект недвижимости' },
        add_date   => { type => 'timestamp with time zone', default => 'now()', not_null => 1, remarks => 'Дата/время добавления (импорта)' },
    ],

    primary_key_columns => [ 'id' ],

    unique_key => [ 'media_id', 'media_num', 'realty_id' ],

    allow_inline_column_values => 1,

    foreign_keys => [
        media => {
            class       => 'Rplus::Model::Media',
            key_columns => { media_id => 'id' },
        },
    ],
);

1;

