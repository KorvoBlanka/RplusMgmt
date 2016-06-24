package RplusMgmt::Controller::Export::Irr;

use Mojo::Base 'Mojolicious::Controller';

use Rplus::Model::Media;
use Rplus::Model::Media::Manager;
use Rplus::Model::Realty;
use Rplus::Model::Realty::Manager;
use Rplus::Model::RuntimeParam;
use Rplus::Model::RuntimeParam::Manager;
use Rplus::Model::Photo;
use Rplus::Model::Photo::Manager;
use Rplus::Model::Option;
use Rplus::Model::Option::Manager;

use Mojo::Util qw(trim);
use File::Temp qw(tmpnam);
use JSON;
use Text::CSV;
use Tie::IxHash;
use URI;
use MIME::Base64;
use Archive::Zip qw( :ERROR_CODES :CONSTANTS );

use Data::Dumper;


my $config;

my $contact_phones = '';
my $agent_phone = 0;
my $contact_name = '';
my $contact_email = '';
my $site_url = '';

sub ordered_hash_ref {
    tie my %hash, 'Tie::IxHash', @_;
    return \%hash;
}

my $filename_hash = {
    'sale-room' => 'real-estate.rooms-sale.csv',
    'rent-room' => 'real-estate.rooms-rent.csv',
    'sale-apartment' => 'real-estate.apartments-sale.secondary.csv',
    'rent-apartment' => 'real-estate.rent.csv',
    'sale-house' => 'real-estate.out-of-town.houses.csv',
    'rent-house' => 'real-estate.out-of-town-rent.csv',

    'sale-commercial' => 'real-estate.commercial.offices.csv',
    'rent-commercial' => 'real-estate.commercial-rent.csv',

    #'sale-lands' => 'real-estate.commercial.offices.csv',
    #'rent-lands' => 'real-estate.commercial-rent.csv',

    #'sale-garages' => 'real-estate.garages.csv',
    #'rent-garages' => 'real-estate.commercial-rent.csv',
};

my $city = '';

my %templates_hash = (
    sale => {
        apartment => ordered_hash_ref (
            "ID" => sub {
                    my $d = shift;
                    return $d->id;
                },
            "Город" => sub {
                    return $city;     # Подставить город из конфига?
                },
            "Метро" => sub {
                    return '';
                },
            "Шоссе" => sub {
                    return '';
                },
            "Цена" => sub {
                    my $d = shift;
                    return $d->price ? $d->price * 1000 : '';
                },
            "Валюта" => sub {
                    return 'rur';
                },
            "До метро (мин/пеш)" => sub {
                    return '';
                },
            "Год постройки (г)" => sub {
                    return '';
                },
            "Серия здания" => sub {
                    return '';
                },
            "Количество этажей" => sub {
                    my $d = shift;
                    return $d->floors_count;
                },
            "Материал стен" => sub {
                    my $d = shift;
                    return $d->house_type ? $d->house_type->name : '';
                },
            "Лифты в здании" => sub {
                    return '';
                },
            "Система отопления" => sub {
                    return '';
                },
            "Система водоснабжения" => sub {
                    return '';
                },
            "Мусоропровод" => sub {
                    return '';
                },
            "Газ в доме" => sub {
                    return '';
                },
            "Охрана здания" => sub {
                    return '';
                },
            "Высота потолков (м)" => sub {
                    return '';
                },
            "Планируется снос здания" => sub {
                    return '';
                },
            "Этаж" => sub {
                    my $d = shift;
                    return $d->floor;
                },
            "Комнат в квартире" => sub {
                    my $d = shift;
                    return $d->rooms_count;
                },
            "Общая площадь (кв.м)" => sub {
                    my $d = shift;
                    return $d->square_total;
                },
            "Жилая площадь (кв.м)" => sub {
                    my $d = shift;
                    return $d->square_living;
                },
            "Площадь кухни (кв.м)" => sub {
                    my $d = shift;
                    return $d->square_kitchen;
                },
            "Балкон/Лоджия" => sub {
                    my $d = shift;
                    return $d->balcony ? $d->balcony->name : '';
                },
            "Санузел" => sub {
                    my $d = shift;
                    return $d->bathroom ? $d->bathroom->name : '';
                },
            "Ремонт" => sub {
                    my $d = shift;
                    return $d->condition ? $d->condition->name : '';
                },
            "Телефон" => sub {
                    return '';
                },
            "Интернет" => sub {
                    return '';
                },
            "Приватизированная квартира" => sub {
                    return '';
                },
            "Улица" => sub {
                    my $d = shift;

                    return $d->address ? $d->address : '';
                },
            "Дом" => sub {
                    my $d = shift;
                    return $d->house_num ? $d->house_num : '';
                },
            "Удаленность, км" => sub {
                    return '';
                },
            "Дополнительные сведения" => sub {
                    my $d = shift;
                    return $d->description ? $d->description : '';
                },
            "Фото" => sub {
                    my $d = shift;
                    my @photos = @{Rplus::Model::Photo::Manager->get_objects(query => [realty_id => $d->id, delete_date => undef], sort_by => 'id ASC', limit => 2)};
                    return join ", ", map {$_->filename} @photos;
                },
            "Контактное лицо" => sub {
                    my $d = shift;
                    my $name = '';
                    if ($d->agent_id) {
                        $name = $d->agent->public_name || '';
                    }
                    return $name;
                },
            "Контактный телефон" => sub {
                    my $d = shift;
                    my $phones = $contact_phones;
                    if ($agent_phone == 1 && $d->agent) {
                        my $x = $d->agent->public_phone_num || $d->agent->phone_num;
                        $phones =  $x . ', ' . $phones;
                    }

                    return $phones;
                },
            "e-mail" => sub {
                    return $contact_email;
                },
            "www-адрес" => sub {
                    return $site_url;
                },
        ),
        room => ordered_hash_ref (
            "ID" => sub {
                    my $d = shift;
                    return $d->id;
                },
            "Город" => sub {
                    return $city;
                },
            "Метро" => sub {
                    return '';
                },
            "Шоссе" => sub {
                    return '';
                },
            "Цена" => sub {
                    my $d = shift;
                    return $d->price ? $d->price * 1000 : '';
                },
            "Валюта" => sub {
                    return 'rur';
                },
            "Удаленность, км" => sub {
                    return '';
                },
            "Комнат в квартире/общежитии" => sub {
                    my $d = shift;
                    return $d->rooms_count;
                },
            "Количество комнат на продажу" => sub {
                    my $d = shift;
                    return $d->rooms_offer_count;
                },
            "Общая площадь квартиры" => sub {
                    my $d = shift;
                    return $d->square_total;
                },
            "Доля (%)" => sub {
                    return '';
                },
            "Площадь продажи" => sub {
                    return '';
                },
            "Год постройки (г)" => sub {
                    return '';
                },
            "Серия здания" => sub {
                    return '';
                },
            "Материал стен" => sub {
                    my $d = shift;
                    return $d->house_type ? $d->house_type->name : '';
                },
            "Лифты в здании" => sub {
                    return '';
                },
            "Система отопления" => sub {
                    return '';
                },
            "Система водоснабжения" => sub {
                    return '';
                },
            "Мусоропровод" => sub {
                    return '';
                },
            "Газ в доме" => sub {
                    return '';
                },
            "Охрана здания" => sub {
                    return '';
                },
            "Высота потолков (м)" => sub {
                    return '';
                },
            "Этаж" => sub {
                    my $d = shift;
                    return $d->floor;
                },
            "Этажей в здании" => sub {
                    my $d = shift;
                    return $d->floors_count;
                },
            "Балкон/Лоджия" => sub {
                    my $d = shift;
                    return $d->balcony ? $d->balcony->name : '';
                },
            "Ремонт" => sub {
                    my $d = shift;
                    return $d->condition ? 'состояние: ' . $d->condition->name : '';
                },
            "Отказ получен" => sub {
                    return '';
                },
            "Улица" => sub {
                    my $d = shift;
                    return $d->address ? $d->address : '';
                },
            "Дом" => sub {
                    my $d = shift;
                    return $d->house_num ? $d->house_num : '';
                },
            "Текст объявления" => sub {
                    my $d = shift;
                    return $d->description ? $d->description : '';
                },
            "Фото" => sub {
                    my $d = shift;
                    my @photos = @{Rplus::Model::Photo::Manager->get_objects(query => [realty_id => $d->id, delete_date => undef], sort_by => 'id ASC', limit => 2)};
                    return join ", ", map {$_->filename} @photos;
                },
            "e-mail" => sub {
                    return $contact_email;
                },
            "www-адрес" => sub {
                    return $site_url;
                },
            "Контактное лицо" => sub {
                    my $d = shift;
                    my $name = '';
                    if ($d->agent_id) {
                        $name = $d->agent->public_name || '';
                    }
                    return $name;
                },
            "Контактный телефон" => sub {
                    my $d = shift;
                    my $phones = $contact_phones;
                    if ($agent_phone == 1 && $d->agent) {
                        my $x = $d->agent->public_phone_num || $d->agent->phone_num;
                        $phones =  $x . ', ' . $phones;
                    }

                    return $phones;
                },
            "" => sub {
                    return '';
                },
            "Общежитие" => sub {
                    return '';
                },

        ),
        house => ordered_hash_ref (
            "ID" => sub {
                    my $d = shift;
                    return $d->id;
                },
            "Город" => sub {
                    return $city;
                },
            "Метро" => sub {
                    return '';
                },
            "Шоссе" => sub {
                    return '';
                },
            "Цена" => sub {
                    my $d = shift;
                    return $d->price ? $d->price * 1000 : '';
                },
            "Валюта" => sub {
                    return 'rur';
                },
            "До метро, мин/пеш" => sub {
                    return '';
                },
            "Удаленность, км" => sub {
                    return '';
                },
            "Год постройки/сдачи (г)" => sub {
                    return '';
                },
            "Площадь участка (сот)" => sub {
                    my $d = shift;
                    return '' unless $d->square_land;
                    my $sq = $d->square_land;
                    if (($d->square_land_type || 'ar') eq 'hectare') {
                        $sq *= 100;
                    }
                    return $sq;
                },
            "Площадь строения" => sub {
                    my $d = shift;
                    return $d->square_total;
                },
            "Категория земли" => sub {
                    return '';
                },
            "Вид разрешенного использования" => sub {
                    return '';
                },
            "Количество этажей" => sub {
                    my $d = shift;
                    return $d->floors_count;
                },
            "Количество комнат" => sub {
                    my $d = shift;
                    return $d->rooms_count;
                },
            "Материал стен" => sub {
                    my $d = shift;
                    return $d->house_type ? $d->house_type->name : '';
                },
            "Гараж" => sub {
                    return '';
                },
            "Под снос" => sub {
                    return '';
                },
            "Газ в доме" => sub {
                    return '';
                },
            "Канализация Водопровод" => sub {
                    return '';
                },
            "Электричество (подведено)" => sub {
                    return '';
                },
            "Строение" => sub {
                    return '';
                },
            "Ремонт" => sub {
                    my $d = shift;
                    return $d->condition ? 'состояние: ' . $d->condition->name : '';
                },
            "Отапливаемый" => sub {
                    return '';
                },
            "Охрана" => sub {
                    return '';
                },
            "Улица" => sub {
                    my $d = shift;
                    return $d->address ? $d->address : '';
                },
            "Дом" => sub {
                    my $d = shift;
                    return $d->house_num ? $d->house_num : '';
                },
            "Текст объявления" => sub {
                    my $d = shift;
                    return $d->description ? $d->description : '';
                },
            "Фото" => sub {
                    my $d = shift;
                    my @photos = @{Rplus::Model::Photo::Manager->get_objects(query => [realty_id => $d->id, delete_date => undef], sort_by => 'id ASC', limit => 2)};
                    return join ", ", map {$_->filename} @photos;
                },
            "e-mail" => sub {
                    return $contact_email;
                },
            "www-адрес" => sub {
                    return $site_url;
                },
            "Контактное лицо" => sub {
                    my $d = shift;
                    my $name = '';
                    if ($d->agent_id) {
                        $name = $d->agent->public_name || '';
                    }
                    return $name;
                },
            "Контактный телефон" => sub {
                    my $d = shift;
                    my $phones = $contact_phones;
                    if ($agent_phone == 1 && $d->agent) {
                        my $x = $d->agent->public_phone_num || $d->agent->phone_num;
                        $phones =  $x . ', ' . $phones;
                    }

                    return $phones;
                },

        ),
        commercial => ordered_hash_ref (
            "ID" => sub {
                    my $d = shift;
                    return $d->id;
                },
            "Город" => sub {
                    return $city;
                },
            "Метро" => sub {
                    return '';
                },
            "Шоссе" => sub {
                    return '';
                },
            "Общая площадь от" => sub {
                    my $d = shift;
                    return $d->square_total;
                },
            "Цена общая" => sub {
                    my $d = shift;
                    return $d->price ? $d->price * 1000 : '';
                },
            "Валюта" => sub {
                    return 'rur';
                },
            "Улица" => sub {
                    my $d = shift;
                    return $d->address ? $d->address : '';
                },
            "Дом" => sub {
                    my $d = shift;
                    return $d->house_num ? $d->house_num : '';
                },
            "До метро, мин/пеш" => sub {
                    return '';
                },
            "Класс" => sub {
                    return '';
                },
            "Тип здания" => sub {
                    return '';
                },
            "Серия здания" => sub {
                    return '';
                },
            "Материал стен" => sub {
                    my $d = shift;
                    return $d->house_type ? $d->house_type->name : '';
                },
            "Год постройки/сдачи (г)" => sub {
                    return '';
                },
            "Количество этажей" => sub {
                    my $d = shift;
                    return $d->floors_count;
                },
            "Лифты в здании" => sub {
                    return '';
                },
            "Система отопления" => sub {
                    return '';
                },
            "Охрана здания" => sub {
                    return '';
                },
            "Высота потолков" => sub {
                    return '';
                },
            "Парковка" => sub {
                    return '';
                },
            "Общее количество машиномест" => sub {
                    return '';
                },
            "Этаж" => sub {
                    return '';
                },
            "Городской телефон" => sub {
                    return '';
                },
            "Ремонт" => sub {
                    my $d = shift;
                    return $d->condition ? $d->condition->name : '';
                },
            "1-я линия" => sub {
                    return '';
                },
            "Отдельный вход" => sub {
                    return '';
                },
            "Охрана парковки" => sub {
                    return '';
                },
            "Удаленность, км" => sub {
                    return '';
                },
            "Дополнительные сведения" => sub {
                    my $d = shift;
                    return $d->description ? $d->description : '';
                },
            "Фото" => sub {
                    my $d = shift;
                    my @photos = @{Rplus::Model::Photo::Manager->get_objects(query => [realty_id => $d->id, delete_date => undef], sort_by => 'id ASC', limit => 2)};
                    return join ", ", map {$_->filename} @photos;
                },
            "www-адрес" => sub {
                    return $site_url;
                },
            "Контактное лицо" => sub {
                    my $d = shift;
                    my $name = '';
                    if ($d->agent_id) {
                        $name = $d->agent->public_name || '';
                    }
                    return $name;
                },
            "Контактный телефон" => sub {
                    my $d = shift;
                    my $phones = $contact_phones;
                    if ($agent_phone == 1 && $d->agent) {
                        my $x = $d->agent->public_phone_num || $d->agent->phone_num;
                        $phones =  $x . ', ' . $phones;
                    }

                    return $phones;
                },
            "e-mail" => sub {
                    return $contact_email;
                },
        ),

    },
    rent => {
        apartment => ordered_hash_ref (
            "ID" => sub {
                    my $d = shift;
                    return $d->id;
                },
            "Город" => sub {
                    return $city;
                },
            "Метро" => sub {
                    return '';
                },
            "Шоссе" => sub {
                    return '';
                },
            "Цена" => sub {
                    my $d = shift;
                    return $d->price ? $d->price * 1000 : '';
                },
            "Валюта" => sub {
                    return 'rur';
                },
            "Период аренды" => sub {
                    return 'долгосрочная';
                },
            "Краткосрочная аренда" => sub {
                    return '';
                },
            "Комнат в квартире" => sub {
                    my $d = shift;
                    return $d->rooms_count;
                },
            "Общая площадь (кв.м)" => sub {
                    my $d = shift;
                    return $d->square_total;
                },
            "Жилая площадь (кв.м)" => sub {
                    my $d = shift;
                    return $d->square_living;
                },
            "Площадь кухни (кв.м)" => sub {
                    my $d = shift;
                    return $d->square_kitchen;
                },
            "До метро, мин/пеш" => sub {
                    return '';
                },
            "Удаленность, км" => sub {
                    return '';
                },
            "Год постройки" => sub {
                    return '';
                },
            "Серия здания" => sub {
                    return '';
                },
            "Этаж" => sub {
                    my $d = shift;
                    return $d->floor;
                },
            "Этажей в здании" => sub {
                    my $d = shift;
                    return $d->floors_count;
                },
            "Материал стен" => sub {
                    my $d = shift;
                    return $d->house_type ? $d->house_type->name : '';
                },
            "Лифты в здании" => sub {
                    return '';
                },
            "Система отопления" => sub {
                    return '';
                },
            "Система водоснабжения" => sub {
                    return '';
                },
            "Мусоропровод" => sub {
                    return '';
                },
            "Газ в доме" => sub {
                    return '';
                },
            "Охрана здания" => sub {
                    return '';
                },
            "Высота потолков (м)" => sub {
                    return '';
                },
            "Балкон/Лоджия" => sub {
                    my $d = shift;
                    return $d->balcony ? $d->balcony->name : '';
                },
            "Санузел" => sub {
                    my $d = shift;
                    return $d->bathroom ? $d->bathroom->name : '';
                },
            "Ремонт" => sub {
                    my $d = shift;
                    return $d->condition ? $d->condition->name : '';
                },
            "Телефон" => sub {
                    return '';
                },
            "Интернет" => sub {
                    return '';
                },
            "Без мебели" => sub {
                    return '';
                },
            "Бытовая техника" => sub {
                    return '';
                },
            "Улица" => sub {
                    my $d = shift;
                    return $d->address ? $d->address : '';
                },
            "Дом" => sub {
                    my $d = shift;
                    return $d->house_num ? $d->house_num : '';
                },
            "Текст объявления" => sub {
                    my $d = shift;
                    return $d->description;
                },
            "Фото" => sub {
                    my $d = shift;
                    my @photos = @{Rplus::Model::Photo::Manager->get_objects(query => [realty_id => $d->id, delete_date => undef], sort_by => 'id ASC', limit => 2)};
                    return join ", ", map {$_->filename} @photos;
                },
            "e-mail" => sub {
                    return $contact_email;
                },
            "www-адрес" => sub {
                    return $site_url;
                },
            "Контактное лицо" => sub {
                    my $d = shift;
                    my $name = '';
                    if ($d->agent_id) {
                        $name = $d->agent->public_name || '';
                    }
                    return $name;
                },
            "Контактный телефон" => sub {
                    my $d = shift;
                    my $phones = $contact_phones;
                    if ($agent_phone == 1 && $d->agent) {
                        my $x = $d->agent->public_phone_num || $d->agent->phone_num;
                        $phones =  $x . ', ' . $phones;
                    }

                    return $phones;
                },
            "" => sub {
                    return '';
                },
            "Комиссия" => sub {
                    return 'без комиссии';
                },

        ),
        room => ordered_hash_ref (
            "ID" => sub {
                    my $d = shift;
                    return $d->id;
                },
            "Город" => sub {
                    return $city;
                },
            "Метро" => sub {
                    return '';
                },
            "Шоссе" => sub {
                    return '';
                },
            "Цена" => sub {
                    my $d = shift;
                    return $d->price ? $d->price * 1000 : '';
                },
            "Валюта" => sub {
                    return 'rur';
                },
            "Период аренды" => sub {
                    return '';
                },
            "Краткосрочная аренда" => sub {
                    return 'долгосрочная';
                },
            "Комнат в квартире" => sub {
                    my $d = shift;
                    return $d->rooms_count;
                },
            "Комнат сдается" => sub {
                    my $d = shift;
                    return $d->rooms_offer_count;
                },
            "До метро, мин/пеш" => sub {
                    return '';
                },
            "Удаленность, км" => sub {
                    return '';
                },
            "Год постройки/сдачи (г)" => sub {
                    return '';
                },
            "Серия здания" => sub {
                    return '';
                },
            "Количество этажей" => sub {
                    my $d = shift;
                    return $d->floors_count;
                },
            "Материал стен" => sub {
                    my $d = shift;
                    return $d->house_type ? $d->house_type->name : '';
                },
            "Лифты в здании" => sub {
                    return '';
                },
            "Система отопления" => sub {
                    return '';
                },
            "Система водоснабжения" => sub {
                    return '';
                },
            "Мусоропровод" => sub {
                    return '';
                },
            "Газ в доме" => sub {
                    return '';
                },
            "Охрана здания" => sub {
                    return '';
                },
            "Высота потолков (м)" => sub {
                    return '';
                },
            "Этаж" => sub {
                    my $d = shift;
                    return $d->floors_count;
                },
            "Площадь арендуемой комнаты" => sub {
                    my $d = shift;
                    return $d->square_total;
                },
            "Ремонт" => sub {
                    my $d = shift;
                    return $d->condition ? $d->condition->name : '';
                },
            "Без мебели" => sub {
                    return '';
                },
            "Бытовая техника" => sub {
                    return '';
                },
            "Улица" => sub {
                    my $d = shift;
                    return $d->address ? $d->address : '';
                },
            "Дом" => sub {
                    my $d = shift;
                    return $d->house_num ? $d->house_num : '';
                },
            "Текст объявления" => sub {
                    my $d = shift;
                    return $d->description;
                },
            "Фото" => sub {
                    my $d = shift;
                    my @photos = @{Rplus::Model::Photo::Manager->get_objects(query => [realty_id => $d->id, delete_date => undef], sort_by => 'id ASC', limit => 2)};
                    return join ", ", map {$_->filename} @photos;
                },
            "e-mail" => sub {
                    return $contact_email;
                },
            "www-адрес" => sub {
                    return $site_url;
                },
            "Контактное лицо" => sub {
                    my $d = shift;
                    my $name = '';
                    if ($d->agent_id) {
                        $name = $d->agent->public_name || '';
                    }
                    return $name;
                },
            "Контактный телефон" => sub {
                    my $d = shift;
                    my $phones = $contact_phones;
                    if ($agent_phone == 1 && $d->agent) {
                        my $x = $d->agent->public_phone_num || $d->agent->phone_num;
                        $phones =  $x . ', ' . $phones;
                    }

                    return $phones;
                },
            "" => sub {
                    return '';
                },
            "Комиссия" => sub {
                    return 'без комиссии';
                },
            "Общежитие" => sub {
                    return '';
                },
        ),
        house => ordered_hash_ref (
            "ID" => sub {
                    my $d = shift;
                    return $d->id;
                },
            "Город" => sub {
                    return $city;
                },
            "Метро" => sub {
                    return '';
                },
            "Шоссе" => sub {
                    return '';
                },
            "Цена" => sub {
                    my $d = shift;
                    return $d->price ? $d->price * 1000 : '';
                },
            "Валюта" => sub {
                    return 'rur';
                },
            "До метро, мин/пеш" => sub {
                    return '';
                },
            "Удаленность от города, км" => sub {
                    return '';
                },
            "Год постройки/сдачи" => sub {
                    return '';
                },
            "Площадь участка (сот)" => sub {
                    my $d = shift;
                    return '' unless $d->square_land;
                    my $sq = $d->square_land;
                    if (($d->square_land_type || 'ar') eq 'hectare') {
                        $sq *= 100;
                    }
                    return $sq;
                },
            "Площадь строения" => sub {
                    my $d = shift;
                    return $d->square_total;
                },
            "Количество этажей" => sub {
                    my $d = shift;
                    return $d->floors_count;
                },
            "Количество комнат" => sub {
                    my $d = shift;
                    return $d->rooms_count;
                },
            "Количество спален" => sub {
                    return '';
                },
            "Материал стен" => sub {
                    my $d = shift;
                    return $d->house_type ? $d->house_type->name : '';
                },
            "Отапливаемый" => sub {
                    return '';
                },
            "Гараж" => sub {
                    return '';
                },
            "Телефон" => sub {
                    return '';
                },
            "Интернет" => sub {
                    return '';
                },
            "Мебель" => sub {
                    return '';
                },
            "Бытовая техника" => sub {
                    return '';
                },
            "Период аренды" => sub {
                    return 'долгосрочная';
                },
            "Охрана" => sub {
                    return '';
                },
            "Газ в доме" => sub {
                    return '';
                },
            "Электричество" => sub {
                    return '';
                },
            "Водопровод" => sub {
                    return '';
                },
            "Ремонт" => sub {
                    my $d = shift;
                    return $d->condition ? $d->condition->name : '';
                },
            "Канализация" => sub {
                    return '';
                },
            "Строение" => sub {
                    return '';
                },
            "Улица" => sub {
                    my $d = shift;
                    return $d->address ? $d->address : '';
                },
            "Дом" => sub {
                    my $d = shift;
                    return $d->house_num ? $d->house_num : '';
                },
            "Текст объявления" => sub {
                    my $d = shift;
                    return $d->description;
                },
            "Фото" => sub {
                    my $d = shift;
                    my @photos = @{Rplus::Model::Photo::Manager->get_objects(query => [realty_id => $d->id, delete_date => undef], sort_by => 'id ASC', limit => 2)};
                    return join ", ", map {$_->filename} @photos;
                },
            "e-mail" => sub {
                    return $contact_email;
                },
            "www-адрес" => sub {
                    return $site_url;
                },
            "Контактное лицо" => sub {
                    my $d = shift;
                    my $name = '';
                    if ($d->agent_id) {
                        $name = $d->agent->public_name || '';
                    }
                    return $name;
                },
            "Контактный телефон" => sub {
                    my $d = shift;

                    my $phones = $contact_phones;
                    if ($agent_phone == 1 && $d->agent) {
                        my $x = $d->agent->public_phone_num || $d->agent->phone_num;
                        $phones =  $x . ', ' . $phones;
                    }

                    return $phones;
                },
            "" => sub {
                    return '';
                },
            "Комиссия" => sub {
                    return 'без комиссии';
                },
        ),

        commercial => ordered_hash_ref (
            "ID" => sub {
                    my $d = shift;
                    return $d->id;
                },
            "Город" => sub {
                    return $city;
                },
            "Метро" => sub {
                    return '';
                },
            "Шоссе" => sub {
                    return '';
                },
            "Общая площадь от" => sub {
                    my $d = shift;
                    return $d->square_total;
                },
            "Цена общая" => sub {
                    my $d = shift;
                    return $d->price ? $d->price * 1000 : '';
                },
            "Валюта" => sub {
                    return 'rur';
                },
            "Улица" => sub {
                    my $d = shift;
                    return $d->address ? $d->address : '';
                },
            "Дом" => sub {
                    my $d = shift;
                    return $d->house_num ? $d->house_num : '';
                },
            "До метро, мин/пеш" => sub {
                    return '';
                },
            "Класс" => sub {
                    return '';
                },
            "Тип здания" => sub {
                    return '';
                },
            "Серия здания" => sub {
                    return '';
                },
            "Материал стен" => sub {
                    my $d = shift;
                    return $d->house_type ? $d->house_type->name : '';
                },
            "Год постройки/сдачи (г)" => sub {
                    return '';
                },
            "Количество этажей" => sub {
                    my $d = shift;
                    return $d->floors_count;
                },
            "Лифты в здании" => sub {
                    return '';
                },
            "Система отопления" => sub {
                    return '';
                },
            "Охрана здания" => sub {
                    return '';
                },
            "Высота потолков" => sub {
                    return '';
                },
            "Парковка" => sub {
                    return '';
                },
            "Общее количество машиномест" => sub {
                    return '';
                },
            "Этаж" => sub {
                    return '';
                },
            "Городской телефон" => sub {
                    return '';
                },
            "Ремонт" => sub {
                    my $d = shift;
                    return $d->condition ? $d->condition->name : '';
                },
            "1-я линия" => sub {
                    return '';
                },
            "Отдельный вход" => sub {
                    return '';
                },
            "Охрана парковки" => sub {
                    return '';
                },
            "Удаленность, км" => sub {
                    return '';
                },
            "Дополнительные сведения" => sub {
                    my $d = shift;
                    return $d->description ? $d->description : '';
                },
            "Фото" => sub {
                    my $d = shift;
                    my @photos = @{Rplus::Model::Photo::Manager->get_objects(query => [realty_id => $d->id, delete_date => undef], sort_by => 'id ASC', limit => 2)};
                    return join ", ", map {$_->filename} @photos;
                },
            "www-адрес" => sub {
                    return $site_url;
                },
            "Контактное лицо" => sub {
                    my $d = shift;
                    my $name = '';
                    if ($d->agent_id) {
                        $name = $d->agent->public_name || '';
                    }
                    return $name;
                },
            "Контактный телефон" => sub {
                    my $d = shift;
                    my $phones = $contact_phones;
                    if ($agent_phone == 1 && $d->agent) {
                        my $x = $d->agent->public_phone_num || $d->agent->phone_num;
                        $phones =  $x . ', ' . $phones;
                    }

                    return $phones;
                },
            "e-mail" => sub {
                    return $contact_email;
                },
            "" => sub {
                    return '';
                },
            "Комиссия" => sub {
                    return '';
                },

        ),

    },
);

sub index {
    my $self = shift;

    $config = $self->config;

    my $acc_id = $self->session('account')->{id};

    return $self->render_not_found unless $self->req->method eq 'POST';
    return $self->render(json => {error => 'Forbidden'}, status => 403) unless $self->has_permission(realty => 'export');

    my $media = Rplus::Model::Media::Manager->get_objects(query => [code => 'irr', type => 'export', delete_date => undef])->[0];
    return $self->render_not_found unless $media;

    Mojo::IOLoop->stream($self->tx->connection)->timeout(900);

    my $pictures = $self->param_b('pictures');
    my $offer_type_code = $self->param('offer_type_code');
    my $realty_type = $self->param('realty_type');

    my $meta = from_json($media->metadata);
    my ($fh, $file) = tmpnam();
    $meta->{'prev_file'} = $file;

    $media->metadata(encode_json($meta));
    $media->save(changes_only => 1);

    if ($pictures && $pictures == 1) {

        my $types = from_json(decode_base64($realty_type));

        my @sq;

        while (my ($offer_type_code, $type_codes) = each %$types) {
          foreach (@{$type_codes}) {
            push @sq, and => [offer_type_code => $offer_type_code, 'type.category_code' =>  $_];
          }
        }

        my $realty_iter = Rplus::Model::Realty::Manager->get_objects_iterator(
            query => [
                or => [
                  @sq
                ],
                account_id => $acc_id,
            ],
            sort_by => 'id ASC',
            require_objects => ['type', 'offer_type'],
            with_objects => ['house_type', 'balcony', 'bathroom', 'condition', 'agent'],
        );

        my $arch_name = "pictures";
        my $zip = Archive::Zip->new();
        while(my $realty = $realty_iter->next) {

            my @photos = @{Rplus::Model::Photo::Manager->get_objects(query => [realty_id => $realty->id, delete_date => undef], sort_by => 'id ASC', limit => 2)};

            foreach (@photos) {
                my $img_realty_id = (URI->new($_->filename)->path_segments)[-2];
                my $img_name = $_->filename;
                my $img_zipname = $img_name;
                my $img_path = '';

                $img_path = $self->config->{'storage'}->{'path'} . '/photos/' . $img_name;
                if (-e $img_path) {
                    my $member = $zip->addFile($img_path, $img_zipname);
                    $member->desiredCompressionLevel(COMPRESSION_LEVEL_NONE);
                }
            }
        }
        # Save the Zip file
        unless ( $zip->writeToFileNamed($file) == AZ_OK ) {

        }
        $self->res->headers->content_disposition("attachment; filename=pictures.zip;");
        $self->res->headers->set_cookie('download=start; path=/');
        $self->res->content->asset(Mojo::Asset::File->new(path => $file));
        return $self->rendered(200);
    }

    $city = $config->{export}->{city};

    my $options = Rplus::Model::Option->new(account_id => $acc_id)->load();
    if ($options) {
        my $e_opt = from_json($options->{options})->{'export'};
        $contact_phones = $e_opt->{'irr-phones'} ? trim($e_opt->{'irr-phones'}) : '';
        $agent_phone = 1 if $e_opt->{'irr-agent-phone'};
        $contact_name = '';
        $contact_email = $e_opt->{'irr-email'} ? $e_opt->{'irr-email'} : '';
        $site_url = $e_opt->{'irr-url'} ? $e_opt->{'irr-url'} : '';
    }

    my $csv = Text::CSV->new ( { binary => 1, quote_binary => 0, quote_space => 0, sep_char=> ";", eol => $/, } ) or return $self->render(json => {error => 'Server error'}, status => 500);

    my $template = $templates_hash{$offer_type_code}->{$realty_type};

    my @f_names = keys %$template;
    $csv->column_names(@f_names);
    $csv->print ($fh, $_) for \@f_names;

    my @tc;
    if ($realty_type eq 'apartment') {
      push @tc, type_code => ['apartment' , 'apartment_new', 'apartment_small', 'townhouse'];
    } elsif ($realty_type eq 'room') {
      push @tc, type_code => ['room'];
    } elsif ($realty_type eq 'house') {
      push @tc, type_code => ['house', 'cottage'];
    } elsif ($realty_type eq 'commercial') {
      push @tc, type_code => ['house'];
    } elsif ($realty_type eq 'land') {
      push @tc, type_code => ['land'];
    } elsif ($realty_type eq 'other') {
      push @tc, type_code => ['other'];
    }

    my $realty_iter = Rplus::Model::Realty::Manager->get_objects_iterator(
        query => [
            offer_type_code => $offer_type_code,
            @tc,
            export_media => {'&&' => $media->id},
            account_id => $acc_id,
        ],
        sort_by => 'id ASC',
        with_objects => ['house_type', 'balcony', 'bathroom', 'condition', 'agent'],
    );

    while(my $realty = $realty_iter->next) {
        my @val_array;
        foreach (keys %$template) {
            push @val_array, $template->{$_}->($realty);
        }
        $csv->print ($fh, \@val_array);
    }

    close $fh;

    my $file_name = $filename_hash->{"$offer_type_code-$realty_type"};
    $self->res->headers->content_disposition("attachment; filename=$file_name;");
    $self->res->content->asset(Mojo::Asset::File->new(path => $file));

    return $self->rendered(200);
}

1;
