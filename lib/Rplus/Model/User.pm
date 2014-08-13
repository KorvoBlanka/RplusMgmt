package Rplus::Model::User;

use strict;

use base qw(Rplus::DB::Object);

__PACKAGE__->meta->setup(
    table   => 'users',

    columns => [
        id               => { type => 'serial', not_null => 1 },
        login            => { type => 'varchar', length => 16, not_null => 1, remarks => 'Логин' },
        password         => { type => 'varchar', not_null => 1, remarks => 'Пароль' },
        role             => { type => 'varchar', length => 10, not_null => 1, remarks => 'Роль в системе' },
        name             => { type => 'varchar', length => 64, not_null => 1, remarks => 'Имя' },
        phone_num        => { type => 'varchar', length => 10, remarks => 'Номер телефона' },
        description      => { type => 'text', remarks => 'Дополнительная информация' },
        metadata         => { type => 'scalar', default => '{}', not_null => 1, remarks => 'Метаданные' },
        add_date         => { type => 'timestamp with time zone', default => 'now()', not_null => 1, remarks => 'Дата/время добавления' },
        delete_date      => { type => 'timestamp with time zone', remarks => 'Дата/время удаления' },
        public_name      => { type => 'varchar', length => 64, remarks => 'Паблик имя' },
        public_phone_num => { type => 'varchar', length => 16, remarks => 'Паблик номер телефона' },
        permissions      => { type => 'scalar', default => '{}', not_null => 1, remarks => 'Локальные права пользователя' },
        ip_telephony     => { type => 'scalar', default => '{}', not_null => 1, remarks => 'sip телефония, хост, логин, пароль' },
        photo_url        => { type => 'varchar', remarks => 'путь к фото пользователя' },
        offer_mode       => { type => 'varchar', default => 'sale', not_null => 1 },
    ],

    primary_key_columns => [ 'id' ],

    allow_inline_column_values => 1,

    relationships => [
        clients => {
            class      => 'Rplus::Model::Client',
            column_map => { id => 'agent_id' },
            type       => 'one to many',
        },

        realty => {
            class      => 'Rplus::Model::Realty',
            column_map => { id => 'agent_id' },
            type       => 'one to many',
        },

        realty_objs => {
            class      => 'Rplus::Model::Realty',
            column_map => { id => 'creator_id' },
            type       => 'one to many',
        },

        subscriptions => {
            class      => 'Rplus::Model::Subscription',
            column_map => { id => 'user_id' },
            type       => 'one to many',
        },

        tasks => {
            class      => 'Rplus::Model::Task',
            column_map => { id => 'assigned_user_id' },
            type       => 'one to many',
        },

        tasks_objs => {
            class      => 'Rplus::Model::Task',
            column_map => { id => 'creator_id' },
            type       => 'one to many',
        },
    ],
);

1;

