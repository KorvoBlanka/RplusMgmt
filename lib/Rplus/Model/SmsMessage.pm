package Rplus::Model::SmsMessage;

use strict;

use base qw(Rplus::DB::Object);

__PACKAGE__->meta->setup(
    table   => 'sms_messages',

    columns => [
        id                 => { type => 'serial', not_null => 1 },
        phone_num          => { type => 'varchar', length => 10, not_null => 1, remarks => 'Номер телефона' },
        text               => { type => 'text', not_null => 1, remarks => 'Текст СМС сообщения' },
        add_date           => { type => 'timestamp with time zone', default => 'now()', not_null => 1, remarks => 'Дата/время добавления сообщения' },
        status             => { type => 'varchar', default => 'queued', length => 10, not_null => 1, remarks => 'Статус сообщения:
      queued - отправка запланирована
      sent - отправлено
      delivered - доставлено
      error - ошибка
      cancelled - отменено' },
        status_change_date => { type => 'timestamp with time zone', default => 'now()', not_null => 1, remarks => 'Дата/время последнего обновления статуса сообщения' },
        attempts_count     => { type => 'integer', default => '0', not_null => 1, remarks => 'Количество попыток отправки' },
        last_error_msg     => { type => 'varchar', length => 512, remarks => 'Последнее сообщение об ошибке' },
        metadata           => { type => 'scalar', default => '{}', not_null => 1, remarks => 'Метаданные' },
    ],

    primary_key_columns => [ 'id' ],

    allow_inline_column_values => 1,
);

1;

