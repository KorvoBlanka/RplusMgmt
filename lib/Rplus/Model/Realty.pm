package Rplus::Model::Realty;

use strict;

use base qw(Rplus::DB::Object);

__PACKAGE__->meta->setup(
    table   => 'realty',

    columns => [
        id                  => { type => 'serial', not_null => 1 },
        type_code           => { type => 'varchar', length => 32, not_null => 1, remarks => 'Тип недвижимости' },
        offer_type_code     => { type => 'varchar', length => 16, not_null => 1, remarks => 'Тип предложения' },
        state_code          => { type => 'varchar', default => 'raw', length => 25, not_null => 1, remarks => 'Состояние объекта' },
        state_change_date   => { type => 'timestamp with time zone', default => 'now()', not_null => 1, remarks => 'Дата/время последней смены состояния объекта' },
        address_object_id   => { type => 'integer', remarks => 'Адресный объект' },
        house_num           => { type => 'varchar', length => 10, remarks => 'Номер дома' },
        house_type_id       => { type => 'integer', remarks => 'Тип дома' },
        ap_num              => { type => 'integer', remarks => 'Номер квартиры' },
        ap_scheme_id        => { type => 'integer', remarks => 'Планировка квартиры' },
        rooms_count         => { type => 'integer', remarks => 'Количество комнат' },
        rooms_offer_count   => { type => 'integer', remarks => 'Количество предлагаемых комнат' },
        room_scheme_id      => { type => 'integer', remarks => 'Планировка комнат' },
        floor               => { type => 'integer', remarks => 'Этаж' },
        floors_count        => { type => 'integer', remarks => 'Количество этажей' },
        levels_count        => { type => 'integer', remarks => 'Этажность квартиры (для элитного жилья)' },
        condition_id        => { type => 'integer', remarks => 'Состояние' },
        balcony_id          => { type => 'integer', remarks => 'Описание балкона(ов)' },
        bathroom_id         => { type => 'integer', remarks => 'Описание санузла(ов)' },
        square_total        => { type => 'float', remarks => 'Общая площадь', scale => 4 },
        square_living       => { type => 'float', remarks => 'Жилая площадь', scale => 4 },
        square_kitchen      => { type => 'float', remarks => 'Площадь кухни', scale => 4 },
        square_land         => { type => 'float', remarks => 'Площадь земельного участка', scale => 4 },
        square_land_type    => { type => 'varchar', length => 7, remarks => 'Тип площади земельного участка:
      ar - сотка
      hectare - гектар' },
        description         => { type => 'text', remarks => 'Дополнительное описание' },
        source_media_id     => { type => 'integer', remarks => 'Источник СМИ, из которого вытянуто объявление' },
        source_media_text   => { type => 'text', remarks => 'Исходный текст объявления' },
        creator_id          => { type => 'integer', remarks => 'Пользователь, зарегистрировавший недвижимость (null - система)' },
        add_date            => { type => 'timestamp with time zone', default => 'now()', not_null => 1, remarks => 'Дата/время добавления' },
        change_date         => { type => 'timestamp with time zone', default => 'now()', not_null => 1, remarks => 'Дата/время изменения' },
        delete_date         => { type => 'timestamp with time zone', remarks => 'Дата/время удаления' },
        owner_id            => { type => 'integer', remarks => 'Собственник' },
        owner_phones        => { type => 'array', not_null => 1, remarks => 'Контактные телефоны собственника данного объекта недвижимости' },
        owner_info          => { type => 'text', remarks => 'Доп. информация от собственника (контакты, удобное время звонка, и т.д.)' },
        owner_price         => { type => 'float', remarks => 'Цена собственника', scale => 4 },
        work_info           => { type => 'text', remarks => 'Доп. информация по продаже недвижимости' },
        agent_id            => { type => 'integer', remarks => 'Агент, за которым закреплен данный объект недвижимости' },
        agency_price        => { type => 'float', remarks => 'Цена агентства', scale => 4 },
        price               => { type => 'float', remarks => 'COALESCE(agency_price, owner_price)', scale => 4 },
        price_change_date   => { type => 'timestamp with time zone', remarks => 'Дата/время последнего изменения цены' },
        buyer_id            => { type => 'integer', remarks => 'Покупатель' },
        final_price         => { type => 'float', remarks => 'Цена продажи по факту', scale => 4 },
        latitude            => { type => 'numeric', remarks => 'Широта' },
        longitude           => { type => 'numeric', remarks => 'Долгота' },
        geocoords           => { type => 'geography', remarks => 'Географические координаты' },
        sublandmark_id      => { type => 'integer', remarks => 'Подориентир' },
        landmarks           => { type => 'array', default => '{}', not_null => 1, remarks => 'Ориентиры, в которые попадает объект' },
        export_media        => { type => 'array', default => '{}', not_null => 1, remarks => 'В какие источники экспортировать недвижимость (объявления)' },
        metadata            => { type => 'scalar', default => '{}', not_null => 1, remarks => 'Метаданные' },
        fts                 => { type => 'scalar', remarks => 'tsvector описания' },
        last_seen_date      => { type => 'timestamp with time zone', default => 'now()', not_null => 1 },
        assign_date         => { type => 'timestamp with time zone', remarks => 'дата-время назначения агента на объект' },
        mediator_company_id => { type => 'integer' },
        source_url          => { type => 'varchar' },
        account_id          => { type => 'integer' },
        hidden_for          => { type => 'array', default => '{}', not_null => 1, remarks => 'ID аккаунтов, для которых не будет виден объект' },
        multylisting        => { type => 'boolean', default => 'false', not_null => 1 },
        mls_price_type      => { type => 'varchar', default => 'rub', length => 255, not_null => 1 },
        mls_price           => { type => 'float', scale => 4 },
        attachments         => { type => 'array', default => '{}', not_null => 1 },
        rent_type           => { type => 'varchar', default => 'long', length => 8, not_null => 1 },
        lease_deposite_id   => { type => 'integer' },
        fts_vector          => { type => 'scalar' },
        district            => { type => 'varchar' },
        poi                 => { type => 'varchar' },
        pois                => { type => 'array' },
        address             => { type => 'varchar' },
        locality            => { type => 'varchar' },
        color_tag           => { type => 'array' },
    ],

    primary_key_columns => [ 'id' ],

    allow_inline_column_values => 1,

    foreign_keys => [
        address_object => {
            class       => 'Rplus::Model::AddressObject',
            key_columns => { address_object_id => 'id' },
        },

        agent => {
            class       => 'Rplus::Model::User',
            key_columns => { agent_id => 'id' },
        },

        ap_scheme => {
            class       => 'Rplus::Model::DictApScheme',
            key_columns => { ap_scheme_id => 'id' },
        },

        balcony => {
            class       => 'Rplus::Model::DictBalcony',
            key_columns => { balcony_id => 'id' },
        },

        bathroom => {
            class       => 'Rplus::Model::DictBathroom',
            key_columns => { bathroom_id => 'id' },
        },

        buyer => {
            class       => 'Rplus::Model::Client',
            key_columns => { buyer_id => 'id' },
        },

        condition => {
            class       => 'Rplus::Model::DictCondition',
            key_columns => { condition_id => 'id' },
        },

        creator => {
            class       => 'Rplus::Model::User',
            key_columns => { creator_id => 'id' },
        },

        house_type => {
            class       => 'Rplus::Model::DictHouseType',
            key_columns => { house_type_id => 'id' },
        },

        mediator_company => {
            class       => 'Rplus::Model::MediatorCompany',
            key_columns => { mediator_company_id => 'id' },
        },

        offer_type => {
            class       => 'Rplus::Model::RealtyOfferType',
            key_columns => { offer_type_code => 'code' },
        },

        owner => {
            class       => 'Rplus::Model::Client',
            key_columns => { owner_id => 'id' },
        },

        room_scheme => {
            class       => 'Rplus::Model::DictRoomScheme',
            key_columns => { room_scheme_id => 'id' },
        },

        source_media => {
            class       => 'Rplus::Model::Media',
            key_columns => { source_media_id => 'id' },
        },

        state => {
            class       => 'Rplus::Model::RealtyState',
            key_columns => { state_code => 'code' },
        },

        sublandmark => {
            class       => 'Rplus::Model::Landmark',
            key_columns => { sublandmark_id => 'id' },
        },

        type => {
            class       => 'Rplus::Model::RealtyType',
            key_columns => { type_code => 'code' },
        },
    ],

    relationships => [
        color_tags => {
            class      => 'Rplus::Model::ColorTag',
            column_map => { id => 'realty_id' },
            type       => 'one to many',
        },

        media_import_history => {
            class      => 'Rplus::Model::MediaImportHistory',
            column_map => { id => 'realty_id' },
            type       => 'one to many',
        },

        photos => {
            class      => 'Rplus::Model::Photo',
            column_map => { id => 'realty_id' },
            type       => 'one to many',
        },

        realty_color_tag => {
            class                => 'Rplus::Model::RealtyColorTag',
            column_map           => { id => 'realty_id' },
            type                 => 'one to one',
            with_column_triggers => '0',
        },

        subscription_realty => {
            class      => 'Rplus::Model::SubscriptionRealty',
            column_map => { id => 'realty_id' },
            type       => 'one to many',
        },
    ],
);

1;

