package Rplus::Model::Subscription;

use strict;

use base qw(Rplus::DB::Object);

__PACKAGE__->meta->setup(
    table   => 'subscriptions',

    columns => [
        id               => { type => 'serial', not_null => 1 },
        client_id        => { type => 'integer', not_null => 1, remarks => 'Клиент' },
        user_id          => { type => 'integer', remarks => 'Пользователь, подписавший клиента' },
        queries          => { type => 'array', not_null => 1, remarks => 'Запросы' },
        offer_type_code  => { type => 'varchar', length => 16, not_null => 1, remarks => 'Тип запроса (продажа/аренда)' },
        metadata         => { type => 'scalar', default => '{}', not_null => 1, remarks => 'Метаданные' },
        add_date         => { type => 'timestamp with time zone', default => 'now()', not_null => 1, remarks => 'Дата/время добавления' },
        end_date         => { type => 'timestamp with time zone', remarks => 'Дата/время окончания действия подписки (null - подписка не активна)' },
        delete_date      => { type => 'timestamp with time zone', remarks => 'Дата/время удаления' },
        last_check_date  => { type => 'timestamp with time zone', remarks => 'Дата/время последней проверки (поиска вариантов)' },
        realty_limit     => { type => 'integer', default => '0', not_null => 1, remarks => 'Ограничение макс. количества подобранных объектов недвижимости' },
        send_owner_phone => { type => 'boolean', default => 'false', not_null => 1, remarks => 'Отправлять в СМС номер собственника или нет' },
    ],

    primary_key_columns => [ 'id' ],

    allow_inline_column_values => 1,

    foreign_keys => [
        client => {
            class       => 'Rplus::Model::Client',
            key_columns => { client_id => 'id' },
        },

        offer_type => {
            class       => 'Rplus::Model::RealtyOfferType',
            key_columns => { offer_type_code => 'code' },
        },

        user => {
            class       => 'Rplus::Model::User',
            key_columns => { user_id => 'id' },
        },
    ],

    relationships => [
        subscription_realty => {
            class      => 'Rplus::Model::SubscriptionRealty',
            column_map => { id => 'subscription_id' },
            type       => 'one to many',
        },
    ],
);

1;

