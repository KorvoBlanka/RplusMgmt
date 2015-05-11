package RplusMgmt::Controller::Export::IrrPartner;

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
use File::Copy qw(move);
use File::Path qw(make_path);
use File::Basename;
use DateTime;
use JSON;
use URI;
use Digest::MD5;

my $region = 'Хабаровский край';
my $city = 'Хабаровск';

my $category_hash = {
    sale => {
        room => {
            category => "/real-estate/rooms-sale",
        },
        apartment => {
            category => "/real-estate/apartments-sale/secondary",
        },
        apartment_new => {
            category => "/real-estate/apartments-sale/secondary",
        },
        apartment_small => {
            category => "/real-estate/apartments-sale/secondary",
        },
        cottage => {
            category => "/real-estate/out-of-town/houses",
        },
        townhouse => {
            category => "/real-estate/out-of-town/houses",
        },
        house => {
            category => "/real-estate/out-of-town/houses",
        },
        land => {
            category => "/real-estate/out-of-town/lands",
        },
        dacha => {
            category => "/real-estate/out-of-town/lands",
        },

        other => {
            category => "/real-estate/commercial-sale/misc",
        },
        garage => {
            category => "/real-estate/garage/stall",
        },

        office => {
            category => "/real-estate/commercial-sale/offices",
        },
        office_place => {
            category => "/real-estate/commercial-sale/offices",
        },
        market_place => {
            category => "/real-estate/commercial-sale/offices",
        },
        building => {
            category => "/real-estate/commercial-sale/retail",
        },
        service_place => {
            category => "/real-estate/commercial-sale/retail",
        },
        warehouse_place => {
            category => "/real-estate/commercial-sale/production-warehouses",
        },
        autoservice_place => {
            category => "/real-estate/commercial-sale/production-warehouses",
        },
        gpurpose_place => {
            category => "/real-estate/commercial-sale/misc",
        },
        production_place => {
            category => "/real-estate/commercial-sale/production-warehouses",
        },
    },
    rent => {
        room => {
            category => "/real-estate/rooms-rent",
        },
        apartment => {
            category => "/real-estate/rent",
        },
        apartment_new => {
            category => "/real-estate/rent",
        },
        apartment_small => {
            category => "/real-estate/rent",
        },

        cottage => {
            category => "/real-estate/out-of-town-rent",
        },
        townhouse => {
            category => "/real-estate/out-of-town-rent",
        },
        house => {
            category => "/real-estate/out-of-town-rent",
        },

        land => {
            category => "/real-estate/out-of-town-rent",
        },
        dacha => {
            category => "/real-estate/out-of-town-rent",
        },


        other => {
            category => "/real-estate/commercial/misc",
        },
        garage => {
            category => "/real-estate/garage-rent/stall",
        },

        office => {
            category => "/real-estate/commercial/offices",
        },
        office_place => {
            category => "/real-estate/commercial/offices",
        },
        market_place => {
            category => "/real-estate/commercial/offices",
        },
        building => {
            category => "/real-estate/commercial/retail",
        },
        service_place => {
            category => "/real-estate/commercial/retail",
        },
        warehouse_place => {
            category => "/real-estate/commercial/production-warehouses",
        },
        autoservice_place => {
            category => "/real-estate/commercial/production-warehouses",
        },
        gpurpose_place => {
            category => "/real-estate/commercial/misc",
        },
        production_place => {
            category => "/real-estate/commercial/production-warehouses",
        },
    }
};

sub buildCustomFields {
    my $self = shift;
    my $realty = shift;

    my %custom_fields = ();

    $custom_fields{'region'} = 'Хабаровский';
    $custom_fields{'address_city'} = 'Хабаровск';
    if ($realty->address_object_id) {
        $custom_fields{'address_street'} = $realty->address_object->name . ' ' . $realty->address_object->short_type;
        $custom_fields{'address_house'} = $realty->house_num;
    }

    if ($realty->type->category_code eq 'apartment') {
        $custom_fields{'rooms'} = $realty->rooms_count;

        $custom_fields{'meters-total'} = $realty->square_total;
        $custom_fields{'meters-living'} = $realty->square_living;
        $custom_fields{'kitchen'} = $realty->square_kitchen;

        $custom_fields{'etage'} = $realty->floor;
        $custom_fields{'etage-all'} = $realty->floors_count;

        $custom_fields{'state'} = $realty->condition ? $realty->condition->name : '';
        $custom_fields{'walltype'} = $realty->house_type ? $realty->house_type->name : '';
        $custom_fields{'toilet'} = $realty->bathroom ? $realty->bathroom->name : '';
        $custom_fields{'balcony'} = $realty->balcony ? $realty->balcony->name : '';

        $custom_fields{'telephone'} = '';
        $custom_fields{'internet'} = '';
        $custom_fields{'private'} = '';

        $custom_fields{'house-year'} = '';
        $custom_fields{'house-series'} = '';
        $custom_fields{'house-ceiling-height'} = '';
        $custom_fields{'house-lift'} = '';
        $custom_fields{'house-garbage-disposer'} = '';

        $custom_fields{'water'} = '';
        $custom_fields{'heating'} = '';
        $custom_fields{'gas'} = '';
        
        $custom_fields{'security'} = '';
        $custom_fields{'distance_mkad'} = '';

        if ($realty->offer_type_code eq 'rent') {
            if ($realty->rent_type eq 'long') {
                $custom_fields{'rentLong'} = 'true';
            } else {
                $custom_fields{'rentLong'} = 'false';
            }
        }
    } elsif ($realty->type->category_code eq 'room') {

        $custom_fields{'rooms'} = '';
        $custom_fields{'meters-total'} = '';
        $custom_fields{'etage'} = '';
        $custom_fields{'meters-living'} = '';
        $custom_fields{'state'} = '';
        $custom_fields{'part'} = '';
        $custom_fields{'rooms-for-sale'} = '';
        $custom_fields{'balcony'} = '';
        $custom_fields{'house-year'} = '';
        $custom_fields{'house-series'} = '';
        $custom_fields{'walltype'} = '';
        $custom_fields{'house-ceiling-height'} = '';

        $custom_fields{'water'} = '';
        $custom_fields{'heating'} = '';
        $custom_fields{'gas'} = '';
        $custom_fields{'house-lift'} = '';
        $custom_fields{'house-garbage-disposer'} = '';
        $custom_fields{'security'} = '';

        $custom_fields{'refuse'} = '';
        $custom_fields{'etage-all'} = '';

        if ($realty->offer_type_code eq 'rent') {
            if ($realty->rent_type eq 'long') {
                $custom_fields{'rentLong'} = 'true';
            } else {
                $custom_fields{'rentLong'} = 'false';
            }
        }

    } elsif ($realty->type->category_code eq 'house') {

        $custom_fields{'object'} = '';
        $custom_fields{'meters-total'} = '';
        $custom_fields{'land'} = '';
        $custom_fields{'rooms'} = '';
        $custom_fields{'watersupply'} = '';
        $custom_fields{'state'} = '';
        $custom_fields{'sewage'} = '';
        $custom_fields{'electricpower'} = '';
        $custom_fields{'garage'} = '';
        $custom_fields{'house-demolition'} = '';
        $custom_fields{'house-year'} = '';

        $custom_fields{'heating1'} = '';
        $custom_fields{'walltype'} = '';
        $custom_fields{'land_purpose'} = '';
        $custom_fields{'gas'} = '';
        $custom_fields{'security'} = '';

        $custom_fields{'distance_mkad'} = '';
        $custom_fields{'land_usage'} = '';


    } elsif ($realty->type->category_code eq 'land') {

        $custom_fields{'land'} = '';
        $custom_fields{'land_purpose'} = '';
        $custom_fields{'land_usage'} = '';
        $custom_fields{'land_law'} = '';
        $custom_fields{'watersupply'} = '';
        $custom_fields{'square_meter'} = '';
        $custom_fields{'electricpower'} = '';
        $custom_fields{'gas'} = '';
        $custom_fields{'buildings'} = '';
        $custom_fields{'security'} = '';

    } elsif ($realty->type_code eq 'garage') {

        $custom_fields{'garage_type'} = '';
        $custom_fields{'heating1'} = '';

    } elsif ($realty->type->category_code eq 'commercial') {

    }

    return \%custom_fields;
}

sub buildTitle {
    my $self = shift;
    my $realty = shift;

    my $title_str = '';

    if ($realty->rooms_count) {
        $title_str .= $realty->rooms_count . ' комн. ';
    }

    $title_str .= $realty->type->name . ', ';

    if ($realty->address_object_id) {
        $title_str .= $realty->address_object->short_type . '. ' . $realty->address_object->name;
    }

    return $title_str;    
}

sub index {
    my $self = shift;

    my $acc_id = $self->session('user')->{account_id};

    return $self->render_not_found unless $self->req->method eq 'POST';
    return $self->render(json => {error => 'Forbidden'}, status => 403) unless $self->has_permission(realty => 'export');

    my $media = Rplus::Model::Media::Manager->get_objects(query => [code => 'irr', type => 'export', delete_date => undef])->[0];
    return $self->render_not_found unless $media;

    Mojo::IOLoop->stream($self->tx->connection)->timeout(900);

    my @sale_realty_types = split ',', $self->param('sale_realty_types');
    my @rent_realty_types = split ',', $self->param('rent_realty_types');
    

    my $realty_types = {
        sale => \@sale_realty_types,
        rent => \@rent_realty_types,
    };

    

    my $meta = from_json($media->metadata);
    my $contact_phones = '';
    my $agent_phone = 0;
    my $contact_name = '';
    my $contact_email = '';
    my $site_url = '';
    my $partner_id = '00000000';

    my $options = Rplus::Model::Option->new(account_id => $acc_id)->load();
    if ($options) {
        my $e_opt = from_json($options->{options})->{'export'};
        $contact_phones = $e_opt->{'irr-phones'} ? trim($e_opt->{'irr-phones'}) : '';
        $agent_phone = 1 if $e_opt->{'irr-agent-phone'};
        $contact_name = '';
        $contact_email = $e_opt->{'irr-email'} ? $e_opt->{'irr-email'} : '';
        $site_url = $e_opt->{'irr-url'} ? $e_opt->{'irr-url'} : '';
        $partner_id = $e_opt->{'irr-partner-id'} ? $e_opt->{'irr-partner-id'} : '';;
    }

    #unlink($meta->{'prev_file'}) if $meta->{'prev_file'};
    my ($fh, $file) = tmpnam();
    $meta->{'prev_file'} = $file;

    $media->metadata(encode_json($meta));
    $media->save(changes_only => 1);



    my $xml_writer = XML::Writer->new(OUTPUT => $fh, DATA_MODE => 1, DATA_INDENT => '  ');
    $xml_writer->xmlDecl("UTF-8");

    $xml_writer->startTag('users');
    $xml_writer->startTag('user', 'deactivate-untouched' => 'false');
    $xml_writer->startTag('match');
    $xml_writer->startTag('user-id');
    $xml_writer->characters($partner_id);
    $xml_writer->endTag('user-id');
    $xml_writer->endTag('match');

    while (my ($offer_type, $value) = each $realty_types) {
        for my $realty_type (@$value) {

            my @tc;
            if ($realty_type =~ /apartments/) {
                push @tc, ('type.category_code' => ['apartment',]);
            };

            if ($realty_type =~ /rooms/) {
                push @tc, (type_code => 'room');
            }

            if ($realty_type =~ /houses/) {
                push @tc, ('type.category_code' => ['house']);
            }

            if ($realty_type =~ /commercials/) {
                push @tc, ('type.category_code' => ['commercial', 'commersial']);
            }

            if ($realty_type =~ /lands/) {
                push @tc, ('type.category_code' => ['land']);
            }

            if ($realty_type =~ /garages/) {
                
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

            my $dt = DateTime->now();
            my $valid_from = $dt->datetime();

            my $valid_till_dt = $dt->add(days => 7);
            my $valid_till = $valid_till_dt->datetime();


            while(my $realty = $realty_iter->next) {
                
                $xml_writer->startTag(
                    'store-ad',
                    'power-ad' => '1',
                    'source-id' => $realty->id,
                    validfrom => $valid_from,
                    validtill => $valid_till,
                    category => $category_hash->{$realty->offer_type_code}->{$realty->type_code}->{category},
                    #adverttype => $category_hash->{$realty->type_code}->{adverttype},
                );

                # премиум объявления
                #$xml_writer->startTag('products');
                #$xml_writer->emptyTag(
                #    'product',
                #    name => 'premium',
                #    type => '7',
                #    validfrom => '2013-12-03',
                #);
                #$xml_writer->endTag('products');

                $xml_writer->startTag(
                    'price',
                    value => $realty->price,
                    currency => 'RUR',
                );
                $xml_writer->endTag('price');

                $xml_writer->startTag('title');
                $xml_writer->characters(buildTitle($self, $realty));
                $xml_writer->endTag('title');

                $xml_writer->startTag('description');
                $xml_writer->characters($realty->description);
                $xml_writer->endTag('description');

                $xml_writer->startTag('fotos');
                my $photo_iter = Rplus::Model::Photo::Manager->get_objects_iterator(query => [realty_id => $realty->id, delete_date => undef], sort_by => 'id', limit => 10);
                while (my $photo = $photo_iter->next) {

                    my $img_filename = '';
                    if ($photo->filename =~ /http:\/\/.+\.com(.+)/) {
                        $img_filename = '/var/data/storage' . $1;
                    }

                    if (open(my $img_fh, "<", $img_filename)) {
                        my $ctx = Digest::MD5->new;
                        $ctx->addfile($img_fh);
                        $xml_writer->emptyTag(
                            'foto-remote',
                            url => $photo->filename,
                            md5 => $ctx->hexdigest,
                        );
                        close $img_fh;
                    }
                }
                $xml_writer->endTag('fotos');

                $xml_writer->startTag('custom-fields');

                my $custom_fields = buildCustomFields($self, $realty);
                foreach my $k (keys %{$custom_fields}) {
                    my $v = $custom_fields->{$k};
                    if ($v) {
                        $xml_writer->startTag('field', name => $k);
                        $xml_writer->characters($v);
                        $xml_writer->endTag('field');
                    }
                }
                #foreach (keys %$template) {
                #    my $val = $template->{$_}->($realty);
                #    next unless $val;
                #    $xml_writer->startTag($_);
                #    if($_ ne 'Images') {
                #        $xml_writer->characters($val);
                #    } else {
                #        print Dumper $val;
                #        for my $photo (@$val) {
                #            $xml_writer->startTag('Image', url => $photo);
                #            $xml_writer->endTag();
                #        }                        
                #    }
                #    $xml_writer->endTag();
                #}
                $xml_writer->endTag('custom-fields');

                $xml_writer->endTag('store-ad');
            }

        }
    }

    $xml_writer->endTag('user');
    $xml_writer->endTag('users');
    $xml_writer->end();

    close $fh;

    my $file_name = 'irr_a'.$acc_id.'.xml';
    my($file_name_a, $new_path, $ext_a) = fileparse($self->config->{'storage'}->{'path'});
    my $new_file = $new_path.'files/export/'.$file_name;
    my($file_name_b, $dir, $ext_b) = fileparse($new_file);
    make_path($dir);
    move($file, $new_file);

    my $mode = 0644;
    chmod $mode, $new_file;

    my($file_name_c, $url_part, $ext_c) = fileparse($self->config->{'storage'}->{'url'});
    my $path = $url_part.'files/export/'.$file_name;

    return $self->render(json => {path => $path});
}

1;
