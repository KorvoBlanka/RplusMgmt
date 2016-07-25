package RplusMgmt::Controller::Export::Yandex;

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

# translate out type to yandex type
# new flat

my $config;

my $company_name = '';
my $contact_phone = '';
my $agent_phone = 0;
my $contact_name = '';
my $contact_email = '';

my $region = '';
my $city = '';
my $timezone = '';

my %realty_types = ();


my %object_type = (

    room => 'room',

    apartment => 'flat',
    apartment_new => 'flat',
    apartment_small => '',

    house => 'house',
    dacha => 'house with lot',
    cottage => 'house',
    townhouse => 'townhouse',

    land => 'lot',

    building => 'commercial',
    office_place => 'commercial',
    service_place => 'commercial',
    gpurpose_place => 'commercial',
    production_place => 'commercial',
    autoservice_place => 'commercial',
    warehouse_place => 'commercial',
    market_place => 'commercial',
);

my %object_commercial_type = (
    office_place => 'office',
    service_place => 'free purpose',
    gpurpose_place => 'free purpose',
    production_place => 'manufacturing',
    autoservice_place => 'auto repair',
    warehouse_place => 'warehouse',
    market_place => 'retail',
);



my @common_fields = qw(type property-type category url creation-date last-update-date location sales-agent price deal-status);
my @description_fields = qw(area living-space kitchen-space lot-area renovation quality description);

my %fields_by_type = (
    living => [
      'rooms', 'rooms-offered', 'floor', 'open-plan', 'apartments', 'rooms-type', 'phone', 'internet',
      'room-furniture', 'kitchen-furniture', 'television', 'washing-machine', 'dishwasher', 'refrigerator',
      'built-in-tech', 'balcony', 'bathroom-unit', 'floor-covering', 'window-view'
    ],

    non_living => [
      'rooms', 'floor', 'entrance-type', 'phone-lines', 'adding-phone-on-request',
      'internet', 'self-selection-telecom', 'room-furniture', 'air-conditioner',
      'ventilation', 'fire-alarm', 'heating-supply', 'water-supply', 'sewerage-supply',
      'electricity-supply', 'electric-capacity', 'gas-supply', 'floor-covering',
      'window-view', 'window-type'
    ],
    building => [
      'floors-total', 'building-name', 'yandex-building-id', 'office-class', 'building-type',
      'building-series', 'building-phase', 'building-section', 'built-year', 'ready-quarter',
      'building-state', 'guarded-building', 'access-control-system', 'twenty-four-seven',
      'lift', 'rubbish-chute', 'is-elite', 'parking', 'parking-places', 'parking-place-price',
      'parking-guest', 'parking-guest-places', 'alarm', 'flat-alarm', 'security', 'ceiling-height',
      'eating-facilities'
    ],
    warehouse_production => [
      'responsible-storage', 'pallet-price', 'freight-elevator', 'truck-entrance', 'ramp',
      'railway', 'office-warehouse', 'open-area', 'service-three-pl', 'temperature-comment'
    ],
    residential => [
      'pmg', 'water-supply', 'sewerage-supply', 'heating-supply', 'electricity-supply',
      'gas-supply', 'kitchen', 'toilet', 'shower', 'pool', 'sauna', 'billiard'
    ]
);



my %fields_sub = (
# общие элементы
    'type' => sub { # продажа/аренда
        my ($r, $xw) = @_;
        $xw->startTag('type');
        $xw->characters($r->offer_type->name);
        $xw->endTag();
    },

    'property-type' => sub {  # жилая/коммерческая
        my ($r, $xw) = @_;
        $xw->startTag('property-type');
        if ($r->type->category_code eq 'commercial') {
            $xw->characters('коммерческая');
        } else {
            $xw->characters('жилая');
        }
        $xw->endTag();
    },

    'category' => sub {   # «комната»/«room», «квартира»/«flat», «таунхаус»/«townhouse», «дом»/«house», «часть дома», «участок»/«lot», «земельный участок», «дом с участком»/«house with lot», «дача»/«cottage», «коммерческая»/«commercial»
        my ($r, $xw) = @_;
        $xw->startTag('category');
        $xw->characters($object_type{$r->type_code});
        $xw->endTag();
    },

    'commercial-type' => sub {
        my ($r, $xw) = @_;
        $xw->startTag('commercial-type');
        $xw->characters($object_commercial_type{$r->type_code});
        $xw->endTag();
    },

    'url' => sub {
        my ($r, $xw) = @_;
        #$xw->startTag('url');
        #$xw->characters('');
        #$xw->endTag();
    },

    'creation-date' => sub {
        my ($r, $xw) = @_;
        $xw->startTag('creation-date');
        $xw->characters($r->add_date . $timezone);
        $xw->endTag();
    },

    'last-update-date' => sub {
        my ($r, $xw) = @_;
        $xw->startTag('last-update-date');
        $xw->characters($r->change_date . $timezone);
        $xw->endTag();
    },

    'location' => sub {
        my ($r, $xw) = @_;

        $xw->startTag('location');

        $xw->startTag('country');
        $xw->characters('Россия');
        $xw->endTag();

        $xw->startTag('region');
        $xw->characters($region);
        $xw->endTag();

        #$xw->startTag('district');
        #$xw->characters('');
        #$xw->endTag();

        $xw->startTag('locality-name');
        $xw->characters($r->locality);
        $xw->endTag();

        $xw->startTag('address');
        $xw->characters($r->address . ', ' . ($r->house_num ? $r->house_num : ''));
        $xw->endTag();

        $xw->startTag('latitude');
        $xw->characters($r->latitude);
        $xw->endTag();

        $xw->startTag('longitude');
        $xw->characters($r->longitude);
        $xw->endTag();

        $xw->endTag();
    },

    'sales-agent' => sub {
        my ($r, $xw) = @_;

        $xw->startTag('sales-agent');

        if ($r->agent && $r->agent->public_name) {
            $xw->startTag('name');
            $xw->characters($r->agent->public_name);
            $xw->endTag();
        }

        if ($r->agent) {
            $xw->startTag('phone');
            $xw->characters($r->agent->public_phone_num || $r->agent->phone_num);
            $xw->endTag();
        }

        $xw->startTag('category');
        $xw->characters('agency');
        $xw->endTag();

        $xw->startTag('organization');
        $xw->characters($company_name);
        $xw->endTag();

        $xw->startTag('email');
        $xw->characters($contact_email);
        $xw->endTag();

        $xw->startTag('url');
        $xw->characters('');
        $xw->endTag();

        #$xw->startTag('photo');
        #$xw->characters('');
        #$xw->endTag();

        $xw->endTag();
    },

    'price' => sub {
        my ($r, $xw) = @_;

        $xw->startTag('price');

        $xw->startTag('value');
        $xw->characters($r->owner_price * 1000);
        $xw->endTag();

        $xw->startTag('currency');
        $xw->characters('RUR');
        $xw->endTag();

        #$xw->startTag('unit');
        #$xw->characters();
        #$xw->endTag();

        if ($r->offer_type_code eq 'rent') {
            $xw->startTag('period');
            my $p;
            if ($r->rent_type eq 'long') {
                $xw->characters('месяц');
            } else {
                $xw->characters('день');
            }
            $xw->endTag();
        }

        $xw->endTag();
    },

    'agent-fee' => sub {
        my ($r, $xw) = @_;

        #$xw->startTag('agent-fee');
        #$xw->endTag();
    },

    'commission' => sub {
        my ($r, $xw) = @_;

        #$xw->startTag('commission');
        #$xw->endTag();
    },

    'deal-status' => sub {
        my ($r, $xw) = @_;

        $xw->startTag('deal-status');

        if ($r->offer_type_code eq 'rent') {
            $xw->characters('direct rent');
        } else {
            $xw->characters('sale');
        }

        $xw->endTag();
    },

    'area' => sub {
        my ($r, $xw) = @_;

        if ($r->square_total) {
            $xw->startTag('area');

            $xw->startTag('value');
            $xw->characters($r->square_total);
            $xw->endTag();

            $xw->startTag('unit');
            $xw->characters('sq. m');
            $xw->endTag();

            $xw->endTag();
        }
    },

    'living-space' => sub {
        my ($r, $xw) = @_;

        if ($r->square_living) {
            $xw->startTag('living-space');

            $xw->startTag('value');
            $xw->characters($r->square_living);
            $xw->endTag();

            $xw->startTag('unit');
            $xw->characters('sq. m');
            $xw->endTag();

            $xw->endTag();
        }
    },

    'kitchen-space' => sub {
        my ($r, $xw) = @_;

        if ($r->square_living) {
            $xw->startTag('kitchen-space');

            $xw->startTag('value');
            $xw->characters($r->square_kitchen);
            $xw->endTag();

            $xw->startTag('unit');
            $xw->characters('sq. m');
            $xw->endTag();

            $xw->endTag();
        }
    },

    'lot-area' => sub {
        my ($r, $xw) = @_;

        if ($r->square_land) {
            $xw->startTag('lot-area');

            $xw->startTag('value');
            $xw->characters($r->square_land);
            $xw->endTag();

            $xw->startTag('unit');
            $xw->characters($r->square_land_type);
            $xw->endTag();

            $xw->endTag();
        }
    },

    'renovation' => sub {
        my ($r, $xw) = @_;

        if ($r->condition) {
            $xw->startTag('renovation');
            $xw->characters($r->condition->name);
            $xw->endTag();
        }
    },

    'quality' => sub {
        my ($r, $xw) = @_;

        #$xw->startTag('quality');
        #$xw->endTag();
    },

    'description' => sub {
        my ($r, $xw) = @_;

        $xw->startTag('description');
        $xw->characters($r->description);
        $xw->endTag();
    },

    'rooms' => sub {
        my ($r, $xw) = @_;

        if ($r->rooms_count) {
            $xw->startTag('rooms');
            $xw->characters($r->rooms_count);
            $xw->endTag();
        }
    },

    'rooms-offered' => sub {
        my ($r, $xw) = @_;

        if ($r->rooms_offer_count) {
            $xw->startTag('rooms-offered');
            $xw->characters($r->rooms_offer_count);
            $xw->endTag();
        }
    },

    'floor' => sub {
        my ($r, $xw) = @_;

        if ($r->floor) {
            $xw->startTag('floor');
            $xw->characters($r->floor);
            $xw->endTag();
        }
    },

    'open-plan' => sub {
        my ($r, $xw) = @_;
    },

    'apartments' => sub {
        my ($r, $xw) = @_;
    },

    'rooms-type' => sub {
        my ($r, $xw) = @_;
        if ($r->room_scheme) {
            $xw->startTag('rooms-type');
            $xw->characters($r->room_scheme->name);
            $xw->endTag();
        }
    },

    'phone' => sub {
        my ($r, $xw) = @_;
    },

    'internet' => sub {
        my ($r, $xw) = @_;
    },

    'room-furniture' => sub {
        my ($r, $xw) = @_;
    },

    'kitchen-furniture' => sub {
        my ($r, $xw) = @_;
    },

    'television' => sub {
        my ($r, $xw) = @_;
    },

    'washing-machine' => sub {
        my ($r, $xw) = @_;
    },

    'dishwasher' => sub {
        my ($r, $xw) = @_;
    },

    'refrigerator' => sub {
        my ($r, $xw) = @_;
    },

    'built-in-tech' => sub {
        my ($r, $xw) = @_;
    },

    'balcony' => sub {
        my ($r, $xw) = @_;
        if ($r->balcony) {
            $xw->startTag('balcony');
            $xw->characters($r->balcony->name);
            $xw->endTag();
        }
    },

    'bathroom-unit' => sub {
        my ($r, $xw) = @_;
        if ($r->bathroom) {
            $xw->startTag('bathroom-unit');
            $xw->characters($r->bathroom->name);
            $xw->endTag();
        }
    },

    'floor-covering' => sub {
        my ($r, $xw) = @_;
    },

    'window-view' => sub {
        my ($r, $xw) = @_;
    },

    'entrance-type' => sub {
        my ($r, $xw) = @_;
    },

    'phone-lines' => sub {
        my ($r, $xw) = @_;
    },

    'adding-phone-on-request' => sub {
        my ($r, $xw) = @_;
    },

    'internet' => sub {
        my ($r, $xw) = @_;
    },

    'self-selection-telecom' => sub {
        my ($r, $xw) = @_;
    },

    'room-furniture' => sub {
        my ($r, $xw) = @_;
    },

    'air-conditioner' => sub {
        my ($r, $xw) = @_;
    },

    'ventilation' => sub {
        my ($r, $xw) = @_;
    },

    'fire-alarm' => sub {
        my ($r, $xw) = @_;
    },

    'heating-supply' => sub {
        my ($r, $xw) = @_;
    },

    'water-supply' => sub {
        my ($r, $xw) = @_;
    },

    'sewerage-supply' => sub {
        my ($r, $xw) = @_;
    },

    'electricity-supply' => sub {
        my ($r, $xw) = @_;
    },

    'electric-capacity' => sub {
        my ($r, $xw) = @_;
    },

    'gas-supply' => sub {
        my ($r, $xw) = @_;
    },

    'floor-covering' => sub {
        my ($r, $xw) = @_;
    },

    'window-type' => sub {
        my ($r, $xw) = @_;
    },

    'floors-total' => sub {
        my ($r, $xw) = @_;
        if ($r->floors_count) {
            $xw->startTag('floors-total');
            $xw->characters($r->floors_count);
            $xw->endTag();
        }
    },

    'building-name' => sub {
        my ($r, $xw) = @_;
    },

    'yandex-building-id' => sub {
        my ($r, $xw) = @_;
    },

    'office-class' => sub {
        my ($r, $xw) = @_;
    },

    'building-type' => sub {
        my ($r, $xw) = @_;
        if ($r->house_type) {
            $xw->startTag('building-type');
            $xw->characters($r->house_type->name);
            $xw->endTag();
        }
    },

    'building-series' => sub {
        my ($r, $xw) = @_;
    },

    'building-phase' => sub {
        my ($r, $xw) = @_;
    },

    'building-section' => sub {
        my ($r, $xw) = @_;
    },

    'built-year' => sub {
        my ($r, $xw) = @_;
    },

    'ready-quarter' => sub {
        my ($r, $xw) = @_;
    },

    'building-state' => sub {
        my ($r, $xw) = @_;
    },

    'guarded-building' => sub {
        my ($r, $xw) = @_;
    },

    'access-control-system' => sub {
        my ($r, $xw) = @_;
    },

    'twenty-four-seven' => sub {
        my ($r, $xw) = @_;
    },

    'lift' => sub {
        my ($r, $xw) = @_;
    },

    'rubbish-chute' => sub {
        my ($r, $xw) = @_;
    },

    'is-elite' => sub {
        my ($r, $xw) = @_;
    },

    'parking' => sub {
        my ($r, $xw) = @_;
    },

    'parking-places' => sub {
        my ($r, $xw) = @_;
    },

    'parking-place-price' => sub {
        my ($r, $xw) = @_;
    },

    'parking-guest' => sub {
        my ($r, $xw) = @_;
    },

    'parking-guest-places' => sub {
        my ($r, $xw) = @_;
    },

    'alarm' => sub {
        my ($r, $xw) = @_;
    },

    'flat-alarm' => sub {
        my ($r, $xw) = @_;
    },

    'security' => sub {
        my ($r, $xw) = @_;
    },

    'ceiling-height' => sub {
        my ($r, $xw) = @_;
    },

    'eating-facilities' => sub {
        my ($r, $xw) = @_;
    },


    'responsible-storage' => sub {
        my ($r, $xw) = @_;
    },

    'pallet-price' => sub {
        my ($r, $xw) = @_;
    },

    'freight-elevator' => sub {
        my ($r, $xw) = @_;
    },

    'truck-entrance' => sub {
        my ($r, $xw) = @_;
    },

    'ramp' => sub {
        my ($r, $xw) = @_;
    },

    'railway' => sub {
        my ($r, $xw) = @_;
    },

    'office-warehouse' => sub {
        my ($r, $xw) = @_;
    },

    'open-area' => sub {
        my ($r, $xw) = @_;
    },

    'service-three-pl' => sub {
        my ($r, $xw) = @_;
    },

    'temperature-comment' => sub {
        my ($r, $xw) = @_;
    },

    'pmg' => sub {
        my ($r, $xw) = @_;
    },

    'water-supply' => sub {
        my ($r, $xw) = @_;
    },

    'sewerage-supply' => sub {
        my ($r, $xw) = @_;
    },

    'heating-supply' => sub {
        my ($r, $xw) = @_;
    },

    'electricity-supply' => sub {
        my ($r, $xw) = @_;
    },

    'gas-supply' => sub {
        my ($r, $xw) = @_;
    },

    'kitchen' => sub {
        my ($r, $xw) = @_;
    },

    'toilet' => sub {
        my ($r, $xw) = @_;
    },

    'shower' => sub {
        my ($r, $xw) = @_;
    },

    'pool' => sub {
        my ($r, $xw) = @_;
    },

    'sauna' => sub {
        my ($r, $xw) = @_;
    },

    'billiard' => sub {
        my ($r, $xw) = @_;
    }
);

sub index {
    my $self = shift;

    Mojo::IOLoop->stream($self->tx->connection)->timeout(900);

    $config = $self->config;
    $region = $config->{export}->{region};
    $city = $config->{export}->{city};
    $timezone = $config->{timezone};

    $timezone = (substr $timezone, 0, 3) . ':00';

    my $media = Rplus::Model::Media::Manager->get_objects(query => [code => 'yandex', type => 'export', delete_date => undef])->[0];
    return $self->render_not_found unless $media;
    my $meta = from_json($media->metadata);

    return $self->render_not_found unless $self->req->method eq 'POST';
    return $self->render(json => {error => 'Forbidden'}, status => 403) unless $self->has_permission(realty => 'export');

    my $acc_id = $self->session('account')->{id};
    my $options = Rplus::Model::Option->new(account_id => $acc_id)->load();
    if ($options) {
        my $e_opt = from_json($options->{options})->{'export'};
        $company_name = $e_opt->{'yandex-company'} ? $e_opt->{'yandex-company'} : '';
        $contact_phone = $e_opt->{'yandex-phone'} ? trim($e_opt->{'yandex-phone'}) : '';
        $agent_phone = 1 if $e_opt->{'yandex-agent-phone'};
        $contact_name = '';
        $contact_email = $e_opt->{'yandex-email'} ? $e_opt->{'yandex-email'} : '';
    }


    my @sale_realty_types = split ',', $self->param('sale_realty_types');
    my @rent_realty_types = split ',', $self->param('rent_realty_types');

    my $realty_types = {
        sale => \@sale_realty_types,
        rent => \@rent_realty_types,
    };

    unlink($meta->{'prev_file'}) if $meta->{'prev_file'};
    my ($fh, $file) = tmpnam();
    $meta->{'prev_file'} = $file;
    $media->metadata(encode_json($meta));
    $media->save(changes_only => 1);

    my $xml_writer = XML::Writer->new(OUTPUT => $fh, DATA_MODE => 1, DATA_INDENT => '  ');
    $xml_writer->startTag('realty-feed', xmlns => "http://webmaster.yandex.ru/schemas/feed/realty/2010-06");

    $xml_writer->startTag('generation-date');
    $xml_writer->characters(DateTime->now() . $timezone);
    $xml_writer->endTag();

    while (my ($offer_type, $value) = each $realty_types) {
        for my $realty_type (@$value) {

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
                with_objects => ['house_type', 'balcony', 'bathroom', 'condition', 'agent'],
            );

            while(my $realty = $realty_iter->next) {

                my @fields = @common_fields;
                push (@fields, @description_fields);

                my $ya_type = 'non_living';

                if ($realty->type_code =~ /apartment/ || $realty->type_code eq 'townhouse' || $realty->type_code eq 'room') {
                    $ya_type = 'living';
                }

                if ($realty->type_code =~ /house/ || $realty->type_code =~ /cottage/) {
                    $ya_type = 'residential';
                }

                my @t_a = @{$fields_by_type{$ya_type}};
                push (@fields, @t_a);

                if ($ya_type ne 'residential') {
                    @t_a = @{$fields_by_type{'building'}};
                    push (@fields, @t_a);
                }

                $xml_writer->startTag('offer', 'internal-id' => $realty->id);
                foreach (@fields) {
                    say $_;
                    $fields_sub{$_}->($realty, $xml_writer);
                }
                $xml_writer->endTag();
            }
        }
    }
    $xml_writer->endTag('realty-feed');
    close $fh;

    my $file_name = 'yandex_a' . $acc_id . '.xml';
    my $path = $self->config->{'storage'}->{'path'} . '/files/export/' . $file_name;
    move($file, $path);

    my $mode = 0644;
    chmod $mode, $path;

    my $url = $config->{'storage'}->{'external'} .'/files/export/' . $file_name;

    return $self->render(json => {path => $url});
}

1;
