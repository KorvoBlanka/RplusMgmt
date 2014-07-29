package RplusMgmt::Controller::Export::Avito;

use Mojo::Base 'Mojolicious::Controller';

use Rplus::Model::Media;
use Rplus::Model::Media::Manager;
use Rplus::Model::Realty;
use Rplus::Model::Realty::Manager;
use Rplus::Model::RuntimeParam;
use Rplus::Model::RuntimeParam::Manager;
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
                    $addr = $r->address_object ? $r->address_object->name . ($r->address_object->short_type ne 'ул' ? ' ' . $r->address_object->short_type : '') : '',
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
                    $addr = $r->address_object ? $r->address_object->name . ($r->address_object->short_type ne 'ул' ? ' ' . $r->address_object->short_type : '') : '',
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
                    $addr = $r->address_object ? $r->address_object->name . ($r->address_object->short_type ne 'ул' ? ' ' . $r->address_object->short_type : '') : '',
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
);

sub index {
    my $self = shift;

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

    my $rt_param = Rplus::Model::RuntimeParam->new(key => 'export')->load();
    if ($rt_param) {
        my $config = from_json($rt_param->{value});
        $company_name = $config->{'avito-company'} ? $config->{'avito-company'} : '';                
        $contact_phone = $config->{'avito-phone'} ? trim($config->{'avito-phone'}) : '';
        $agent_phone = 1 if $config->{'avito-agent-phone'} eq 'true';
        $contact_name = '';
        $contact_email = $config->{'irr-email'} ? $config->{'irr-email'} : '';
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
                push @tc, (type_code => 'apartment');
                push @tc, (type_code => 'apartment_small');
                push @tc, (type_code => 'apartment_new');
                push @tc, (type_code => 'townhouse');
            };

            if ($realty_type =~ /rooms/) {
                push @tc, (type_code => 'room');
            }

            if ($realty_type =~ /houses/) {
                push @tc, (type_code => 'house');
                push @tc, (type_code => 'cottage');
                push @tc, (type_code => 'dacha');
                push @tc, (type_code => 'land');
            }

            my $realty_iter = Rplus::Model::Realty::Manager->get_objects_iterator(
                query => [
                    state_code => 'work',
                    offer_type_code => $offer_type,
                    or => [
                            @tc,
                        ],
                    export_media => {'&&' => $media->id},
                ],
                sort_by => 'id ASC',
                require_objects => ['offer_type'],
                with_objects => ['address_object', 'house_type', 'balcony', 'bathroom', 'condition', 'agent', 'type'],
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
