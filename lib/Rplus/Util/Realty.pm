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
    if (1 == 2 && $data{'source_media_text'}) {     # выключим проверку на тексту объявления, посмотрим что получится
        # Поиск в таблице недвижимости по тексту объявления
        my $realty = Rplus::Model::Realty::Manager->get_objects(
            #select => 'id',
            query => [
                source_media_text => $data{'source_media_text'},

                type_code => $data{'type_code'},
                offer_type_code => $data{'offer_type_code'},
                #state_code => $data{'state_code'},
                ($data{'id'} ? ('!id' => $data{'id'}) : ()),
            ],
            limit => 10,
        );
        return $realty if scalar @{$realty} > 0;

        # Поиск в таблице истории импорта по тексту объявления
        #my $mih = Rplus::Model::MediaImportHistory::Manager->get_objects(
        #    select => 'id, realty_id',
        #    query => [
        #        media_text => $data{'source_media_text'},

        #        'realty.type_code' => $data{'type_code'},
        #        'realty.offer_type_code' => $data{'offer_type_code'},
        #        'realty.state_code' => $data{'state_code'},
        #        ($data{'id'} ? ('!realty_id' => $data{'id'}) : ()),
        #    ],
        #    require_objects => ['realty'],
        #    limit => 1
        #)->[0];
        #return $mih->realty_id if $mih;
    }

    #
    # Универсальное правило
    # Совпадение: один из номеров телефонов + проверка по остальным параметрам
    #
    if (ref($data{'owner_phones'}) eq 'ARRAY' && @{$data{'owner_phones'}}) {
        my $realty = Rplus::Model::Realty::Manager->get_objects(
            #select => 'id',
            query => [
                \("owner_phones && '{".join(',', map { '"'.$_.'"' } @{$data{'owner_phones'}})."}'"),

                type_code => $data{'type_code'},
                offer_type_code => $data{'offer_type_code'},
                locality => $data{'locality'}, address => $data{'address'}, house_num => $data{'house_num'},                
                #state_code => $data{'state_code'},

                ($data{'id'} ? ('!id' => $data{'id'}) : ()),

                ($data{'ap_num'} ? (OR => [ap_num => $data{'ap_num'}, ap_num => undef]) : ()),
                ($data{'rooms_count'} ? (OR => [rooms_count => $data{'rooms_count'}, rooms_count => undef]) : ()),
                ($data{'rooms_offer_count'} ? (OR => [rooms_offer_count => $data{'rooms_offer_count'}, rooms_offer_count => undef]) : ()),
                ($data{'floor'} ? (OR => [floor => $data{'floor'}, floor => undef]) : ()),
                ($data{'floors_count'} ? (OR => [floors_count => $data{'floors_count'}, floors_count => undef]) : ()),
                ($data{'square_total'} ? (OR => [square_total => $data{'square_total'}, square_total => undef]) : ()),
                ($data{'square_living'} ? (OR => [square_living => $data{'square_living'}, square_living => undef]) : ()),
                ($data{'square_land'} ? (OR => [square_land => $data{'square_land'}, square_land => undef]) : ()),
            ],
            limit => 10,
        );
        return $realty if scalar @{$realty} > 0;
    }

    # Недвижимость чистая
    return [];
}

1;
