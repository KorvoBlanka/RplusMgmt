package Rplus::Model::Task;

use strict;

use base qw(Rplus::DB::Object);

__PACKAGE__->meta->setup(
    table   => 'tasks',

    columns => [
        id               => { type => 'serial', not_null => 1 },
        parent_task_id   => { type => 'integer', remarks => 'Родительская задача' },
        creator_id       => { type => 'integer', remarks => 'Сотрудник, создавший задачу, либо система (null)' },
        assigned_user_id => { type => 'integer', not_null => 1, remarks => 'Сотрудник, отвечающий за выполнение задачи' },
        add_date         => { type => 'timestamp with time zone', default => 'now()', not_null => 1, remarks => 'Дата/время добавления задачи' },
        delete_date      => { type => 'timestamp with time zone', remarks => 'Дата/время удаления' },
        deadline_date    => { type => 'date', not_null => 1, remarks => 'Дата дедлайна' },
        remind_date      => { type => 'timestamp with time zone', remarks => 'Дата/время напоминания' },
        description      => { type => 'text', not_null => 1, remarks => 'Описание задачи' },
        status           => { type => 'varchar', length => 10, not_null => 1, remarks => 'Статус задачи:
      scheduled - запланировано,
      finished - завершено,
      cancelled - отменено' },
        realty_id        => { type => 'integer', remarks => 'Объект недвижимости, связанный с задачей' },
        category         => { type => 'varchar', length => 32, not_null => 1, remarks => 'Категория задачи (realty, other)' },
        type             => { type => 'varchar', length => 3, not_null => 1, remarks => 'Тип задачи:
      in - входящая
      out - исходящая' },
    ],

    primary_key_columns => [ 'id' ],

    allow_inline_column_values => 1,

    foreign_keys => [
        assigned_user => {
            class       => 'Rplus::Model::User',
            key_columns => { assigned_user_id => 'id' },
        },

        creator => {
            class       => 'Rplus::Model::User',
            key_columns => { creator_id => 'id' },
        },

        parent_task => {
            class       => 'Rplus::Model::Task',
            key_columns => { parent_task_id => 'id' },
        },

        realty => {
            class       => 'Rplus::Model::Realty',
            key_columns => { realty_id => 'id' },
        },
    ],

    relationships => [
        tasks => {
            class      => 'Rplus::Model::Task',
            column_map => { id => 'parent_task_id' },
            type       => 'one to many',
        },
    ],
);

1;

