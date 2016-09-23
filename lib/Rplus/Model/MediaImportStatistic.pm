package Rplus::Model::MediaImportStatistic;

use strict;

use base qw(Rplus::DB::Object);

__PACKAGE__->meta->setup(
    table   => 'media_import_statistic',

    columns => [
        id             => { type => 'serial', not_null => 1 },
        media_id       => { type => 'integer', not_null => 1, remarks => 'Источник СМИ' },
        add_date_start => { type => 'timestamp with time zone', not_null => 1, remarks => 'Дата/время последнего запуска импорта' },
        all_link       => { type => 'integer', not_null => 1, remarks => 'Кол-во ссылок для обработки' },
        new_ad         => { type => 'integer', not_null => 1, remarks => 'Кол-во новых объектов' },
        update_ad      => { type => 'integer', not_null => 1, remarks => 'Кол-во обновленных объектов' },
        errors_link    => { type => 'integer', not_null => 1, remarks => 'Кол-во ошибок при обработки' },
        add_date_end   => { type => 'timestamp with time zone', not_null => 1, remarks => 'Дата/время окончания импорта' },
        update_link    => { type => 'integer', not_null => 1, remarks => 'Кол-во обновленных ссылок' },
    ],

    primary_key_columns => [ 'id' ],

    foreign_keys => [
        media => {
            class       => 'Rplus::Model::Media',
            key_columns => { media_id => 'id' },
        },
    ],

    relationships => [
        media_import_errors => {
            class      => 'Rplus::Model::MediaImportError',
            column_map => { id => 'id_import_stat' },
            type       => 'one to many',
        },
    ],
);

1;

