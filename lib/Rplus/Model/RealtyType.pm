package Rplus::Model::RealtyType;

use strict;

use base qw(Rplus::DB::Object);

__PACKAGE__->meta->setup(
    table   => 'realty_types',

    columns => [
        id            => { type => 'integer', not_null => 1 },
        category_code => { type => 'varchar', not_null => 1, remarks => 'Категория' },
        name          => { type => 'varchar', length => 32, not_null => 1, remarks => 'Название' },
        code          => { type => 'varchar', length => 32, not_null => 1, remarks => 'Код' },
        keywords      => { type => 'varchar', length => 128, remarks => 'Ключевые слова' },
        metadata      => { type => 'scalar', default => '{}', not_null => 1, remarks => 'Метаданные' },
    ],

    primary_key_columns => [ 'id' ],

    unique_key => [ 'code' ],

    foreign_keys => [
        category => {
            class       => 'Rplus::Model::RealtyCategory',
            key_columns => { category_code => 'code' },
        },
    ],

    relationships => [
        realty => {
            class      => 'Rplus::Model::Realty',
            column_map => { code => 'type_code' },
            type       => 'one to many',
        },
    ],
);

1;

