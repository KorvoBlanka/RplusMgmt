package RplusMgmt::Controller::Export::Vnh;

use Mojo::Base 'Mojolicious::Controller';

use Rplus::Model::Media;
use Rplus::Model::Media::Manager;
use Rplus::Model::Realty;
use Rplus::Model::Realty::Manager;
use Rplus::Model::Landmark;
use Rplus::Model::Landmark::Manager;
use Rplus::Model::Option;
use Rplus::Model::Option::Manager;
use Rplus::Model::Photo;
use Rplus::Model::Photo::Manager;

use Mojo::Util qw(trim);
use File::Temp qw(tmpnam);
use Excel::Writer::XLSX;
use JSON;
use Rplus::Util::Config qw(get_config);

sub index {
    my $self = shift;

    my $config = get_config();
    my $acc_id = $self->session('user')->{account_id};

    return $self->render_not_found unless $self->req->method eq 'POST';
    return $self->render(json => {error => 'Forbidden'}, status => 403) unless $self->has_permission(realty => 'export');

    my $media = Rplus::Model::Media::Manager->get_objects(query => [code => 'vnh', type => 'export', delete_date => undef])->[0];
    return $self->render_not_found unless $media;

    my $meta = from_json($media->metadata);

    
    my @sale_realty_types = split ',', $self->param('sale_realty_types');
    my @rent_realty_types = split ',', $self->param('rent_realty_types');

    my %realty_types;

    for (my $i = 0; $i < @sale_realty_types; $i ++) {
        $realty_types{$sale_realty_types[$i]}->{sale} = 1;
    }

    for (my $i = 0; $i < @rent_realty_types; $i ++) {
        $realty_types{$rent_realty_types[$i]}->{rent} = 1;
    }

    my $company = '';
    my $conf_phones = '';
    my $agent_phone = 0;

    my $options = Rplus::Model::Option->new(account_id => $acc_id)->load();
    if ($options) {
        my $e_opt = from_json($options->{options})->{'export'};
        $conf_phones = $e_opt->{'vnh-phones'} ? trim($e_opt->{'vnh-phones'}) : '';
        $agent_phone = 1 if $e_opt->{'vnh-agent-phone'};
        $company = $e_opt->{'vnh-company'} ? trim($e_opt->{'vnh-company'}) : '';
    }

    unlink($meta->{'prev_file'}) if $meta->{'prev_file'};
    my $file = tmpnam();
    $meta->{'prev_file'} = $file;

    $media->metadata(encode_json($meta));
    $media->save(changes_only => 1);


    {
        my $workbook = Excel::Writer::XLSX->new($file);
        my $header_fmt = $workbook->add_format(border => 1, bold => 1, bg_color => 'silver', valign  => 'vcenter', align => 'center', text_wrap => 1);
        my $txt_fmt = $workbook->add_format(num_format => '@');
        my $P = $meta->{'params'};

        # Раздел: Квартиры
        if ($realty_types{apartments}) {
            my @offer_types;
            if ($realty_types{apartments}->{sale}) {
                push @offer_types, 'sale';
            }
            if ($realty_types{apartments}->{rent}) {
                push @offer_types, 'rent';
            }

            my $worksheet = $workbook->add_worksheet("КВАРТИРЫ");
            # Заголовок листа
            my $header = {
                'A1' => { text => "Тип сделки",},
                'B1' => { text => "Тип объекта",},
                'C1' => { text => "Тип здания",},
                'D1' => { text => "Кол-во комнат",},
                'E1' => { text => "Тип комнат",},
                'F1' => { text => "Город/Нас. пункт",},
                'G1' => { text => "Район",},
                'H1' => { text => "Улица",},
                'I1' => { text => "Дом",},
                'J1' => { text => "Этаж",},
                'K1' => { text => "Всего этажей",},
                'L1' => { text => "Материал дома",},
                'M1' => { text => "Планировка",},
                'N1' => { text => "Общая площадь",},
                'O1' => { text => "Площадь жилая",},
                'P1' => { text => "Площадь кухни",},
                'Q1' => { text => "Санузел",},
                'R1' => { text => "Балкон",},
                'S1' => { text => "Остекление",},
                'T1' => { text => "Лоджия",},
                'U1' => { text => "Остекление",},
                'V1' => { text => "Площадь лоджии",},
                'W1' => { text => "Состояние",},
                'X1' => { text => "Описание",},
                'Y1' => { text => "Цена",},
                'Z1' => { text => "Телефон",},
                'AA1' => { text => "Фото",},
            };
            for my $x (keys %$header) {
                $worksheet->write_string($x, $header->{$x}->{'text'}, $header_fmt);
                $worksheet->set_column("$x:$x", $header->{$x}->{'width'}) if exists $header->{$x}->{'width'};
            }

            # Выборка объектов недвижимости
            my $realty_iter = Rplus::Model::Realty::Manager->get_objects_iterator(
                query => [
                    state_code => 'work',
                    offer_type_code => [@offer_types],
                    'type.category_code' => ['apartment'],
                    export_media => {'&&' => $media->id},
                    account_id => $acc_id,
                ],
                sort_by => 'address_object.expanded_name',
                with_objects => ['address_object', 'sublandmark', 'type', 'agent'],
            );

            my $row_num = 1;
            while(my $realty = $realty_iter->next) {
                my $city = 'Хабаровск';
                my $street = '';
                my $house_num = '';
                if ($realty->address_object_id) {
                    my $addrobj = $realty->address_object;
                    my $meta = from_json($addrobj->metadata);
                    $street = $addrobj->name.' '.$addrobj->short_type;
                    #$street = $addrobj->name.($addrobj->short_type ne 'ул' ? ' '.$addrobj->short_type : '');
                    $house_num = $realty->house_num;
                }
                my ($area, $subarea);
                if (@{$realty->landmarks}) {
                    $area = Rplus::Model::Landmark::Manager->get_objects(query => [id => scalar($realty->landmarks), type => 'vnh_area', delete_date => undef], limit => 1)->[0];
                    $subarea = Rplus::Model::Landmark::Manager->get_objects(query => [id => scalar($realty->landmarks), type => 'vnh_subarea', delete_date => undef], limit => 1)->[0];
                }

                my $phones = $conf_phones;
                if ($agent_phone == 1 && $realty->agent) {
                    my $x = $realty->agent->public_phone_num || $realty->agent->phone_num;
                    $phones =  $x . ', ' . $phones;
                }

                my $photos;
                my $photo_iter = Rplus::Model::Photo::Manager->get_objects_iterator(query => [realty_id => [$realty->id], delete_date => undef],);
                while (my $photo = $photo_iter->next) {
                    $photos = $photo->thumbnail_filename . ', ' . $photos;
                }

                my $row = [
                    $realty->offer_type->name,
                    'Квартира',
                    $realty->type_code eq 'apartment_new' ? 'новостройка' : 'вторичка',
                    $realty->rooms_count || '',
                    getVnhRoomsScheme($realty->room_scheme_id),
                    $city,
                    $area ? $area->name : '',
                    $street,
                    $house_num,
                    $realty->floor,
                    $realty->floors_count,
                    getVnhHouseType($realty->house_type_id),
                    getVnhApScheme($realty->ap_scheme_id),
                    $realty->square_total,
                    $realty->square_living,
                    $realty->square_kitchen,
                    getVnhBathroomScheme($realty->bathroom_id),
                    '', # балкон
                    '', # остекление
                    '', # лоджия
                    '', # остекление
                    '', # площадь лоджии
                    #$realty->balcony_id ? (($P->{'dict'}->{'balconies'}->{$realty->balcony_id}) // '') : '',
                    getVnhCondition($realty->condition_id),
                    $realty->description,
                    $realty->price,
                    $phones,
                    $photos,
                ];
                for my $col_num (0..(scalar(@$row)-1)) {
                    #if ($col_num == 5) {
                    #    $worksheet->write_string($row_num, $col_num, $row->[$col_num], $txt_fmt);
                    #} 
                    $worksheet->write($row_num, $col_num, $row->[$col_num]);
                }
                $row_num++;
            }
        }

        # Раздел: Комнаты
        if ($realty_types{rooms}) {
            my @offer_types;
            if ($realty_types{rooms}->{sale}) {
                push @offer_types, 'sale';
            }
            if ($realty_types{rooms}->{rent}) {
                push @offer_types, 'rent';
            }
            my $worksheet = $workbook->add_worksheet("КОМНАТЫ");
            # Заголовок листа
            my $header = {
                'A1' => { text => "Тип сделки",},
                'B1' => { text => "Тип объекта",},
                'C1' => { text => "Тип здания",},
                'D1' => { text => "Комнат на продажу",},
                'E1' => { text => "Комнат в квартире",},
                'F1' => { text => "Город/Нас. пункт",},
                'G1' => { text => "Район",},
                'H1' => { text => "Улица",},
                'I1' => { text => "Дом",},
                'J1' => { text => "Этаж",},
                'K1' => { text => "Всего этажей",},
                'L1' => { text => "Материал дома",},
                'M1' => { text => "Планировка",},
                'N1' => { text => "Общая площадь",},
                'O1' => { text => "Площадь жилая",},
                'P1' => { text => "Площадь кухни",},
                'Q1' => { text => "Санузел",},
                'R1' => { text => "Балкон",},
                'S1' => { text => "Остекление",},
                'T1' => { text => "Лоджия",},
                'U1' => { text => "Остекление",},
                'V1' => { text => "Площадь лоджии",},
                'W1' => { text => "Состояние",},
                'X1' => { text => "Описание",},
                'Y1' => { text => "Цена",},
                'Z1' => { text => "Телефон",},
                'AA1' => { text => "Фото",},
            };
            for my $x (keys %$header) {
                $worksheet->write_string($x, $header->{$x}->{'text'}, $header_fmt);
                $worksheet->set_column("$x:$x", $header->{$x}->{'width'}) if exists $header->{$x}->{'width'};
            }

            # Выборка объектов недвижимости
            my $realty_iter = Rplus::Model::Realty::Manager->get_objects_iterator(
                query => [
                    state_code => 'work',
                    offer_type_code => [@offer_types],
                    'type.category_code' => ['room'],
                    export_media => {'&&' => $media->id},
                    account_id => $acc_id,
                ],
                sort_by => 'address_object.expanded_name',
                with_objects => ['address_object', 'sublandmark', 'type', 'agent'],
            );
            my $row_num = 1;
            while(my $realty = $realty_iter->next) {
                my $city = 'Хабаровск';
                my $street = '';
                my $house_num = '';
                if ($realty->address_object_id) {
                    my $addrobj = $realty->address_object;
                    my $meta = from_json($addrobj->metadata);
                    $street = $addrobj->name.($addrobj->short_type ne 'ул' ? ' '.$addrobj->short_type : '');
                    $house_num = $realty->house_num;
                }
                my ($area, $subarea);
                if (@{$realty->landmarks}) {
                    $area = Rplus::Model::Landmark::Manager->get_objects(query => [id => scalar($realty->landmarks), type => 'vnh_area', delete_date => undef], limit => 1)->[0];
                    $subarea = Rplus::Model::Landmark::Manager->get_objects(query => [id => scalar($realty->landmarks), type => 'vnh_subarea', delete_date => undef], limit => 1)->[0];
                }

                my $phones = $conf_phones;
                if ($agent_phone == 1 && $realty->agent) {
                    my $x = $realty->agent->public_phone_num || $realty->agent->phone_num;
                    $phones =  $x . ', ' . $phones;
                }

                my $photos;
                my $photo_iter = Rplus::Model::Photo::Manager->get_objects_iterator(query => [realty_id => [$realty->id], delete_date => undef],);
                while (my $photo = $photo_iter->next) {
                    $photos = $photo->thumbnail_filename . ', ' . $photos;
                }

                my $row = [
                    $realty->offer_type->name,
                    'Комната',
                    $realty->type_code eq 'apartment_new' ? 'новостройка' : 'вторичка',
                    $realty->rooms_offer_count || '',
                    $realty->rooms_count || '',
                    $city,
                    $area ? $area->name : '',
                    $street,
                    $house_num,
                    $realty->floor,
                    $realty->floors_count,
                    getVnhHouseType($realty->house_type_id),
                    getVnhApScheme($realty->ap_scheme_id),
                    $realty->square_total,
                    $realty->square_living,
                    $realty->square_kitchen,
                    getVnhBathroomScheme($realty->bathroom_id),
                    '', # балкон
                    '', # остекление
                    '', # лоджия
                    '', # остекление
                    '', # площадь лоджии
                    #$realty->balcony_id ? (($P->{'dict'}->{'balconies'}->{$realty->balcony_id}) // '') : '',
                    getVnhCondition($realty->condition_id),
                    $realty->description,
                    $realty->price,
                    $phones,
                    $photos,
                ];
                for my $col_num (0..(scalar(@$row)-1)) {
                    #if ($col_num == 5) {
                    #    $worksheet->write_string($row_num, $col_num, $row->[$col_num], $txt_fmt);
                    #}
                    $worksheet->write($row_num, $col_num, $row->[$col_num]);
                }
                $row_num++;
            }
        }

        # Раздел: Частные дома и коттеджи
        if ($realty_types{houses})  {
            my @offer_types;
            if ($realty_types{houses}->{sale}) {
                push @offer_types, 'sale';
            }
            if ($realty_types{houses}->{rent}) {
                push @offer_types, 'rent';
            }
            my $worksheet = $workbook->add_worksheet("ДОМА");

            # Заголовок листа
            my $header = {
                'A1' => { text => "Тип сделки",},
                'B1' => { text => "Город/Нас. пункт",},
                'C1' => { text => "Район",},
                'D1' => { text => "Улица",},
                'E1' => { text => "№дома",},
                'F1' => { text => "Всего этажей",},
                'G1' => { text => "Материал дома",},
                'H1' => { text => "Участок соток",},
                'I1' => { text => "Общая площадь",},
                'J1' => { text => "Площадь жилая",},
                'K1' => { text => "Площадь кухни",},
                'L1' => { text => "Количество комнат",},
                'M1' => { text => "Описание",},
                'N1' => { text => "Цена",},
                'O1' => { text => "Телефон",},
                'P1' => { text => "Фото",},
            };
            for my $x (keys %$header) {
                $worksheet->write_string($x, $header->{$x}->{'text'}, $header_fmt);
                $worksheet->set_column("$x:$x", $header->{$x}->{'width'}) if exists $header->{$x}->{'width'};
            }

            # Выборка частных домов и коттеджей
            my $realty_iter = Rplus::Model::Realty::Manager->get_objects_iterator(
                query => [
                    state_code => 'work',
                    offer_type_code => [@offer_types],
                    'type.category_code' => 'house',
                    export_media => {'&&' => $media->id},
                    account_id => $acc_id,
                ],
                sort_by => 'address_object.expanded_name',
                with_objects => ['address_object', 'sublandmark', 'type', 'agent'],
            );
            my $row_num = 1;
            while(my $realty = $realty_iter->next) {
                my $city = 'Хабаровск';
                my $street = '';
                my $house_num = '';
                if ($realty->address_object_id) {
                    my $addrobj = $realty->address_object;
                    my $meta = from_json($addrobj->metadata);
                    $street = $addrobj->name.($addrobj->short_type ne 'ул' ? ' '.$addrobj->short_type : '');
                    $house_num = $realty->house_num;
                }
                my ($area, $subarea);
                if (@{$realty->landmarks}) {
                    $area = Rplus::Model::Landmark::Manager->get_objects(query => [id => scalar($realty->landmarks), type => 'vnh_area', delete_date => undef], limit => 1)->[0];
                    $subarea = Rplus::Model::Landmark::Manager->get_objects(query => [id => scalar($realty->landmarks), type => 'vnh_subarea', delete_date => undef], limit => 1)->[0];
                }

                my $phones = $conf_phones;
                if ($agent_phone == 1 && $realty->agent) {
                    my $x = $realty->agent->public_phone_num || $realty->agent->phone_num;
                    $phones =  $x . ', ' . $phones;
                }

                my $photos;
                my $photo_iter = Rplus::Model::Photo::Manager->get_objects_iterator(query => [realty_id => [$realty->id], delete_date => undef],);
                while (my $photo = $photo_iter->next) {
                    $photos = $photo->thumbnail_filename . ', ' . $photos;
                }

                my $row = [
                    $realty->offer_type->name,
                    $city,
                    $area ? $area->name : '',
                    $street,
                    $house_num,
                    $realty->floors_count,

                    getVnhHouseType($realty->house_type_id),

                    $realty->square_land, # перевести в сотки если не сотки

                    $realty->square_total,
                    $realty->square_living,
                    $realty->square_kitchen,

                    $realty->rooms_count,

                    $realty->description,
                    $realty->price,
                    $phones,
                    $photos,
                ];
                for my $col_num (0..(scalar(@$row)-1)) {
                    $worksheet->write($row_num, $col_num, $row->[$col_num]);
                }
                $row_num++;
            }
        }

        # Раздел: Частные дома и коттеджи
        if ($realty_types{commercials})  {
            my @offer_types;
            if ($realty_types{commercials}->{sale}) {
                push @offer_types, 'sale';
            }
            if ($realty_types{commercials}->{rent}) {
                push @offer_types, 'rent';
            }
            my $worksheet = $workbook->add_worksheet("КОММЕРЧЕСКАЯ НЕДВИЖИМОСТЬ");

            # Заголовок листа
            my $header = {
                'A1' => { text => "Тип сделки",},
                'B1' => { text => "Город",},
                'C1' => { text => "Район",},
                'D1' => { text => "Улица",},
                'E1' => { text => "№дома",},
                'F1' => { text => "Назначение объекта",},
                'G1' => { text => "Общая площадь, кв.м",},
                'H1' => { text => "Описание",},
                'I1' => { text => "Цена",},
                'J1' => { text => "Телефон",},
                'K1' => { text => "Фото",},
            };
            for my $x (keys %$header) {
                $worksheet->write_string($x, $header->{$x}->{'text'}, $header_fmt);
                $worksheet->set_column("$x:$x", $header->{$x}->{'width'}) if exists $header->{$x}->{'width'};
            }

            # Выборка частных домов и коттеджей
            my $realty_iter = Rplus::Model::Realty::Manager->get_objects_iterator(
                query => [
                    state_code => 'work',
                    offer_type_code => [@offer_types],
                    'type.category_code' => ['commercial', 'commersial'],
                    export_media => {'&&' => $media->id},
                    account_id => $acc_id,
                ],
                sort_by => 'address_object.expanded_name',
                with_objects => ['address_object', 'sublandmark', 'type', 'agent'],
            );
            my $row_num = 1;
            while(my $realty = $realty_iter->next) {
                my $city = 'Хабаровск';
                my $street = '';
                my $house_num = '';
                if ($realty->address_object_id) {
                    my $addrobj = $realty->address_object;
                    my $meta = from_json($addrobj->metadata);
                    $street = $addrobj->name.($addrobj->short_type ne 'ул' ? ' '.$addrobj->short_type : '');
                    $house_num = $realty->house_num;
                }
                my ($area, $subarea);
                if (@{$realty->landmarks}) {
                    $area = Rplus::Model::Landmark::Manager->get_objects(query => [id => scalar($realty->landmarks), type => 'vnh_area', delete_date => undef], limit => 1)->[0];
                    $subarea = Rplus::Model::Landmark::Manager->get_objects(query => [id => scalar($realty->landmarks), type => 'vnh_subarea', delete_date => undef], limit => 1)->[0];
                }

                my $phones = $conf_phones;
                if ($agent_phone == 1 && $realty->agent) {
                    my $x = $realty->agent->public_phone_num || $realty->agent->phone_num;
                    $phones =  $x . ', ' . $phones;
                }

                my $photos;
                my $photo_iter = Rplus::Model::Photo::Manager->get_objects_iterator(query => [realty_id => [$realty->id], delete_date => undef],);
                while (my $photo = $photo_iter->next) {
                    $photos = $photo->thumbnail_filename . ', ' . $photos;
                }

                my $row = [
                    $realty->offer_type->name,
                    $city,
                    $area ? $area->name : '',
                    $street,
                    $house_num,
                    toVnhType($realty->type_code),
                    $realty->square_total,
                    $realty->description,
                    $realty->price,
                    $phones,
                    $photos,
                ];
                for my $col_num (0..(scalar(@$row)-1)) {
                    $worksheet->write($row_num, $col_num, $row->[$col_num]);
                }
                $row_num++;
            }
        }

        # Раздел: участки и дачи
        if ($realty_types{lands})  {
            my @offer_types;
            if ($realty_types{lands}->{sale}) {
                push @offer_types, 'sale';
            }
            if ($realty_types{lands}->{rent}) {
                push @offer_types, 'rent';
            }
            my $worksheet = $workbook->add_worksheet("ЗЕМЕЛЬНЫЕ УЧАСТКИ");

            # Заголовок листа
            my $header = {
                'A1' => { text => "Тип сделки",},
                'B1' => { text => "Город",},
                'C1' => { text => "Район",},
                'D1' => { text => "Улица",},
                'E1' => { text => "№дома",},
                'F1' => { text => "Участок соток",},
                'G1' => { text => "Описание",},
                'H1' => { text => "Цена",},
                'I1' => { text => "Телефон",},
                'J1' => { text => "Фото",},
            };
            for my $x (keys %$header) {
                $worksheet->write_string($x, $header->{$x}->{'text'}, $header_fmt);
                $worksheet->set_column("$x:$x", $header->{$x}->{'width'}) if exists $header->{$x}->{'width'};
            }

            # Выборка частных домов и коттеджей
            my $realty_iter = Rplus::Model::Realty::Manager->get_objects_iterator(
                query => [
                    state_code => 'work',
                    offer_type_code => [@offer_types],
                    'type.category_code' => 'land',
                    export_media => {'&&' => $media->id},
                    account_id => $acc_id,
                ],
                sort_by => 'address_object.expanded_name',
                with_objects => ['address_object', 'sublandmark', 'type', 'agent'],
            );
            my $row_num = 1;
            while(my $realty = $realty_iter->next) {
                my $city = 'Хабаровск';
                my $street = '';
                my $house_num = '';
                if ($realty->address_object_id) {
                    my $addrobj = $realty->address_object;
                    my $meta = from_json($addrobj->metadata);
                    $street = $addrobj->name.($addrobj->short_type ne 'ул' ? ' '.$addrobj->short_type : '');
                    $house_num = $realty->house_num;
                }
                my ($area, $subarea);
                if (@{$realty->landmarks}) {
                    $area = Rplus::Model::Landmark::Manager->get_objects(query => [id => scalar($realty->landmarks), type => 'vnh_area', delete_date => undef], limit => 1)->[0];
                    $subarea = Rplus::Model::Landmark::Manager->get_objects(query => [id => scalar($realty->landmarks), type => 'vnh_subarea', delete_date => undef], limit => 1)->[0];
                }

                my $phones = $conf_phones;
                if ($agent_phone == 1 && $realty->agent) {
                    my $x = $realty->agent->public_phone_num || $realty->agent->phone_num;
                    $phones =  $x . ', ' . $phones;
                }

                my $photos;
                my $photo_iter = Rplus::Model::Photo::Manager->get_objects_iterator(query => [realty_id => [$realty->id], delete_date => undef],);
                while (my $photo = $photo_iter->next) {
                    $photos = $photo->thumbnail_filename . ', ' . $photos;
                }

                my $row = [
                    $realty->offer_type->name,
                    $city,
                    $area ? $area->name : '',
                    $street,
                    $house_num,
                    $realty->square_land,   # пнривести к соткам
                    $realty->description,
                    $realty->price,
                    $phones,
                    $photos,
                ];
                for my $col_num (0..(scalar(@$row)-1)) {
                    $worksheet->write($row_num, $col_num, $row->[$col_num]);
                }
                $row_num++;
            }
        }

        # Раздел: гаражи
        if ($realty_types{garages})  {
            my @offer_types;
            if ($realty_types{garages}->{sale}) {
                push @offer_types, 'sale';
            }
            if ($realty_types{garages}->{rent}) {
                push @offer_types, 'rent';
            }
            my $worksheet = $workbook->add_worksheet("ГАРАЖИ");

            # Заголовок листа
            my $header = {
                'A1' => { text => "Тип сделки",},
                'B1' => { text => "Город",},
                'C1' => { text => "Район",},
                'D1' => { text => "Улица",},
                'E1' => { text => "Описание",},
                'F1' => { text => "Цена",},
                'G1' => { text => "Телефон",},
                'H1' => { text => "Фото",},
            };
            for my $x (keys %$header) {
                $worksheet->write_string($x, $header->{$x}->{'text'}, $header_fmt);
                $worksheet->set_column("$x:$x", $header->{$x}->{'width'}) if exists $header->{$x}->{'width'};
            }

            # Выборка частных домов и коттеджей
            my $realty_iter = Rplus::Model::Realty::Manager->get_objects_iterator(
                query => [
                    state_code => 'work',
                    offer_type_code => [@offer_types],
                    type_code => 'garage',
                    export_media => {'&&' => $media->id},
                    account_id => $acc_id,
                ],
                sort_by => 'address_object.expanded_name',
                with_objects => ['address_object', 'sublandmark', 'type', 'agent'],
            );
            my $row_num = 1;
            while(my $realty = $realty_iter->next) {
                my $city = 'Хабаровск';
                my $street = '';
                my $house_num = '';
                if ($realty->address_object_id) {
                    my $addrobj = $realty->address_object;
                    my $meta = from_json($addrobj->metadata);
                    $street = $addrobj->name.($addrobj->short_type ne 'ул' ? ' '.$addrobj->short_type : '');
                    $house_num = $realty->house_num;
                }
                my ($area, $subarea);
                if (@{$realty->landmarks}) {
                    $area = Rplus::Model::Landmark::Manager->get_objects(query => [id => scalar($realty->landmarks), type => 'vnh_area', delete_date => undef], limit => 1)->[0];
                    $subarea = Rplus::Model::Landmark::Manager->get_objects(query => [id => scalar($realty->landmarks), type => 'vnh_subarea', delete_date => undef], limit => 1)->[0];
                }

                my $phones = $conf_phones;
                if ($agent_phone == 1 && $realty->agent) {
                    my $x = $realty->agent->public_phone_num || $realty->agent->phone_num;
                    $phones =  $x . ', ' . $phones;
                }

                my $photos;
                my $photo_iter = Rplus::Model::Photo::Manager->get_objects_iterator(query => [realty_id => [$realty->id], delete_date => undef],);
                while (my $photo = $photo_iter->next) {
                    $photos = $photo->thumbnail_filename . ', ' . $photos;
                }
                my $row = [
                    $realty->offer_type->name,
                    $city,
                    $area ? $area->name : '',
                    $street,
                    $realty->description,
                    $realty->price,
                    $phones,
                    $photos,
                ];
                for my $col_num (0..(scalar(@$row)-1)) {
                    $worksheet->write($row_num, $col_num, $row->[$col_num]);
                }
                $row_num++;
            }
        }

        $workbook->close;
    }

    $self->res->headers->content_disposition('attachment; filename=vnh.xlsx;');
    $self->res->content->asset(Mojo::Asset::File->new(path => $file));

    return $self->rendered(200);
}

sub toVnhType {
    my $type = shift;
    given ($type) {
        when ('market_place') {
            return 'магазин';
        }
        when ('office_place') {
            return 'офис';
        }
        when ('building') {
            return 'офис';
        }
        when ('production_place') {
            return 'промышленного назначения';
        }
        when ('gpurpose_place') {
            return 'свободного назначения';
        }
        when ('autoservice_place') {
            return 'промышленного назначения';
        }
        when ('service_place') {
            return 'ресторан';
        }
        when ('warehouse_place') {
            return 'база';
        }
    }
    return 'свободного назначения';
}

sub getVnhRoomsScheme {
    my $room_scheme_id = shift;
    given ($room_scheme_id) {
        when (1) {
            return 'студия';
        }
        when (2) {
            return 'другое';
        }
        when (3) {
            return 'раздельные';
        }
        when (4) {
            return 'смежные';
        }
        when (5) {
            return 'икарус';
        }
        when (6) {
            return 'смежно-раздельные';
        }
    }
    return 'другое';
}

sub getVnhHouseType {
    my $house_type_id = shift;
    given ($house_type_id) {
        when (1) {
            return 'кирпич';
        }
        when (2) {
            return 'монолит';
        }
        when (3) {
            return 'панель';
        }
        when (4) {
            return 'дерево';
        }
        when (5) {
            return 'брус';
        }
        when (6) {
            return 'дерево';
        }
        when (7) {
            return 'кирпич';
        }
    }
    return '';
}

sub getVnhApScheme {
    my $ap_scheme_id = shift;
    given ($ap_scheme_id) {
        when (1) {
            return 'сталинка';
        }
        when (2) {
            return 'хрущевка';
        }
        when (3) {
            return 'улучшенка';
        }
        when (4) {
            return 'новая планировка';
        }
        when (5) {
            return 'индивидуальная';
        }
        when (6) {
            return 'общежитие';
        }
    }
    return '';
}

sub getVnhBathroomScheme {
    my $bathroom_id = shift;

    given ($bathroom_id) {
        when (1) {
            return 'раздельный';
        }
        when (2) {
            return '';
        }
        when (3) {
            return 'раздельный';
        }
        when (4) {
            return 'совмещенный';
        }
        when (5) {
            return 'раздельный';
        }
        when (6) {
            return 'совмещенный';
        }
        when (7) {
            return 'совмещенный';
        }
        when (8) {
            return 'совмещенный';
        }
        when (8) {
            return 'совмещенный';
        }
        when (9) {
            return 'совмещенный';
        }
    }
    return '';
}

sub getVnhCondition {
    my $condition_id = shift;
    given ($condition_id) {
        when (1) {
            return 'после строителей';
        }
        when (2) {
            return 'хорошее';
        }
        when (3) {
            return 'хорошее';
        }
        when (4) {
            return 'евроремонт';
        }
        when (5) {
            return 'евроремонт';
        }
        when (6) {
            return 'требуется ремонт';
        }
        when (7) {
            return 'требуется ремонт';
        }
        when (9) {
            return 'удовлетворительное';
        }
        when (10) {
            return 'удовлетворительное';
        }
        when (11) {
            return 'хорошее';
        }
        when (12) {
            return 'отличное';
        }
    }
    return '';
}

1;
