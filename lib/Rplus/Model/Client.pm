package Rplus::Model::Client;

use strict;

use base qw(Rplus::DB::Object);

__PACKAGE__->meta->setup(
    table   => 'clients',

    columns => [
        id                       => { type => 'serial', not_null => 1 },
        name                     => { type => 'varchar', length => 64, remarks => 'Имя' },
        login                    => { type => 'varchar', length => 24, remarks => 'Логин' },
        password                 => { type => 'varchar', length => 32, remarks => 'Пароль' },
        phone_num                => { type => 'varchar', length => 10, not_null => 1, remarks => 'Основной номер телефона' },
        email                    => { type => 'varchar', length => 64, remarks => 'Email' },
        additional_phones        => { type => 'array', default => '{}', not_null => 1, remarks => 'Дополнительные телефоны' },
        metadata                 => { type => 'scalar', default => '{}', not_null => 1, remarks => 'Метаданные' },
        add_date                 => { type => 'timestamp with time zone', default => 'now()', not_null => 1, remarks => 'Дата/время добавления' },
        delete_date              => { type => 'timestamp with time zone', remarks => 'Дата/время удаления' },
        last_signin_date         => { type => 'timestamp with time zone', remarks => 'Дата/время последнего входа' },
        description              => { type => 'text', remarks => 'Дополнительная информация по клиенту' },
        send_owner_phone         => { type => 'boolean', default => 'false', not_null => 1, remarks => 'Отправлять в СМС номер собственника или нет' },
        skype                    => { type => 'varchar' },
        change_date              => { type => 'timestamp with time zone', default => 'now()', not_null => 1, remarks => 'дата изменения' },
        subscription_offer_types => { type => 'varchar', default => 'none', not_null => 1 },
        agent_id                 => { type => 'integer', remarks => 'идентификатор агента, занимающегося этим клиентом' },
        account_id               => { type => 'integer', not_null => 1 },
    ],

    primary_key_columns => [ 'id' ],

    allow_inline_column_values => 1,

    foreign_keys => [
        agent => {
            class       => 'Rplus::Model::User',
            key_columns => { agent_id => 'id' },
        },
    ],

    relationships => [
        client_color_tags => {
            class      => 'Rplus::Model::ClientColorTag',
            column_map => { id => 'client_id' },
            type       => 'one to many',
        },

        realty => {
            class      => 'Rplus::Model::Realty',
            column_map => { id => 'buyer_id' },
            type       => 'one to many',
        },

        realty_objs => {
            class      => 'Rplus::Model::Realty',
            column_map => { id => 'owner_id' },
            type       => 'one to many',
        },

        subscriptions => {
            class      => 'Rplus::Model::Subscription',
            column_map => { id => 'client_id' },
            type       => 'one to many',
        },
    ],
);

1;

