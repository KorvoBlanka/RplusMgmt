package Rplus::Model::DictColorTag;

use strict;

use base qw(Rplus::DB::Object);

__PACKAGE__->meta->setup(
    table   => 'dict_color_tags',

    columns => [
        id           => { type => 'serial', not_null => 1 },
        name         => { type => 'varchar', length => 12, not_null => 1, remarks => 'имя тега для отображения пользователю' },
        color        => { type => 'varchar', length => 6, not_null => 1, remarks => 'цвет тега' },
        border_color => { type => 'varchar', default => 'c8c8c8', length => 6, not_null => 1, remarks => 'цвет окантовки тега' },
        add_date     => { type => 'timestamp with time zone', default => 'now()', not_null => 1, remarks => 'Дата/время добавления' },
        delete_date  => { type => 'timestamp with time zone', remarks => 'Дата/время удаления' },
    ],

    primary_key_columns => [ 'id' ],

    allow_inline_column_values => 1,
);

1;

