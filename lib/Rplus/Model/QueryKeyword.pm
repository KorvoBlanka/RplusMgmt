package Rplus::Model::QueryKeyword;

use strict;

use base qw(Rplus::DB::Object);

__PACKAGE__->meta->setup(
    table   => 'query_keywords',

    columns => [
        ftype => { type => 'varchar', length => 32, not_null => 1, remarks => 'Тип внешнего поля' },
        fkey  => { type => 'integer', not_null => 1, remarks => 'Внешний ключ' },
        fval  => { type => 'varchar', not_null => 1, remarks => 'Значение' },
        fts   => { type => 'scalar', remarks => 'Данные для полнотекстового поиска' },
    ],

    primary_key_columns => [ 'ftype', 'fkey', 'fval' ],

    unique_key => [ 'fkey', 'ftype', 'fval' ],
);

1;

