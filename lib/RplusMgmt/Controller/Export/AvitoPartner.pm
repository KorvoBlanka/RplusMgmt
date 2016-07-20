package RplusMgmt::Controller::Export::AvitoPartner;

use Mojo::Base 'Mojolicious::Controller';

use Rplus::Model::Media::Manager;
use Rplus::Model::Realty::Manager;
use Rplus::Model::Option::Manager;
use Rplus::Model::Photo::Manager;
use Rplus::Model::RealtyType::Manager;
use Rplus::Model::Landmark::Manager;

use XML::Writer;
use Mojo::Util qw(trim);
use File::Temp qw(tmpnam);
use File::Copy qw(move);
use File::Path qw(make_path);
use File::Basename;
use DateTime;
use JSON;
use URI;

my $config;

my $company_name = '';
my $contact_phone = '';
my $agent_phone = 0;
my $contact_name = '';
my $contact_email = '';

my $region = '';
my $city = '';

my %realty_types = ();
my %realty_types_keywords = ();

my $type_iter = Rplus::Model::RealtyType::Manager->get_objects_iterator(query => [],);
while (my $rt = $type_iter->next) {
    $realty_types{$rt->code} = $rt->category_code;
    $realty_types_keywords{$rt->code} = $rt->keywords;
}


# в категории other 'гаражи'' и 'other'. сделать категорию 'гараж'
my %realty_categorys = (
    apartment => "Квартиры",
    room => "Комнаты",
    house => "Дома, дачи, коттеджи",
    land => "Земельные участки",
    other => "Гаражи и машиноместа",
    commercial => "Коммерческая недвижимость",
    0 => "Недвижимость за рубежом",
);

my %to_avito_object_type = (

    house => 'Дом',
    dacha => 'Дача',
    cottage => 'Коттедж',
    townhouse => 'Таунхаус',


    land => 'Сельхозназначения (СНТ, ДНП)',
    #"Поселений (ИЖС)",
    #"Сельхозназначения (СНТ, ДНП)",
    #"Промназначения";

    garage => 'Гараж',
    #"Машиноместо";


    #"Гостиница",
    building => 'Помещение свободного назначения',
    office_place => 'Офисное помещение',
    service_place => 'Торговое помещение',
    gpurpose_place => 'Помещение свободного назначения',
    production_place => 'Производственное помещение',
    autoservice_place => 'Производственное помещение',
    warehouse_place => 'Складское помещение',
    market_place => 'Торговое помещение',

);


my %to_avito_house_type = (
    1 => 'Кирпичный',
    2 => 'Монолитный',
    3 => 'Панельный',
    4 => 'Деревянный',
    5 => 'Деревянный',
    6 => 'Деревянный',
    7 => 'Кирпичный',
);

my %to_avito_walls_type = (
    1 => 'Кипич',
    2 => 'Кипич',
    3 => 'Ж/б панели',
    4 => 'Бревно',
    5 => 'Брус',
    6 => 'Брус',
    7 => 'Кипич',
);

my @realty_fileds_common = qw(Id DateBegin DateEnd AdStatus EMail AllowEmail CompanyName ManagerName ContactPhone Region City Subway District Street Latitude Longitude Description Category OperationType Country Price Square Images VideoURL);

my %additional_fileds_by_type = (
    apartments => ['Rooms', 'Floor', 'Floors', 'HouseType', 'MarketType', 'NewDevelopmentId', 'CadastralNumber'],
    rooms => ['Rooms', 'Floor', 'Floors', 'HouseType', 'CadastralNumber'],
    houses => ['DistanceToCity', 'DirectionRoad', 'PriceType', 'Rooms', 'Floors', 'WallsType', 'ObjectType', 'CadastralNumber'],
    lands => ['DistanceToCity', 'DirectionRoad', 'PriceType', 'ObjectType', 'CadastralNumber'],
    garages => ['ObjectSubtype', 'Secured', 'ObjectType'],
    commercials => ['Title', 'PriceType', 'BuildingClass', 'ObjectType', 'CadastralNumber'],
);

my %additional_fileds_by_offer = (
    sale => [],
    rent => [
        'LeaseType',
        'LeaseBeds',
        'LeaseSleepingPlaces',
        'LeaseMultimedia',
        'LeaseAppliances',
        'LeaseComfort',
        'LeaseAdditionally',
        'LeaseCommission',
        'LeaseCommissionSize',
        'LeaseDeposit'
    ]
);

my %fields_sub = (
# общие элементы
    Id => sub {
        my $r = shift;
        return $r->id;
    },
    DateBegin => sub { return '' },
    DateEnd => sub { return '' },
    AdStatus => sub { return '' },

# контактная информация
    EMail => sub { return $contact_email; },
    AllowEmail => sub { return '' },
    CompanyName => sub { return $company_name; },
    ManagerName => sub {
        my $r = shift;
        my $name = '';
        if ($r->agent_id) {
            $name = $r->agent->public_name || '';
        }
        return $name;
    },
    ContactPhone => sub {
        my $r = shift;
        my $phones = $contact_phone;
        if ($agent_phone == 1 && $r->agent) {
            my $x = $r->agent->public_phone_num || $r->agent->phone_num;
            $phones =  $x;
        }
        return $phones;
    },

# местоположение
    Region => sub { return $region },
    City => sub { return $city },
    Subway => sub { return '' },
    District => sub {
        my $r = shift;
        my $area = Rplus::Model::Landmark::Manager->get_objects(query => [id => scalar($r->landmarks), type => 'farpost', delete_date => undef], limit => 1)->[0] if @{$r->landmarks};
        return $area ? $area->name : '';
    },    # ???
    Street => sub {
        my $r = shift;
        my $addr = '';
        if ($r->address && $r->locality) {
            $addr = $r->locality .', '. $r->address;
            if ($r->house_num) {
                $addr .= ' ' . $r->house_num;
            }
        }
        return $addr;
    },
    DistanceToCity => sub { return '0'; },
    DirectionRoad => sub { return ''; },
    Latitude => sub {
        my $r = shift;
        return $r->longitude ? $r->longitude : '';
    },
    Longitude => sub {
        my $r = shift;
        return $r->latitude ? $r->latitude : '';
    },

# Описание
    Description => sub {
        my $r = shift;
        return $r->description;
    },

# параметры недвижимости
    Category => sub {
        my $r = shift;
        my $category_code = $realty_types{$r->type_code};

        my $cat = $realty_categorys{$category_code};

        return $cat;
    },
    OperationType => sub {
        my $r = shift;
        if ($r->offer_type_code eq 'sale') {
            return 'Продам';
        } else {
            return 'Сдам';
        }
    },
    Country => sub { return '' },

    # (для ком недвижимости - вид объекта, осн парам)
    Title => sub {
        my $r = shift;
        my $title = $realty_types_keywords{$r->type_code};
    },
    Price => sub {
        my $r = shift;
        return $r->price * 1000;
    },
    PriceType => sub {
        my $r = shift;
        if ($r->offer_type_code eq 'sale') {
            return 'за всё';
        } else {
            return 'в месяц';
        }
    },
    Rooms => sub {
        my $r = shift;
        return $r->rooms_count;
    },
    Square => sub {
        my $r = shift;
        return $r->square_total;
    },

    LandArea => sub {
        my $r = shift;
        my $area = $r->square_land;
        if ($r->square_land_type eq 'hectare') {
            $area *= 100;
        }
        return $area;
    },
    Floor => sub {
        my $r = shift;
        return $r->floor;
    },
    Floors => sub {
        my $r = shift;
        return $r->floors_count;
    },

    HouseType => sub {
        my $r = shift;
        return $r->house_type_id ? $to_avito_house_type{$r->house_type_id} : '';
    },
    WallsType => sub {
        my $r = shift;
        return $r->house_type_id ? $to_avito_walls_type{$r->house_type_id} : '';
    },

    MarketType => sub {
        my $r = shift;
        return 'Новостройка' if ($r->type_code eq 'apartment_new');
        return 'Вторичка';
    },
    NewDevelopmentId => sub {
        return '';
    },

    ObjectType => sub {
        my $r = shift;
        return $to_avito_object_type{$r->type_code};
    },
    ObjectSubtype => sub {
        #только для гаражей
        return 'Кирпичный';
    },

    BuildingClass => sub {
        return '';
    },
    CadastralNumber => sub {
        return '';
    },
    Secured => sub {
        return 'Нет';
    },

# параметры и опции аренды
    LeaseType => sub {
        my $r = shift;
        return $r->rent_type eq 'long' ? 'На длительный срок' : 'Посуточно';
    },
    LeaseBeds => sub {
        return '';
    },
    LeaseSleepingPlaces => sub {
        return '';
    },
    LeaseMultimedia => sub {
        return '';
    },
    LeaseAppliances => sub {
        return '';
    },
    LeaseComfort => sub {
        return '';
    },
    LeaseAdditionally => sub {
        return '';
    },
    LeaseCommission => sub {
        my $r = shift;
        return 'Есть' if $r->agency_price > 0;
        return 'Нет';
    },
    LeaseCommissionSize => sub {
        my $r = shift;
        $r->agency_price ? (($r->price - $r->agency_price) * 1000) : '0';
    },
    LeaseDeposit => sub {
        my $r = shift;
        my $deposite = '';
        return 'Без залога' unless $r->lease_deposite_id;

        given($r->lease_deposite_id) {
            when (1) { $deposite = '0,5 месяца'; }
            when (2) { $deposite = '1 месяц'; }
            when (3) { $deposite = '1,5 месяца'; }
            when (4) { $deposite = '2 месяца'; }
            when (5) { $deposite = '2,5 месяца'; }
            when (6) { $deposite = '3 месяца'; }
        }

        return $deposite;
    },

#фото и видео
    Images => sub {
        my $r = shift;
        my @photos;
        my $photo_iter = Rplus::Model::Photo::Manager->get_objects_iterator(query => [realty_id => $r->id, delete_date => undef], sort_by => 'id');
        while (my $photo = $photo_iter->next) {
            my $url = '';
            if ($_ !~ /^http/) {
                $url = $config->{storage}->{external} . '/photos/';
            }
            push @photos, $url . $photo->filename;
        }
        return \@photos;
    },
    VideoURL => sub { return '' },
);

sub index {
    my $self = shift;

    $config = $self->config;

    my $acc_id = $self->session('account')->{id};

    return $self->render_not_found unless $self->req->method eq 'POST';
    return $self->render(json => {error => 'Forbidden'}, status => 403) unless $self->has_permission(realty => 'export');

    my $media = Rplus::Model::Media::Manager->get_objects(query => [code => 'avito', type => 'export', delete_date => undef])->[0];
    return $self->render_not_found unless $media;

    Mojo::IOLoop->stream($self->tx->connection)->timeout(900);

    my @sale_realty_types = split ',', $self->param('sale_realty_types');
    my @rent_realty_types = split ',', $self->param('rent_realty_types');

    my $realty_types = {
        sale => \@sale_realty_types,
        rent => \@rent_realty_types,
    };

    $region = $config->{export}->{region};
    $city = $config->{export}->{city};

    my $meta = from_json($media->metadata);

    my $options = Rplus::Model::Option->new(account_id => $acc_id)->load();
    if ($options) {
        my $e_opt = from_json($options->{options})->{'export'};
        $company_name = $e_opt->{'avito-company'} ? $e_opt->{'avito-company'} : '';
        $contact_phone = $e_opt->{'avito-phone'} ? trim($e_opt->{'avito-phone'}) : '';
        $agent_phone = 1 if $e_opt->{'avito-agent-phone'};
        $contact_name = '';
        $contact_email = $e_opt->{'avito-email'} ? $e_opt->{'avito-email'} : '';
    }

    unlink($meta->{'prev_file'}) if $meta->{'prev_file'};
    my ($fh, $file) = tmpnam();
    $meta->{'prev_file'} = $file;
    $media->metadata(encode_json($meta));
    $media->save(changes_only => 1);

    my $xml_writer = XML::Writer->new(OUTPUT => $fh, DATA_MODE => 1, DATA_INDENT => '  ');
    $xml_writer->startTag('Ads', target => 'Avito.ru', formatVersion => '3');

    while (my ($offer_type, $value) = each $realty_types) {
        for my $realty_type (@$value) {

            my @fields = @realty_fileds_common;
            my @t_a = @{$additional_fileds_by_type{$realty_type}};
            push (@fields, @t_a);
            @t_a = @{$additional_fileds_by_offer{$offer_type}};
            push (@fields, @t_a);

            #my $template = $templates_hash{$realty_type};

            my $realty_category = {};
            my @tc;
            if ($realty_type =~ /apartments/) {
                push @tc, 'type.category_code' => ['apartment'];
            };

            if ($realty_type =~ /rooms/) {
                push @tc, 'type.category_code' => ['room'];
            }

            if ($realty_type =~ /houses/) {
                push @tc, 'type.category_code' => ['house'];
            }

            if ($realty_type =~ /lands/) {
                push @tc, 'type.category_code' => ['land'];
            }

            if ($realty_type =~ /commercials/) {
                push @tc, 'type.category_code' => ['commercial', 'commersial'],;
            }

            if ($realty_type =~ /garages/) {
                push @tc, type_code => 'garage';
            }

            my $realty_iter = Rplus::Model::Realty::Manager->get_objects_iterator(
                query => [
                    offer_type_code => $offer_type,
                    or => [
                            @tc,
                        ],
                    export_media => {'&&' => $media->id},
                    account_id => $acc_id,
                ],
                sort_by => 'id ASC',
                require_objects => ['type', 'offer_type'],
                with_objects => ['house_type', 'balcony', 'bathroom', 'condition', 'agent',],
            );

            while(my $realty = $realty_iter->next) {

                $xml_writer->startTag('Ad');
                foreach (@fields) {
                    my $val = $fields_sub{$_}->($realty);
                    #next unless $val;   # ???
                    $xml_writer->startTag($_);
                    if($_ ne 'Images') {
                        $xml_writer->characters($val);
                    } else {
                        for my $photo (@$val) {
                            $xml_writer->startTag('Image', url => $photo);
                            $xml_writer->endTag();
                        }
                    }
                    $xml_writer->endTag();
                }
                $xml_writer->endTag();
            }

        }
    }
    $xml_writer->endTag('Ads');
    $xml_writer->end();
    close $fh;

    my $file_name = 'avito_a' . $acc_id . '.xml';
    my $path = $self->config->{'storage'}->{'path'} . '/files/export/' . $file_name;
    move($file, $path);

    my $mode = 0644;
    chmod $mode, $path;

    my $url = $config->{'storage'}->{'external'} .'/files/export/' . $file_name;

    return $self->render(json => {path => $url});
}

1;
