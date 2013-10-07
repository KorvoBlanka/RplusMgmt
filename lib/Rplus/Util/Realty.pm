package Rplus::Util::Realty;

use Rplus::Modern;

use Rplus::Model::Realty;
use Rplus::Model::Realty::Manager;
use Rplus::Model::RealtyType;
use Rplus::Model::RealtyType::Manager;
use Rplus::Model::MediaImportHistory;
use Rplus::Model::MediaImportHistory::Manager;

sub find_similar {
    my $class = shift;
    my %data = @_;

    return unless %data;
    return unless $data{'type_code'};
    return unless $data{'offer_type_code'};
    return unless $data{'state_code'};

    # Определим категорию недвижимости
    my $realty_type = Rplus::Model::RealtyType::Manager->get_objects(query => [code => $data{'type_code'}])->[0];
    return unless $realty_type;
    my $category_code = $realty_type->category_code;

    #
    # Поиск по тексту объявления
    #
    if ($data{'source_media_text'}) {
        # Поиск в таблице недвижимости по тексту объявления
        my $realty = Rplus::Model::Realty::Manager->get_objects(
            select => 'id',
            query => [
                source_media_text => $data{'source_media_text'},

                type_code => $data{'type_code'},
                offer_type_code => $data{'offer_type_code'},
                state_code => $data{'state_code'},
                ($data{'id'} ? ('!id' => $data{'id'}) : ()),
            ],
            limit => 1,
        )->[0];
        return $realty->id if $realty;

        # Поиск в таблице истории импорта по тексту объявления
        my $mih = Rplus::Model::MediaImportHistory::Manager->get_objects(
            select => 'id, realty_id',
            query => [
                media_text => $data{'source_media_text'},

                'realty.type_code' => $data{'type_code'},
                'realty.offer_type_code' => $data{'offer_type_code'},
                'realty.state_code' => $data{'state_code'},
                ($data{'id'} ? ('!realty_id' => $data{'id'}) : ()),
            ],
            require_objects => ['realty'],
            limit => 1
        )->[0];
        return $mih->realty_id if $mih;
    }

    #
    # Комната (room)
    #
    if ($category_code eq 'room') {
        # Совпадение: адресный объект, номер дома, номер квартиры, площадь комнаты
        if ($data{'address_object_id'} && $data{'house_num'} && $data{'ap_num'} && $data{'square_living'}) {
            my $realty = Rplus::Model::Realty::Manager->get_objects(
                select => 'id',
                query => [
                    ($data{'latitude'} && $data{'longitude'} ? (
                        or => [
                            and => [latitude => $data{'latitude'}, longitude => $data{'longitude'}],
                            and => [address_object_id => $data{'address_object_id'}, house_num => $data{'house_num'}],
                        ],
                    ) : (
                        address_object_id => $data{'address_object_id'}, house_num => $data{'house_num'},
                    )),
                    ap_num => $data{'ap_num'},
                    square_living => $data{'square_living'},

                    type_code => $data{'type_code'},
                    offer_type_code => $data{'offer_type_code'},
                    state_code => $data{'state_code'},
                    ($data{'id'} ? ('!id' => $data{'id'}) : ()),
                ],
                limit => 1
            )->[0];
            return $realty->id if $realty;
        }
    }

    #
    # Квартира (apartment)
    #
    if ($category_code eq 'apartment') {
        # Совпадение: адресный объект, номер дома, номер квартиры
        if ($data{'address_object_id'} && $data{'house_num'} && $data{'ap_num'}) {
            my $realty = Rplus::Model::Realty::Manager->get_objects(
                select => 'id',
                query => [
                    ($data{'latitude'} && $data{'longitude'} ? (
                        or => [
                            and => [latitude => $data{'latitude'}, longitude => $data{'longitude'}],
                            and => [address_object_id => $data{'address_object_id'}, house_num => $data{'house_num'}],
                        ],
                    ) : (
                        address_object_id => $data{'address_object_id'}, house_num => $data{'house_num'},
                    )),
                    ap_num => $data{'ap_num'},

                    type_code => $data{'type_code'},
                    offer_type_code => $data{'offer_type_code'},
                    state_code => $data{'state_code'},
                    ($data{'id'} ? ('!id' => $data{'id'}) : ()),
                ],
                limit => 1
            )->[0];
            return $realty->id if $realty;
        }
    }

    #
    # Дом (house) + Земельный участок (land)
    #
    if ($category_code eq 'house' || $category_code eq 'land') {
        # Совпадение: адресный объект, номер дома
        if ($data{'address_object_id'} && $data{'house_num'}) {
            my $realty = Rplus::Model::Realty::Manager->get_objects(
                select => 'id',
                query => [
                    ($data{'latitude'} && $data{'longitude'} ? (
                        or => [
                            and => [latitude => $data{'latitude'}, longitude => $data{'longitude'}],
                            and => [address_object_id => $data{'address_object_id'}, house_num => $data{'house_num'}],
                        ],
                    ) : (
                        address_object_id => $data{'address_object_id'}, house_num => $data{'house_num'},
                    )),

                    type_code => $data{'type_code'},
                    offer_type_code => $data{'offer_type_code'},
                    state_code => $data{'state_code'},
                    ($data{'id'} ? ('!id' => $data{'id'}) : ()),
                ],
                limit => 1,
            )->[0];
            return $realty->id if $realty;
        }
    }

    #
    # Коммерческая недвижимость
    #
    if ($category_code eq 'commersial') {
        # Совпадение: адресный объект, номер дома + проверка по "номер кв/офиса"
        if ($data{'address_object_id'} && $data{'house_num'}) {
            my $realty = Rplus::Model::Realty::Manager->get_objects(
                select => 'id',
                query => [
                    ($data{'latitude'} && $data{'longitude'} ? (
                        or => [
                            and => [latitude => $data{'latitude'}, longitude => $data{'longitude'}],
                            and => [address_object_id => $data{'address_object_id'}, house_num => $data{'house_num'}],
                        ],
                    ) : (
                        address_object_id => $data{'address_object_id'}, house_num => $data{'house_num'},
                    )),
                    ($data{'ap_num'} ? (OR => [ap_num => $data{'ap_num'}, ap_num => undef]) : ()),

                    type_code => $data{'type_code'},
                    offer_type_code => $data{'offer_type_code'},
                    state_code => $data{'state_code'},
                    ($data{'id'} ? ('!id' => $data{'id'}) : ()),
                ],
                limit => 1,
            )->[0];
            return $realty->id if $realty;
        }
    }

    #
    # Универсальное правило
    # Совпадение: один из номеров телефонов + проверка по остальным параметрам
    #
    if (ref($data{'seller_phones'}) eq 'ARRAY' && @{$data{'seller_phones'}}) {
        my $realty = Rplus::Model::Realty::Manager->get_objects(
            select => 'id',
            query => [
                \("seller_phones && '{".join(',', map { '"'.$_.'"' } @{$data{'seller_phones'}})."}'"),

                type_code => $data{'type_code'},
                offer_type_code => $data{'offer_type_code'},
                state_code => $data{'state_code'},
                ($data{'id'} ? ('!id' => $data{'id'}) : ()),

                ($data{'address_object_id'} ? (OR => [address_object_id => $data{'address_object_id'}, address_object_id => undef]) : ()),
                ($data{'house_num'} ? (OR => [house_num => $data{'house_num'}, house_num => undef]) : ()),
                ($data{'ap_num'} ? (OR => [ap_num => $data{'ap_num'}, ap_num => undef]) : ()),
                ($data{'rooms_count'} ? (OR => [rooms_count => $data{'rooms_count'}, rooms_count => undef]) : ()),
                ($data{'rooms_offer_count'} ? (OR => [rooms_offer_count => $data{'rooms_offer_count'}, rooms_offer_count => undef]) : ()),
                ($data{'floor'} ? (OR => [floor => $data{'floor'}, floor => undef]) : ()),
                ($data{'floors_count'} ? (OR => [floors_count => $data{'floors_count'}, floors_count => undef]) : ()),
                ($data{'square_total'} ? (OR => [square_total => $data{'square_total'}, square_total => undef]) : ()),
                ($data{'square_living'} ? (OR => [square_living => $data{'square_living'}, square_living => undef]) : ()),
                ($data{'square_land'} ? (OR => [square_land => $data{'square_land'}, square_land => undef]) : ()),
            ],
            limit => 1,
        )->[0];
        return $realty->id if $realty;
    }

    # Недвижимость чистая
    return;
}

1;
