package RplusMgmt::Controller::Export::Avito;

use Mojo::Base 'Mojolicious::Controller';

use Rplus::Model::Media;
use Rplus::Model::Media::Manager;
use Rplus::Model::Realty;
use Rplus::Model::Realty::Manager;
use Rplus::Model::Option;
use Rplus::Model::Option::Manager;
use Rplus::Model::Photo;
use Rplus::Model::Photo::Manager;

use XML::Writer;
use Mojo::Util qw(trim);
use File::Temp qw(tmpnam);
use Tie::IxHash;
use JSON;
use Data::Dumper;
use URI;

my $company_name = '';
my $contact_phone = '';
my $agent_phone = 0;
my $contact_name = '';
my $contact_email = '';

my $region = 'Хабаровский край';
my $city = 'Хабаровск';

sub ordered_hash_ref {
    tie my %hash, 'Tie::IxHash', @_;
    return \%hash;
}

my %templates_hash = (
    apartments => ordered_hash_ref (
        'ID' => sub {
                my $r = shift;
                return $r->id;
            },
        'Category' => sub {
                return 'Квартиры';
            },
        'OperationType' => sub {
                my $r = shift;
                if ($r->offer_type_code eq 'sale') {
                    return 'Продам';
                } else {
                    return 'Сдам';
                }
            },
        'Region' => sub {
                return $region;
            },
        'City' => sub {
                return $city;
            },
        'Street' => sub {
                my $r = shift;
                my $addr = '';
                if ($r->address_object) {
                    $addr = $r->address_object ? $r->address_object->name . ($r->address_object->short_type ne 'ул' ? ' ' . $r->address_object->short_type : '') : '';
                    if ($r->house_num) {
                        $addr .= ' ' . $r->house_num;
                    }
                }
                return $addr;
            },

        'Rooms' => sub {
                my $r = shift;
                return $r->rooms_count;
            },
        'Square' => sub {
                my $r = shift;
                return $r->square_total;
            },
        'Floor' => sub {
                my $r = shift;
                return $r->floor;
            },
        'Floors' => sub {
                my $r = shift;
                return $r->floors_count;
            },
        'HouseType' => sub {
                my $r = shift;
                return $r->house_type ? $r->house_type->name : '';
            },
        'Description' => sub {
                my $r = shift;
                return $r->description;
            },
        'Price' => sub {
                my $r = shift;
                return $r->price * 1000;
            },

        'CompanyName' => sub {
                return $company_name;
            },
        'ManagerName' => sub {
                my $r = shift;
                my $name = '';
                if ($r->agent_id) {
                    $name = $r->agent->public_name || '';
                }
                return $name;
            },
        'ContactPhone' => sub {
                my $r = shift;
                my $phones = $contact_phone;
                if ($agent_phone == 1 && $r->agent) {
                    my $x = $r->agent->public_phone_num || $r->agent->phone_num;
                    $phones =  $x;
                }
                return $phones;
            },
        'EMail' => sub {
                return $contact_email;
            },
        'Images' => sub {
                my $r = shift;
                my @photos;
                my $photo_iter = Rplus::Model::Photo::Manager->get_objects_iterator(query => [realty_id => $r->id, delete_date => undef], sort_by => 'id');
                while (my $photo = $photo_iter->next) {
                    push @photos, $photo->filename;
                }
                return \@photos;
            },
        'AdStatus' => sub {
                return 'Free';
            },
    ),
    rooms => ordered_hash_ref (
        'ID' => sub {
                my $r = shift;
                return $r->id;
            },
        'Category' => sub {
                return 'Комнаты';
            },
        'OperationType' => sub {
                my $r = shift;
                if ($r->offer_type_code eq 'sale') {
                    return 'Продам';
                } else {
                    return 'Сдам';
                }
            },
        'Region' => sub {
                return $region;
            },
        'City' => sub {
                return $city;
            },
        'Street' => sub {
                my $r = shift;
                my $addr = '';
                if ($r->address_object) {
                    $addr = $r->address_object ? $r->address_object->name . ($r->address_object->short_type ne 'ул' ? ' ' . $r->address_object->short_type : '') : '';
                    if ($r->house_num) {
                        $addr .= ' ' . $r->house_num;
                    }
                }
                return $addr;
            },
        'SaleRooms' => sub {
                my $r = shift;
                return $r->rooms_offer_count;
            },
        'Rooms' => sub {
                my $r = shift;
                return $r->rooms_count;
            },
        'Square' => sub {
                my $r = shift;
                return $r->square_total;
            },
        'Floor' => sub {
                my $r = shift;
                return $r->floor;
            },
        'Floors' => sub {
                my $r = shift;
                return $r->floors_count;
            },
        'HouseType' => sub {
                my $r = shift;
                return $r->house_type ? $r->house_type->name : '';
            },
        'Description' => sub {
                my $r = shift;
                return $r->description;
            },
        'Price' => sub {
                my $r = shift;
                return $r->price * 1000,
            },

        'CompanyName' => sub {
                return $company_name;
            },
        'ManagerName' => sub {
                my $r = shift;
                my $name = '';
                if ($r->agent_id) {
                    $name = $r->agent->public_name || '';
                }
                return $name;
            },
        'ContactPhone' => sub {
                my $r = shift;
                my $phones = $contact_phone;
                if ($agent_phone == 1 && $r->agent) {
                    my $x = $r->agent->public_phone_num || $r->agent->phone_num;
                    $phones =  $x;
                }
                return $phones;
            },
        'EMail' => sub {
                return $contact_email;
            },
        'Images' => sub {
                my $r = shift;
                my @photos;
                my $photo_iter = Rplus::Model::Photo::Manager->get_objects_iterator(query => [realty_id => $r->id, delete_date => undef], sort_by => 'id');
                while (my $photo = $photo_iter->next) {
                    push @photos, $photo->filename;
                }
                return \@photos;
            },
        'AdStatus' => sub {
                return 'Free';
            },
    ),
    houses => ordered_hash_ref (
        'ID' => sub {
                my $r = shift;
                return $r->id;
            },
        'Category' => sub {
                return 'Дома, дачи, коттеджи';
            },
        'ObjectType' => sub {
                my $r = shift;
                return $r->type_code ? $r->type->name : '';
            },
        'OperationType' => sub {
                my $r = shift;
                if ($r->offer_type_code eq 'sale') {
                    return 'Продам';
                } else {
                    return 'Сдам';
                }
            },
        'Region' => sub {
                return $region;
            },
        'City' => sub {
                return $city;
            },
        'Street' => sub {
                my $r = shift;
                my $addr = '';
                if ($r->address_object) {
                    $addr = $r->address_object ? $r->address_object->name . ($r->address_object->short_type ne 'ул' ? ' ' . $r->address_object->short_type : '') : '';
                    if ($r->house_num) {
                        $addr .= ' ' . $r->house_num;
                    }
                }
                return $addr;
            },
        'DistanceToCity' => sub {
                return 0;
            },            
        'Square' => sub {
                my $r = shift;
                return $r->square_total;
            },
        'LandArea' => sub {
                my $r = shift;
                return $r->square_land;
            },
        'Floors' => sub {
                my $r = shift;
                return $r->floors_count;
            },
        'WallsType' => sub {
                my $r = shift;
                return $r->house_type ? $r->house_type->name : '';
            },
        'Description' => sub {
                my $r = shift;
                return $r->description;
            },
        'Price' => sub {
                my $r = shift;
                return $r->price * 1000,
            },

        'CompanyName' => sub {
                return $company_name;
            },
        'ManagerName' => sub {
                my $r = shift;
                my $name = '';
                if ($r->agent_id) {
                    $name = $r->agent->public_name || '';
                }
                return $name;
            },
        'ContactPhone' => sub {
                my $r = shift;
                my $phones = $contact_phone;
                if ($agent_phone == 1 && $r->agent) {
                    my $x = $r->agent->public_phone_num || $r->agent->phone_num;
                    $phones =  $x;
                }
                return $phones;
            },
        'EMail' => sub {
                return $contact_email;
            },
        'Images' => sub {
                my $r = shift;
                my @photos;
                my $photo_iter = Rplus::Model::Photo::Manager->get_objects_iterator(query => [realty_id => $r->id, delete_date => undef], sort_by => 'id');
                while (my $photo = $photo_iter->next) {
                    push @photos, $photo->filename;
                }
                return \@photos;
            },
        'AdStatus' => sub {
                return 'Free';
            },
    ),

    lands => ordered_hash_ref (
        'ID' => sub {
                my $r = shift;
                return $r->id;
            },
        'Category' => sub {
                return 'Земельные участки';
            },
        'ObjectType' => sub {
                my $r = shift;
                return $r->type_code ? $r->type->name : '';
            },
        'OperationType' => sub {
                my $r = shift;
                if ($r->offer_type_code eq 'sale') {
                    return 'Продам';
                } else {
                    return 'Сдам';
                }
            },
        'Region' => sub {
                return $region;
            },
        'City' => sub {
                return $city;
            },
        'Street' => sub {
                my $r = shift;
                my $addr = '';
                if ($r->address_object) {
                    $addr = $r->address_object ? $r->address_object->name . ($r->address_object->short_type ne 'ул' ? ' ' . $r->address_object->short_type : '') : '';
                    if ($r->house_num) {
                        $addr .= ' ' . $r->house_num;
                    }
                }
                return $addr;
            },
        'DistanceToCity' => sub {
                return 0;
            },            
        'LandArea' => sub {
                my $r = shift;
                return $r->square_land;
            },
        'Description' => sub {
                my $r = shift;
                return $r->description;
            },
        'Price' => sub {
                my $r = shift;
                return $r->price * 1000,
            },

        'CompanyName' => sub {
                return $company_name;
            },
        'ManagerName' => sub {
                my $r = shift;
                my $name = '';
                if ($r->agent_id) {
                    $name = $r->agent->public_name || '';
                }
                return $name;
            },
        'ContactPhone' => sub {
                my $r = shift;
                my $phones = $contact_phone;
                if ($agent_phone == 1 && $r->agent) {
                    my $x = $r->agent->public_phone_num || $r->agent->phone_num;
                    $phones =  $x;
                }
                return $phones;
            },
        'EMail' => sub {
                return $contact_email;
            },
        'Images' => sub {
                my $r = shift;
                my @photos;
                my $photo_iter = Rplus::Model::Photo::Manager->get_objects_iterator(query => [realty_id => $r->id, delete_date => undef], sort_by => 'id');
                while (my $photo = $photo_iter->next) {
                    push @photos, $photo->filename;
                }
                return \@photos;
            },
        'AdStatus' => sub {
                return 'Free';
            },
    ),

    garages => ordered_hash_ref (
        'ID' => sub {
                my $r = shift;
                return $r->id;
            },
        'Category' => sub {
                return 'Гаражи и стоянки';
            },
        'ObjectType' => sub {
                my $r = shift;
                return 'Гараж';
            },
        'OperationType' => sub {
                my $r = shift;
                if ($r->offer_type_code eq 'sale') {
                    return 'Продам';
                } else {
                    return 'Сдам';
                }
            },
        'Region' => sub {
                return $region;
            },
        'City' => sub {
                return $city;
            },
        'Street' => sub {
                my $r = shift;
                my $addr = '';
                if ($r->address_object) {
                    $addr = $r->address_object ? $r->address_object->name . ($r->address_object->short_type ne 'ул' ? ' ' . $r->address_object->short_type : '') : '';
                    if ($r->house_num) {
                        $addr .= ' ' . $r->house_num;
                    }
                }
                return $addr;
            },
        'DistanceToCity' => sub {
                return 0;
            },            
        'Square' => sub {
                my $r = shift;
                return $r->square_total;
            },
        'Description' => sub {
                my $r = shift;
                return $r->description;
            },
        'Price' => sub {
                my $r = shift;
                return $r->price * 1000,
            },

        'CompanyName' => sub {
                return $company_name;
            },
        'ManagerName' => sub {
                my $r = shift;
                my $name = '';
                if ($r->agent_id) {
                    $name = $r->agent->public_name || '';
                }
                return $name;
            },
        'ContactPhone' => sub {
                my $r = shift;
                my $phones = $contact_phone;
                if ($agent_phone == 1 && $r->agent) {
                    my $x = $r->agent->public_phone_num || $r->agent->phone_num;
                    $phones =  $x;
                }
                return $phones;
            },
        'EMail' => sub {
                return $contact_email;
            },
        'Images' => sub {
                my $r = shift;
                my @photos;
                my $photo_iter = Rplus::Model::Photo::Manager->get_objects_iterator(query => [realty_id => $r->id, delete_date => undef], sort_by => 'id');
                while (my $photo = $photo_iter->next) {
                    push @photos, $photo->filename;
                }
                return \@photos;
            },
        'AdStatus' => sub {
                return 'Free';
            },
    ),

    commercials => ordered_hash_ref (
        'ID' => sub {
                my $r = shift;
                return $r->id;
            },
        'Category' => sub {
                return 'Коммерческая недвижимость';
            },
        'ObjectType' => sub {
                my $r = shift;
                given ($r->type_code) {

                    when ('market_place') {
                        return 'Торговое помещение';
                    }
                    when ('office_place') {
                        return 'Офисное помещение'
                    }
                    when ('office') {
                        return 'Офисное помещение'
                    }
                    when ('building') {
                        return 'Помещение свободного назначения'
                    }
                    when ('production_place') {
                        return 'Производственное помещение'
                    }
                    when ('gpurpose_place') {
                        return 'Помещение свободного назначения'
                    }
                    when ('autoservice_place') {
                        return 'Производственное помещение'
                    }
                    when ('service_place') {
                        return 'Помещение свободного назначения'
                    }
                    when ('warehouse_place') {
                        return 'Складское помещение'
                    }
                }
                return 'Помещение свободного назначения'
            },
        'OperationType' => sub {
                my $r = shift;
                if ($r->offer_type_code eq 'sale') {
                    return 'Продам';
                } else {
                    return 'Сдам';
                }
            },
        'Region' => sub {
                return $region;
            },
        'City' => sub {
                return $city;
            },
        'Street' => sub {
                my $r = shift;
                my $addr = '';
                if ($r->address_object) {
                    $addr = $r->address_object ? $r->address_object->name . ($r->address_object->short_type ne 'ул' ? ' ' . $r->address_object->short_type : '') : '';
                    if ($r->house_num) {
                        $addr .= ' ' . $r->house_num;
                    }
                }
                return $addr;
            },
        'DistanceToCity' => sub {
                return 0;
            },            
        'Square' => sub {
                my $r = shift;
                return $r->square_total;
            },
        'Description' => sub {
                my $r = shift;
                return $r->description;
            },
        'Price' => sub {
                my $r = shift;
                return $r->price * 1000,
            },

        'CompanyName' => sub {
                return $company_name;
            },
        'ManagerName' => sub {
                my $r = shift;
                my $name = '';
                if ($r->agent_id) {
                    $name = $r->agent->public_name || '';
                }
                return $name;
            },
        'ContactPhone' => sub {
                my $r = shift;
                my $phones = $contact_phone;
                if ($agent_phone == 1 && $r->agent) {
                    my $x = $r->agent->public_phone_num || $r->agent->phone_num;
                    $phones =  $x;
                }
                return $phones;
            },
        'EMail' => sub {
                return $contact_email;
            },
        'Images' => sub {
                my $r = shift;
                my @photos;
                my $photo_iter = Rplus::Model::Photo::Manager->get_objects_iterator(query => [realty_id => $r->id, delete_date => undef], sort_by => 'id');
                while (my $photo = $photo_iter->next) {
                    push @photos, $photo->filename;
                }
                return \@photos;
            },
        'AdStatus' => sub {
                return 'Free';
            },
    ),
);

sub index {
    my $self = shift;

    my $acc_id = $self->session('user')->{account_id};

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

    my $meta = from_json($media->metadata);

    my $options = Rplus::Model::Option->new(account_id => $acc_id)->load();
    if ($options) {
        my $e_opt = from_json($options->{options})->{'export'};
        $company_name = $e_opt->{'avito-company'} ? $e_opt->{'avito-company'} : '';                
        $contact_phone = $e_opt->{'avito-phone'} ? trim($e_opt->{'avito-phone'}) : '';
        $agent_phone = 1 if $e_opt->{'avito-agent-phone'};
        $contact_name = '';
        $contact_email = $e_opt->{'irr-email'} ? $e_opt->{'irr-email'} : '';
    }

    unlink($meta->{'prev_file'}) if $meta->{'prev_file'};
    my ($fh, $file) = tmpnam();
    $meta->{'prev_file'} = $file;
    $media->metadata(encode_json($meta));
    $media->save(changes_only => 1);

    my $xml_writer = XML::Writer->new(OUTPUT => $fh, DATA_MODE => 1, DATA_INDENT => '  ');
    $xml_writer->startTag('Ads', target => 'Avito.ru', formatVersion => '2');

    while (my ($offer_type, $value) = each $realty_types) {
        for my $realty_type (@$value) {
            my $template = $templates_hash{$realty_type};

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
                    state_code => 'work',
                    offer_type_code => $offer_type,
                    or => [
                            @tc,
                        ],
                    export_media => {'&&' => $media->id},
                    account_id => $acc_id,
                ],
                sort_by => 'id ASC',
                require_objects => ['type', 'offer_type'],
                with_objects => ['address_object', 'house_type', 'balcony', 'bathroom', 'condition', 'agent',],
            );

            while(my $realty = $realty_iter->next) {
                
                $xml_writer->startTag('Ad');
                foreach (keys %$template) {
                    my $val = $template->{$_}->($realty);
                    next unless $val;
                    $xml_writer->startTag($_);
                    if($_ ne 'Images') {
                        $xml_writer->characters($val);
                    } else {
                        print Dumper $val;
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

    $self->res->headers->content_disposition("attachment; filename=avito.xml;");
    $self->res->content->asset(Mojo::Asset::File->new(path => $file));

    return $self->rendered(200);
}

1;
