package Rplus::Model::Media;

use strict;

use base qw(Rplus::DB::Object);

__PACKAGE__->meta->setup(
    table   => 'media',

    columns => [
        id          => { type => 'serial', not_null => 1 },
        name        => { type => 'varchar', length => 32, not_null => 1, remarks => 'Наименование СМИ (газеты, сайта и пр.)' },
        code        => { type => 'varchar', length => 32, not_null => 1, remarks => 'Уникальный код для данного типа' },
        type        => { type => 'varchar', length => 8, not_null => 1, remarks => 'Тип: import/export' },
        metadata    => { type => 'scalar', default => '{}', not_null => 1, remarks => 'Метаданные' },
        add_date    => { type => 'timestamp with time zone', default => 'now()', not_null => 1, remarks => 'Дата/время добавления' },
        delete_date => { type => 'timestamp with time zone', remarks => 'Дата/время удаления' },
        keywords    => { type => 'varchar', length => 128, remarks => 'Ключевые слова для поиска' },
    ],

    primary_key_columns => [ 'id' ],

    allow_inline_column_values => 1,

    relationships => [
        realty => {
            class      => 'Rplus::Model::Realty',
            column_map => { id => 'source_media_id' },
            type       => 'one to many',
        },
    ],
);

1;

