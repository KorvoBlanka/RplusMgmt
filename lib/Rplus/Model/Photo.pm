package Rplus::Model::Photo;

use strict;

use base qw(Rplus::DB::Object);

__PACKAGE__->meta->setup(
    table   => 'photos',

    columns => [
        id                 => { type => 'serial', not_null => 1 },
        realty_id          => { type => 'integer', not_null => 1, remarks => 'Объект недвижимости' },
        filename           => { type => 'varchar', length => 128, not_null => 1, remarks => 'Имя файла с оригинальной фотографией' },
        thumbnail_filename => { type => 'varchar', length => 128, not_null => 1, remarks => 'Имя файла с миниатюрой' },
        is_main            => { type => 'boolean', default => 'false', not_null => 1, remarks => 'Фотография обложки или нет' },
        add_date           => { type => 'timestamp with time zone', default => 'now()', not_null => 1, remarks => 'Дата/время добавления' },
        delete_date        => { type => 'timestamp with time zone', remarks => 'Дата/время удаления' },
    ],

    primary_key_columns => [ 'id' ],

    allow_inline_column_values => 1,

    foreign_keys => [
        realty => {
            class       => 'Rplus::Model::Realty',
            key_columns => { realty_id => 'id' },
        },
    ],
);

1;

