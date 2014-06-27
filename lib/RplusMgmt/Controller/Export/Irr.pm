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

use Mojo::Util qw(trim);
use File::Temp qw(tmpnam);
use JSON;
use Text::CSV;
use Tie::IxHash;
use Data::Dumper;

my $contact_phones = '';
my $agent_phone = 0;
my $contact_name = '';
my $contact_email = '';
my $site_url = '';

sub ordered_hash_ref {
    tie my %hash, 'Tie::IxHash', @_;
    return \%hash;
}

my %templates_hash = (
    sale => {
        apartments => ordered_hash_ref (
            "ID" => sub {
                    my $d = shift;
                    return $d->id;
                },
            "Город" => sub {
                    return 'Хабаровск';     # Подставить город из конфига?
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
                    return 'Рубли';
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
                    my $location = '';
                    if ($d->address_object) {
                        my $addr_obj = $d->address_object;
                        $location = $addr_obj->name . ($addr_obj->short_type ne 'ул' ? ' ' . $addr_obj->short_type : '');
                    }
                    
                    return $d->address_object ? $d->address_object->name : '';
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
                    my @photos = @{Rplus::Model::Photo::Manager->get_objects(query => [realty_id => $d->id, delete_date => undef])};
                    return join(", ", map { $_->filename } @photos);
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
        rooms => ordered_hash_ref (
            "ID" => sub {
                    my $d = shift;
                    return $d->id;
                },
            "Город" => sub {
                    return 'Хабароск';
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
                    return 'Рубли';
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
                    my $location = '';
                    if ($d->address_object) {
                        my $addr_obj = $d->address_object;
                        $location = $addr_obj->name . ($addr_obj->short_type ne 'ул' ? ' ' . $addr_obj->short_type : '');
                    }
                    
                    return $d->address_object ? $d->address_object->name : '';
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
                    my @photos = @{Rplus::Model::Photo::Manager->get_objects(query => [realty_id => $d->id, delete_date => undef])};
                    return join(", ", map { $_->filename } @photos);
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
        houses => ordered_hash_ref (
            "ID" => sub {
                    my $d = shift;
                    return $d->id;
                },
            "Город" => sub {
                    return 'Хабароск';
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
                    return 'Рубли';
                },
            "Удаленность, км" => sub {
                    return '';
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
                    my $location = '';
                    if ($d->address_object) {
                        my $addr_obj = $d->address_object;
                        $location = $addr_obj->name . ($addr_obj->short_type ne 'ул' ? ' ' . $addr_obj->short_type : '');
                    }
                    
                    return $d->address_object ? $d->address_object->name : '';
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
                    my @photos = @{Rplus::Model::Photo::Manager->get_objects(query => [realty_id => $d->id, delete_date => undef])};
                    return join(", ", map { $_->filename } @photos);
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
    },
    rent => {
        apartments => ordered_hash_ref (
            "ID" => sub {
                    my $d = shift;
                    return $d->id;
                },
            "Город" => sub {
                    return 'Хабароск';
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
                    return 'Рубли';
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
            "Мебель" => sub {
                    return '';
                },
            "Бытовая техника" => sub {
                    return '';
                },
            "Улица" => sub {
                    my $d = shift;
                    my $location = '';
                    if ($d->address_object) {
                        my $addr_obj = $d->address_object;
                        $location = $addr_obj->name . ($addr_obj->short_type ne 'ул' ? ' ' . $addr_obj->short_type : '');
                    }
                    
                    return $d->address_object ? $d->address_object->name : '';
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
                    my @photos = @{Rplus::Model::Photo::Manager->get_objects(query => [realty_id => $d->id, delete_date => undef])};
                    return join(", ", map { $_->filename } @photos);
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
        rooms => ordered_hash_ref (
            "ID" => sub {
                    my $d = shift;
                    return $d->id;                    
                },
            "Город" => sub {
                    return 'Хабароск';                    
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
                    return 'Рубли';
                },
            "Период аренды" => sub {
                    return 'Рубли';
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
            "Мебель" => sub {
                    return '';
                },
            "Бытовая техника" => sub {
                    return '';
                },
            "Улица" => sub {
                    my $d = shift;
                    my $location = '';
                    if ($d->address_object) {
                        my $addr_obj = $d->address_object;
                        $location = $addr_obj->name . ($addr_obj->short_type ne 'ул' ? ' ' . $addr_obj->short_type : '');
                    }
                    
                    return $d->address_object ? $d->address_object->name : '';
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
                    my @photos = @{Rplus::Model::Photo::Manager->get_objects(query => [realty_id => $d->id, delete_date => undef])};
                    return join(", ", map { $_->filename } @photos);
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
        houses => ordered_hash_ref (
            "ID" => sub {
                    my $d = shift;
                    return $d->id;                    
                },
            "Город" => sub {
                    return 'Хабароск';                    
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
                    return 'Рубли';
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
                    my $location = '';
                    if ($d->address_object) {
                        my $addr_obj = $d->address_object;
                        $location = $addr_obj->name . ($addr_obj->short_type ne 'ул' ? ' ' . $addr_obj->short_type : '');
                    }
                    
                    return $d->address_object ? $d->address_object->name : '';
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
                    my @photos = @{Rplus::Model::Photo::Manager->get_objects(query => [realty_id => $d->id, delete_date => undef])};
                    return join(", ", map { $_->filename } @photos);
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
    },
);

sub index {
    my $self = shift;

    return $self->render_not_found unless $self->req->method eq 'POST';
    return $self->render(json => {error => 'Forbidden'}, status => 403) unless $self->has_permission(realty => 'export');

    my $media = Rplus::Model::Media::Manager->get_objects(query => [code => 'irr', type => 'export', delete_date => undef])->[0];
    return $self->render_not_found unless $media;

    my $offer_type_code = $self->param('offer_type_code');
    my $realty_type = $self->param('realty_type');

    my $meta = from_json($media->metadata);

    my $rt_param = Rplus::Model::RuntimeParam->new(key => 'export')->load();
    if ($rt_param) {
        my $config = from_json($rt_param->{value});
        $contact_phones = $config->{'irr-phones'} ? trim($config->{'irr-phones'}) : '';
        $agent_phone = 1 if $config->{'irr-agent-phone'} eq 'true';
        $contact_name = '';
        $contact_email = $config->{'irr-email'} ? $config->{'irr-email'} : '';
        $site_url = $config->{'irr-url'} ? $config->{'irr-url'} : '';        
    }

    unlink($meta->{'prev_file'}) if $meta->{'prev_file'};
    my ($fh, $file) = tmpnam();
    $meta->{'prev_file'} = $file;

    $media->metadata(encode_json($meta));
    $media->save(changes_only => 1);

    my $csv = Text::CSV->new ( { binary => 1, eol => $/, } ) or return $self->render(json => {error => 'Server error'}, status => 500);

    my $template = $templates_hash{$offer_type_code}->{$realty_type};

    my @f_names = keys %$template;
    $csv->column_names(@f_names);
    $csv->print ($fh, $_) for \@f_names;


    my $realty_category = {};

    my @tc;
    given ($realty_type) {
        when (/apartments/) {
            push @tc, 'apartment';
            push @tc, 'apartment_small';
            push @tc, 'apartment_new';
            push @tc, 'townhouse';
        }
        when (/rooms/) {
            push @tc, 'room';
            push @tc, 'room';
            push @tc, 'room';
            push @tc, 'room';
        }
        when (/houses/) {
            push @tc, 'house';
            push @tc, 'cottage';
            push @tc, 'dacha';
            push @tc, 'land';

        }
    }

    print Dumper(@tc);

    my $realty_iter = Rplus::Model::Realty::Manager->get_objects_iterator(
        query => [
            state_code => 'work',
            offer_type_code => $offer_type_code,
            or => [
                  type_code => $tc[0],
                  type_code => $tc[1],
                  type_code => $tc[2],
                  type_code => $tc[3],
                ],
            export_media => {'&&' => $media->id},
        ],
        sort_by => 'address_object.expanded_name',
        require_objects => ['type', 'offer_type'],
        with_objects => ['address_object', 'house_type', 'balcony', 'bathroom', 'condition', 'agent'],
    );

    while(my $realty = $realty_iter->next) {
        my @val_array;
        foreach (keys %$template) {
            push @val_array, $template->{$_}->($realty);
        }
        $csv->print ($fh, \@val_array);
    }

    close $fh;

    $self->res->headers->content_disposition("attachment; filename=irr-$offer_type_code-$realty_type.csv;");
    $self->res->content->asset(Mojo::Asset::File->new(path => $file));

    return $self->rendered(200);
}

1;
