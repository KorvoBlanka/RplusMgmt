package Rplus::Model::QueryCache;

use strict;

use base qw(Rplus::DB::Object);

__PACKAGE__->meta->setup(
    table   => '_query_cache',

    columns => [
        id       => { type => 'serial', not_null => 1 },
        query    => { type => 'varchar', not_null => 1, remarks => 'Запрос' },
        add_date => { type => 'timestamp with time zone', default => 'now()', not_null => 1, remarks => 'Дата/время добавления' },
        params   => { type => 'scalar', not_null => 1, remarks => 'Распознанные параметры' },
    ],

    primary_key_columns => [ 'id' ],

    allow_inline_column_values => 1,
);

1;

