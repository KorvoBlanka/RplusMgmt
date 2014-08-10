package Rplus::Model::Tag;

use strict;

use base qw(Rplus::DB::Object);

__PACKAGE__->meta->setup(
    table   => 'tags',

    columns => [
        id          => { type => 'serial', not_null => 1 },
        name        => { type => 'varchar', length => 32, not_null => 1, remarks => 'Название' },
        keywords    => { type => 'varchar', length => 128, remarks => 'Ключевые слова' },
        metadata    => { type => 'scalar', default => '{}', not_null => 1, remarks => 'Метаданные' },
        add_date    => { type => 'timestamp with time zone', default => 'now()', not_null => 1, remarks => 'Дата/время добавления' },
        delete_date => { type => 'timestamp with time zone', remarks => 'Дата/время удаления' },
    ],

    primary_key_columns => [ 'id' ],

    allow_inline_column_values => 1,
);

1;

