package RplusMgmt::Controller::Export::Zipal;

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
my $company_phone = '';
my $agent_phone = 0;
my $company_email = '';

my %fields_by_type = (
  apartments => [qw(type roomsCount roomsCountTotal separatedRoomsCount floorNumber floorsNumber material)],
  houses => [qw(landSquare houseType furniture renovation material heating distance burden electricity gas plumbing sewerage relief)],
  lands => [qw(distance burden electricity gas plumbing sewerage relief)],
  offices => [qw(buildingClass layout)],
  commercials => [qw(businessUsageType buildingType vatIncluded)],
  warehouses => [qw(sublease vatIncluded warehouseType floorsNumber)],
);

my %additional_fields_by_type = (
    apartments => [qw(usefulSquare kitchenSquare ceilingHeight renovation number toilet balcony series heating windowView)],
    houses => [qw(floorsNumber newFlat toilet roomsCount highwayId highwayName landUsageType communityName cadastralNumber railway railwayDistance railwayDistanceType forestDistance waterDistance)],
    lands => [qw(highwayId highwayName landUsageType communityName cadastralNumber railway railwayDistance railwayDistanceType forestDistance waterDistance)],
    offices => [],
    commercials => [qw(hallSquare groundFloor floorNumber floorsNumber objectCondition centerName parkingPlaces parkingType ceilingHeight year)],
    warehouses => [qw(conditioning storageType floorPressure columnSpace power floor unloading gate highwayAccess ceilingHeight year)],
);

my %fileds_by_offer = (
    sale => {
      apartments => [qw(credit mortgage)],
      houses => [qw(shape purpose credit mortgage)],
      lands => [qw(shape purpose)],
      offices => [],
      warehouses => [],
      commercials => [],
    },
    rent => {
      apartments => [qw(maxPeople)],
      houses => [qw()],
      lands => [qw()],
      offices => [qw(sublease)],
      warehouses => [qw(sublease)],
      commercials => [qw(sublease)],
    }
);

my %common_fields_by_offer = (
  sale => [qw(name description ownership price currency square)],
  rent => [qw(name description ownership price currency square deposit priceType period)]
);


my $get_zipal_balcony = {
  'без балкона' => '',
  'балкон' => 'BALCONY',
  'лоджия' => 'LOGGIA',
  '2 балкона' => 'BALCONY',
  '2 лоджии' => 'LOGGIA',
  'балкон и лоджия' => 'LOGGIA',
  'балкон застеклен' => 'BALCONY',
  'лоджия застеклена' => 'LOGGIA'
};

my $to_zipal_type = {
  'сталинка' => 'STALINKA',
  'хрущевка' => 'HRUSHEVKA',
  'общежитие' => 'GOSTINKA',
  'улучшенная' => 'FLAT',
  'новая' => 'FLAT',
  'индивидуальная' => 'FLAT'
};

sub get_zipal_flat_type {
  my $r = shift;

  return 'MALOSEMEIKA' if ($r->type_code eq 'apartment_small');
  return 'STUDIO' if ($r->room_scheme && $r->room_scheme->name eq 'студия');

  return $to_zipal_type->{$r->ap_scheme->name} if $r->ap_scheme;

  #ELITE
  #PENTHOUSE
  #APARTMENTS
  #HOSTEL
}

my $get_zipal_material = {
  'брус' => 'TIMBER',
  'кирпичный' => 'BRICK',
  'монолитный' => 'MONOLITH',
  'панельный' => 'PANEL',
  'деревянный' => 'WOOD',
  'каркасно-засыпной' => 'WOOD',
  'монолитно-кирпичный' => 'MONOBRICK'

  #CONCRETE
  #BLOCK
};

my $get_zipal_renovation = {
  'социальный ремонт' => 'COSMETIC',
  'сделан ремонт' => 'COSMETIC',
  'дизайнерский ремонт' => 'AUTHOR',
  'требуется ремонт' => 'NONE',
  'требуется косм. ремонт' => 'NONE',
  'после строителей' => 'NONE',
  'евроремонт' => 'EURO',
  'удовлетворительное' => 'NONE',
  'нормальное' => 'COSMETIC',
  'хорошее' => 'COSMETIC',
  'отличное' => 'COSMETIC'
};

my $get_zipal_toilet = {
  'с удобствами' => 'JOINED',
  'санузел совмещенный' => 'JOINED',
  'туалет' => 'SEPARATED',
  'душ и туалет' => 'SEPARATED',
  '2 раздельных санузла' => 'TWO',
  '2 смежных санузла' => 'TWO',
  'санузел раздельный' => 'SEPARATED',
  'без удобств' => ''
};

my %common_subs = (
    name => sub {
      my $r = shift;
      return _build_header($r);
    },
    description => sub {
      my $r = shift;
      return $r->description;
    },
    ownership => sub {
      return 'AGENT';
    },
    price => sub {
      my $r = shift;
      return $r->owner_price * 1000;
    },
    currency => sub {
      return "RUR";
    },
    square => sub {
      my $r = shift;
      return $r->square_total;
    },
    commission => sub {
      my $r = shift;
      return ($r->agency_price - $r->owner_price) * 1000;
    },
    commissionType => sub {
      my $r = shift;
      return "RUR";
    },

    deposit => sub {
      my $r = shift;
      my $hp = $r->owner_price / 2;

      if ($r->lease_deposite_id) {
        return $r->lease_deposite_id * $hp * 1000;
      } else {
        return 1;
      }
    },

    priceType => sub {
      my $r = shift;
      if ($r->rent_type eq 'long') {
        return 'MONTH';
      } else {
        return 'DAY';
      }
    },

    period => sub {
      my $r = shift;
      if ($r->rent_type eq 'long') {
        return 'LONG';
      } else {
        return 'SHORT';
      }
    },
);

my %fields_sub = (

    type => sub { # планировка
      my $r = shift;
      return get_zipal_flat_type($r);
    },

    roomsCount => sub {
      my $r = shift;
      return $r->rooms_offer_count if $r->rooms_offer_count;
      return $r->rooms_count;
    },

    roomsCountTotal => sub {
      my $r = shift;
      return $r->rooms_count;
    },

    separatedRoomsCount => sub {
      my $r = shift;
      return $r->rooms_count;
    },

    floorNumber => sub {
      my $r = shift;
      return $r->floor;
    },

    floorsNumber => sub {
      my $r = shift;
      return $r->floors_count;
    },

    material => sub {
      my $r = shift;
      return $get_zipal_material->{$r->house_type->name} if $r->house_type;
      return '';
    },

    usefulSquare => sub {
      my $r = shift;
      return $r->square_living;
    },

    kitchenSquare => sub {
      my $r = shift;
      return $r->square_kitchen;
    },

    ceilingHeight => sub {
      my $r = shift;
      return '';
    },

    renovation => sub {
      my $r = shift;
      return $get_zipal_renovation->{$r->condition->name} if $r->condition;
    },


    number => sub {
      my $r = shift;
      return $r->ap_num;
    },

    toilet => sub {
      my $r = shift;
      return $get_zipal_toilet->{$r->bathroom->name} if $r->bathroom;
    },

    balcony => sub {
      my $r = shift;
      return $get_zipal_balcony->{$r->balcony->name} if $r->balcony;
    },

    series => sub {
      my $r = shift;
      return '';
    },

    heating => sub {
      my $r = shift;
      return '';
    },

    windowView => sub {
      my $r = shift;
      return '';
    },

    landSquare => sub {
      my $r = shift;
      return $r->square_land;
    },

    houseType => sub {
      my $r = shift;
      return $r->type_code;
    },

    furniture => sub {
      my $r = shift;
      return 'PART';
    },

    distance => sub {
      my $r = shift;
      return '3';
    },

    burden => sub {
      my $r = shift;
      return 'false';
    },

    electricity => sub {
      my $r = shift;
      return 'YES';
    },

    gas => sub {
      my $r = shift;
      return 'NO';
    },

    plumbing => sub {
      my $r = shift;
      return 'YES';
    },

    sewerage => sub {
      my $r = shift;
      return 'YES';
    },

    relief => sub {
      my $r = shift;
      return 'FLAT';
    },

    newFlat => sub {
      my $r = shift;
      return '';
    },

    highwayId => sub {
      my $r = shift;
      return '';
    },

    highwayName => sub {
      my $r = shift;
      return '';
    },

    landUsageType => sub {
      my $r = shift;
      return '';
    },

    communityName => sub {
      my $r = shift;
      return '';
    },

    cadastralNumber => sub {
      my $r = shift;
      return '';
    },

    railway => sub {
      my $r = shift;
      return '';
    },

    railwayDistance => sub {
      my $r = shift;
      return '';
    },

    railwayDistanceType => sub {
      my $r = shift;
      return '';
    },

    forestDistance => sub {
      my $r = shift;
      return '';
    },

    waterDistance => sub {
      my $r = shift;
      return '';
    },

    buildingClass => sub {
      my $r = shift;
      return 'AMINUS';
    },

    layout => sub {
      my $r = shift;
      return 'MIXED';
    },

    buildingType => sub {
      my $r = shift;
      return 'OFFICE_BUILDING';
    },

    vatIncluded => sub {
      my $r = shift;
      return 'false';
    },

    businessUsageType => sub {
      my $r = shift;
      return 'ANY';
    },

    sublease => sub {
      my $r = shift;
      return 'false';
    },

    warehouseType => sub {
      my $r = shift;
      return 'WAREHOUSE';
    },

    groundFloor => sub {
      my $r = shift;
      return '';
    },

    objectCondition => sub {
      my $r = shift;
      return '';
    },

    centerName => sub {
      my $r = shift;
      return '';
    },

    parkingPlaces => sub {
      my $r = shift;
      return '';
    },

    parkingType => sub {
      my $r = shift;
      return '';
    },

    year => sub {
      my $r = shift;
      return '';
    },

    hallSquare => sub {
      my $r = shift;
      return $r->square_total;
    },

    conditioning => sub {
      my $r = shift;
      return '';
    },

    storageType => sub {
      my $r = shift;
      return '';
    },

    floorPressure => sub {
      my $r = shift;
      return '';
    },

    columnSpace => sub {
      my $r = shift;
      return '';
    },

    power => sub {
      my $r = shift;
      return '';
    },

    floor => sub {
      my $r = shift;
      return '';
    },

    unloading => sub {
      my $r = shift;
      return '';
    },

    gate => sub {
      my $r = shift;
      return '';
    },

    highwayAccess => sub {
      my $r = shift;
      return '';
    },

    shape => sub {
      my $r = shift;
      return 'REGULAR';
    },

    purpose => sub {
      my $r = shift;
      return 'RESERVATIONS';
    },

    credit => sub {
      my $r = shift;
      if ($r->description =~ /рассрочка/i) {
        return 'true';
      }
      return 'false';
    },

    mortgage => sub {
      my $r = shift;
      if ($r->description =~ /ипотека/i) {
        return 'true';
      }
      return 'false';
    },

    maxPeople => sub {
      my $r = shift;
      return '';
    },
);

sub get_db_type {
  my $zipal_type = shift;
  my @db_types;

  given ($zipal_type) {
    when (/apartments/) {
      push @db_types, ('apartment', 'apartment_new', 'apartment_new', 'apartment_small');
    }

    when (/houses/) {
      push @db_types, ('house', 'cottage', 'dacha', 'townhouse');
    }

    when (/lands/) {
      push @db_types, ('land');
    }

    when (/offices/) {
      push @db_types, ('office_place');
    }


    when (/commercials/) {
      push @db_types, ('market_place', 'building', 'production_place', 'gpurpose_place', 'autoservice_place', 'service_place');
    }

    when (/warehouses/) {
      push @db_types, ('warehouse_place');
    }
  }
  return \@db_types;
}

my $get_zipal_rq_type = {
  sale => {
    apartment => 'FlatSellRequestType',
    apartment_new => 'FlatSellRequestType',
    apartment_small => 'FlatSellRequestType',
    room => 'FlatSellRequestType',

    house => 'HouseSellRequestType',
    cottage => 'HouseSellRequestType',
    dacha => 'HouseSellRequestType',
    townhouse => 'HouseSellRequestType',

    land => 'LandSellRequestType',

    office_place => 'OfficeSellRequestType',
    warehouse_place => 'WarehouseSellRequestType',

    production_place => 'BusinessSellRequestType',
    autoservice_place => 'BusinessSellRequestType',
    building => 'BusinessSellRequestType',
    gpurpose_place => 'BusinessSellRequestType',
    service_place => 'BusinessSellRequestType',
    market_place => 'BusinessSellRequestType'
  },
  rent => {
    apartment => 'FlatRentRequestType',
    apartment_new => 'FlatRentRequestType',
    apartment_small => 'FlatRentRequestType',
    room => 'FlatRentRequestType',

    house => 'HouseRentRequestType',
    cottage => 'HouseRentRequestType',
    dacha => 'HouseRentRequestType',
    townhouse => 'HouseRentRequestType',

    land => '',   # no such type in zipal

    office_place => 'OfficeRentlRequestType',
    warehouse_place => 'WarehouseRentRequestType',

    production_place => 'BusinessRentRequestType',
    autoservice_place => 'BusinessRentRequestType',
    building => 'BusinessRentRequestType',
    gpurpose_place => 'BusinessRentRequestType',
    service_place => 'BusinessRentRequestType',
    market_place => 'BusinessRentRequestType'
  }
};


sub index {
    my $self = shift;

    $config = $self->config;

    my $acc_id = $self->session('account')->{id};

    return $self->render_not_found unless $self->req->method eq 'POST';
    return $self->render(json => {error => 'Forbidden'}, status => 403) unless $self->has_permission(realty => 'export');

    my $media = Rplus::Model::Media::Manager->get_objects(query => [code => 'zipal', type => 'export', delete_date => undef])->[0];
    return $self->render_not_found unless $media;

    Mojo::IOLoop->stream($self->tx->connection)->timeout(900);

    my @sale_realty_types = split ',', $self->param('sale_realty_types');
    my @rent_realty_types = split ',', $self->param('rent_realty_types');

    my $realty_types = {
        sale => \@sale_realty_types,
        rent => \@rent_realty_types,
    };

    my $meta = from_json($media->metadata);

    my $options = Rplus::Model::Option->new(account_id => $acc_id)->load();
    if ($options) {
        my $e_opt = from_json($options->{options})->{'export'};
        $company_name = $e_opt->{'zipal-company'} ? $e_opt->{'zipal-company'} : '';
        $company_phone = $e_opt->{'zipal-phone'} ? trim($e_opt->{'zipal-phone'}) : '';
        $agent_phone = 1 if $e_opt->{'zipal-agent-phone'};
        $company_email = $e_opt->{'zipal-email'} ? $e_opt->{'zipal-email'} : '';
    }

    unlink($meta->{'prev_file'}) if $meta->{'prev_file'};
    my ($fh, $file) = tmpnam();
    $meta->{'prev_file'} = $file;
    $media->metadata(encode_json($meta));
    $media->save(changes_only => 1);

    my $xml_writer = XML::Writer->new(OUTPUT => $fh, DATA_MODE => 1, DATA_INDENT => '  ');
    my $ts = time;
    $xml_writer->startTag('MassUploadRequest', timestamp => $ts, xmlns => 'http://assis.ru/ws/api');

    while (my ($offer_type, $value) = each $realty_types) {
        for my $realty_type (@$value) {

            my @fields;
            my @t_a = @{$fields_by_type{$realty_type}};
            push @fields, @t_a;
            @t_a = @{$additional_fields_by_type{$realty_type}};
            push @fields, @t_a;
            @t_a = @{$fileds_by_offer{$offer_type}->{$realty_type}};
            push @fields, @t_a;

            my $tc = get_db_type($realty_type);


            my @common_fields;
            push @common_fields, @{$common_fields_by_offer{$offer_type}};

            my $realty_iter = Rplus::Model::Realty::Manager->get_objects_iterator(
                query => [
                    offer_type_code => $offer_type,
                    or => [
                            type_code => $tc,
                        ],
                    export_media => {'&&' => $media->id},
                    account_id => $acc_id,
                ],
                sort_by => 'id ASC',
                require_objects => ['type', 'offer_type'],
                with_objects => ['house_type', 'balcony', 'bathroom', 'condition', 'agent',],
            );

            while(my $realty = $realty_iter->next) {

                $xml_writer->startTag('object', externalId => $realty->id, publish => "true");
                $xml_writer->startTag('request',
                  'xmlns:xsi' => 'http://www.w3.org/2001/XMLSchema-instance',
                  'xsi:type' => $get_zipal_rq_type->{$realty->offer_type_code}->{$realty->type_code},
                );

                my @common_params;
                foreach (@common_fields) {
                  my $val = $common_subs{$_}->($realty);
                  push @common_params, $_ => $val if $val;
                }

                $xml_writer->startTag('common',
                  @common_params
                );
                $xml_writer->startTag("address",
                  dom => $realty->house_num
                );

                if ($realty->latitude && $realty->longitude) {
                  $xml_writer->startTag("coordinates",
                    lat => $realty->latitude,
                    lon => $realty->longitude
                  );
                  $xml_writer->endTag();  # coordinates
                } else {
                  $xml_writer->startTag("styreet",
                    'xsi:type' => "SimpleStreetType",
                    name => $realty->locality . ' ' . $realty->address,
                  );
                }

                $xml_writer->endTag();  # address

                my @photos;
                my $photo_iter = Rplus::Model::Photo::Manager->get_objects_iterator(query => [realty_id => $realty->id, delete_date => undef], sort_by => 'id');
                while (my $photo = $photo_iter->next) {

                  my $url = '';
                  if ($photo->filename !~ /^http/) {
                      $url = $config->{storage}->{external} . '/photos/';
                  }

                  my $t = $url . $photo->filename;
                  $xml_writer->startTag('photos', url => $t, description => '');
                  $xml_writer->endTag();
                }


                my $contact_name = '';
                if ($realty->agent) {
                  $contact_name = $realty->agent->public_name || '';
                }

                my $contact_phone = '';
                if ($agent_phone && $realty->agent) {
                  $contact_phone = $realty->agent->public_phone_num || $realty->agent->phone_num;
                } else {
                  $contact_phone = $company_phone;
                }

                $xml_writer->startTag('contactInfo',
                  name => $contact_name,
                  phone => $contact_phone,
                  email => $company_email,
                  company => $company_name
                );
                $xml_writer->endTag();
                $xml_writer->endTag();  # common


                my @spec_params;
                foreach (@fields) {
                  my $val = $fields_sub{$_}->($realty);
                  push @spec_params, $_ => $val if $val;
                }

                $xml_writer->startTag('specific',
                  @spec_params
                );
                $xml_writer->endTag();

                $xml_writer->endTag();  # request
                $xml_writer->endTag();  # object
            }

        }
    }
    $xml_writer->endTag();  # req
    $xml_writer->end();
    close $fh;

    my $file_name = 'zipal_a' . $acc_id . '.xml';
    my $path = $self->config->{'storage'}->{'path'} . '/files/export/' . $file_name;
    move($file, $path);

    my $mode = 0644;
    chmod $mode, $path;

    my $url = $config->{'storage'}->{'external'} .'/files/export/' . $file_name;

    return $self->render(json => {path => $url});
}

sub _build_header {
  my $realty = shift;

  my @header;
  push @header, $realty->type->name;
  push @header, $realty->rooms_count . ' к.' if $realty->rooms_count;
  push @header, $realty->locality if $realty->locality;
  push @header, $realty->address if $realty->address;
  if ($realty->district) {
    push @header, '(' . $realty->district . ' )';
  }

  return join ', ', @header;
}

1;
