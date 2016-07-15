package Rplus::Model::SubscriptionRealty;

use strict;

use base qw(Rplus::DB::Object);

__PACKAGE__->meta->setup(
    table   => 'subscription_realty',

    columns => [
        id              => { type => 'serial', not_null => 1 },
        subscription_id => { type => 'integer', not_null => 1, remarks => 'Подписка' },
        realty_id       => { type => 'integer', not_null => 1, remarks => 'Объект недвижимости' },
        metadata        => { type => 'scalar', default => '{}', not_null => 1, remarks => 'Метаданные' },
        add_date        => { type => 'timestamp with time zone', default => 'now()', not_null => 1, remarks => 'Дата/время добавления' },
        state_code      => { type => 'varchar', default => 'new', not_null => 1 },
        offered         => { type => 'boolean', default => 'false', not_null => 1 },
    ],

    primary_key_columns => [ 'id' ],

    allow_inline_column_values => 1,

    foreign_keys => [
        realty => {
            class       => 'Rplus::Model::Realty',
            key_columns => { realty_id => 'id' },
        },

        subscription => {
            class       => 'Rplus::Model::Subscription',
            key_columns => { subscription_id => 'id' },
        },
    ],
    relationships => [
        realty_color_tag => {
            class      => 'Rplus::Model::RealtyColorTag',
            column_map => { realty_id => 'realty_id' },
            type       => 'one to many',
        },
    ],
);

1;
